# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=https://github.com/ntfsprogs-plus/ntfsprogs-plus
TERMUX_PKG_DESCRIPTION="NTFS filesystem utilities (ntfs-3g successor with extended attribute and POSIX ACL support)"
TERMUX_PKG_LICENSE="GPL-2.0-or-later"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=1.0.0
TERMUX_PKG_SRCURL=https://api.github.com/repos/ntfsprogs-plus/ntfsprogs-plus/tarball/refs/tags/${TERMUX_PKG_VERSION}
TERMUX_PKG_SHA256=28f24aa673a81bf84d339cd0842dc7afd571bfa5345b6554fe3760ed6a71e343
TERMUX_PKG_DEPENDS="libuuid, libgcrypt"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--disable-ldconfig
--enable-xattr-mappings
--enable-posix-acls
--bindir=$TERMUX_PREFIX/bin
--sbindir=$TERMUX_PREFIX/bin
--exec-prefix=$TERMUX_PREFIX
"

# NOTE on --exec-prefix: without it configure.ac sees exec_prefix=NONE and
# hardcodes rootbindir=/bin, rootsbindir=/sbin, rootlibdir=/lib*; libntfs'
# install-exec-hook then tries `mv $libdir/libntfs.so* -> //lib` under the
# DESTDIR staging and fails (CI run 32915299822). Setting exec-prefix selects
# the branch that maps all three to $(bindir)/$(sbindir)/$(libdir), making
# the hook's `-ef` same-directory guard skip the move. Upstream offers no
# --with-rootlibdir override; this is the supported knob.

termux_step_pre_configure() {
	# GitHub API tarballs ship no generated configure script.
	./autogen.sh
}

termux_step_post_make_install() {
	ln -sf ntfsck "$TERMUX_PREFIX/bin/ntfsfix"
}
