# fparted-toolchain (Repo A)

Deterministic, reproducible Android/Bionic rootfs toolchain builder for the `fparted` rooted partition editor.

## Purpose

This repository produces signed, verified rootfs bundles for each supported Android ABI that the `fparted` app consumes during startup and toolchain installation.

## Key Contracts

- **Package ID**: `vn.shadichy.parted`
- **Rootfs prefix**: `/data/data/vn.shadichy.parted/files`
- **No `/data/data/com.termux`** artifacts allowed in any output
- **No `/files/usr` path leakage** allowed in any output
- **No standard Termux prefix binaries** from `com.termux` repository

## Release Signing & Publishing

- Release manifests are signed with a real GPG key (ed25519). The private key lives only in the `GPG_PRIVATE_KEY` repository secret; the public key is committed at `keys/release-pubkey.asc`.
- Signing is mandatory: the `assemble-release` job fails if the detached signature cannot be produced.
- Tag pushes (v*.*.*) publish releases automatically — no draft is created.

## Directory Layout

```text
.
├── .github/workflows/
│   └── ci.yml       # Single pipeline: PR validation + 2-ABI builds + verify-all + release assembly
├── config/
│   ├── packages.yaml          # Package definitions with source hashes, licenses
│   ├── aliases.yaml           # User-facing name → canonical target mapping
│   ├── required-binaries.yaml # Source-of-truth for required executables
│   └── termux-lock.json       # Pinned termux/termux-packages commit + metadata
├── overlays/
│   ├── packages/              # Missing/modified package recipes
│   └── root-packages/         # Root-level recipe overlays
├── patches/
│   └── termux-prefix.patch    # Custom prefix patch for fparted
├── scripts/
│   ├── resolve-packages.py    # Alias validation + dependency graph resolution
│   ├── build-rootfs.sh        # One-architecture rootfs build script
│   ├── assemble-rootfs.py     # Deterministic bundle assembly + manifest generation
│   ├── validate-rootfs.py     # ELF/path/dep/license/SBOM/smoke validation
│   └── make-release-manifest.py  # Release manifest + SHA256SUMS + SPDX generation
├── keys/
│   └── release-pubkey.asc    # Release signing public key (verifies release-manifest.sig)
├── schemas/
│   ├── release-manifest.schema.json
│   └── rootfs-manifest.schema.json
├── tests/                     # Test fixtures and test scripts
└── README.md
```

## Quick Start

### 1. Resolve dependencies for a package

```bash
python3 scripts/resolve-packages.py --graph parted --json
```

### 2. Build rootfs for one ABI

```bash
bash scripts/build-rootfs.sh arm64-v8a
```

### 3. Validate a bundle

```bash
python3 scripts/validate-rootfs.py \
  --bundle staging/arm64-v8a/fparted-rootfs-*.zip \
  --strict
```

### 4. Assemble release assets

```bash
python3 scripts/make-release-manifest.py \
  --bundle-dir staging/ \
  --toolchain-version 1.0.0 \
  --termux-commit 436ebf0f917285fe86659e9d4e43c0d257256f75 \
  --output-dir release-output
```

## ABI Mapping

| Android ABI | Termux Architecture |
| --- | --- |
| `arm64-v8a` | `aarch64` |
| `x86_64` | `x86_64` |

## Validation Gates

Every release bundle must pass:

1. **Manifest schema validation** — `schemas/release-manifest.schema.json` and `schemas/rootfs-manifest.schema.json`
2. **No path traversal / zip-slip** — all archive entries use relative, non-`..` paths
3. **No forbidden prefixes** — no `com.termux` or `/files/usr` paths in any entry
4. **Per-file SHA-256 hash verification** — matches `rootfs-manifest.json`
5. **ELF architecture check** — matches target ABI
6. **Required binary presence** — all binaries in `required-binaries.yaml` are present
7. **License/SBOM coverage** — `packages.spdx.json` included in release
8. **Forbidden prefix grep** — CI fails if standard Termux prefix appears in output

## Device Smoke Test (Manual, Out-of-Band)

Device validation is a **manual gate** performed by the maintainer outside CI: GitHub-hosted runners can never attach a rooted Android device, so the former `smoke-test` CI job was removed. After a release is published, validate the artifacts on a rooted Android device or an Android x86_64 emulator/VM connected via adb before announcing the release.

Artifacts needed (from the release):

- `fparted-rootfs-<version>-<abi>.zip` for the target ABI (`arm64-v8a` or `x86_64`)
- `rootfs-manifest.json`
- `release-manifest.json`
- `release-manifest.sig`
- `SHA256SUMS`

Procedure:

1. **Fetch** the release assets for the target ABI (`arm64-v8a` or `x86_64`).
2. **Verify integrity**:
   ```bash
   sha256sum -c SHA256SUMS
   ```
   (or compare each asset hash against `release-manifest.json`).
3. **Verify the manifest signature**:
   ```bash
   gpg --import keys/release-pubkey.asc
   gpg --verify release-manifest.sig release-manifest.json
   ```
4. **Inspect the bundle**: extract the zip to a scratch dir and confirm the rootfs layout under the prefix `data/data/vn.shadichy.parted/files` (`usr/bin`, `lib`, …) matches `rootfs-manifest.json`.
5. **Run on device**: push/extract the bundle onto the device via adb and run each of the 18 required binaries from `config/required-binaries.yaml` (`parted`, `blkid`, `dd`, `test`, `e2fsck`, `mke2fs`, `resize2fs`, `tune2fs`, `mkfs.fat`, `fsck.fat`, `fatlabel`, `mkfs.exfat`, `fsck.exfat`, `exfatlabel`, `mkfs.f2fs`, `fsck.f2fs`, `btrfs`, `mkfs.btrfs`), verifying each prints a version/usage line and exits non-zero properly when invoked incorrectly.
6. **Record** the device/VM image, Android version, ABI, and results in the release notes or PR.

## Repo A Interface with the App

The `fparted` app communicates with Repo A **only through versioned manifests**:

- `release-manifest.json` — declares assets per ABI, schema version, toolchain version, Termux commit, prefix, ABI mapping, required binaries, and SHA-256 hashes
- `rootfs-manifest.json` — describes each entry inside the bundle (path, type, mode, hash, symlink target, package owner)

The app verifies signature, schema, package ID, prefix, ABI, size, and every asset SHA-256 before extraction.
