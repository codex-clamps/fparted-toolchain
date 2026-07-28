TERMUX_PKG_HOMEPAGE=https://github.com/jaegeuk/f2fs-tools
TERMUX_PKG_DESCRIPTION="F2FS (Flash Friendly File System) userspace utilities"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@fparted"
TERMUX_PKG_VERSION=1.9.0
TERMUX_PKG_SRCURL=https://github.com/jaegeuk/f2fs-tools/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=77217562ae7011a6d81b7b3c43c42623db1796a57596408d6c8037def70d6cc7
TERMUX_PKG_DEPENDS="libblkid, zlib, liblzma"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="--enable-libf2fs"

termux_step_pre_configure() {
	autoreconf -fiv
}
