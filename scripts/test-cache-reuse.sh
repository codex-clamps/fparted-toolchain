#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_ARCH="x86_64"
TARGET_ABI="x86_64"
STAGING_DIR="${REPO_ROOT}/staging/${TARGET_ABI}"
CHECKOUT_DIR="${STAGING_DIR}/termux-checkout"
BUILD_OUTPUT_DIR="${STAGING_DIR}/packages"
TERMUX_BUILD_CACHE_DIR="${STAGING_DIR}/termux-build-cache"

echo "=== Test 1: Clean build of 'm4' ==="
rm -rf "${TERMUX_BUILD_CACHE_DIR}"
mkdir -p "${TERMUX_BUILD_CACHE_DIR}"
chmod a+w "${TERMUX_BUILD_CACHE_DIR}"

if [[ ! -d "${CHECKOUT_DIR}" ]]; then
    echo "Please run build-rootfs.sh first to clone the checkout!"
    exit 1
fi

docker run --rm \
    --cap-add SYS_ADMIN --cap-add DAC_READ_SEARCH --device /dev/fuse \
    -e ANDROID_ROOT=/system \
    -e TERMUX_TOPDIR=/home/builder/.termux-build \
    --volume "${CHECKOUT_DIR}:/home/builder/termux-packages" \
    --volume "${BUILD_OUTPUT_DIR}:/output" \
    --volume "${TERMUX_BUILD_CACHE_DIR}:/home/builder/.termux-build" \
    --workdir /home/builder/termux-packages \
    ghcr.io/termux/package-builder \
    ./build-package.sh -a "${TARGET_ARCH}" --format pacman -o /output m4

echo ""
echo "=== Test 2: Build a package that depends on 'm4' (e.g. autoconf) with cache intact ==="
echo "You should see 'Found locally built dependency m4' and it extracting instead of building."
docker run --rm \
    --cap-add SYS_ADMIN --cap-add DAC_READ_SEARCH --device /dev/fuse \
    -e ANDROID_ROOT=/system \
    -e TERMUX_TOPDIR=/home/builder/.termux-build \
    --volume "${CHECKOUT_DIR}:/home/builder/termux-packages" \
    --volume "${BUILD_OUTPUT_DIR}:/output" \
    --volume "${TERMUX_BUILD_CACHE_DIR}:/home/builder/.termux-build" \
    --workdir /home/builder/termux-packages \
    ghcr.io/termux/package-builder \
    ./build-package.sh -a "${TARGET_ARCH}" --format pacman -o /output autoconf

echo ""
echo "=== Test 3: Wipe .built-packages cache, but keep /output packages intact ==="
echo "This simulates a fresh container build or wiped cache, but existing .pkg.tar.xz files in /output."
rm -rf "${TERMUX_BUILD_CACHE_DIR}"
mkdir -p "${TERMUX_BUILD_CACHE_DIR}"
chmod a+w "${TERMUX_BUILD_CACHE_DIR}"

docker run --rm \
    --cap-add SYS_ADMIN --cap-add DAC_READ_SEARCH --device /dev/fuse \
    -e ANDROID_ROOT=/system \
    -e TERMUX_TOPDIR=/home/builder/.termux-build \
    --volume "${CHECKOUT_DIR}:/home/builder/termux-packages" \
    --volume "${BUILD_OUTPUT_DIR}:/output" \
    --volume "${TERMUX_BUILD_CACHE_DIR}:/home/builder/.termux-build" \
    --workdir /home/builder/termux-packages \
    ghcr.io/termux/package-builder \
    ./build-package.sh -a "${TARGET_ARCH}" --format pacman -o /output autoconf

echo ""
echo "Tests finished. If Test 3 finished very quickly and skipped rebuilding m4 and autoconf, the mechanism works!"
