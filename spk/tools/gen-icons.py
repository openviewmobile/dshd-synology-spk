#!/usr/bin/env python3
"""Generate the DSHD package icons.

Pure Python (stdlib only) so the assets can be reproduced on any machine
without Pillow or ImageMagick:

    python3 spk/tools/gen-icons.py

The design is a dark rounded-square terminal tile with a cyan prompt and a
green caret, plus a small stacked-layers motif for the NAS/container context.
It is rendered at 4x and box-filtered down for clean edges.
"""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

SUPERSAMPLE = 4
DESIGN = 256.0


class Canvas:
    def __init__(self, size: int) -> None:
        self.size = size
        self.data = bytearray(size * size * 4)

    def _blend(self, index: int, color: tuple[int, int, int, int]) -> None:
        r, g, b, a = color
        if a == 0:
            return
        d = self.data
        if a == 255:
            d[index] = r
            d[index + 1] = g
            d[index + 2] = b
            d[index + 3] = 255
            return
        sa = a / 255.0
        da = d[index + 3] / 255.0
        oa = sa + da * (1.0 - sa)
        if oa <= 0:
            return
        d[index] = int(round((r * sa + d[index] * da * (1.0 - sa)) / oa))
        d[index + 1] = int(round((g * sa + d[index + 1] * da * (1.0 - sa)) / oa))
        d[index + 2] = int(round((b * sa + d[index + 2] * da * (1.0 - sa)) / oa))
        d[index + 3] = int(round(oa * 255))

    def span(self, y: int, xa: float, xb: float, color: tuple[int, int, int, int]) -> None:
        if y < 0 or y >= self.size:
            return
        start = max(0, int(math.floor(xa)))
        end = min(self.size, int(math.ceil(xb)))
        base = y * self.size * 4
        for x in range(start, end):
            self._blend(base + x * 4, color)

    def circle(self, cx: float, cy: float, radius: float, color: tuple[int, int, int, int]) -> None:
        r2 = radius * radius
        for y in range(max(0, int(cy - radius)), min(self.size, int(cy + radius) + 1)):
            dy = y + 0.5 - cy
            if abs(dy) > radius:
                continue
            dx = math.sqrt(max(0.0, r2 - dy * dy))
            self.span(y, cx - dx, cx + dx, color)

    def rounded_rect(
        self,
        x0: float,
        y0: float,
        x1: float,
        y1: float,
        radius: float,
        color: tuple[int, int, int, int],
    ) -> None:
        radius = min(radius, (x1 - x0) / 2.0, (y1 - y0) / 2.0)
        for y in range(max(0, int(y0)), min(self.size, int(math.ceil(y1)))):
            cy = y + 0.5
            if cy < y0 + radius:
                dy = y0 + radius - cy
                dx = radius - math.sqrt(max(0.0, radius * radius - dy * dy))
            elif cy > y1 - radius:
                dy = cy - (y1 - radius)
                dx = radius - math.sqrt(max(0.0, radius * radius - dy * dy))
            else:
                dx = 0.0
            self.span(y, x0 + dx, x1 - dx, color)

    def rounded_rect_gradient(
        self,
        x0: float,
        y0: float,
        x1: float,
        y1: float,
        radius: float,
        top: tuple[int, int, int],
        bottom: tuple[int, int, int],
    ) -> None:
        radius = min(radius, (x1 - x0) / 2.0, (y1 - y0) / 2.0)
        for y in range(max(0, int(y0)), min(self.size, int(math.ceil(y1)))):
            cy = y + 0.5
            if cy < y0 + radius:
                dy = y0 + radius - cy
                dx = radius - math.sqrt(max(0.0, radius * radius - dy * dy))
            elif cy > y1 - radius:
                dy = cy - (y1 - radius)
                dx = radius - math.sqrt(max(0.0, radius * radius - dy * dy))
            else:
                dx = 0.0
            t = min(1.0, max(0.0, (cy - y0) / (y1 - y0)))
            color = tuple(int(round(top[i] + (bottom[i] - top[i]) * t)) for i in range(3)) + (255,)
            self.span(y, x0 + dx, x1 - dx, color)

    def line(
        self,
        x0: float,
        y0: float,
        x1: float,
        y1: float,
        width: float,
        color: tuple[int, int, int, int],
    ) -> None:
        half = width / 2.0
        dx, dy = x1 - x0, y1 - y0
        length2 = dx * dx + dy * dy
        minx = max(0, int(min(x0, x1) - half - 1))
        maxx = min(self.size - 1, int(max(x0, x1) + half + 1))
        miny = max(0, int(min(y0, y1) - half - 1))
        maxy = min(self.size - 1, int(max(y0, y1) + half + 1))
        for y in range(miny, maxy + 1):
            py = y + 0.5
            for x in range(minx, maxx + 1):
                px = x + 0.5
                if length2 == 0:
                    d2 = (px - x0) ** 2 + (py - y0) ** 2
                else:
                    t = ((px - x0) * dx + (py - y0) * dy) / length2
                    t = min(1.0, max(0.0, t))
                    qx, qy = x0 + t * dx, y0 + t * dy
                    d2 = (px - qx) ** 2 + (py - qy) ** 2
                if d2 <= half * half:
                    self._blend(y * self.size * 4 + x * 4, color)

    def downsample(self, factor: int) -> "Canvas":
        out_size = self.size // factor
        out = Canvas(out_size)
        area = factor * factor
        for y in range(out_size):
            for x in range(out_size):
                r = g = b = a = 0
                for oy in range(factor):
                    base = ((y * factor + oy) * self.size + x * factor) * 4
                    for ox in range(factor):
                        i = base + ox * 4
                        r += self.data[i]
                        g += self.data[i + 1]
                        b += self.data[i + 2]
                        a += self.data[i + 3]
                i = (y * out_size + x) * 4
                out.data[i] = r // area
                out.data[i + 1] = g // area
                out.data[i + 2] = b // area
                out.data[i + 3] = a // area
        return out


def render(size: int) -> Canvas:
    canvas_size = size * SUPERSAMPLE
    scale = canvas_size / DESIGN
    c = Canvas(canvas_size)

    def s(value: float) -> float:
        return value * scale

    # Rounded app tile: outer rim then dark navy gradient body.
    c.rounded_rect(s(8), s(8), s(248), s(248), s(54), (30, 58, 95, 255))
    c.rounded_rect_gradient(
        s(11), s(11), s(245), s(245), s(51), (12, 23, 39), (19, 41, 67)
    )

    # Soft ambient glows (alpha-blended).
    c.circle(s(190), s(58), s(78), (34, 211, 238, 22))
    c.circle(s(64), s(208), s(86), (59, 130, 246, 16))
    c.circle(s(128), s(132), s(104), (16, 185, 129, 7))

    # Terminal card with a subtle drop shadow.
    c.rounded_rect(s(42), s(74), s(220), s(194), s(19), (0, 0, 0, 80))
    c.rounded_rect(s(38), s(66), s(218), s(190), s(18), (43, 76, 111, 255))
    c.rounded_rect(s(40), s(68), s(216), s(188), s(16), (8, 18, 32, 245))

    # Window controls.
    c.circle(s(57), s(79), s(4.2), (248, 113, 113, 255))
    c.circle(s(71), s(79), s(4.2), (251, 191, 36, 255))
    c.circle(s(85), s(79), s(4.2), (52, 211, 153, 255))
    c.rounded_rect(s(42), s(93), s(214), s(94.5), s(0.7), (27, 50, 78, 255))

    # Prompt: cyan chevron + green caret.
    c.line(s(78), s(115), s(106), s(139), s(12), (34, 211, 238, 255))
    c.line(s(106), s(139), s(78), s(163), s(12), (34, 211, 238, 255))
    c.rounded_rect(s(118), s(151), s(164), s(162), s(5.5), (52, 211, 153, 255))

    # Stacked layers: the "NAS / container" motif.
    c.rounded_rect(s(99), s(205), s(157), s(211), s(3), (96, 165, 250, 230))
    c.rounded_rect(s(106), s(217), s(150), s(223), s(3), (96, 165, 250, 175))
    c.rounded_rect(s(113), s(229), s(143), s(235), s(3), (96, 165, 250, 125))

    return c.downsample(SUPERSAMPLE)


def write_png(path: Path, canvas: Canvas) -> None:
    size = canvas.size
    raw = bytearray()
    stride = size * 4
    for y in range(size):
        raw.append(0)  # filter type: none
        raw.extend(canvas.data[y * stride : (y + 1) * stride])

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def main() -> int:
    here = Path(__file__).resolve().parent.parent
    targets = [
        (72, here / "PACKAGE_ICON.PNG"),
        (256, here / "PACKAGE_ICON_256.PNG"),
    ]
    for size, path in targets:
        write_png(path, render(size))
        print(f"wrote {path} ({size}x{size})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
