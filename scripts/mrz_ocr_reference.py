#!/usr/bin/env python3
"""The machine-readable-zone reader of e.gfx.vision (D4809) as plain integer Python: the oracle the Neper code is checked
against, the generator of its glyph templates, and the maker of the test pages.

  mrz_ocr_reference.py templates            the packed glyph templates as a Neper string function body
  mrz_ocr_reference.py page NAME FONT SIZE   write NAME.png (two TD3 lines under a caption) and print its bytes
  mrz_ocr_reference.py read FILE.png         read a PNG with the Python reader

Templates come from OFL monospaced fonts (JetBrains Mono Regular and Bold, Cascadia Mono, Intel One Mono), each at two
stroke widths, rendered at 48 px: 37 symbols (`<`, 0-9, A-Z) normalised the way the reader normalises a glyph -- the cell is
centred on the glyph's ink, as wide as the font's advance, as tall as the body rows of a line of capitals and digits plus a
fifth below the baseline (so a Q's tail is inside), area-averaged to 10 x 16 and quantised to four levels.
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

CHARS = "<0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
CW, CH = 10, 16
LINE = 44
FONTS = ["JetBrainsMono-Regular.ttf", "JetBrainsMono-Bold.ttf", "CascadiaMono.ttf", "intelone-mono-font-family-regular.ttf"]
STROKES = (0, 1)
FONT_DIR = "C:/Windows/Fonts/"


# ---- cells ------------------------------------------------------------------------------------------------------

def cell_of(ink, x0, x1, y0, y1):
    """Area-average the box [x0,x1) x [y0,y1) of the ink bitmap (0/1) to CH x CW coverage 0..255 (integers; columns
    outside the image count as no ink and the box keeps its size)."""
    height, width = ink.shape
    h = y1 - y0
    w = x1 - x0
    out = np.zeros((CH, CW), np.int32)
    for j in range(CH):
        ya = y0 + j * h // CH
        yb = max(y0 + (j + 1) * h // CH, ya + 1)
        for i in range(CW):
            xa = x0 + i * w // CW
            xb = max(x0 + (i + 1) * w // CW, xa + 1)
            total = 0
            for y in range(ya, yb):
                if 0 <= y < height:
                    for x in range(xa, xb):
                        if 0 <= x < width:
                            total += int(ink[y, x])
            area = (yb - ya) * (xb - xa)
            out[j, i] = total * 255 // area
    return out


def quant(c):
    return (c * 3 + 127) // 255


def blur(c):
    """3 x 3 [1 2 1; 2 4 2; 1 2 1] / 16 with the edge cells repeated."""
    p = np.pad(c.astype(np.int32), 1, mode="edge")
    out = np.zeros(c.shape, np.int32)
    k = ((1, 2, 1), (2, 4, 2), (1, 2, 1))
    for j in range(3):
        for i in range(3):
            out += k[j][i] * p[j:j + c.shape[0], i:i + c.shape[1]]
    return out // 16


def normalise(ink, x0, x1, y0, y1):
    return blur(quant(cell_of(ink, x0, x1, y0, y1)) * 85)


# ---- templates --------------------------------------------------------------------------------------------------

def render(text, path, size, pad, stroke=0):
    f = ImageFont.truetype(path, size)
    adv = f.getlength("0")
    asc, desc = f.getmetrics()
    im = Image.new("L", (int(adv * len(text) + 2 * pad) + 2, asc + desc + 2 * pad), 255)
    d = ImageDraw.Draw(im)
    for k, c in enumerate(text):
        d.text((pad + k * adv, pad), c, font=f, fill=0, stroke_width=stroke, stroke_fill=0)
    return im, int(round(adv))


def body_rows(ink):
    rows = ink.sum(axis=1)
    keep = np.nonzero(rows * 4 >= rows.max())[0]
    return int(keep[0]), int(keep[-1]) + 1


def template_cells():
    """[(font index, stroke, char, 4-level cell)] for every template."""
    out = []
    for fi, name in enumerate(FONTS):
        for st in STROKES:
            line, _ = render(CHARS[1:] + CHARS[1:], FONT_DIR + name, 48, 4, st)
            a = (np.array(line) < 128).astype(np.uint8)
            y0, y1 = body_rows(a)
            y1 += (y1 - y0) // 5
            for ch in CHARS:
                im, adv = render(ch, FONT_DIR + name, 48, 4, st)
                g = (np.array(im) < 128).astype(np.uint8)
                cols = g[y0:y1].sum(axis=0)
                nz = np.nonzero(cols)[0]
                c2 = int(nz[0]) + int(nz[-1]) + 1
                xa = (c2 - adv) // 2
                out.append((fi, st, ch, quant(cell_of(g, xa, xa + adv, y0, y1))))
    return out


def pack(cells):
    """Two bits a value, four to a byte, row-major, in the order font, stroke, char."""
    data = bytearray()
    for _, _, _, q in cells:
        flat = [int(v) for v in q.flatten()]
        for k in range(0, len(flat), 4):
            data.append(flat[k] | flat[k + 1] << 2 | flat[k + 2] << 4 | flat[k + 3] << 6)
    return bytes(data)


def neper_string(data):
    out = []
    for b in data:
        if b == 92: out.append("\\\\")
        elif b == 34: out.append('\\"')
        elif 32 <= b < 127: out.append(chr(b))
        else: out.append("\\x%02x" % b)
    return "".join(out)


def load_templates():
    t = []
    for fi, st, ch, q in template_cells():
        t.append((ch, blur(q * 85)))
    return t


# ---- reading ----------------------------------------------------------------------------------------------------

def otsu(gray):
    hist = [0] * 256
    for v in gray.ravel():
        hist[int(v)] += 1
    total = sum(hist)
    sum_all = sum(i * hist[i] for i in range(256))
    wb = 0
    sb = 0
    best = -1.0
    thr = 128
    for t in range(256):
        wb += hist[t]
        if wb == 0:
            continue
        wf = total - wb
        if wf == 0:
            break
        sb += t * hist[t]
        # between-class variance * (wb*wf)^1 compared in integers: (mb - mf)^2 * wb * wf with mb = sb/wb, mf = (all-sb)/wf
        num = float(sb * wf - (sum_all - sb) * wb)
        between = num * num / float(wb * wf)
        if between > best:
            best = between
            thr = t
    return thr


def text_lines(ink):
    rows = ink.sum(axis=1)
    out = []
    inside = False
    for y, v in enumerate(rows):
        if v > 0 and not inside:
            inside = True
            ys = y
        elif v == 0 and inside:
            inside = False
            out.append([ys, y])
    if inside:
        out.append([ys, len(rows)])
    merged = []
    for l in out:
        if merged and l[0] - merged[-1][1] < 2:
            merged[-1][1] = l[1]
        else:
            merged.append(l)
    return merged


def runs_of(cols):
    out = []
    inside = False
    for x, v in enumerate(cols):
        if v > 0 and not inside:
            inside = True
            xs = x
        elif v == 0 and inside:
            inside = False
            out.append((xs, x))
    if inside:
        out.append((xs, len(cols)))
    return out


def segment(ink, y0, y1, n):
    """The n cell boxes (x0, x1) of a line: one ink run a glyph when there are exactly n of them, else a pitch grid
    searched in quarter pixels for the boundaries with the least ink around them."""
    cols = ink[y0:y1].sum(axis=0).astype(np.int64)
    runs = runs_of(cols)
    nz = np.nonzero(cols)[0]
    xf, xl = int(nz[0]), int(nz[-1])
    span = xl - xf + 1
    pitch4 = 16 * span // (4 * n - 1)
    boxes = []
    if len(runs) == n:
        half = (pitch4 + 2) // 4
        for a_, b_ in runs:
            xa = (a_ + b_ - half) // 2
            boxes.append((xa, xa + half))
        return boxes
    best = None
    p4 = span * 4 // n
    p4_max = span * 40 // (n * 10 - 6) + 1
    while p4 <= p4_max:
        w = max(1, 18 * p4 // 400)
        phase4 = xf * 4 - 45 * p4 // 100
        while phase4 <= xf * 4 + 1:
            cost = 0
            for k in range(1, n):
                x = (phase4 + k * p4 + 2) // 4
                if 0 <= x < len(cols):
                    cost += int(cols[max(x - w, 0):x + w + 1].sum())
            if best is None or cost < best[0]:
                best = (cost, p4, phase4)
            phase4 += 1
        p4 += 1
    _, p4, phase4 = best
    half = (p4 + 2) // 4
    for k in range(n):
        xa = (phase4 + k * p4 + 2) // 4
        xb = (phase4 + (k + 1) * p4 + 2) // 4
        lo = max(xa, 0)
        seg = cols[lo:max(xb, 0)]
        nzs = np.nonzero(seg)[0]
        if len(nzs):
            c2 = 2 * lo + int(nzs[0]) + int(nzs[-1]) + 1
            xa2 = (c2 - half) // 2
            boxes.append((xa2, xa2 + half))
        else:
            boxes.append((xa, xb))
    return boxes


def classify(cell, T):
    """(best char, best distance, second char, second distance) over distinct chars; shifts of a column either way cost 40."""
    best = {}
    for ch, t in T:
        d = 1 << 30
        for dx in (-1, 0, 1):
            s = np.zeros_like(cell)
            if dx == 0:
                s = cell
            elif dx > 0:
                s[:, dx:] = cell[:, :-dx]
            else:
                s[:, :dx] = cell[:, -dx:]
            dd = int(((s - t) ** 2).sum()) // 16 + (40 if dx else 0)
            if dd < d:
                d = dd
        if ch not in best or d < best[ch]:
            best[ch] = d
    ranked = sorted(best.items(), key=lambda kv: (kv[1], CHARS.index(kv[0])))
    return ranked[0][0], ranked[0][1], ranked[1][0], ranked[1][1]


NUM = {"O": "0", "D": "0", "Q": "0", "I": "1", "L": "1", "B": "8", "S": "5", "Z": "2", "G": "6"}
ALP = {"0": "O", "1": "I", "8": "B", "5": "S", "2": "Z", "6": "G"}


def context(l1, l2):
    num = lambda s: "".join(NUM.get(c, c) for c in s)
    alp = lambda s: "".join(ALP.get(c, c) for c in s)
    return alp(l1), (l2[0:9] + num(l2[9]) + alp(l2[10:13]) + num(l2[13:20]) + alp(l2[20]) + num(l2[21:28]) + l2[28:42] + num(l2[42:44]))


def value(c):
    if c.isdigit():
        return int(c)
    if "A" <= c <= "Z":
        return ord(c) - 55
    return 0


def check(s):
    return sum(value(c) * (7, 3, 1)[i % 3] for i, c in enumerate(s)) % 10


def td3_ok(l1, l2):
    if l1[0] != "P":
        return False
    def field(a, b):
        c = l2[b]
        return (c.isdigit() or c == "<") and check(l2[a:b]) == (int(c) if c.isdigit() else 0)
    return (field(0, 9) and field(13, 19) and field(21, 27) and field(28, 42) and l2[43].isdigit()
            and check(l2[0:10] + l2[13:20] + l2[21:43]) == int(l2[43]))


def read(gray, T, k=8):
    thr = otsu(gray)
    ink = (gray < thr).astype(np.uint8)
    if int(ink.sum()) * 2 > ink.size:
        ink = 1 - ink
    ls = [l for l in text_lines(ink) if l[1] - l[0] >= 6]
    pair = None
    for i in range(len(ls) - 1, 0, -1):
        h1 = ls[i - 1][1] - ls[i - 1][0]
        h2 = ls[i][1] - ls[i][0]
        if abs(h1 - h2) * 3 <= max(h1, h2):
            pair = (ls[i - 1], ls[i])
            break
    if pair is None:
        return None
    res = []
    for ya, yb in pair:
        b0, b1 = body_rows(ink[ya:yb])
        b1 += (b1 - b0) // 5
        boxes = segment(ink, ya + b0, ya + b1, LINE)
        res.append([classify(normalise(ink, xa, xb, ya + b0, ya + b1), T) for xa, xb in boxes])
    lines = ["".join(c[0] for c in rr) for rr in res]
    l1, l2 = context(*lines)
    if td3_ok(l1, l2):
        return l1, l2, 0
    margins = []
    for li, rr in enumerate(res):
        for pos, c in enumerate(rr):
            margins.append((c[3] - c[1], li, pos, c[2]))
    margins.sort()
    pick = margins[:k]
    best = None
    for mask in range(1, 1 << len(pick)):
        ls2 = [list(lines[0]), list(lines[1])]
        for bit, (m, li, pos, ch) in enumerate(pick):
            if mask >> bit & 1:
                ls2[li][pos] = ch
        a, b = context("".join(ls2[0]), "".join(ls2[1]))
        if td3_ok(a, b):
            pc = bin(mask).count("1")
            if best is None or pc < best[2]:
                best = (a, b, pc)
    if best:
        return best
    return l1, l2, -1


def make_page(path, font, size, bad=False):
    l1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
    l2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
    if bad:
        l2 = "L898902C37UTO7408122F1204159ZE184226B<<<<<10"
    cap, _ = render("PASSPORT   UTOPIA", font, size // 2 + 4, 6)
    a, _ = render(l1, font, size, 6)
    b, _ = render(l2, font, size, 6)
    w = max(a.size[0], b.size[0]) + 40
    page = Image.new("L", (w, cap.size[1] + a.size[1] + b.size[1] + 50), 255)
    page.paste(cap, (20, 10))
    page.paste(a, (20, 20 + cap.size[1]))
    page.paste(b, (20, 26 + cap.size[1] + a.size[1]))
    page.save(path)
    return page


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "templates":
        data = pack(template_cells())
        print(len(data))
        print(neper_string(data))
    elif cmd == "page":
        make_page(sys.argv[2] + ".png", sys.argv[3], int(sys.argv[4]), len(sys.argv) > 5 and sys.argv[5] == "bad")
        raw = open(sys.argv[2] + ".png", "rb").read()
        print(len(raw))
        print(", ".join(str(b) for b in raw))
    elif cmd == "read":
        T = load_templates()
        g = np.array(Image.open(sys.argv[2]).convert("L"))
        print(read(g, T))
