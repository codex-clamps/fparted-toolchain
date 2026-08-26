# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=https://xfs.wiki.kernel.org/
TERMUX_PKG_DESCRIPTION="XFS filesystem utilities (mkfs.xfs, xfs_repair, xfs_admin, xfs_growfs)"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=7.1.1
TERMUX_PKG_SRCURL=https://www.kernel.org/pub/linux/utils/fs/xfs/xfsprogs/xfsprogs-${TERMUX_PKG_VERSION}.tar.xz
TERMUX_PKG_SHA256=063edc31ba8e85c95c7faf9be465a04898bba7c6e622fdd9b146eed4ca5415e8
TERMUX_PKG_DEPENDS="libblkid, libinih, liburcu, libuuid"
# xfsprogs' generated Makefiles live only in the source tree: configure does
# not emit build-dir Makefiles for out-of-tree builds, so a default Termux
# out-of-tree build runs `make` in a directory with no Makefile and the
# package assembles empty ("No files in package"). Building in-source keeps
# make/install operating on the real tree, matching upstream's supported mode.
TERMUX_PKG_BUILD_IN_SRC=true
# xfsprogs' builddefs substitutes only @CFLAGS@ into its Makefiles and drops
# CPPFLAGS entirely, so the sysroot -isystem paths termux places in CPPFLAGS
# never reach any compile line ("urcu.h"/"uuid/uuid.h" not found). Fold
# CPPFLAGS into CFLAGS before configure so builddefs captures them.
termux_step_pre_configure() {
	CFLAGS+=" ${CPPFLAGS}"
	CXXFLAGS+=" ${CPPFLAGS}"
}

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--enable-gettext=no
--enable-editline=no
--enable-libicu=no
--bindir=$TERMUX_PREFIX/bin
--sbindir=$TERMUX_PREFIX/bin
"

# NLS, editline history, and ICU name scanning are non-essential for a
# partition-management toolchain and are disabled to keep the dependency
# closure minimal. libuuid stays enabled for UUID handling in mkfs.xfs.
#
# xfsprogs 7.x configure aborts with FATAL ERROR unless blkid, ini.h
# (libinih) and urcu.h (liburcu) headers are found, so all three are
# declared as hard dependencies alongside libuuid.

# xfsprogs' install rules use absolute PKG_SBIN_DIR/PKG_LIB_DIR paths from
# include/builddefs (all derived from --prefix), so the default
# termux_step_make_install `make install` populates the real prefix and the
# packager harvests it; no DIST_ROOT staging override is needed.
