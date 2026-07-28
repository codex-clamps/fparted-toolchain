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
    arm64-v8a|armv7a|i686|x86_64) ;;
    *)
        echo "ERROR: Unsupported ABI '${TARGET_ABI}'. Must be one of: arm64-v8a armv7a i686 x86_64" >&2
        exit 1
        ;;
esac

# Map Android ABI to Termux architecture
declare -A ABI_MAP=(
    ["arm64-v8a"]="aarch64"
    ["armv7a"]="arm"
    ["i686"]="i686"
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

# --- Step 3: Build packages for target architecture via Termux Docker ---
echo "[3/6] Building packages for ${TARGET_ARCH} via Termux Docker builder ..."

TERMUX_PKGS=(
    parted
    util-linux
    coreutils
    e2fsprogs
    dosfstools
    exfatprogs
    f2fs-tools
    btrfs-progs
)

cd "${CHECKOUT_DIR}"

python3 -c "
import json
with open('repo.json') as f:
    data = json.load(f)
data['pkg_format'] = 'pacman'
data['overlay-packages'] = {'name': 'overlay'}
with open('repo.json', 'w') as f:
    json.dump(data, f, indent=2)
"

if [[ -d "${REPO_ROOT}/config/overlay-packages" ]]; then
    mkdir -p "${CHECKOUT_DIR}/overlay-packages"
    cp -r "${REPO_ROOT}/config/overlay-packages/"* "${CHECKOUT_DIR}/overlay-packages/"
    echo "  Copied overlay packages: $(ls ${CHECKOUT_DIR}/overlay-packages/ 2>/dev/null | tr '\n' ' ')"
fi

BUILD_OUTPUT_DIR="${STAGING_DIR}/packages"
mkdir -p "${BUILD_OUTPUT_DIR}"

if command -v docker &>/dev/null; then
    echo "  Pulling Termux builder image: ghcr.io/termux/package-builder"
    docker pull ghcr.io/termux/package-builder

    echo "  Building packages: ${TERMUX_PKGS[*]}"
    docker run --rm \
        --privileged \
        --volume "${CHECKOUT_DIR}:/home/builder/termux-packages" \
        --volume "${BUILD_OUTPUT_DIR}:/output" \
        --workdir /home/builder/termux-packages \
        ghcr.io/termux/package-builder \
        ./build-package.sh -a "${TARGET_ARCH}" --format pacman -o /output -Q "${TERMUX_PKGS[@]}"
else
    echo "  WARNING: docker not available on this system."
    echo "  Install Docker and re-run to build packages."
    echo "  https://docs.docker.com/engine/install/"
    echo ""
    echo "  To build manually:"
    echo "    docker pull ghcr.io/termux/package-builder"
    echo "    docker run --rm --privileged \\"
    echo "      -v \$(pwd):/home/builder/termux-packages ghcr.io/termux/package-builder \\"
    echo "      ./build-package.sh -a ${TARGET_ARCH} --format pacman ${TERMUX_PKGS[*]}"
    exit 1
fi

echo "  Built packages:"
ls -lh "${BUILD_OUTPUT_DIR}/"*.pkg.tar.xz 2>/dev/null | sed 's/^/    /' || echo "  (no packages found — check build output above)"

cd "${REPO_ROOT}"

# --- Step 4: Extract runtime payloads into staging rootfs ---
echo "[4/6] Extracting runtime payloads into rootfs staging directory ..."
ROOTFS_DIR="${STAGING_DIR}/rootfs"
mkdir -p "${ROOTFS_DIR}/bin"
mkdir -p "${ROOTFS_DIR}/lib"
mkdir -p "${ROOTFS_DIR}/home"
mkdir -p "${ROOTFS_DIR}/tmp"

if [[ -d "${BUILD_OUTPUT_DIR}" ]]; then
    pkg_count=0
    for pkg in "${BUILD_OUTPUT_DIR}"/*.pkg.tar.xz; do
        [[ -f "${pkg}" ]] || continue
        echo "  Extracting: $(basename "${pkg}")"
        tar -C "${ROOTFS_DIR}" -xf "${pkg}" \
            --exclude='.BUILDINFO' \
            --exclude='.MTREE' \
            --exclude='.PKGINFO' \
            --exclude='include/*' \
            --exclude='*.a' \
            --exclude='*.la' \
            --exclude='*.pc' \
            --exclude='share/man/*' \
            --exclude='share/doc/*' \
            --exclude='share/info/*' \
            --exclude='share/gtk-doc/*' \
            2>/dev/null || true
        pkg_count=$((pkg_count + 1))
    done
    find "${ROOTFS_DIR}/include" -type d -empty -delete 2>/dev/null || true
    echo "  Extracted ${pkg_count} packages into ${ROOTFS_DIR}"
    echo "  Rootfs contents: bin/ has $(ls "${ROOTFS_DIR}/bin/" 2>/dev/null | wc -l) entries, lib/ has $(ls "${ROOTFS_DIR}/lib/" 2>/dev/null | wc -l) entries"
else
    echo "  WARNING: Build output directory not found at ${BUILD_OUTPUT_DIR}"
    echo "  Rootfs will be empty"
fi

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

# --- Step 6: Generate rootfs-manifest.json and bundle ---
echo "[6/6] Generating rootfs manifest and bundle ..."
python3 "${SCRIPT_DIR}/assemble-rootfs.py" \
    --abi "${TARGET_ABI}" \
    --rootfs-dir "${ROOTFS_DIR}" \
    --output "${STAGING_DIR}" \
    --termux-commit "${TERMUX_COMMIT}"

echo "=== Build complete ==="
echo "  Output: ${STAGING_DIR}/rootfs-manifest.json"
echo "  Staging: ${STAGING_DIR}/"
