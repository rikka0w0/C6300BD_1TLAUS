#!/usr/bin/env python3
"""
Patch the unpacked C6300BD eCos image so ip_hal/IpHal `dload` uses the
current command-table instance's IP stack number.

This patch targets IP Stack HAL Commands only:
  - command table constructor: 0x80443FC0, "IP Stack HAL Commands"
  - command name:              dload
  - handler/case:              sub_80444A0C, command id 4

It is not the DOCSIS `dload` path.

Original behavior calls sub_80445F80(), which scans IP stack 1..8 and chooses
the first DHCP/static-ready stack. The patch derives the stack number from the
current BcmEcosIpHalIf instance tag at +0x34 before the handler reuses $s1 for
a local stack object:

  IP StackN tag = 0x6970732f + N
  selectedStack = *(uint8_t *)(instance + 0x37) - 0x2f

After the patch, tftp download from LAN should work:
  /ip_hal/dload (4) -i 3 192.168.0.3  C6300BD_1TLAUS_K2630_PATCHED.bin
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


MATCH_VA = 0x80445180

ORIGINAL_MATCH = bytes.fromhex(
    "27 b1 00 18"  # addiu $s1, $sp, 0x18
    "0c 00 40 5a"  # jal   sub_80010168
    "02 20 20 21"  # move  $a0, $s1
    "24 14 00 02"  # li    $s4, 2
    "0c 11 17 e0"  # jal   sub_80445F80
    "27 a4 00 98"  # addiu $a0, $sp, 0x98
    "10 40 01 cd"  # beqz  $v0, loc_804458D0
    "02 20 20 21"  # move  $a0, $s1
    "8e 42 00 00"  # lw    $v0, 0($s2)
    "8c 42 00 28"  # lw    $v0, 0x28($v0)
)

OLD_BUGGY_MATCH = bytes.fromhex(
    "27 b1 00 18"  # addiu $s1, $sp, 0x18
    "0c 00 40 5a"  # jal   sub_80010168
    "02 20 20 21"  # move  $a0, $s1
    "24 14 00 02"  # li    $s4, 2
    "92 22 00 37"  # lbu   $v0, 0x37($s1)  ; wrong: $s1 is already local
    "24 42 ff d1"  # addiu $v0, $v0, -0x2f
    "10 40 01 cd"  # beqz  $v0, loc_804458D0
    "af a2 00 98"  # sw    $v0, 0x98($sp)
    "8e 42 00 00"  # lw    $v0, 0($s2)
    "8c 42 00 28"  # lw    $v0, 0x28($v0)
)

PATCHED_MATCH = bytes.fromhex(
    "92 22 00 37"  # lbu   $v0, 0x37($s1)
    "24 42 ff d1"  # addiu $v0, $v0, -0x2f
    "af a2 00 98"  # sw    $v0, 0x98($sp)
    "27 b1 00 18"  # addiu $s1, $sp, 0x18
    "0c 00 40 5a"  # jal   sub_80010168
    "02 20 20 21"  # move  $a0, $s1
    "24 14 00 02"  # li    $s4, 2
    "02 20 20 21"  # move  $a0, $s1
    "8e 42 00 00"  # lw    $v0, 0($s2)
    "8c 42 00 28"  # lw    $v0, 0x28($v0)
)

MATCHES = (
    ("original ip_hal dload window", ORIGINAL_MATCH),
    ("previous buggy ip_hal dload patch", OLD_BUGGY_MATCH),
    ("already patched ip_hal dload window", PATCHED_MATCH),
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
        return input_path.with_name(f"{input_path.stem}.iphal-dload-stack{input_path.suffix}")
    return input_path.with_name(f"{input_path.name}.iphal-dload-stack")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Patch unpacked C6300BD eCos image: make ip_hal dload use the "
            "current command instance's IP stack number."
        )
    )
    parser.add_argument("input", type=Path, help="unpacked eCos binary, e.g. /tmp/ecos-unlzma.bin")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="patched output path; default is INPUT with .iphal-dload-stack before suffix",
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
    found: list[tuple[str, int]] = []
    for label, pattern in MATCHES:
        for pos in find_all(data, pattern):
            found.append((label, pos))

    if len(found) != 1:
        raise SystemExit(
            f"expected exactly one ip_hal dload instruction-window match near "
            f"IDA VA 0x{MATCH_VA:08x}, found {len(found)}"
        )

    match_label, match_off = found[0]
    if match_label == "already patched ip_hal dload window":
        print(f"already patched: VA 0x{MATCH_VA:08x} at file offset 0x{match_off:x}")
        if output_path != input_path:
            output_path.write_bytes(data)
            print(f"wrote unchanged already-patched copy {output_path}")
        return 0

    patched = bytearray(data)

    print(f"matched {match_label} VA 0x{MATCH_VA:08x} at file offset 0x{match_off:x}")
    old = bytes(patched[match_off : match_off + len(PATCHED_MATCH)])
    patched[match_off : match_off + len(PATCHED_MATCH)] = PATCHED_MATCH
    print(f"patch VA 0x{MATCH_VA:08x} file+0x{match_off:x}:")
    print(f"  {old.hex()}")
    print(f"  ->")
    print(f"  {PATCHED_MATCH.hex()}")
    print("effect: selectedStack = current IP Stack instance number before $s1 is reused")

    output_path.write_bytes(patched)
    print(f"wrote {output_path}")
    print(f"input  sha256 {sha256(data)}")
    print(f"output sha256 {sha256(bytes(patched))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
