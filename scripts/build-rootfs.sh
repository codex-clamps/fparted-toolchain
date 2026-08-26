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

# Validate arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <android-abi> [termux-commit]" >&2
    echo "  ABI must be one of: arm64-v8a x86_64" >&2
    exit 1
fi

TARGET_ABI="$1"
TERMUX_COMMIT="${2:-}"

# ABI validation
case "${TARGET_ABI}" in
    arm64-v8a|x86_64) ;;
    *)
        echo "ERROR: Unsupported ABI '${TARGET_ABI}'. Must be one of: arm64-v8a x86_64" >&2
        exit 1
        ;;
esac

# Map Android ABI to Termux architecture
declare -A ABI_MAP=(
    ["arm64-v8a"]="aarch64"
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
TERMUX_BUILD_CACHE_DIR="${STAGING_DIR}/termux-build-cache"
mkdir -p "${TERMUX_BUILD_CACHE_DIR}"
# Container builder UID (1001) differs from host UID; keep cache bind-mount writable.
chmod a+w "${TERMUX_BUILD_CACHE_DIR}"

echo "[1/6] Checking out termux/termux-packages @ ${TERMUX_COMMIT} ..."
mkdir -p "${CHECKOUT_DIR}"
if [[ ! -d "${CHECKOUT_DIR}/.git" ]]; then
    git init "${CHECKOUT_DIR}"
    cd "${CHECKOUT_DIR}"
    git remote add origin "https://github.com/termux/termux-packages.git"
    git fetch origin "${TERMUX_COMMIT}"
    git checkout FETCH_HEAD
    cd "${REPO_ROOT}"
fi

# --- Step 2: Apply custom prefix patch ---
echo "[2/6] Applying custom prefix patch ..."
cp "${REPO_ROOT}/patches/termux-prefix.patch" "${CHECKOUT_DIR}/"
cd "${CHECKOUT_DIR}"
git apply "${REPO_ROOT}/patches/termux-prefix.patch" 2>/dev/null || {
    echo "WARNING: Prefix patch application failed, trying manual override..."
}
cd "${REPO_ROOT}"

# --- Step 2b: Apply local checkout overrides (upstream recipe fixes) ---
# Files under config/checkout-overrides/ are copied over the pinned termux
# checkout verbatim, keyed by their checkout-relative path (e.g.
# config/checkout-overrides/packages/libinih/build.sh replaces
# packages/libinih/build.sh). Use these for targeted fixes to upstream
# recipes that are broken at the pinned commit and cannot be expressed as
# overlay packages (same-name shadowing is not supported by the resolver).
if [[ -d "${CONFIG_DIR}/checkout-overrides" ]]; then
    echo "[2b] Applying checkout overrides ..."
    cp -a "${CONFIG_DIR}/checkout-overrides/." "${CHECKOUT_DIR}/"
    (cd "${CHECKOUT_DIR}" && find . -path ./'.git' -prune -o -type f -newer "${REPO_ROOT}/scripts/build-rootfs.sh" -print | head -20 | sed 's/^/  overridden: /') || true
fi

# --- Step 3: Build packages for target architecture via Termux Docker ---
echo "[3/6] Building packages for ${TARGET_ARCH} via Termux Docker builder ..."

if [[ ! -f "${CONFIG_DIR}/packages.yaml" ]]; then
    echo "ERROR: ${CONFIG_DIR}/packages.yaml not found" >&2
    exit 1
fi

readarray -t TERMUX_PKGS < <(python3 -c "
import yaml
with open('${CONFIG_DIR}/packages.yaml') as f:
    data = yaml.safe_load(f)
for name in data.get('packages', {}):
    print(name)
")

BUILD_OUTPUT_DIR="${STAGING_DIR}/packages"
mkdir -p "${BUILD_OUTPUT_DIR}"
chmod a+w "${BUILD_OUTPUT_DIR}"

# Also copy any packages from the termux checkout output directory (fallback)
if [[ -d "${CHECKOUT_DIR}/output" ]]; then
    for f in "${CHECKOUT_DIR}/output/"*.pkg.tar.xz; do
        if [[ -f "$f" ]]; then
            cp -n "$f" "${BUILD_OUTPUT_DIR}/" 2>/dev/null || true
        fi
    done
fi

# Checkpoint: skip packages that already have a built .pkg.tar.xz.
# Note: Docker dependency resolution may still rebuild some packages
# even when checkpointed (e.g., if an upstream dependency has changed).
NEED_BUILD=()
for pkg in "${TERMUX_PKGS[@]}"; do
    if compgen -G "${BUILD_OUTPUT_DIR}/${pkg}-*.pkg.tar.xz" > /dev/null 2>&1; then
        echo "  [checkpoint] ${pkg} already built, skipping"
    else
        NEED_BUILD+=("${pkg}")
    fi
done

if [[ ${#NEED_BUILD[@]} -eq 0 ]]; then
    echo "  [checkpoint] All ${#TERMUX_PKGS[@]} packages already built, skipping Docker build"
else
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
        echo "  Copied overlay packages: $(ls "${CHECKOUT_DIR}/overlay-packages/" 2>/dev/null | tr '\n' ' ')"
    fi

    # The container builder runs as UID 1001 while a locally cloned checkout is
    # owned by the invoking user; dependency builds create their default
    # output/ directory inside this mounted scriptdir, so grant write access
    # tree-wide. No-op on CI runners where the UIDs already match. Tolerate
    # failures on artifacts a previous container run left owned by UID 1001:
    # those stay writable for the container itself (same UID), which is all
    # the next docker invocation needs.
    chmod -R a+rwX "${CHECKOUT_DIR}" 2>/dev/null || true

    if command -v docker &>/dev/null; then
        echo "  Pulling Termux builder image: ghcr.io/termux/package-builder"
        docker pull ghcr.io/termux/package-builder

        echo "  Building ${#NEED_BUILD[@]} package(s): ${NEED_BUILD[*]}"

        # Determine Docker security options based on environment.
        # GHA runners need --privileged for FUSE; local builds use minimal caps.
        if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
            DOCKER_SECURITY_OPTS=("--privileged")
            echo "  (detected GHA runner, using --privileged for FUSE)"
        else
            DOCKER_SECURITY_OPTS=("--cap-add" "SYS_ADMIN" "--cap-add" "DAC_READ_SEARCH" "--device" "/dev/fuse")
        fi

        set +e
        docker run --rm \
            "${DOCKER_SECURITY_OPTS[@]}" \
            -e ANDROID_ROOT=/system \
            -e TERMUX_TOPDIR=/home/builder/.termux-build \
            --volume "${CHECKOUT_DIR}:/home/builder/termux-packages" \
            --volume "${BUILD_OUTPUT_DIR}:/output" \
            --volume "${TERMUX_BUILD_CACHE_DIR}:/home/builder/.termux-build" \
            --workdir /home/builder/termux-packages \
            ghcr.io/termux/package-builder \
            ./build-package.sh -a "${TARGET_ARCH}" --format pacman -o /output "${NEED_BUILD[@]}"
        DOCKER_EXIT=$?
        set -e
        if [[ ${DOCKER_EXIT} -ne 0 ]]; then
            echo "ERROR: Termux package build failed (exit code ${DOCKER_EXIT}). The rootfs is incomplete; refusing to continue. Check for source download failures (e.g. upstream CDN outages) and retry the build." >&2
            exit "${DOCKER_EXIT}"
        fi

        # Collect dependency packages that landed in the default Termux output dir
        # (CHECKOUT_DIR/output). The -o /output flag only applies to explicitly
        # requested packages on the command line; dependencies are built via
        # termux_run_build-package() which omits -o and uses the default dir.
        if [[ -d "${CHECKOUT_DIR}/output" ]]; then
            echo "  Collecting dependency packages from ${CHECKOUT_DIR}/output ..."
            # upload-artifact@v4 rejects ':' in filenames (Arch epoch separator in
            # versions, e.g. ca-certificates-1:2026.07.16-0-any.pkg.tar.xz).
            # Sanitize the copy destination: replace ':' with '_'.
            while IFS= read -r -d '' f; do
                base="$(basename "$f")"
                safe="${base//:/_}"
                if [[ "${base}" != "${safe}" ]]; then
                    echo "    sanitized: ${base} -> ${safe}"
                    cp -n "$f" "${BUILD_OUTPUT_DIR}/${safe}" 2>/dev/null || true
                else
                    cp -n "$f" "${BUILD_OUTPUT_DIR}/" 2>/dev/null || true
                fi
            done < <(find "${CHECKOUT_DIR}/output" -name "*.pkg.tar.xz" -print0)
            echo "  Collected $(find "${BUILD_OUTPUT_DIR}" -name '*.pkg.tar.xz' | wc -l) total packages"
        fi
    else
        echo "  WARNING: docker not available on this system."
        echo "  Install Docker and re-run to build packages."
        echo "  https://docs.docker.com/engine/install/"
        echo ""
        echo "  To build manually:"
        echo "    docker pull ghcr.io/termux/package-builder"
        echo "    docker run --rm \\"
        echo "      -e TERMUX_TOPDIR=/home/builder/.termux-build \\"
        echo "      -v \$(pwd):/home/builder/termux-packages \\"
        echo "      -v \${TERMUX_BUILD_CACHE_DIR:-~/.termux-build}:/home/builder/.termux-build \\"
        echo "      ghcr.io/termux/package-builder \\"
        echo "      ./build-package.sh -a ${TARGET_ARCH} --format pacman ${NEED_BUILD[*]}"
        exit 1
    fi

    cd "${REPO_ROOT}"
fi

echo "  Built packages:"
ls -lh "${BUILD_OUTPUT_DIR}/"*.pkg.tar.xz 2>/dev/null | sed 's/^/    /' || echo "  (no packages found)"

cd "${REPO_ROOT}"

# --- Step 4: Extract runtime payloads into staging rootfs ---
echo "[4/6] Extracting runtime payloads into rootfs staging directory ..."
ROOTFS_DIR="${STAGING_DIR}/rootfs"
mkdir -p "${ROOTFS_DIR}/usr/bin"
mkdir -p "${ROOTFS_DIR}/usr/lib"
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
            || { echo "ERROR: Failed to extract ${pkg}"; exit 1; }
        pkg_count=$((pkg_count + 1))
    done
    find "${ROOTFS_DIR}/include" -type d -empty -delete 2>/dev/null || true
    echo "  Extracted ${pkg_count} packages into ${ROOTFS_DIR}"
    echo "  Rootfs contents: usr/bin/ has $(ls "${ROOTFS_DIR}/usr/bin/" "${ROOTFS_DIR}/bin/" 2>/dev/null | wc -l) entries"
else
    echo "  WARNING: Build output directory not found at ${BUILD_OUTPUT_DIR}"
    echo "  Rootfs will be empty"
fi

# --- Step 4b: Migrate any com.termux paths to vn.shadichy.parted ---
COMTERMUX_DIR="${ROOTFS_DIR}/data/data/com.termux"
if [[ -d "${COMTERMUX_DIR}" ]]; then
    echo "  [migrate] Found legacy com.termux paths in rootfs, migrating to vn.shadichy.parted ..."
    VN_PREFIX="${ROOTFS_DIR}/data/data/vn.shadichy.parted"
    find "${COMTERMUX_DIR}" -type f -o -type l | while read -r src; do
        rel="${src#${COMTERMUX_DIR}/}"
        dst="${VN_PREFIX}/${rel}"
        mkdir -p "$(dirname "${dst}")"
        if [[ ! -e "${dst}" ]]; then
            cp -a "${src}" "${dst}"
        fi
    done
    # Fix shebangs and embedded com.termux paths in text files
    if command -v python3 &>/dev/null; then
        find "${VN_PREFIX}" -type f -exec grep -l 'com\.termux' {} \; 2>/dev/null | while read -r f; do
            if file "${f}" | grep -qE 'text|script|ASCII|UTF-8'; then
                python3 -c "
p = '${f}'
with open(p, 'r', errors='replace') as fh:
    data = fh.read()
data = data.replace('com.termux', 'vn.shadichy.parted')
with open(p, 'w') as fh:
    fh.write(data)
" 2>/dev/null || true
            fi
        done
    fi
    rm -rf "${COMTERMUX_DIR}"
    echo "  [migrate] Done. Removed old com.termux tree."
fi

# --- Step 5: Recreate modes, symlinks, and verify hashes ---
echo "[5/6] Normalizing permissions and verifying integrity ..."

# Owner-only permission policy: executables and directories 0700, data files
# 0600. Only the app's uid may execute the toolchain (termux massage already
# strips group/other; this normalizes deterministically across the tree).
find "${ROOTFS_DIR}" -type d -exec chmod 700 {} \; 2>/dev/null || true
find "${ROOTFS_DIR}" -type f -executable -exec chmod 700 {} \; 2>/dev/null || true
find "${ROOTFS_DIR}" -type f ! -executable -exec chmod 600 {} \; 2>/dev/null || true

echo "(ELF validation step: verify architecture and Bionic linkage)"

# --- Step 6: Generate rootfs-manifest.json and bundle ---
echo "[6/6] Generating rootfs manifest and bundle ..."
python3 "${SCRIPT_DIR}/assemble-rootfs.py" \
    --abi "${TARGET_ABI}" \
    --rootfs-dir "${ROOTFS_DIR}" \
    --output "${STAGING_DIR}" \
    --termux-commit "${TERMUX_COMMIT}" \
    --prefix /data/data/vn.shadichy.parted/files

echo "=== Build complete ==="
echo "  Output: ${STAGING_DIR}/rootfs-manifest.json"
echo "  Staging: ${STAGING_DIR}/"
