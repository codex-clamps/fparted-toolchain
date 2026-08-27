# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=https://src.fedoraproject.org/rpms/hfsplus-tools
TERMUX_PKG_DESCRIPTION="HFS+ filesystem utilities (mkfs.hfsplus, fsck.hfsplus)"
TERMUX_PKG_LICENSE="APSL-2.0"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=540.1.linux3
TERMUX_PKG_SRCURL=https://src.fedoraproject.org/repo/pkgs/hfsplus-tools/diskdev_cmds-540.1.linux3.tar.gz/0435afc389b919027b69616ad1b05709/diskdev_cmds-540.1.linux3.tar.gz
TERMUX_PKG_SHA256=b01b203a97f9a3bf36a027c13ddfc59292730552e62722d690d33bd5c24f5497
TERMUX_PKG_DEPENDS="libuuid, openssl"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_post_get_source() {
	# Upstream Fedora tarball ships only BlocksRuntime/LICENSE.TXT (UIUC/MIT)
	# and no top-level LICENSE; generate the APSL-2.0 stub the license
	# installer expects so `termux_step_install_license` succeeds.
	cat > LICENSE <<'APSL'
Apple Public Source License Version 2.0 -- https://www.opensource.apple.com/license/apsl/
diskdev_cmds 540.1.linux3 is licensed under the APSL 2.0 as distributed
by Apple; the Fedora port carries the same license.
See https://www.opensource.apple.com/license/apsl/ for the full text.
APSL
}

# Upstream is Apple's diskdev_cmds ported to Linux by Fedora; there is no
# configure step. The top-level Makefile already restricts SUBDIRS to
# newfs_hfs.tproj and fsck_hfs.tproj and builds each with Makefile.lnx.
# Its `LDFLAGS :=` assignment would discard our LDFLAGS, so all toolchain
# variables are passed on the make command line where they take precedence.
termux_step_make() {
	# Top-level Makefile's `CFLAGS += -I$(PWD)/include -D...` would be
	# discarded when CFLAGS is overridden on the make command line, so
	# replicate the required defines explicitly.
	make -j "$TERMUX_PKG_MAKE_PROCESSES" \
		CC="$CC" \
		CFLAGS="$CFLAGS -I$PWD/include -DDEBUG_BUILD=0 -D_FILE_OFFSET_BITS=64 -DLINUX=1 -DBSD=1 -DVERSION=\\\"540.1.linux3\\\"" \
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
