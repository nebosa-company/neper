#!/usr/bin/env python3
"""Write tests/selfhost/fixtures/link/barcode_scan/src/main.e: QR symbols (made by the `qrcode` package) drawn at a
module size, turned by an angle with OpenCV and thresholded, packed one bit a pixel, and found and read by
e.barcode.qr_scan; a blank and a noise image find nothing. Set NEPER_PYLIB to a directory holding qrcode."""
import os
import random
import sys
from pathlib import Path

sys.path.insert(0, os.environ.get("NEPER_PYLIB", "D:/Temp/claude/pylib"))
import cv2  # noqa: E402
import numpy as np  # noqa: E402
import qrcode  # noqa: E402
from qrcode import constants  # noqa: E402

LEVELS = [constants.ERROR_CORRECT_L, constants.ERROR_CORRECT_M, constants.ERROR_CORRECT_Q, constants.ERROR_CORRECT_H]
rng = random.Random(7)


def render(data: bytes, level: int, scale: int, angle: float, canvas: int):
    qr = qrcode.QRCode(version=None, error_correction=LEVELS[level], border=4)
    qr.add_data(data, optimize=0)
    qr.make(fit=True)
    m = np.array(qr.get_matrix(), dtype=np.uint8)
    img = np.where(m == 1, 0, 255).astype(np.uint8)
    img = cv2.resize(img, (img.shape[1] * scale, img.shape[0] * scale), interpolation=cv2.INTER_NEAREST)
    canvas = max(canvas, int(max(img.shape) * 1.42) + 16)
    canvas -= canvas % 8
    big = np.full((canvas, canvas), 255, dtype=np.uint8)
    y0 = (canvas - img.shape[0]) // 2
    x0 = (canvas - img.shape[1]) // 2
    big[y0:y0 + img.shape[0], x0:x0 + img.shape[1]] = img
    # A stray dark bar and a dot, away from the symbol, so the search has something else to ignore.
    big[2:5, 2:30] = 0
    big[canvas - 6:canvas - 3, canvas - 6:canvas - 3] = 0
    if angle:
        rot = cv2.getRotationMatrix2D((canvas / 2, canvas / 2), angle, 1.0)
        big = cv2.warpAffine(big, rot, (canvas, canvas), flags=cv2.INTER_LINEAR, borderValue=255)
    return np.where(big < 128, 0, 255).astype(np.uint8)


def pack(img) -> str:
    bits = (img.flatten() == 0).astype(np.uint8)  # 1 = dark
    pad = (-len(bits)) % 8
    bits = np.concatenate([bits, np.zeros(pad, dtype=np.uint8)])
    out = np.packbits(bits)
    return "".join("\\x%02x" % b for b in out)


def lit(data: bytes) -> str:
    return '"' + "".join("\\x%02x" % b for b in data) + '"'


def text(n: int, seed: int) -> bytes:
    r = random.Random(seed)
    return "".join(r.choice("abcdefghijklmnopqrstuvwxyz0123456789 .-/:") for _ in range(n)).encode()


cases = [
    (b"https://neper.dev/", 1, 5, 0.0, 160),
    (b"Skyline Air|SFO to NRT", 1, 4, 12.0, 160),
    (b"hello", 0, 6, -20.0, 160),
    (text(40, 3), 3, 3, 7.0, 160),
    (text(100, 4), 1, 3, 0.0, 180),
    (b"WIFI:S:home;T:WPA;P:secret;;", 2, 4, -9.0, 180),
]
calls = []
for n, (data, level, scale, angle, canvas) in enumerate(cases, 1):
    img = render(data, level, scale, angle, canvas)
    calls.append('    r = scan_case(a, "%s", %d, %s)\n    if r != 0usize { os.exit(%d + i32(r)) }' % (pack(img), img.shape[0], lit(data), n * 4))
# No symbol: blank, and noise.
blank = np.full((120, 120), 255, dtype=np.uint8)
noise = np.where(np.random.RandomState(5).rand(120, 120) < 0.4, 0, 255).astype(np.uint8)
n = len(cases) + 1
calls.append('    r = none_case(a, "%s", 120)\n    if r != 0usize { os.exit(%d + i32(r)) }' % (pack(blank), n * 4))
n += 1
calls.append('    r = none_case(a, "%s", 120)\n    if r != 0usize { os.exit(%d + i32(r)) }' % (pack(noise), n * 4))

head = """// `e.barcode.qr_scan`: QR symbols made by the qrcode package, drawn, turned and thresholded by
// scripts/gen_qrscan_test.py (packed one bit a pixel, 1 dark), found by their finder patterns and read; a blank
// image and a noise image find nothing. A check's exit code is four times its position plus the stage.
use e.os
use e.mem
use e.barcode as bar

fn unpack(a: *mem.Arena, packed: str, side: usize) -> ([]u8, err) {
    let (luma, luma_error) = mem.alloc[u8](a, side * side)
    if luma_error != ok { ret (luma, luma_error) }
    var i = 0usize
    while i < side * side {
        let bit = (usize(packed[i >> 3usize]) >> (7usize - (i & 7usize))) & 1usize
        if bit == 1usize { luma[i] = 0u8 } else { luma[i] = 255u8 }
        i += 1usize
    }
    ret (luma, ok)
}

fn scan_case(a: *mem.Arena, packed: str, side: usize, expected: str) -> usize {
    let (luma, luma_error) = unpack(a, packed, side)
    if luma_error != ok { ret 1usize }
    let (found, found_error) = bar.qr_scan(a, luma, side, side)
    if found_error != ok { ret 2usize }
    if found.len != expected.len { ret 3usize }
    var i = 0usize
    while i < found.len {
        if found[i] != expected[i] { ret 3usize }
        i += 1usize
    }
    ret 0usize
}

fn none_case(a: *mem.Arena, packed: str, side: usize) -> usize {
    let (luma, luma_error) = unpack(a, packed, side)
    if luma_error != ok { ret 1usize }
    let (found, found_error) = bar.qr_scan(a, luma, side, side)
    if found_error != bar.NotFound { ret 2usize }
    ret 0usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    var r = 0usize
"""
dest = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/barcode_scan/src/main.e"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(head + "\n".join(calls) + "\n    ret ok\n}\n", encoding="utf-8", newline="\n")
print(dest, len(calls), "checks", dest.stat().st_size, "bytes")
