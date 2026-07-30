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

	python3 -c "
import re, sys

f = open('$TERMUX_PKG_SRCDIR/lib/libf2fs.c', 'r')
content = f.read()
f.close()

# 1. Add <sys/sysmacros.h> for major()/minor() on Bionic
if '#include <sys/sysmacros.h>' not in content:
	content = '#include <sys/sysmacros.h>\n' + content

# 2. Replace hasmntopt() calls with disabled code (Bionic compat)
#    Following Android's approach from android-tools patch: #if 0
content = content.replace(
	'if (hasmntopt(mnt, MNTOPT_RO))',
	'#if 0\n\t\t\tif (hasmntopt(mnt, MNTOPT_RO))'
)
# Close the #if 0 block after the hasmntopt usage line(s)
content = content.replace(
	'c.ro = 1;',
	'c.ro = 1;\n#endif'
)

# 3. setmntent/getmntent/endmntent are available via <mntent.h>
#    in the Termux NDK toolchain. No need to strip the include.

f = open('$TERMUX_PKG_SRCDIR/lib/libf2fs.c', 'w')
f.write(content)
f.close()
" || {
	echo "ERROR: Failed to patch libf2fs.c for Bionic compatibility" >&2
	exit 1
}
}
