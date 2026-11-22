#!/usr/bin/env python3
"""Print the pixel dimensions of a PNG as WIDTHxHEIGHT.

Used by the build/check scripts so icon dimensions can be verified without
Pillow or ImageMagick. Exits non-zero on a missing/short/non-PNG file.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    if data[12:16] != b"IHDR":
        raise ValueError("missing IHDR chunk")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} FILE.png", file=sys.stderr)
        return 2
    try:
        width, height = png_size(Path(sys.argv[1]))
    except (OSError, ValueError) as exc:
        print(f"{sys.argv[1]}: {exc}", file=sys.stderr)
        return 1
    print(f"{width}x{height}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
