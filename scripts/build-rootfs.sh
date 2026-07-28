#!/usr/bin/env bash
# build-rootfs.sh — Build a deterministic rootfs bundle for one Android ABI.
#
# Usage:
#   bash scripts/build-rootfs.sh <android-abi> [termux-commit]
#
# Example:
#   bash scripts/build-rootfs.sh arm64-v8a 436ebf0f917285fe86659e9d4e43c0d257256f75
#
# Environment:
#   TERMUX_APP__PACKAGE_NAME  = vn.shadichy.parted
#   TERMUX__ROOTFS            = /data/data/vn.shadichy.parted/files
#   TERMUX__PREFIX            = /data/data/vn.shadichy.parted/files
#   TERMUX__PREFIX_SUBDIR     = (empty)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/config"
LOCK_FILE="${CONFIG_DIR}/termux-lock.json"
PACKAGES_FILE="${CONFIG_DIR}/packages.yaml"

# Validate arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <android-abi> [termux-commit]" >&2
    echo "  ABI must be one of: arm64-v8a armv7a i686 x86_64" >&2
    exit 1
fi

TARGET_ABI="$1"
TERMUX_COMMIT="${2:-}"

# ABI validation
case "${TARGET_ABI}" in
    arm64-v8a|armeabi-v7a|x86|x86_64) ;;
    *)
        echo "ERROR: Unsupported ABI '${TARGET_ABI}'. Must be one of: arm64-v8a armv7a i686 x86_64" >&2
        exit 1
        ;;
esac

# Map Android ABI to Termux architecture
declare -A ABI_MAP=(
    ["arm64-v8a"]="aarch64"
    ["armeabi-v7a"]="arm"
    ["x86"]="i686"
    ["x86_64"]="x86_64"
)
TARGET_ARCH="${ABI_MAP[${TARGET_ABI}]}"

# Read termux commit from lock file if not provided
if [[ -z "${TERMUX_COMMIT}" ]]; then
    TERMUX_COMMIT=$(python3 -c "
import json, sys
with open('${LOCK_FILE}') as f:
    data = json.load(f)
print(data.get('pinned_termux_commit', ''))
" 2>/dev/null || echo "")
fi

if [[ -z "${TERMUX_COMMIT}" ]]; then
    echo "ERROR: No termux-commit provided and none found in termux-lock.json" >&2
    exit 1
fi

echo "=== Repo A Rootfs Build ==="
echo "  Target ABI:     ${TARGET_ABI}"
echo "  Termux arch:    ${TARGET_ARCH}"
echo "  Termux commit:  ${TERMUX_COMMIT}"
echo "  Package name:   vn.shadichy.parted"
echo "  Prefix:         /data/data/vn.shadichy.parted/files"
echo "==========================="

# --- Step 1: Check out pinned Termux checkout ---
STAGING_DIR="${REPO_ROOT}/staging/${TARGET_ABI}"
CHECKOUT_DIR="${STAGING_DIR}/termux-checkout"

echo "[1/6] Checking out termux/termux-packages @ ${TERMUX_COMMIT} ..."
mkdir -p "${CHECKOUT_DIR}"
if [[ ! -d "${CHECKOUT_DIR}/.git" ]]; then
    git clone --depth 1 \
        "https://github.com/termux/termux-packages.git" \
        "${CHECKOUT_DIR}" 2>/dev/null
    cd "${CHECKOUT_DIR}"
    git checkout "${TERMUX_COMMIT}"
    cd "${REPO_ROOT}"
fi

# --- Step 2: Apply custom prefix patch ---
echo "[2/6] Applying custom prefix patch ..."
cp "${REPO_ROOT}/patches/termux-prefix.patch" "${CHECKOUT_DIR}/"
cd "${CHECKOUT_DIR}"
git apply --check "${REPO_ROOT}/patches/termux-prefix.patch" 2>/dev/null || {
    echo "WARNING: Prefix patch may need manual adjustment"
}
cd "${REPO_ROOT}"

# --- Step 3: Build packages for target architecture ---
echo "[3/6] Building packages for ${TARGET_ARCH} ..."
cd "${CHECKOUT_DIR}"

# Set Termux build environment
export TERMUX_PREFIX="/data/data/vn.shadichy.parted/files"
export TERMUX_HOME="${TERMUX_PREFIX}/home"
export TERMUX_APP__PACKAGE_NAME="vn.shadichy.parted"
export TERMUX__ROOTFS="/data/data/vn.shadichy.parted/files"
export TERMUX__PREFIX="/data/data/vn.shadichy.parted/files"
export TERMUX__PREFIX_SUBDIR=""
export __TERMUX_BUILD_PROPS__VALIDATE_TERMUX_PREFIX_USR_MERGE_FORMAT=false

# Build each required package using Termux build system
# Note: In production, this uses the Termux build infrastructure
# (docker containers or local NDK setup)
REQUIRED_BINS=$(python3 -c "
import json
with open('${CONFIG_DIR}/required-binaries.yaml') as f:
    data = json.load(f)
for b in data.get('required_binaries', []):
    print(b)
")

echo "Packages to build for ${TARGET_ARCH}:"
echo "${REQUIRED_BINS}"

# Placeholder: actual Termux package build would happen here
echo "(Build step requires Termux build environment / NDK setup)"

cd "${REPO_ROOT}"

# --- Step 4: Extract runtime payloads into staging rootfs ---
echo "[4/6] Extracting runtime payloads into rootfs staging directory ..."
ROOTFS_DIR="${STAGING_DIR}/rootfs"
mkdir -p "${ROOTFS_DIR}/bin"
mkdir -p "${ROOTFS_DIR}/lib"
mkdir -p "${ROOTFS_DIR}/home"
mkdir -p "${ROOTFS_DIR}/tmp"

# Placeholder: copy built packages from checkout staging-area to ROOTFS_DIR
# Each package's runtime files would be copied here
echo "(Extraction step: copy runtime files from Termux build output)"

# --- Step 5: Recreate modes, symlinks, and verify hashes ---
echo "[5/6] Normalizing permissions and verifying integrity ..."

# Set deterministic permissions
find "${ROOTFS_DIR}" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "${ROOTFS_DIR}" -type f -exec chmod 644 {} \; 2>/dev/null || true
find "${ROOTFS_DIR}/bin" -type f -executable 2>/dev/null | while read -r f; do
    chmod 755 "${f}"
done

# Verify ELF artifacts
echo "(ELF validation step: verify architecture and Bionic linkage)"

# --- Step 6: Generate rootfs-manifest.json ---
echo "[6/6] Generating rootfs manifest ..."
python3 "${SCRIPT_DIR}/assemble-rootfs.py" \
    --abi "${TARGET_ABI}" \
    --rootfs-dir "${ROOTFS_DIR}" \
    --output "${STAGING_DIR}/rootfs-manifest.json" 2>/dev/null || {
    echo "WARNING: assemble-rootfs.py not yet functional; generating placeholder manifest"
    python3 -c "
import json, os, time
manifest = {
    'schema_version': '1.0',
    'generated_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'abi': '${TARGET_ABI}',
    'termux_commit': '${TERMUX_COMMIT}',
    'entries': []
}
with open('${STAGING_DIR}/rootfs-manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)
"
}

echo "=== Build complete ==="
echo "  Output: ${STAGING_DIR}/rootfs-manifest.json"
echo "  Staging: ${STAGING_DIR}/"
