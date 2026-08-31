TERMUX_PKG_HOMEPAGE=https://developer.android.com/
TERMUX_PKG_DESCRIPTION="Android platform tools and LP utilities (lpdump, lpmake, lpunpack)"
TERMUX_PKG_LICENSE="Apache-2.0, BSD 2-Clause"
TERMUX_PKG_LICENSE_FILE="LICENSE, vendor/core/fastboot/LICENSE"
TERMUX_PKG_MAINTAINER="fparted <fparted@shadichy.vn>"
TERMUX_PKG_VERSION="36.0.1+really35.0.2"
TERMUX_PKG_SRCURL="https://github.com/nmeum/android-tools/releases/download/${TERMUX_PKG_VERSION#*really}/android-tools-${TERMUX_PKG_VERSION#*really}.tar.xz"
TERMUX_PKG_SHA256=d2c3222280315f36d8bfa5c02d7632b47e365bfe2e77e99a3564fb6576f04097
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="abseil-cpp, brotli, fmt, libc++, liblz4, libprotobuf, pcre2, zlib, zstd"
TERMUX_PKG_BUILD_DEPENDS="googletest"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DANDROID_TOOLS_USE_BUNDLED_LIBUSB=ON
-DANDROID_TOOLS_BUILD_LP_TOOLS=ON
"

termux_step_pre_configure() {
	termux_setup_protobuf
	termux_setup_golang

	LDFLAGS+=" $($TERMUX_SCRIPTDIR/packages/libprotobuf/interface_link_libraries.sh)"
}

termux_step_post_make_install() {
	# Install headers needed by lptools
	mkdir -p $TERMUX_PREFIX/include/android-tools/{base,lp,sparse,log,crypto_utils,cutils,utils,ext4_utils}
	cp -r $TERMUX_PKG_SRCDIR/vendor/core/base/include/* $TERMUX_PREFIX/include/android-tools/base/ || true
	cp -r $TERMUX_PKG_SRCDIR/vendor/core/fs_mgr/liblp/include/* $TERMUX_PREFIX/include/android-tools/lp/ || true
	cp -r $TERMUX_PKG_SRCDIR/vendor/core/libsparse/include/* $TERMUX_PREFIX/include/android-tools/sparse/ || true
	cp -r $TERMUX_PKG_SRCDIR/vendor/core/liblog/include/* $TERMUX_PREFIX/include/android-tools/log/ || true
	cp -r $TERMUX_PKG_SRCDIR/vendor/core/libcrypto_utils/include/* $TERMUX_PREFIX/include/android-tools/crypto_utils/ || true
	cp -r $TERMUX_PKG_SRCDIR/vendor/core/libcutils/include/* $TERMUX_PREFIX/include/android-tools/cutils/ || true
	cp -r $TERMUX_PKG_SRCDIR/vendor/core/libutils/include/* $TERMUX_PREFIX/include/android-tools/utils/ || true
	cp -r $TERMUX_PKG_SRCDIR/vendor/extras/ext4_utils/include/* $TERMUX_PREFIX/include/android-tools/ext4_utils/ || true

	# Install static libs needed by lptools
	find $TERMUX_PKG_BUILDDIR -name "libbase.a" -exec cp {} $TERMUX_PREFIX/lib/libandroid-base.a \;
	find $TERMUX_PKG_BUILDDIR -name "liblp.a" -exec cp {} $TERMUX_PREFIX/lib/libandroid-lp.a \;
	find $TERMUX_PKG_BUILDDIR -name "libsparse.a" -exec cp {} $TERMUX_PREFIX/lib/libandroid-sparse.a \;
	find $TERMUX_PKG_BUILDDIR -name "liblog.a" -exec cp {} $TERMUX_PREFIX/lib/libandroid-log.a \;
	find $TERMUX_PKG_BUILDDIR -name "libcrypto_utils.a" -exec cp {} $TERMUX_PREFIX/lib/libandroid-crypto_utils.a \;
	find $TERMUX_PKG_BUILDDIR -name "libcutils.a" -exec cp {} $TERMUX_PREFIX/lib/libandroid-cutils.a \;
	find $TERMUX_PKG_BUILDDIR -name "libutils.a" -exec cp {} $TERMUX_PREFIX/lib/libandroid-utils.a \;
	find $TERMUX_PKG_BUILDDIR -name "libext4_utils.a" -exec cp {} $TERMUX_PREFIX/lib/libandroid-ext4_utils.a \;
}
