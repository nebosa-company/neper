#!/usr/bin/env python3
"""Write tests/selfhost/fixtures/link/barcode/src/main.e: QR Code, Code 128 and EAN-13 symbols made by the
`qrcode` and `python-barcode` packages (set NEPER_PYLIB to a directory holding them, e.g. a `pip install
--target`) checked against e.barcode module for module, the QR matrices read back (with damaged modules and a
damaged format word), and the refusals. A check's exit code is six times its position plus the stage that failed."""
import os
import random
import sys
from pathlib import Path

sys.path.insert(0, os.environ.get("NEPER_PYLIB", "D:/Temp/claude/pylib"))
import qrcode  # noqa: E402
from qrcode import base, constants  # noqa: E402
from barcode.codex import Code128  # noqa: E402
from barcode.ean import EuropeanArticleNumber13  # noqa: E402

LEVELS = [constants.ERROR_CORRECT_L, constants.ERROR_CORRECT_M, constants.ERROR_CORRECT_Q, constants.ERROR_CORRECT_H]
rng = random.Random(20261011)


def make(data, level, mask):
    qr = qrcode.QRCode(version=None, error_correction=LEVELS[level], mask_pattern=mask, border=0)
    qr.add_data(data, optimize=0)
    qr.make(fit=True)
    rows = qr.get_matrix()
    bits = "".join("1" if cell else "0" for row in rows for cell in row)
    return qr.version, len(rows), bits


def lit(data):
    """A Neper string literal for bytes: every byte escaped, so any value is safe."""
    return '"' + "".join("\\x%02x" % b for b in data) + '"'


def text(n, seed):
    letters = "abcdefghijklmnopqrstuvwxyz0123456789 .,-_/:"
    r = random.Random(seed)
    return "".join(r.choice(letters) for _ in range(n)).encode()


def ecc_per_block(version, level):
    blocks = base.rs_blocks(version, LEVELS[level])
    return blocks[0].total_count - blocks[0].data_count


qr_cases = [
    (b"neper", 0, 0),
    (b"hello, world", 1, 1),
    (b"https://neper.dev/", 2, 2),
    (b"WIFI:S:home;T:WPA;P:secret;;", 0, 3),
    (text(40, 5), 3, 4),
    (text(100, 6), 1, 5),
    (text(150, 7), 2, 6),
    (text(200, 8), 0, 7),
    (text(255, 9), 0, 0),
    (bytes(rng.randrange(256) for _ in range(60)), 3, 2),
    (b"a", 3, 5),
    (text(120, 10), 1, 3),
    (text(46, 11), 3, 1),
]

calls = []
count = [0]


def call(expr):
    count[0] += 1
    calls.append("    r = %s\n    if r != 0usize { os.exit(%d + i32(r)) }" % (expr, count[0] * 6))


for data, level, mask in qr_cases:
    version, size, bits = make(data, level, mask)
    t = min(ecc_per_block(version, level) // 2, 6)
    flips = set()
    while len(flips) < t:
        x = rng.randrange(9, max(10, size - 9))
        y = rng.randrange(9, max(10, size - 9))
        flips.add((x, y))
    spec = ";".join("%d,%d" % f for f in sorted(flips))
    call('qr_case(a, %s, "%s", %d, %d, %d, "%s")' % (lit(data), bits, size, level, mask, spec))

for data, level, mask in qr_cases[:8]:
    call('auto_case(a, %s, %d)' % (lit(data), level))

for data in (b"0123456789012345", b"HELLO WORLD 12345 $%*+-./:"):
    version, size, bits = make(data, 1, None)
    call('read_case(a, "%s", %d, %s, "")' % (bits, size, lit(data)))

version, size, bits = make(b"neper", 0, 2)
call('read_case(a, "%s", %d, "neper", "8,0;8,1;8,2")' % (bits, size))
wreck = []
for yy in range(9, 12):
    for xx in range(9, 12):
        wreck.append((xx, yy))
for yy in range(12, 16):
    for xx in range(9, 18):
        wreck.append((xx, yy))
call('wreck_case(a, "%s", %d, "%s")' % (bits, size, ";".join("%d,%d" % w for w in wreck)))

for t in ("Neper", "123456", "12", "hello world", "~ ", "A1", "Hello-World!", "0123456789"):
    call('code_case(a, "%s", "%s")' % (t, Code128(t).build()[0]))

for digits in ("590123412345", "400638133393", "978020137962", "000000000000"):
    e = EuropeanArticleNumber13(digits)
    call('ean_case(a, "%s", "%s", "%s")' % (digits, e.get_fullcode(), e.build()[0]))

HEAD = open(Path(__file__).with_name("gen_barcode_head.e.txt"), encoding="utf-8").read()
last = (count[0] + 1) * 6
tail = """    let (big, big_error) = bar.qr_encode(a, %s, 0usize)
    if big_error != bar.TooLong { os.exit(%d) }
    let (bad_level, bad_level_error) = bar.qr_encode(a, "x", 7usize)
    if bad_level_error != bar.Invalid { os.exit(%d) }
    let (empty, empty_error) = bar.code128(a, "")
    if empty_error != bar.Invalid { os.exit(%d) }
    let (ctl, ctl_error) = bar.code128(a, "a\\x01b")
    if ctl_error != bar.Invalid { os.exit(%d) }
    let (wrong, wrong_error) = bar.ean13(a, "5901234123458")
    if wrong_error != bar.Invalid { os.exit(%d) }
    let (alpha, alpha_error) = bar.ean13(a, "59012341234x")
    if alpha_error != bar.Invalid { os.exit(%d) }
    let (short, short_error) = bar.ean13(a, "5901234")
    if short_error != bar.Invalid { os.exit(%d) }
    ret ok
}
""" % (lit(text(300, 99)), last, last + 1, last + 2, last + 3, last + 4, last + 5, last + 6)
dest = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/barcode/src/main.e"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(HEAD + "\n".join(calls) + "\n" + tail, encoding="utf-8", newline="\n")
print(dest, count[0], "checks")
