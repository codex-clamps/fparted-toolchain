# shellcheck shell=bash disable=SC2034
TERMUX_PKG_HOMEPAGE="https://github.com/phhusson/vendor_lptools"
TERMUX_PKG_DESCRIPTION="Live dynamic partition manipulation tool for Android (lptools)"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="fparted <fparted@shadichy.vn>"
TERMUX_PKG_VERSION="1.0.0.20240101"
_COMMIT="c8be7de57b80eab61a6f94ec86464a01fb9056f2"
TERMUX_PKG_SRCURL="https://github.com/phhusson/vendor_lptools/archive/${_COMMIT}.tar.gz"
TERMUX_PKG_SHA256="c1052860187359ce89dd5efeaf096c37c008e4431269fddd59d735b1566fc797"
TERMUX_PKG_DEPENDS="libandroid-support, zlib"

TERMUX_PKG_BUILD_DEPENDS="android-tools"

termux_step_pre_configure() {
	cp $TERMUX_PKG_BUILDER_DIR/src/CMakeLists.txt $TERMUX_PKG_SRCDIR/
}
