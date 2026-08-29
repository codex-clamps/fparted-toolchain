TERMUX_PKG_HOMEPAGE="https://github.com/mhx/dwarfs"
TERMUX_PKG_DESCRIPTION="Fast, high compression read-only file system (mkdwarfs, dwarfs, dwarfsck, dwarfsextract)"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="fparted <fparted@shadichy.vn>"
TERMUX_PKG_VERSION="0.9.9.20240829"
_COMMIT="9062b57f51de5b61505319ef29ef2f5e4a128fc2"
TERMUX_PKG_SRCURL="https://github.com/mhx/dwarfs/archive/${_COMMIT}.tar.gz"
TERMUX_PKG_SHA256="5124de2d5b8394050af8d362e484e13444e55018856cd689f3af4c5cb2a177ba"
TERMUX_PKG_DEPENDS="boost, libarchive, liblz4, xxhash, zstd, brotli, xz-utils, openssl, libfuse3, utf8cpp, nlohmann-json"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DNIXPKGS_DWARFS_VERSION_OVERRIDE=v0.9.9
-DWITH_LIBDWARFS=ON
-DWITH_TOOLS=ON
-DWITH_FUSE_DRIVER=ON
-DWITH_TESTS=OFF
-DWITH_BENCHMARKS=OFF
-DWITH_MAN_PAGES=OFF
-DWITH_MAN_OPTION=OFF
-DENABLE_STACKTRACE=OFF
-DUSE_JEMALLOC=OFF
-DUSE_MIMALLOC=OFF
-DDISABLE_MOLD=ON
-DDISABLE_CCACHE=ON
"

termux_step_pre_configure() {
	tar -xJf /output/boost-headers-*.pkg.tar.xz -C / --anchored --exclude=.{BUILDINFO,PKGINFO,MTREE,INSTALL} --force-local --no-overwrite-dir || echo "Failed to extract boost headers"
	CPPFLAGS+=" -I$TERMUX_PREFIX/include -I$TERMUX_PREFIX/include/utf8cpp"
	CXXFLAGS+=" -I$TERMUX_PREFIX/include -I$TERMUX_PREFIX/include/utf8cpp"
}
