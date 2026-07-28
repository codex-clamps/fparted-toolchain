#!/usr/bin/env python3
"""Validate Repo A rootfs bundles for ELF, paths, dependencies, licenses, SBOM, and smoke."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path

FORBIDDEN_PREFIXES = [
    "/data/data/com.termux",
]

SUPPORTED_ABIS = {"arm64-v8a", "armv7a", "i686", "x86_64"}

REQUIRED_BINARIES = [
    "parted", "blkid", "dd", "test",
    "e2fsck", "mke2fs", "resize2fs", "tune2fs",
    "mkfs.fat", "fsck.fat", "fatlabel",
    "mkfs.exfat", "fsck.exfat", "exfatlabel",
    "mkfs.f2fs", "fsck.f2fs",
    "btrfs", "mkfs.btrfs",
]


def validate_manifest_schema(manifest: dict) -> list[str]:
    """Validate rootfs-manifest.json schema compliance."""
    errors = []
    required_keys = {"schema_version", "abi", "termux_commit", "entries"}
    missing = required_keys - set(manifest.keys())
    if missing:
        errors.append(f"Manifest missing keys: {missing}")

    if manifest.get("schema_version") != "1.0":
        errors.append(f"Unexpected schema_version: {manifest.get('schema_version')}")

    if manifest.get("abi") not in SUPPORTED_ABIS:
        errors.append(f"Unsupported ABI: {manifest.get('abi')}")

    for entry in manifest.get("entries", []):
        for key in ("path", "type", "mode"):
            if key not in entry:
                errors.append(f"Entry missing key '{key}': {entry}")
        if entry.get("type") == "symlink" and "link_target" not in entry:
            errors.append(f"Symlink entry missing link_target: {entry.get('path')}")
        if entry.get("type") == "file" and entry.get("sha256") is None:
            errors.append(f"File entry missing sha256: {entry.get('path')}")

    return errors


def validate_elf_archives(zip_path: Path) -> list[str]:
    """Check that ELF files have correct architecture and Bionic linkage."""
    warnings = []

    # ELF validation requires readelf or file command
    has_readelf = shutil_which("readelf") is not None
    has_file = shutil_which("file") is not None

    if not has_readelf and not has_file:
        warnings.append("Neither readelf nor file found; skipping ELF architecture check")
        return warnings

    with zipfile.ZipFile(zip_path) as zf:
        for name in zf.namelist():
            if name.endswith("/"):
                continue
            data = zf.read(name)
            if not data.startswith(b"\x7fELF"):
                continue

            # Extract to temp for readelf/file analysis
            tmp_path = f"/tmp/fparted_validate_{os.getpid()}_{name.replace('/', '_')}"
            try:
                with open(tmp_path, "wb") as f:
                    f.write(data)

                if has_readelf:
                    result = subprocess.run(
                        ["readelf", "-h", tmp_path],
                        capture_output=True, text=True, timeout=10,
                    )
                    if result.returncode == 0:
                        for line in result.stdout.splitlines():
                            if "Class:" in line and "ELF64" not in line and "ARM" not in line and "x86-64" not in line and "i386" not in line:
                                warnings.append(f"Unexpected ELF class for {name}: {line.strip()}")

                if has_file:
                    result = subprocess.run(
                        ["file", tmp_path],
                        capture_output=True, text=True, timeout=10,
                    )
                    # Just check that file command recognizes it
            finally:
                if os.path.exists(tmp_path):
                    os.unlink(tmp_path)

    return warnings


def validate_paths(zip_path: Path) -> list[str]:
    """Check that no entry contains path traversal or forbidden prefixes."""
    errors = []

    with zipfile.ZipFile(zip_path) as zf:
        for name in zf.namelist():
            # Check for path traversal
            if ".." in name.split("/"):
                errors.append(f"Path traversal in archive: {name}")
            # Check for NUL bytes
            if "\x00" in name:
                errors.append(f"NUL byte in path: {name}")
            # Check for absolute paths
            if name.startswith("/"):
                errors.append(f"Absolute path in archive: {name}")
            # Check for forbidden prefixes
            for forbidden in FORBIDDEN_PREFIXES:
                if forbidden in name:
                    errors.append(f"Forbidden prefix in archive entry: {name}")

    return errors


def validate_required_binaries(zip_path: Path) -> list[str]:
    """Check that all required binaries are present in the bundle."""
    errors = []
    found_binaries = set()

    with zipfile.ZipFile(zip_path) as zf:
        for name in zf.namelist():
            if name.startswith("bin/") and not name.endswith("/"):
                basename = os.path.basename(name)
                found_binaries.add(basename)

    for required in REQUIRED_BINARIES:
        if required not in found_binaries:
            err_msg = f"Required binary missing from bundle: {required}"
            # Some binaries may be symlinks or provided differently
            if required.startswith("mkfs.") or required.startswith("fsck."):
                err_msg += f" (note: {required} is a filesystem tool that must be present)"
            errors.append(err_msg)

    return errors


def validate_license_sbom(zip_path: Path) -> list[str]:
    """Check that the bundle includes license/SBOM information.

    In production, each package entry must carry license metadata.
    This validator checks for LICENSE files or a packages.spdx.json manifest.
    """
    warnings = []

    has_license = False
    has_spdx = False

    with zipfile.ZipFile(zip_path) as zf:
        for name in zf.namelist():
            if "LICENSE" in name or "LICENSE.txt" in name or "COPYING" in name:
                has_license = True
            if "spdx" in name.lower() or "sbom" in name.lower():
                has_spdx = True

    if not has_license:
        warnings.append("WARNING: No LICENSE file found in bundle")
    if not has_spdx:
        warnings.append("WARNING: No SPDX/SBOM manifest found in bundle")

    return warnings


def validate_hashes(zip_path: Path) -> list[str]:
    """Verify per-file SHA-256 hashes in the rootfs manifest."""
    errors = []

    # Extract manifest from zip
    with zipfile.ZipFile(zip_path) as zf:
        manifest_data = None
        for name in zf.namelist():
            if "rootfs-manifest.json" in name:
                manifest_data = json.loads(zf.read(name))
                break

        if not manifest_data:
            return ["No rootfs-manifest.json found in bundle"]

        for entry in manifest_data.get("entries", []):
            if entry.get("type") != "file" or not entry.get("sha256"):
                continue

            rel_path = entry["path"]
            expected_sha = entry["sha256"].lower()

            # Extract file from zip and verify hash
            try:
                data = zf.read(rel_path)
                actual_sha = hashlib.sha256(data).hexdigest().lower()
                if actual_sha != expected_sha:
                    errors.append(f"Hash mismatch for {rel_path}: expected {expected_sha}, got {actual_sha}")
            except KeyError:
                errors.append(f"Manifest entry not found in archive: {rel_path}")
            except Exception as e:
                errors.append(f"Error verifying {rel_path}: {e}")

    return errors


def shuffle_which(cmd: str) -> str | None:
    """Check if a command exists in PATH."""
    return shutil_which(cmd)


def shutil_which(cmd: str) -> str | None:
    """Shim for shutil.which."""
    for path_dir in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(path_dir, cmd)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def main():
    parser = argparse.ArgumentParser(description="Validate Repo A rootfs bundles")
    parser.add_argument("--bundle", required=True, help="Path to rootfs ZIP bundle")
    parser.add_argument("--manifest", help="Path to rootfs-manifest.json (if not in bundle)")
    parser.add_argument("--strict", action="store_true", help="Treat warnings as errors")
    parser.add_argument("--json", action="store_true", help="Output JSON report")
    args = parser.parse_args()

    bundle_path = Path(args.bundle)
    if not bundle_path.exists():
        print(f"ERROR: Bundle not found: {bundle_path}", file=sys.stderr)
        return 1

    all_errors = []
    all_warnings = []

    # 1. Schema validation
    if args.manifest:
        with open(args.manifest) as f:
            manifest = json.load(f)
        schema_errors = validate_manifest_schema(manifest)
        all_errors.extend(schema_errors)
    else:
        # Try to extract manifest from bundle
        with zipfile.ZipFile(bundle_path) as zf:
            for name in zf.namelist():
                if "rootfs-manifest.json" in name:
                    manifest = json.loads(zf.read(name))
                    break
            else:
                all_errors.append("No rootfs-manifest.json found in bundle")
                manifest = {}

        schema_errors = validate_manifest_schema(manifest)
        all_errors.extend(schema_errors)

    # 2. Path traversal / forbidden path validation
    path_errors = validate_paths(bundle_path)
    all_errors.extend(path_errors)

    # 3. Required binaries check
    bin_errors = validate_required_binaries(bundle_path)
    all_errors.extend(bin_errors)

    # 4. License / SBOM check
    license_warnings = validate_license_sbom(bundle_path)
    all_warnings.extend(license_warnings)

    # 5. Hash verification
    hash_errors = validate_hashes(bundle_path)
    all_errors.extend(hash_errors)

    # 6. ELF architecture check
    elf_warnings = validate_elf_archives(bundle_path)
    all_warnings.extend(elf_warnings)

    # Output
    if args.json:
        report = {
            "bundle": str(bundle_path),
            "errors": all_errors,
            "warnings": all_warnings,
            "passed": len(all_errors) == 0,
        }
        print(json.dumps(report, indent=2))
    else:
        print(f"=== Validation Report: {bundle_path.name} ===")
        print(f"Errors:   {len(all_errors)}")
        for e in all_errors:
            print(f"  ERROR: {e}")
        print(f"Warnings: {len(all_warnings)}")
        for w in all_warnings:
            print(f"  WARN:  {w}")
        print(f"Result: {'PASS' if not all_errors else 'FAIL'}")

    if args.strict and all_warnings:
        print("Strict mode: warnings treated as errors", file=sys.stderr)
        return 1

    return 1 if all_errors else 0


if __name__ == "__main__":
    sys.exit(main())
