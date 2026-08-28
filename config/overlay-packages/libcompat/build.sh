TERMUX_PKG_HOMEPAGE="https://github.com/ag-sdc/libcompat"
TERMUX_PKG_DESCRIPTION="Compatibility library for Bionic libc"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="fparted <fparted@shadichy.vn>"
TERMUX_PKG_VERSION="0.1.7"
TERMUX_PKG_SRCURL="https://github.com/ag-sdc/libcompat/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="5d097dd2dbe1786d455a1ec0b012c684264922f1ac72fb17068cd5ceff07c65b"
TERMUX_PKG_AUTO_UPDATE=false

termux_step_post_make_install() {
	mkdir -p "$TERMUX_PREFIX/lib/pkgconfig"
	cat <<- PC_EOF > "$TERMUX_PREFIX/lib/pkgconfig/libcompat.pc"
prefix=$TERMUX_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libcompat
Description: Compatibility library for Bionic libc
Version: $TERMUX_PKG_VERSION
Libs: -L\${libdir} -lcompat
Cflags: -I\${includedir}
PC_EOF
}
