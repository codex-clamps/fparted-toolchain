# shellcheck shell=bash disable=SC2034
TERMUX_PKG_HOMEPAGE="https://github.com/topjohnwu/Magisk"
TERMUX_PKG_DESCRIPTION="Android boot image unpacking, repacking, and hexpatching tool (magiskboot)"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="fparted <fparted@shadichy.vn>"
TERMUX_PKG_VERSION="27.0"
_COMMIT="5bdf354924ec984df6d84f88baad7adabef594a9"
TERMUX_PKG_SRCURL="https://github.com/topjohnwu/Magisk/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="3a26a5d03602720322aaf764783d2acbaad8c2f070dec3f57b9113a699136a14"
TERMUX_PKG_DEPENDS="liblzma, liblz4, zlib, bzip2"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_pre_configure() {
	termux_setup_rust
	cargo install cxxbridge-cmd
}

termux_step_make() {
	cd $TERMUX_PKG_SRCDIR/native/src
	
	cargo build --release --target $CARGO_TARGET_NAME --package magiskboot
	
	cd boot
	cxxbridge lib.rs > boot-rs.cpp
	cxxbridge lib.rs --header > boot-rs.hpp
	cd ..
	
	CXX_FLAGS="$CXXFLAGS $CPPFLAGS -Ibase/include -Icore/include -Iexternal/compat/include -std=c++17 -Wall"
	
	# libbase
	for src in base/logging.cpp base/misc.cpp base/xwrap.cpp base/files.cpp base/cpio.cpp base/selinux.cpp base/wrapper.cpp base/Vector.cpp; do
		$CXX $CXX_FLAGS -c $src -o ${src}.o
	done
	
	# libcompat
	$CXX $CXX_FLAGS -c external/compat/compat.cpp -o external/compat/compat.o
	
	# magiskboot
	for src in boot/main.cpp boot/bootimg.cpp boot/compress.cpp boot/format.cpp boot/boot-rs.cpp; do
		$CXX $CXX_FLAGS -c $src -o ${src}.o
	done
	
	$CXX $CXXFLAGS $LDFLAGS boot/*.o base/*.o external/compat/*.o \
		target/$CARGO_TARGET_NAME/release/libmagiskboot.a \
		-llzma -llz4 -lbz2 -lz -o magiskboot
}

termux_step_make_install() {
	install -Dm755 $TERMUX_PKG_SRCDIR/native/src/magiskboot $TERMUX_PREFIX/bin/magiskboot
}
