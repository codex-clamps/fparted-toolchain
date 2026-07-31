# fparted-toolchain — Complete Walkthrough

## Overview
What this project is: A deterministic, reproducible rootfs builder for the fparted Android partition editor app. It produces signed, verified rootfs bundles for 2 Android ABIs (arm64-v8a, x86_64).

## The Problem We Solved
- The fparted app needs a Linux toolchain on Android to run parted, e2fsprogs, dosfstools, etc.
- Termux provides the build infrastructure but uses com.termux package ID/prefix
- We need vn.shadichy.parted prefix with all packages compiled from source
- Standard Termux .deb packages use wrong prefix — everything must be built from source with our patch

## Repository Structure
Explain each directory:
- .github/workflows/ — single CI/build/release pipeline (ci.yml)
- config/ — packages.yaml, aliases.yaml, termux-lock.json, overlay-packages/
- overlays/ — package recipe overlays
- patches/ — termux prefix patch
- scripts/ — build-rootfs.sh, assemble-rootfs.py, validate-rootfs.py, etc.
- schemas/ — JSON schemas for manifests
- staging/ — built artifacts

## Pipeline Walkthrough (6 Steps)

### Step 1: Checkout Termux Packages
- Clones termux/termux-packages at pinned commit from config/termux-lock.json
- Uses git init + fetch + checkout FETCH_HEAD for exact commit

### Step 2: Apply Prefix Patch
- patches/termux-prefix.patch changes TERMUX_APP_PACKAGE_NAME from com.termux to vn.shadichy.parted
- Also updates repo.json to use pacman format (.pkg.tar.xz)
- Applied via git apply

### Step 3: Build Packages via Docker
- Uses ghcr.io/termux/package-builder Docker image
- Reads package list from config/packages.yaml
- Builds with --format pacman for .pkg.tar.xz output
- Checkpointing: skips packages with existing .pkg.tar.xz in staging
- Persistent build cache via volume mount at $TERMUX_TOPDIR
- Post-build sweep: collects dependency .pkg.tar.xz from entire build cache
- FUSE requirement: --privileged on GHA runners, --cap-add SYS_ADMIN + /dev/fuse locally

### Step 4: Extract Rootfs
- Extracts all .pkg.tar.xz files into rootfs/ staging directory
- Handles both top-level packages and dependencies

### Step 5: Assemble Bundle
- assemble-rootfs.py creates deterministic ZIP bundle
- Strips Android prefix path (/data/data/vn.shadichy.parted/files) from entries
- Generates rootfs-manifest.json with entries, hashes, types
- Handles symlinks properly in ZIP
- Validates: no absolute paths, no path traversal, no forbidden prefixes

### Step 6: Validate
- validate-rootfs.py checks:
  - Schema compliance
  - Required binaries present
  - All file hashes match manifest
  - ELF architecture matches target ABI
  - No forbidden paths

## GitHub Actions Workflows

### Build & Release (ci.yml)
Single consolidated workflow replacing the former ci.yml, build.yml, release.yml, and build-abi.yml.
Triggers on push to master, tag push (v*), PRs, and workflow_dispatch.
- PR: x86_64-only smoke build + config/schema/shellcheck/reproducibility validation
- Push to master: matrix build for both ABIs (arm64-v8a, x86_64) + verify-all
- Tag push (v*): 2-ABI build + release manifest/signing/SHA256SUMS assembly + draft GitHub release + smoke test
- Each build job: checkout → setup Python → build rootfs → validate → upload artifact

## Build Results
- x86_64: Built locally 2026-07-30, validated, tested on real Android 12 device (libvirt/qemu VM)
- All 9 target packages built from source (plus 42+ dependencies = 116 .pkg.tar.xz)
- Rootfs bundle: 72 MB ZIP, 2384 entries
- Zero com.termux references in output
- All required binaries present and functional
- ADB test: all 8 required binaries pass version checks, library linkage works

## Key Decisions

### Why not use pre-built .deb packages?
- .deb packages use com.termux prefix. Building from source with patch ensures correct vn.shadichy.parted prefix.

### Why Arch Linux format (.pkg.tar.xz)?
- pacman format produces single-file .pkg.tar.xz per package (instead of multiple .deb files for split packages)
- Simpler extraction pipeline

### Why FUSE/overlayfs?
- Termux package-builder uses overlay filesystem for isolated builds
- Requires --privileged on GHA runners (no /dev/fuse available)
- Requires --cap-add SYS_ADMIN + --device /dev/fuse on local machines

### Why not use com.termux prefix?
- Security isolation: fparted manages its own toolchain independent of any Termux installation
- Deterministic: the app controls exactly which packages and versions are installed

## Issues Encountered and Fixes

1. armv7a vs armeabi-v7a ABI mismatch in scaffolding scripts → Fixed
2. --privileged required for FUSE but not available on GHA runners → Environment detection
3. build-package.sh -o /output only copies top-level packages, not dependencies → Post-build sweep
4. f2fs-tools missing sys/sysmacros.h and hasmntopt() on Bionic → Overlay patch (Python-based)
5. git apply --check never applied prefix patch (validation only) → Changed to git apply
6. Docker --rm destroyed build cache between runs → Persistent volume mount
7. Symlinks flattened in ZIP by Android unzip → Use python3 -m zipfile -e or bsdtar for extraction
8. ZIP entries had full Android prefix paths → --prefix arg in assemble-rootfs.py strips them

## Current Status
- Last build completed: 2026-07-30
- Both ABI builds running on GHA (in progress)
- Release v0.2.0 tag created and pushed
- 3/3 Repo A CI runs: ✅ success
- 0/3 previous Build Rootfs runs: ❌ failure (FUSE + missing packages — should be fixed now)
- 1/1 previous Publish Release run: ❌ failure (v0.1.0 — same FUSE issue)

## How to Build Locally
```bash
# Build x86_64 rootfs
bash scripts/build-rootfs.sh x86_64

# Validate
python3 scripts/validate-rootfs.py \
  --bundle staging/x86_64/fparted-rootfs-*.zip \
  --strict

# Generate release manifest
python3 scripts/make-release-manifest.py \
  --bundle-dir staging/ \
  --toolchain-version 1.0.0 \
  --termux-commit e0177c596fc96693f9a008f73e3482cf25873a84 \
  --output-dir release-output
```

## How to Release
```bash
# Tag and push
git tag -a v0.3.0 -m "release description"
git push origin v0.3.0

# GHA handles the rest
```

## Integration with fparted App
- (Note: This section describes what the fparted app needs to do with these artifacts — not yet implemented)
- App downloads release-manifest.json from GitHub Releases
- Validates signature against trusted key
- Downloads the ZIP bundle matching device ABI
- Validates size, SHA-256, schema
- Extracts to /data/data/vn.shadichy.parted/files/
- Verifies required binaries are present and executable

## Validation Results

```
=== Validation Report: fparted-rootfs-1.0.0-x86_64.zip ===
Errors:   0
Warnings: 1
  WARN:  WARNING: No SPDX/SBOM manifest found in bundle
Result: PASS
```
