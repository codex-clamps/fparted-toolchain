#!/usr/bin/env python3
"""Create release manifests for Repo A GitHub releases.

Packages one or more rootfs bundles with:
  - release-manifest.json (schema, version, Termux commit, prefix, ABI mapping, asset hashes)
  - release-manifest.sig (real detached GPG signature; required with --sign)
  - SHA256SUMS (per-asset and per-bundle hashes)
  - packages.spdx.json (SPDX SBOM)
  - source-offer.json (source availability declaration)
"""

import argparse
import hashlib
import json
import os
import re
import sys
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def compute_file_hash(path: Path, algorithm: str = "sha256") -> str:
    """Compute hash of a file."""
    h = hashlib.new(algorithm)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def collect_bundles(release_dir: Path, pattern: str = "*.zip") -> list[dict]:
    """Find and hash all release bundles in a directory."""
    bundles = []
    for bundle_path in sorted(release_dir.glob(pattern)):
        bundles.append({
            "path": str(bundle_path),
            "name": bundle_path.name,
            "size": bundle_path.stat().st_size,
            "sha256": compute_file_hash(bundle_path),
        })
    return bundles


def generate_release_manifest(
    bundles: list[dict],
    toolchain_version: str,
    termux_commit: str,
    schema_version: str = "1.1",
) -> dict:
    """Generate a release manifest from bundle metadata."""
    assets = {}
    for b in bundles:
        # Extract ABI from filename: fparted-rootfs-<version>-<abi>.zip
        # ABIs with hyphens (arm64-v8a, x86_64) must be matched as a whole.
        name = b["name"]
        abi = "unknown"
        abi_match = re.search(r"-(arm64-v8a|x86_64)$", name.replace(".zip", ""))
        if abi_match:
            abi = abi_match.group(1)

        if abi in assets:
            print(f"WARNING: duplicate ABI {abi}, overwriting")
        assets[abi] = {
            "url": f"https://github.com/codex-clamps/fparted-toolchain/releases/download/v{toolchain_version}/{name}",
            "name": name,
            "size": b["size"],
            "sha256": b["sha256"],
        }

    return {
        "schema_version": schema_version,
        "toolchain_version": toolchain_version,
        "termux_commit": termux_commit,
        "package_id": "vn.shadichy.parted",
        "prefix": "/data/data/vn.shadichy.parted/files",
        "min_android_api": 24,
        "app_compatibility": {
            "application_id": "vn.shadichy.parted",
            "abi": list(assets.keys()),
        },
        "assets": assets,
        "required_binaries": [
            "parted", "blkid", "dd", "test",
            "e2fsck", "mke2fs", "resize2fs", "tune2fs",
            "mkfs.fat", "fsck.fat", "fatlabel",
            "mkfs.exfat", "fsck.exfat", "exfatlabel",
            "mkfs.f2fs", "fsck.f2fs",
            "btrfs", "mkfs.btrfs",
            "mkfs.ntfs", "ntfsfix", "ntfslabel", "ntfsresize",
            "mkfs.xfs", "xfs_repair", "xfs_admin", "xfs_growfs",
            "mkfs.jfs", "jfs_fsck", "jfs_tune",
            "mkfs.hfsplus", "fsck.hfsplus",
            "mkfs.apfs", "mkapfs", "apfs-label", "apfs-snap", "apfsck", "fsck.apfs",
            "mkfs.bcachefs", "mkfs.fuse.bcachefs", "fsck.bcachefs", "fsck.fuse.bcachefs",
            "mount.bcachefs", "mount.fuse.bcachefs", "bcachefs",
        ],
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


def generate_spdx(bundles: list[dict], toolchain_version: str) -> dict:
    """Generate a minimal SPDX SBOM."""
    packages = []
    for b in bundles:
        packages.append({
            "SPDXID": f"SPDXRef-Bundle-{b['name']}",
            "name": b["name"],
            "downloadLocation": f"https://github.com/codex-clamps/fparted-toolchain/releases/download/v{toolchain_version}/{b['name']}",
            "filesAnalyzed": False,
            "shasum": f"SHA-256:{b['sha256']}",
            "licenseConcluded": "GPL-2.0",
            "licenseDeclared": "GPL-2.0",
        })

    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "fparted-toolchain",
        "documentNamespace": f"https://github.com/codex-clamps/fparted-toolchain/releases/v{toolchain_version}",
        "creationInfo": {
            "created": datetime.now(timezone.utc).isoformat(),
        },
        "packages": packages,
    }


def get_release_key_fingerprint() -> str:
    """Return the full fingerprint of the committed release signing key.

    Derived from keys/release-pubkey.asc (the public half of the release
    signing key; the private half lives only in the GPG_PRIVATE_KEY repository
    secret). Pinning the full fingerprint -- rather than a short key ID --
    avoids short-ID collisions and ensures we never sign with an arbitrary key
    from the local keyring.
    """
    key_path = Path(__file__).resolve().parent.parent / "keys" / "release-pubkey.asc"
    result = subprocess.run(
        [
            "gpg",
            "--with-colons",
            "--import-options",
            "show-only",
            "--import",
            str(key_path),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(
            f"gpg failed to read release key {key_path}"
            + (f" ({detail})" if detail else "")
        )
    for line in result.stdout.splitlines():
        if line.startswith("fpr:"):
            fields = line.split(":")
            # Colon output: field 10 (1-indexed) carries the full fingerprint.
            if len(fields) > 9 and fields[9]:
                return fields[9]
    raise RuntimeError(f"release public key {key_path} contains no fingerprint record")


def sign_manifest(manifest: dict, output_path: Path) -> bool:
    """Sign the manifest with a GPG key. Returns True on success."""
    try:
        manifest_json = json.dumps(manifest, indent=2, sort_keys=True)
        # Pin the signing key by the full fingerprint of the committed public
        # key (keys/release-pubkey.asc) instead of letting gpg choose one.
        fingerprint = get_release_key_fingerprint()
        result = subprocess.run(
            [
                "gpg",
                "--batch",
                "--yes",
                "--pinentry-mode",
                "loopback",
                "--local-user",
                fingerprint,
                "--detach-sign",
                "--armor",
                "--output",
                str(output_path),
            ],
            input=manifest_json,
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            print(
                f"ERROR: gpg signing failed (exit code {result.returncode})",
                file=sys.stderr,
            )
            if detail:
                print(f"  gpg: {detail}", file=sys.stderr)
            return False
        return True
    except FileNotFoundError:
        print("ERROR: gpg executable not found; cannot sign release manifest", file=sys.stderr)
        return False
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return False
    except subprocess.TimeoutExpired:
        print("ERROR: gpg signing timed out", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Create Repo A release manifests")
    parser.add_argument("--bundle-dir", required=True, help="Directory containing rootfs ZIP bundles")
    parser.add_argument("--toolchain-version", required=True, help="Toolchain version string (e.g. 1.0.0)")
    parser.add_argument("--termux-commit", required=True, help="Pinned termux/termux-packages commit")
    parser.add_argument("--output-dir", required=True, help="Output directory for release files")
    parser.add_argument("--sign", action="store_true", help="Attempt GPG signing of release manifest")
    parser.add_argument("--json", action="store_true", help="Output JSON manifest to stdout")
    args = parser.parse_args()

    bundle_dir = Path(args.bundle_dir)
    output_dir = Path(args.output_dir)

    if not bundle_dir.exists():
        print(f"ERROR: Bundle directory does not exist: {bundle_dir}", file=sys.stderr)
        return 1

    # Collect bundles
    bundles = collect_bundles(bundle_dir)
    if not bundles:
        print(f"ERROR: No bundles found in {bundle_dir}", file=sys.stderr)
        return 1

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate release manifest
    manifest = generate_release_manifest(
        bundles,
        args.toolchain_version,
        args.termux_commit,
    )

    # Write release manifest
    manifest_path = output_dir / "release-manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)

    # Sign manifest if requested
    sig_path = output_dir / "release-manifest.sig"
    if args.sign and not sign_manifest(manifest, sig_path):
        print("ERROR: manifest signing failed", file=sys.stderr)
        return 1

    # Write SHA256SUMS
    sums_path = output_dir / "SHA256SUMS"
    with open(sums_path, "w") as f:
        for b in bundles:
            f.write(f"{b['sha256']}  {b['name']}\n")
        # Also add manifest hash
        manifest_hash = compute_file_hash(manifest_path)
        f.write(f"{manifest_hash}  release-manifest.json\n")

    # Generate SPDX SBOM
    spdx = generate_spdx(bundles, args.toolchain_version)
    spdx_path = output_dir / "packages.spdx.json"
    with open(spdx_path, "w") as f:
        json.dump(spdx, f, indent=2)

    # Generate source offer
    source_offer = {
        "schema_version": "1.0",
        "source_url": "https://github.com/termux/termux-packages",
        "pinned_commit": args.termux_commit,
        "overlay_commit": None,
        "build_instructions": "See README.md",
        "license": "GPL-2.0 (Termux packages; individual packages vary)",
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    source_path = output_dir / "source-offer.json"
    with open(source_path, "w") as f:
        json.dump(source_offer, f, indent=2)

    if args.json:
        print(json.dumps(manifest, indent=2))
    else:
        print(f"Release manifest written to: {manifest_path}")
        print(f"SHA256SUMS: {sums_path}")
        print(f"SPDX SBOM: {spdx_path}")
        print(f"Source offer: {source_path}")
        if args.sign:
            print(f"Signature: {sig_path}")
        print(f"Bundles included: {len(bundles)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
