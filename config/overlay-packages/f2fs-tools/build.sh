# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=https://git.kernel.org/pub/scm/linux/kernel/git/jaegeuk/f2fs-tools.git/about/
TERMUX_PKG_DESCRIPTION="Tools for the Flash-Friendly File System (F2FS)"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=1.16.0
TERMUX_PKG_SRCURL=https://git.kernel.org/pub/scm/linux/kernel/git/jaegeuk/f2fs-tools.git/snapshot/f2fs-tools-1.16.0.tar.gz
TERMUX_PKG_SHA256=208c7a07e95383fbd7b466b5681590789dcb41f41bf197369c41a95383b57c5e
TERMUX_PKG_DEPENDS="libuuid, libblkid"
# --without-selinux: keep ambient detection deterministic. Termux's
# libandroid-selinux (pulled in by coreutils) installs selinux/android.h into
# the shared prefix, but configure.ac checks that header unconditionally and
# the guarded sload.c block would then require AOSP-private headers. The
# sload-android-guard patch additionally pins those includes behind
# WITH_ANDROID, which autotools builds never define.
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="--bindir=$TERMUX_PREFIX/bin --sbindir=$TERMUX_PREFIX/bin --without-selinux"

termux_step_pre_configure() {
	# Kernel.org cgit snapshots ship no generated configure script.
	./autogen.sh
}
