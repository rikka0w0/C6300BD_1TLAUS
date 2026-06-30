#!/usr/bin/env python3
"""
Patch unpacked C6300BD eCos image so sub_8025CA04 initializes
byte_814FD43F to 1 instead of 0.

Expected IDA window, 11 MIPS big-endian instructions:
  0x8025CA18 .. 0x8025CA40

The target store cannot be changed to "store immediate 1" as a single MIPS
instruction. This patch uses $s2 as a temporary before the function first uses
it, then stores that byte into byte_814FD43F.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


MATCH_VA = 0x8025CA18

MATCH = bytes.fromhex(
    "3c 02 81 50"  # lui   $v0, 0x8150
    "24 50 d4 3c"  # addiu $s0, $v0, -0x2bc4
    "a0 40 d4 3c"  # sb    $zero, byte_814FD43C
    "a2 00 00 01"  # sb    $zero, 1($s0)
    "a2 00 00 02"  # sb    $zero, 2($s0)
    "a2 00 00 03"  # sb    $zero, 3($s0)
    "26 11 00 04"  # addiu $s1, $s0, 4
    "02 20 20 21"  # move  $a0, $s1
    "00 00 28 21"  # move  $a1, $zero
    "0c 2f 7c d5"  # jal   sub_80BDF354
    "24 06 00 10"  # li    $a2, 0x10
)

PATCHES = (
    {
        "va": 0x8025CA24,
        "old": bytes.fromhex("a2 00 00 01"),  # sb $zero, 1($s0)
        "new": bytes.fromhex("24 12 00 01"),  # li $s2, 1
        "note": "load 1 into $s2 scratch register",
    },
    {
        "va": 0x8025CA2C,
        "old": bytes.fromhex("a2 00 00 03"),  # sb $zero, 3($s0)
        "new": bytes.fromhex("a2 12 00 03"),  # sb $s2, 3($s0)
        "note": "store 1 into byte_814FD43F",
    },
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def find_all(data: bytes, needle: bytes) -> list[int]:
    offsets: list[int] = []
    start = 0
    while True:
        pos = data.find(needle, start)
        if pos < 0:
            return offsets
        offsets.append(pos)
        start = pos + 1


def default_output_path(input_path: Path) -> Path:
    if input_path.suffix:
        return input_path.with_name(f"{input_path.stem}.patched{input_path.suffix}")
    return input_path.with_name(f"{input_path.name}.patched")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch unpacked C6300BD eCos image: byte_814FD43F init 0 -> 1."
    )
    parser.add_argument("input", type=Path, help="unpacked eCos binary")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="patched output path; default is INPUT with .patched before suffix",
    )
    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="overwrite output if it already exists",
    )
    args = parser.parse_args()

    input_path = args.input
    output_path = args.output or default_output_path(input_path)

    if not input_path.is_file():
        raise SystemExit(f"input is not a file: {input_path}")
    if output_path.exists() and not args.force:
        raise SystemExit(f"output exists, use --force to overwrite: {output_path}")

    data = input_path.read_bytes()
    matches = find_all(data, MATCH)
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one 0x{MATCH_VA:x} instruction-window match, "
            f"found {len(matches)}"
        )

    match_off = matches[0]
    patched = bytearray(data)

    print(f"matched VA 0x{MATCH_VA:08x} at file offset 0x{match_off:x}")
    for patch in PATCHES:
        rel = patch["va"] - MATCH_VA
        file_off = match_off + rel
        old = patch["old"]
        new = patch["new"]
        current = bytes(patched[file_off : file_off + len(old)])
        if current != old:
            raise SystemExit(
                f"unexpected bytes at VA 0x{patch['va']:08x} "
                f"(file offset 0x{file_off:x}): got {current.hex()}, expected {old.hex()}"
            )
        patched[file_off : file_off + len(old)] = new
        print(
            f"patch VA 0x{patch['va']:08x} file+0x{file_off:x}: "
            f"{old.hex()} -> {new.hex()} ({patch['note']})"
        )

    output_path.write_bytes(patched)
    print(f"wrote {output_path}")
    print(f"input  sha256 {sha256(data)}")
    print(f"output sha256 {sha256(bytes(patched))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
