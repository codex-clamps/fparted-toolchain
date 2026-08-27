# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=https://bcachefs.org/
TERMUX_PKG_DESCRIPTION="BCachefs filesystem utilities (mkfs.bcachefs, fsck.bcachefs, mount.bcachefs)"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=1.3
TERMUX_PKG_SRCURL=https://github.com/koverstreet/bcachefs-tools/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=2e53f6864e89a44e9fff85d9588244b6cf742c9c98bade01276bc9c6fe41c2de
TERMUX_PKG_DEPENDS="libblkid, libuuid, liburcu, libsodium, zlib, liblz4, zstd, keyutils, libaio"
TERMUX_PKG_BUILD_IN_SRC=true

# v1.3 is the last C-only release; later versions require Rust/bindgen and
# libclang, which the pinned toolchain does not provide.
# The initramfs integration and FUSE variant are skipped (NO_BCACHEFS_FS).
termux_step_make() {
	make -j "$TERMUX_PKG_MAKE_PROCESSES" \
		CC="$CC" \
		NO_BCACHEFS_FS=1 \
		NO_RUST=1 \
		VERSION="v$TERMUX_PKG_VERSION"
}

termux_step_make_install() {
	install -Dm755 bcachefs "$TERMUX_PREFIX/bin/bcachefs"
	local link
	for link in mkfs.bcachefs fsck.bcachefs mount.bcachefs \
		mkfs.fuse.bcachefs fsck.fuse.bcachefs mount.fuse.bcachefs; do
		ln -sf bcachefs "$TERMUX_PREFIX/bin/$link"
	done
	install -Dm644 bcachefs.8 "$TERMUX_PREFIX/share/man/man8/bcachefs.8"
}

# bcachefs-tools-1.3-no-libudev.patch: PKGCONFIG_LIBS lists libudev although no
#   source file references udev; drop it so pkg-config does not fail.
# bcachefs-tools-1.3-atomic-set-return.patch: `return` of a void-valued
#   uatomic_set() do-statement breaks compilation with current liburcu.
# bcachefs-tools-1.3-glibc23-bsearch-macro.patch: #undef glibc's C23
#   const-generic bsearch macro so include/linux/bsearch.h compiles.
# bcachefs-tools-1.3-bionic-api24-compat.patch: Bionic API 24 compatibility fixes:
#   include_next chaining for types.h/wait.h/stat.h to avoid header collision with NDK,
#   aligned_alloc shim via memalign, and pointer-based byteorder macros.
