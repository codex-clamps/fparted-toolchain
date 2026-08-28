TERMUX_PKG_HOMEPAGE="https://openzfs.github.io/openzfs-docs/"
TERMUX_PKG_DESCRIPTION="OpenZFS userland command line tools (zfs, zpool, zdb)"
TERMUX_PKG_LICENSE="CDDL-1.0"
TERMUX_PKG_LICENSE_FILE="LICENSE, COPYRIGHT"
TERMUX_PKG_MAINTAINER="fparted <fparted@shadichy.vn>"
TERMUX_PKG_VERSION="2.2.6"
TERMUX_PKG_SRCURL="https://github.com/openzfs/zfs/releases/download/zfs-${TERMUX_PKG_VERSION}/zfs-${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="c92e02103ac5dd77bf01d7209eabdca55c7b3356aa747bb2357ec4222652a2a7"

TERMUX_PKG_DEPENDS="util-linux, openssl, zlib, libtirpc, libcurl, libcompat"

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--with-config=user
--without-udev
--without-udevdir
--disable-systemd
--disable-sysvinit
--disable-pyzfs
--without-pam
--disable-nls
--without-python
--without-dracut
--without-initramfs
--without-selinux
--disable-debug
--sbindir=$TERMUX_PREFIX/bin
--with-mounthelperdir=$TERMUX_PREFIX/bin
--with-zfsexecdir=$TERMUX_PREFIX/libexec/zfs
"

termux_step_pre_configure() {
	export CFLAGS="$CFLAGS -I$TERMUX_PREFIX/include/tirpc -I$TERMUX_PREFIX/include -D_GNU_SOURCE"
	export CPPFLAGS="$CPPFLAGS -I$TERMUX_PREFIX/include/tirpc -I$TERMUX_PREFIX/include -D_GNU_SOURCE"
	export LDFLAGS="$LDFLAGS -ltirpc -lcompat"
	autoreconf -fi
}

termux_step_post_make_install() {
	rm -rf "$TERMUX_PREFIX/lib/modules"
	rm -rf "$TERMUX_PREFIX/share/zfs"
	rm -rf "$TERMUX_PREFIX/etc/zfs"
}
