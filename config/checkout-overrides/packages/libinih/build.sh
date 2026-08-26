# shellcheck shell=bash disable=SC2034,SC2155
TERMUX_PKG_HOMEPAGE=https://github.com/benhoyt/inih
TERMUX_PKG_DESCRIPTION="A simple .INI file parser written in C"
TERMUX_PKG_LICENSE="BSD 3-Clause"
TERMUX_PKG_LICENSE_FILE="LICENSE.txt"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="62"
TERMUX_PKG_SRCURL=https://github.com/benhoyt/inih/archive/refs/tags/r${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=9c15fa751bb8093d042dae1b9f125eb45198c32c6704cd5481ccde460d4f8151
# Checkout override (see scripts/build-rootfs.sh step 2b): upstream r62 ships
# only a mixed-case LICENSE.txt, which termux_step_install_license's filename
# discovery never matches; without TERMUX_PKG_LICENSE_FILE the build aborts
# after a fully successful meson install.
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_UPDATE_VERSION_REGEXP="\d+"
TERMUX_PKG_DEPENDS="libc++"

termux_step_post_get_source() {
	# Do not forget to bump revision of reverse dependencies and rebuild them
	# after SOVERSION is changed.
	local _SOVERSION=0

	local v=$(sed -n "/library('inih'/,/)\s*$/p" meson.build | \
			sed -En "s/\s*soversion\s*:\s*'?([0-9]+).*/\1/p")
	if [ "${v}" != "${_SOVERSION}" ]; then
		termux_error_exit "SOVERSION guard check failed."
	fi
}
