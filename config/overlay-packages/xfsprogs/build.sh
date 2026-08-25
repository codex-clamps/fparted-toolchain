# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=https://xfs.wiki.kernel.org/
TERMUX_PKG_DESCRIPTION="XFS filesystem utilities (mkfs.xfs, xfs_repair, xfs_admin, xfs_growfs)"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=7.1.1
TERMUX_PKG_SRCURL=https://www.kernel.org/pub/linux/utils/fs/xfs/xfsprogs/xfsprogs-${TERMUX_PKG_VERSION}.tar.xz
TERMUX_PKG_SHA256=063edc31ba8e85c95c7faf9be465a04898bba7c6e622fdd9b146eed4ca5415e8
TERMUX_PKG_DEPENDS="libuuid"
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
