#!/usr/bin/env python3
"""Assemble deterministic rootfs bundles and manifests for Repo A.

Produces one ZIP bundle per ABI and a rootfs-manifest.json describing
every entry's path, type, mode, SHA-256, symlink target, package owner,
and mutability classification.
"""

import argparse
import hashlib
import json
import os
import stat
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path


def compute_sha256(path: Path) -> str:
    """Compute SHA-256 hash of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def classify_entry(rel_path: str) -> str:
    """Classify an entry as mutable or immutable."""
    # Binaries and libraries are immutable (check usr/ paths first, then bin/ lib/ fallback)
    if rel_path.startswith("usr/bin/") or rel_path.startswith("usr/lib/") or \
       rel_path.startswith("bin/") or rel_path.startswith("lib/"):
        return "immutable"
    # Home and tmp are mutable
    if rel_path.startswith("home/") or rel_path.startswith("tmp/"):
        return "mutable"
    return "immutable"


def _walk_rootfs(rootfs_dir: Path) -> list[Path]:
    """Walk rootfs directory including dotfiles, returning all entry paths."""
    entries = []
    for dirpath, _dirnames, filenames in os.walk(rootfs_dir, followlinks=False):
        # Only regular files and file symlinks (os.walk's filenames) are
        # collected here. Directory entries are intentionally not emitted:
        # parent directories are implied by the file paths, and extraction /
        # installation recreates them implicitly.
        for name in filenames:
            entries.append(Path(dirpath) / name)
    return entries


def collect_entries(rootfs_dir: Path, prefix: str = "") -> list[dict]:
    """Walk rootfs directory and collect all entries for the manifest."""
    entries = []

    for entry_path in sorted(_walk_rootfs(rootfs_dir)):
        if not entry_path.is_absolute():
            continue

        rel = entry_path.relative_to(rootfs_dir)
        rel_str = str(rel)

        # Strip the configurable prefix from the relative path.
        # rel_str has no leading / (e.g. "data/data/vn.shadichy.parted/files/usr/bin/parted")
        # prefix has a leading / (e.g. "/data/data/vn.shadichy.parted/files").
        strippable = prefix.lstrip("/")
        if strippable and rel_str.startswith(strippable):
            rel_str = rel_str[len(strippable):].lstrip("/")

        if not rel_str:
            continue

        # Skip the staging directory itself
        if rel_str == ".":
            continue

        entry = {
            "path": rel_str,
        }

        if entry_path.is_symlink():
            entry["type"] = "symlink"
            entry["link_target"] = os.readlink(entry_path)
            entry["mode"] = stat.S_IMODE(entry_path.lstat().st_mode)
            entry["sha256"] = None
        elif entry_path.is_file():
            entry["type"] = "file"
            entry["mode"] = stat.S_IMODE(entry_path.stat().st_mode)
            entry["sha256"] = compute_sha256(entry_path)
            entry["link_target"] = None
        elif entry_path.is_dir():
            entry["type"] = "directory"
            entry["mode"] = stat.S_IMODE(entry_path.stat().st_mode)
            entry["sha256"] = None
            entry["link_target"] = None
        else:
            continue

        entry["owner"] = classify_entry(rel_str)
        entry["mutability"] = "immutable" if entry["owner"] == "immutable" else "mutable"

        entries.append(entry)

    return entries


def assemble_bundle(
    rootfs_dir: Path,
    output_dir: Path,
    abi: str,
    toolchain_version: str,
    termux_commit: str,
    prefix: str = "/data/data/vn.shadichy.parted/files",
) -> dict:
    """Assemble the rootfs bundle and return the manifest."""
    entries = collect_entries(rootfs_dir, prefix=prefix)

    # Ensure output directory exists
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate manifest
    manifest = {
        "schema_version": "1.1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "abi": abi,
        "termux_commit": termux_commit,
        "package_id": "vn.shadichy.parted",
        "prefix": "/data/data/vn.shadichy.parted/files",
        "entry_count": len(entries),
        "entries": entries,
    }

    manifest_path = output_dir / "rootfs-manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)

    # Create ZIP bundle
    bundle_name = f"fparted-rootfs-{toolchain_version}-{abi}.zip"
    bundle_path = output_dir / bundle_name

    # Verify no path traversal or forbidden paths in entries
    forbidden_prefixes = [
        "/data/data/com.termux",
    ]
    for entry in entries:
        epath = entry["path"]
        if epath.startswith("/"):
            raise ValueError(f"Forbidden absolute path in rootfs: {epath}")
        if ".." in epath.split("/"):
            raise ValueError(f"Path traversal detected: {epath}")
        if "\x00" in epath:
            raise ValueError(f"NUL character in path: {epath}")
        abs_epath = prefix.rstrip("/") + "/" + epath
        for forbidden in forbidden_prefixes:
            if forbidden in abs_epath:
                raise ValueError(f"Forbidden prefix in rootfs entry: {epath}")

    with zipfile.ZipFile(bundle_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for entry_path in sorted(_walk_rootfs(rootfs_dir)):
            arcname = str(entry_path.relative_to(rootfs_dir))
            # Strip prefix from arcname, same as collect_entries
            strippable = prefix.lstrip("/")
            if strippable and arcname.startswith(strippable):
                arcname = arcname[len(strippable):].lstrip("/")
            if entry_path.is_symlink():
                link_target = os.readlink(entry_path)
                info = zipfile.ZipInfo(arcname)
                info.external_attr = entry_path.lstat().st_mode << 16
                zf.writestr(info, link_target)
            elif entry_path.is_file():
                zf.write(entry_path, arcname)
        # Also embed the manifest in the bundle
        zf.writestr("rootfs-manifest.json", json.dumps(manifest, indent=2, sort_keys=True))

    return {
        "bundle_path": str(bundle_path),
        "bundle_name": bundle_name,
        "manifest_path": str(manifest_path),
        "entry_count": len(entries),
    }


def main():
    parser = argparse.ArgumentParser(description="Assemble deterministic rootfs bundles")
    parser.add_argument("--rootfs-dir", required=True, help="Path to rootfs staging directory")
    parser.add_argument("--output", required=True, help="Output directory for bundle and manifest")
    parser.add_argument("--abi", required=True, help="Target Android ABI (arm64-v8a, x86_64)")
    parser.add_argument("--toolchain-version", default="1.0.0", help="Toolchain version string")
    parser.add_argument("--termux-commit", required=True, help="Pinned termux/termux-packages commit")
    parser.add_argument("--prefix", default="/data/data/vn.shadichy.parted/files",
                        help="Rootfs prefix to strip from archive paths")
    parser.add_argument("--json", action="store_true", help="Output JSON manifest")
    args = parser.parse_args()

    rootfs_dir = Path(args.rootfs_dir)
    if not rootfs_dir.exists():
        print(f"ERROR: rootfs-dir does not exist: {rootfs_dir}", file=sys.stderr)
        return 1

    result = assemble_bundle(
        rootfs_dir,
        Path(args.output),
        args.abi,
        args.toolchain_version,
        args.termux_commit,
        prefix=args.prefix,
    )

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Bundle: {result['bundle_name']}")
        print(f"Manifest: {result['manifest_path']}")
        print(f"Entries: {result['entry_count']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
