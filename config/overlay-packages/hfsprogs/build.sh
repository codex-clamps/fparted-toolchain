# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=https://src.fedoraproject.org/rpms/hfsplus-tools
TERMUX_PKG_DESCRIPTION="HFS+ filesystem utilities (mkfs.hfsplus, fsck.hfsplus)"
TERMUX_PKG_LICENSE="APSL-2.0"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=540.1.linux3
TERMUX_PKG_SRCURL=https://src.fedoraproject.org/repo/pkgs/hfsplus-tools/diskdev_cmds-540.1.linux3.tar.gz/0435afc389b919027b69616ad1b05709/diskdev_cmds-540.1.linux3.tar.gz
TERMUX_PKG_SHA256=b01b203a97f9a3bf36a027c13ddfc59292730552e62722d690d33bd5c24f5497
TERMUX_PKG_DEPENDS="openssl"
TERMUX_PKG_BUILD_IN_SRC=true

# Upstream is Apple's diskdev_cmds ported to Linux by Fedora; there is no
# configure step. The top-level Makefile already restricts SUBDIRS to
# newfs_hfs.tproj and fsck_hfs.tproj and builds each with Makefile.lnx.
# Its `LDFLAGS :=` assignment would discard our LDFLAGS, so all toolchain
# variables are passed on the make command line where they take precedence.
termux_step_make() {
	make -j "$TERMUX_MAKE_PROCESSES" \
		CC="$CC" \
		CFLAGS="$CFLAGS" \
		LDFLAGS="$LDFLAGS -Wl,--build-id"
}

termux_step_make_install() {
	install -Dm755 -t "$TERMUX_PREFIX/bin" \
		newfs_hfs.tproj/newfs_hfs \
		fsck_hfs.tproj/fsck_hfs
	ln -sf mkfs.hfsplus "$TERMUX_PREFIX/bin/mkfs.hfs"
	ln -sf fsck.hfsplus "$TERMUX_PREFIX/bin/fsck.hfs"
}

# hfsplus-tools-no-blocks.patch: drop the Apple Blocks extension dependency.
# hfsplus-tools-learn-to-stdarg.patch: fix varargs misuse (breaks on ARM/Bionic).
# hfsplus-tools-sysctl.patch: use the Linux sysctl.h header.
