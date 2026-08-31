# shellcheck shell=bash disable=SC2034
TERMUX_PKG_HOMEPAGE="https://github.com/ssut/payload-dumper-go"
TERMUX_PKG_DESCRIPTION="Android and ChromeOS OTA payload.bin dumper and partition extractor (payload-dumper-go)"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="fparted <fparted@shadichy.vn>"
TERMUX_PKG_VERSION="1.3.0"
TERMUX_PKG_SRCURL="https://github.com/ssut/payload-dumper-go/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="d7ba33a80c539674c0b63443b8c6dd9c2040ec996323f38ffe72e024d302eb2d"
TERMUX_PKG_DEPENDS="xz-utils"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_make() {
	termux_setup_golang
	export CGO_ENABLED=1
	export CGO_CFLAGS="-I$TERMUX_PREFIX/include"
	export CGO_LDFLAGS="-L$TERMUX_PREFIX/lib"

	go mod download

	local gozstd_dir
	gozstd_dir=$(go list -m -f '{{.Dir}}' github.com/valyala/gozstd 2>/dev/null || true)
	if [ -n "$gozstd_dir" ] && [ -d "$gozstd_dir" ]; then
		chmod -R u+w "$gozstd_dir"
		(
			cd "$gozstd_dir"
			ZSTD_LEGACY_SUPPORT=0 make -C zstd/lib CC="$CC" AR="$AR" CFLAGS="-O3 -fPIC" clean libzstd.a
			cp zstd/lib/libzstd.a libzstd_linux_amd64.a
			cp zstd/lib/libzstd.a libzstd_linux_arm64.a
			cp zstd/lib/libzstd.a libzstd_linux_arm.a
		)
	fi

	go build -ldflags="-s -w" -o "$TERMUX_PREFIX/bin/payload-dumper-go"
}

termux_step_make_install() {
	chmod 700 "$TERMUX_PREFIX/bin/payload-dumper-go"
}
