# shellcheck shell=bash disable=SC2034  # Termux recipe format: variables are consumed by the sourced build library.
TERMUX_PKG_HOMEPAGE=https://github.com/eafer/apfsprogs
TERMUX_PKG_DESCRIPTION="APFS filesystem utilities (mkfs.apfs, fsck.apfs, apfs-label, apfs-snap)"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="Shadichy <shadichy@blisslabs.org>"
TERMUX_PKG_VERSION=0.2.1
TERMUX_PKG_SRCURL=https://github.com/eafer/apfsprogs/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=92cf4beaf0a34182a2ad02a4babf2235c5ae88c819fda22eeca64dc77bb30a52
TERMUX_PKG_BUILD_IN_SRC=true

# No configure system: each program lives in its own directory with a private
# Makefile and links against ../lib/libapfs.a built on first use.
termux_step_make() {
	local d
	for d in mkapfs apfsck apfs-label apfs-snap; do
		make -j "$TERMUX_PKG_MAKE_PROCESSES" -C "$d" \
			CC="$CC" \
			CFLAGS="$CFLAGS" \
			LDFLAGS="$LDFLAGS" \
			GIT_COMMIT="$TERMUX_PKG_VERSION"
	done
}

# Each Makefile's install target honours DESTDIR/BINDIR/MANDIR and already
# creates the mkfs.apfs / fsck.apfs compatibility symlinks.
termux_step_make_install() {
	local d
	for d in mkapfs apfsck apfs-label apfs-snap; do
		make -C "$d" install \
			DESTDIR="$TERMUX_PREFIX" \
			BINDIR="/bin" \
			MANDIR="/share/man/man8"
	done
}
