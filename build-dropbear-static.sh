#!/usr/bin/env bash
set -euo pipefail

: "${DROPBEAR_VERSION:=2025.88}"
: "${TOOLCHAIN_DIR:=/home/rikka/mcp/openwrt/staging_dir/toolchain-mips_mips32_gcc-14.3.0_musl}"
: "${CROSS_PREFIX:=mips-openwrt-linux}"
: "${TARGET:=${CROSS_PREFIX}}"
: "${PROGRAMS:=dropbear dbclient dropbearkey dropbearconvert scp}"
: "${CFLAGS:=-Os -fno-pie -mips32 -EB -Wno-undef}"
: "${LDFLAGS:=-static -no-pie}"
: "${CPPFLAGS:=-DDROPBEAR_X11FWD -DDROPBEAR_ALLOW_RO_BSDPTY=1}"
: "${STRIP_BINARY:=1}"
: "${DISABLE_LOGIN_RECORDS:=1}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
toolchain_bin="${TOOLCHAIN_DIR}/bin"

: "${BUILD_ROOT:=${script_dir}/build}"
: "${DOWNLOAD_DIR:=${script_dir}/downloads}"
: "${OUTPUT_DIR:=${script_dir}/out}"
: "${OUTPUT:=${OUTPUT_DIR}/dropbearmulti}"
: "${JOBS:=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
: "${STAGING_DIR:=$(dirname "${TOOLCHAIN_DIR}")}"

export PATH="${toolchain_bin}:${PATH}"
export STAGING_DIR
export CC="${CC:-${toolchain_bin}/${CROSS_PREFIX}-gcc}"
export AR="${AR:-${toolchain_bin}/${CROSS_PREFIX}-ar}"
export RANLIB="${RANLIB:-${toolchain_bin}/${CROSS_PREFIX}-ranlib}"
export STRIP="${STRIP:-${toolchain_bin}/${CROSS_PREFIX}-strip}"
export READELF="${READELF:-${toolchain_bin}/${CROSS_PREFIX}-readelf}"

dropbear_tar="dropbear-${DROPBEAR_VERSION}.tar.bz2"
dropbear_url="https://matt.ucc.asn.au/dropbear/releases/${dropbear_tar}"
tar_path="${DOWNLOAD_DIR}/${dropbear_tar}"
src_dir="${BUILD_ROOT}/dropbear-${DROPBEAR_VERSION}"

download() {
	if command -v curl >/dev/null 2>&1; then
		curl -fL --retry 3 -o "$tar_path" "$dropbear_url"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$tar_path" "$dropbear_url"
	else
		printf 'error: curl or wget is required to download %s\n' "$dropbear_url" >&2
		exit 1
	fi
}

require_tool() {
	if ! command -v "$1" >/dev/null 2>&1; then
		printf 'error: required tool not found: %s\n' "$1" >&2
		exit 1
	fi
}

mkdir -p "$BUILD_ROOT" "$DOWNLOAD_DIR" "$OUTPUT_DIR"

require_tool "$CC"
require_tool "$AR"
require_tool "$RANLIB"
require_tool "$STRIP"
require_tool "$READELF"
require_tool make
require_tool mktemp
require_tool patch
require_tool tar

if [ ! -s "$tar_path" ]; then
	printf 'Downloading %s\n' "$dropbear_url"
	download
fi

printf 'Preparing %s\n' "$src_dir"
rm -rf "$src_dir"
tar -C "$BUILD_ROOT" -xf "$tar_path"

cd "$src_dir"

printf 'Applying read-only BSD PTY compatibility patch\n'
patch -p1 < "${script_dir}/dropbear-2025.88-ro-bsd-pty.patch"

printf 'Configuring Dropbear %s for %s\n' "$DROPBEAR_VERSION" "$TARGET"
configure_flags=(
	--host="$TARGET"
	--disable-pam
	--disable-zlib
	--enable-bundled-libtom
	--enable-static
	--disable-openpty
)

if [ "$DISABLE_LOGIN_RECORDS" = "1" ]; then
	configure_flags+=(
		--disable-lastlog
		--disable-utmp
		--disable-utmpx
		--disable-wtmp
		--disable-wtmpx
		--disable-pututline
		--disable-pututxline
	)
fi

env \
	CC="$CC" \
	AR="$AR" \
	RANLIB="$RANLIB" \
	STRIP="$STRIP" \
	CFLAGS="$CFLAGS" \
	LDFLAGS="$LDFLAGS" \
	CPPFLAGS="$CPPFLAGS" \
	./configure "${configure_flags[@]}"

printf 'Building multicall binary: %s\n' "$PROGRAMS"
make -s -j "$JOBS" PROGRAMS="$PROGRAMS" MULTI=1 ARFLAGS=rc

cp dropbearmulti "$OUTPUT"
if [ "$STRIP_BINARY" = "1" ]; then
	"$STRIP" "$OUTPUT"
fi

for program in $PROGRAMS; do
	ln -sfn "$(basename "$OUTPUT")" "${OUTPUT_DIR}/${program}"
done

printf '\nBuilt %s\n' "$OUTPUT"
if command -v file >/dev/null 2>&1; then
	file "$OUTPUT"
fi
"$READELF" -h "$OUTPUT" | sed -n '/Class:/p;/Data:/p;/Machine:/p;/Flags:/p'
readelf_dynamic="$(mktemp)"
"$READELF" -d "$OUTPUT" >"$readelf_dynamic" 2>&1 || true
cat "$readelf_dynamic"
rm -f "$readelf_dynamic"

printf '\nPTY config:\n'
grep -E 'HAVE_OPENPTY|USE_DEV_PTMX|HAVE__GETPTY|HAVE_DEV_PTS_AND_PTC' config.h
