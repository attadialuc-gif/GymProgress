"""Generates the app icon (1024x1024 PNG, opaque, sRGB) without third-party libraries.

Original design: a lime upward arrow rising out of a simple barbell, on a near-black background.
Usage: python3 scripts/gen_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import struct
import sys
import zlib

SIZE = 1024
SS = 3  # supersampling per axis for anti-aliasing

BG_TOP = (18, 20, 24)
BG_BOTTOM = (6, 7, 9)
ACCENT = (199, 217, 51)     # matches AccentColor (dark appearance)
PLATE = (225, 228, 232)
BAR = (150, 155, 162)


def inside_round_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def inside_triangle(x, y, a, b, c):
    def sign(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    d1, d2, d3 = sign((x, y), a, b), sign((x, y), b, c), sign((x, y), c, a)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def color_at(x, y):
    # Barbell (horizontal, lower third)
    bar_y = 690
    if inside_round_rect(x, y, 170, bar_y - 18, 854, bar_y + 18, 18):
        c = BAR
    else:
        c = None
    for px0, px1, h in ((205, 265, 300), (275, 320, 220), (704, 749, 220), (759, 819, 300)):
        if inside_round_rect(x, y, px0, bar_y - h / 2, px1, bar_y + h / 2, 22):
            c = PLATE
    # Upward arrow (shaft + head), drawn over the bar
    if inside_round_rect(x, y, 462, 300, 562, 760, 28):
        c = ACCENT
    if inside_triangle(x, y, (512, 150), (330, 380), (694, 380)):
        c = ACCENT
    if c is not None:
        return c
    t = y / SIZE
    return tuple(int(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3))


def render():
    rows = []
    for y in range(SIZE):
        row = bytearray([0])  # filter type 0
        for x in range(SIZE):
            acc = [0, 0, 0]
            for sy in range(SS):
                for sx in range(SS):
                    c = color_at(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
                    acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]
            n = SS * SS
            row += bytes((acc[0] // n, acc[1] // n, acc[2] // n))
        rows.append(bytes(row))
    return b"".join(rows)


def png(raw):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB, no alpha
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


if __name__ == "__main__":
    with open(sys.argv[1], "wb") as fh:
        fh.write(png(render()))
    print("ok", sys.argv[1])
