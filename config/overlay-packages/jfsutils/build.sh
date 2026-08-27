# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=http://jfs.sourceforge.net/
TERMUX_PKG_DESCRIPTION="IBM Journaling File System utilities (mkfs.jfs, fsck.jfs)"
TERMUX_PKG_LICENSE="GPL-3.0-or-later"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=1.1.15
TERMUX_PKG_SRCURL=https://jfs.sourceforge.net/project/pub/jfsutils-1.1.15.tar.gz
TERMUX_PKG_SHA256=244a15f64015ce3ea17e49bdf6e1a0fb4f9af92b82fa9e05aa64cb30b5f07a4d
TERMUX_PKG_DEPENDS="libuuid"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="--bindir=$TERMUX_PREFIX/bin --sbindir=$TERMUX_PREFIX/bin"

# jfsutils-1.1.15-sysmacros.patch: glibc >= 2.28 and Bionic moved major()/minor()
#   out of <sys/types.h>; include <sys/sysmacros.h> on Linux.
# jfsutils-1.1.15-stdint.patch: libfs/devices.h uses uint types without including <stdint.h>.
# jfsutils-1.1.15-gcc10_fix-1.patch: -fno-common default in GCC >= 10 (BLFS).
# jfsutils-1.1.15-mntent-bionic.patch: Bionic declares hasmntopt() only from API 26
#   and lacks glibc's _PATH_MNTTAB; comma-token scan + fallback define.

termux_step_post_make_install() {
	# Upstream's install rules create the fsck.jfs/mkfs.jfs alias man pages as
	# hard links to jfs_fsck.8/jfs_mkfs.8, and termux's man-page compression
	# refuses multi-link files ("has 1 other link -- file ignored"), failing the
	# build. Break the man-page hard links into independent copies first.
	local man_file
	for man_file in "$TERMUX_PREFIX"/share/man/man8/*.8; do
		if [ -f "$man_file" ] && [ "$(stat -c %h "$man_file")" -gt 1 ]; then
			cp -f "$man_file" "$man_file.dedup" && mv -f "$man_file.dedup" "$man_file"
		fi
	done
}
