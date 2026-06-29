#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: c6300bd-sqfs-pack.sh [-f|--force] [ROOTFS_DIR] [OUTPUT_BIN]

Repack a fakeroot-extracted C6300BD SquashFS tree and restore the vendor
header fields expected by img2.bin:
  magic             hsqs -> shsq
  compression field lzma -> gzip

Defaults:
  ROOTFS_DIR        ./rootfs.fakeroot, or the directory passed to unpack
  OUTPUT_BIN        <directory-of-ROOTFS_DIR>/img2-patched.bin

The script expects the sidecar files written by c6300bd-sqfs-unpack.sh:
  ROOTFS_DIR.fakeroot.state
  ROOTFS_DIR.c6300bd-sqfs.env
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

force=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            force=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            usage
            die "unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -le 2 ]] || { usage; exit 2; }

need dd
need fakeroot
need mkfifo
need mksquashfs
need realpath

rootfs=${1:-rootfs.fakeroot}
rootfs=$(realpath -m "$rootfs")
[[ -d "$rootfs" ]] || die "rootfs directory not found: $rootfs"

meta="${rootfs}.c6300bd-sqfs.env"
if [[ -f "$meta" ]]; then
    # shellcheck source=/dev/null
    . "$meta"
fi

state=${FAKEROOT_STATE:-"${rootfs}.fakeroot.state"}
mkfs_time=${MKFS_TIME:-1401088145}
block_size=${BLOCK_SIZE:-65536}

[[ -f "$state" ]] || die "fakeroot state not found: $state; run c6300bd-sqfs-unpack.sh first"

rootfs_dir=$(dirname "$rootfs")
output=${2:-"$rootfs_dir/img2-patched.bin"}
output=$(realpath -m "$output")
tmp="${output}.standard.sqfs"

if [[ -e "$output" || -e "$tmp" ]]; then
    if [[ "$force" -ne 1 ]]; then
        die "output already exists; rerun with --force to replace: $output"
    fi
    rm -f -- "$output" "$tmp"
fi

# Keep /dev/initctl as FIFO in the fake metadata before packing.
if [[ -e "$rootfs/dev/initctl" ]]; then
    fakeroot -i "$state" -s "$state" -- sh -c '
        target=$1
        rm -f -- "$target"
        mkfifo -- "$target"
        chmod 0644 "$target"
        chown 0:0 "$target"
        touch -d "2014-05-26 17:08:00" "$target" 2>/dev/null || true
    ' sh "$rootfs/dev/initctl"
fi

fakeroot -i "$state" -s "$state" -- \
    mksquashfs "$rootfs" "$tmp" \
        -noappend \
        -comp lzma \
        -b "$block_size" \
        -mkfs-time "$mkfs_time" \
        -all-root

mv -- "$tmp" "$output"

# Restore the vendor header fields in the final img2 payload.
printf '\x73\x68\x73\x71' | dd of="$output" bs=1 seek=0 count=4 conv=notrunc status=none
printf '\x01\x00' | dd of="$output" bs=1 seek=$((0x14)) count=2 conv=notrunc status=none

echo "Wrote: $output"
echo "Restored vendor magic shsq and compression field 0x0001."
