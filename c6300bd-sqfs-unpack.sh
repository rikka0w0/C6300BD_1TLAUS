#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: c6300bd-sqfs-unpack.sh [-f|--force] IMG2_BIN [OUTDIR]

Patch the C6300BD vendor SquashFS header in IMG2_BIN to a standard SquashFS
header, then extract it through fakeroot.

Defaults:
  OUTDIR                 <directory-of-IMG2_BIN>/rootfs.fakeroot
  fakeroot state file    OUTDIR.fakeroot.state
  fixed SquashFS copy    OUTDIR.fixed.sqfs
  metadata sidecar       OUTDIR.c6300bd-sqfs.env
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

[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 2; }

need cp
need dd
need fakeroot
need mkfifo
need realpath
need unsquashfs

input=$(realpath "$1")
[[ -f "$input" ]] || die "input file not found: $input"

input_dir=$(dirname "$input")
outdir=${2:-"$input_dir/rootfs.fakeroot"}
outdir=$(realpath -m "$outdir")
state="${outdir}.fakeroot.state"
fixed="${outdir}.fixed.sqfs"
meta="${outdir}.c6300bd-sqfs.env"

case "$outdir" in
    /|"")
        die "refusing unsafe output directory: $outdir"
        ;;
esac

if [[ -e "$outdir" || -e "$state" || -e "$fixed" || -e "$meta" ]]; then
    if [[ "$force" -ne 1 ]]; then
        die "output already exists; rerun with --force to replace: $outdir"
    fi
    rm -rf -- "$outdir" "$state" "$fixed" "$meta"
fi

magic=$(dd if="$input" bs=1 count=4 status=none | od -An -tx1 | tr -d ' \n')
case "$magic" in
    73687371|68737173)
        ;;
    *)
        die "unexpected SquashFS magic 0x$magic; expected vendor shsq or standard hsqs"
        ;;
esac

cp -- "$input" "$fixed"

# Vendor image uses magic "shsq" and declares gzip.  The payload is standard
# little-endian SquashFS with LZMA blocks, so convert the copy for unsquashfs.
printf '\x68\x73\x71\x73' | dd of="$fixed" bs=1 seek=0 count=4 conv=notrunc status=none
printf '\x02\x00' | dd of="$fixed" bs=1 seek=$((0x14)) count=2 conv=notrunc status=none

mkfs_time=$(unsquashfs -mkfs-time "$fixed")
block_size=$(unsquashfs -s "$fixed" | awk '/^Block size / {print $3; exit}')
[[ -n "$block_size" ]] || die "could not determine SquashFS block size"

fakeroot -s "$state" -- unsquashfs -d "$outdir" "$fixed"

# fakeroot records device nodes correctly, but on this image the FIFO may be
# represented as a regular empty file in the fake state.  Force it back.
if unsquashfs -lls "$fixed" 2>/dev/null | awk '$1 ~ /^p/ && $NF == "squashfs-root/dev/initctl" { found = 1 } END { exit found ? 0 : 1 }'; then
    fakeroot -i "$state" -s "$state" -- sh -c '
        target=$1
        rm -f -- "$target"
        mkfifo -- "$target"
        chmod 0644 "$target"
        chown 0:0 "$target"
        touch -d "2014-05-26 17:08:00" "$target" 2>/dev/null || true
    ' sh "$outdir/dev/initctl"
fi

{
    printf 'SOURCE=%q\n' "$input"
    printf 'OUTDIR=%q\n' "$outdir"
    printf 'FAKEROOT_STATE=%q\n' "$state"
    printf 'FIXED_SQFS=%q\n' "$fixed"
    printf 'MKFS_TIME=%q\n' "$mkfs_time"
    printf 'BLOCK_SIZE=%q\n' "$block_size"
} > "$meta"

echo "Extracted to: $outdir"
echo "fakeroot state: $state"
echo "fixed SquashFS copy: $fixed"
echo "metadata: $meta"
echo
echo "Edit files under $outdir, then run:"
echo "  c6300bd-sqfs-pack.sh $outdir"
