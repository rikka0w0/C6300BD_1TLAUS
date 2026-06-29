#!/usr/bin/env python3
import sys
from pathlib import Path


def main() -> int:
    in_path = Path(sys.argv[1]) if len(sys.argv) >= 2 else Path("img1.bin")
    out_path = Path(sys.argv[2]) if len(sys.argv) >= 3 else Path("img1-patched.bin")

    pattern = bytes.fromhex(
        "ac a0 00 08 "
        "8c 83 01 90 "
        "93 a4 00 63 "
        "24 02 04 00 "
        "00 04 10 0a "
        "00 74 18 21 "
        "ac 62 00 18"
    )
    patched = bytes.fromhex(
        "ac a0 00 08 "
        "8c 83 01 90 "
        "93 a4 00 63 "
        "24 02 00 00 "
        "00 04 10 0a "
        "00 74 18 21 "
        "ac 62 00 18"
    )

    data = in_path.read_bytes()

    hits = []
    pos = data.find(pattern)
    while pos != -1:
        hits.append(pos)
        pos = data.find(pattern, pos + 1)

    if len(hits) != 1:
        print(f"error: expected exactly one match, found {len(hits)}", file=sys.stderr)
        for hit in hits[:16]:
            print(f"match at file offset 0x{hit:x}", file=sys.stderr)
        return 1

    hit = hits[0]
    data = data[:hit] + patched + data[hit + len(pattern):]
    out_path.write_bytes(data)

    print(f"patched {in_path} -> {out_path}")
    print(f"match offset: 0x{hit:x}")
    print(f"changed instruction offset: 0x{hit + 12:x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
