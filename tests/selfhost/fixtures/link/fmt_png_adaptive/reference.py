# Oracle for e.fmt.png encode_adaptive (L163). Generates the images the fixture builds, models libpng's
# filter heuristic and palette choice in Python, checks the model against Pillow (libpng-equivalent
# ZipEncode) byte for byte on the non-interlaced cases, and prints the expected table for src/main.e.
import io, struct, sys, zlib
from PIL import Image

def lcg():
    s = 12345
    while True:
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        yield s >> 16

def gen(kind, w, h):
    n = lcg()
    px = []
    for y in range(h):
        for x in range(w):
            if kind == 'two':
                c = (10, 40, 200, 255) if ((x // 5) + (y // 3)) % 2 else (250, 250, 250, 255)
            elif kind == 'four':
                c = [(0, 0, 0, 0), (255, 0, 0, 128), (0, 255, 0, 255), (0, 0, 255, 255)][(x // 4 + y // 5) % 4]
            elif kind == 'sixteen':
                k = (x // 3 + y) % 11
                c = (k * 23, 255 - k * 20, (k * k * 3) % 256, 255)
            elif kind == 'twohundred':
                k = (x * 5 + y * 7) % 200
                c = (k, k * 3 % 256, 255 - k, 255)
            elif kind == 'smooth':
                c = ((2 * x + y + (next(n) & 7)) & 255, (x + 3 * y) & 255, (x * y >> 3) & 255, 255)
            elif kind == 'smooth_alpha':
                c = ((2 * x + y + (next(n) & 7)) & 255, (x + 3 * y) & 255, (x * y >> 3) & 255, 255 - ((x + y) % 5) * 10)
            elif kind == 'gray':
                c = ((x * 6 + y * 2 + (next(n) & 7)) & 255,)
            elif kind == 'wide':
                c = ((x * 3 + y * 17 + (next(n) & 15)) & 255, (x // 2 + (next(n) & 3)) & 255, 255 - x % 256, 255)
            px.append(c)
    return px

PASSES = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]

def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc: return a
    if pb <= pc: return b
    return c

def filt(kind, cur, up, bpp):
    out = bytearray()
    for i, v in enumerate(cur):
        a = cur[i - bpp] if i >= bpp else 0
        b = up[i]
        c = up[i - bpp] if i >= bpp else 0
        p = (0, a, b, (a + b) >> 1, paeth(a, b, c))[kind]
        out.append((v - p) & 255)
    return bytes(out)

def model(px, w, h, channels, alpha_used, interlace):
    """channels 1 (R8) or 4 (RGBA). Returns (color, depth, palette, raw)."""
    if channels == 4:
        colors = []
        seen = {}
        for c in px:
            c = c if alpha_used else c[:3] + (255,)
            if c not in seen:
                if len(seen) == 256: seen = None; break
                seen[c] = len(seen); colors.append(c)
    else:
        seen = None
    passes = PASSES if interlace else [(0, 0, 1, 1)]
    raw = bytearray()
    if seen is not None:
        n = len(seen)
        depth = 1 if n <= 2 else 2 if n <= 4 else 4 if n <= 16 else 8
        for x0, y0, dx, dy in passes:
            ys = range(y0, h, dy); xs = list(range(x0, w, dx))
            if not xs: continue
            for y in ys:
                idx = [seen[px[y * w + x] if alpha_used else px[y * w + x][:3] + (255,)] for x in xs]
                raw.append(0)
                per = 8 // depth
                for i in range(0, len(idx), per):
                    byte = 0
                    for j, v in enumerate(idx[i:i + per]):
                        byte |= v << (8 - depth * (j + 1))
                    raw.append(byte)
        return 3, depth, colors, bytes(raw)
    ch = 1 if channels == 1 else (4 if alpha_used else 3)
    for x0, y0, dx, dy in passes:
        xs = list(range(x0, w, dx))
        if not xs: continue
        prev = bytes(len(xs) * ch)
        for y in range(y0, h, dy):
            cur = bytearray()
            for x in xs:
                c = px[y * w + x]
                cur += bytes(c[:ch])
            cur = bytes(cur)
            best, bs = 0, None
            for k in range(5):
                f = filt(k, cur, prev, ch)
                s = sum(v if v < 128 else 256 - v for v in f)
                if bs is None or s < bs: best, bs = k, s
            raw.append(best)
            raw += filt(best, cur, prev, ch)
            prev = cur
    return {1: 0, 3: 2, 4: 6}[ch], 8, None, bytes(raw)

def idat_raw(png):
    pos, z = 8, b''
    while pos < len(png):
        n, = struct.unpack('>I', png[pos:pos + 4]); t = png[pos + 4:pos + 8]
        if t == b'IDAT': z += png[pos + 8:pos + 8 + n]
        pos += 12 + n
    return zlib.decompress(z), len(z)

CASES = [  # name, kind, w, h, channels, alpha_used, interlace
    ('two', 'two', 61, 20, 4, True, False),
    ('four', 'four', 33, 20, 4, True, False),
    ('sixteen', 'sixteen', 100, 30, 4, True, False),
    ('twohundred', 'twohundred', 50, 40, 4, True, False),
    ('smooth', 'smooth', 97, 61, 4, False, False),
    ('smooth_alpha', 'smooth_alpha', 97, 61, 4, True, False),
    ('gray', 'gray', 40, 30, 1, False, False),
    ('wide', 'wide', 1500, 6, 4, False, False),
    ('two_adam7', 'two', 61, 20, 4, True, True),
    ('sixteen_adam7', 'sixteen', 100, 30, 4, True, True),
    ('smooth_adam7', 'smooth', 97, 61, 4, False, True),
    ('gray_adam7', 'gray', 40, 30, 1, False, True),
]

def pillow_png(px, w, h, channels, alpha_used, color, depth, palette):
    b = io.BytesIO()
    if color == 3:
        im = Image.new('P', (w, h))
        pal = []
        for c in palette: pal += list(c[:3])
        im.putpalette(pal)
        look = {c: i for i, c in enumerate(palette)}
        im.putdata([look[c if alpha_used else c[:3] + (255,)] for c in px])
        tr = bytes(c[3] for c in palette)
        kw = {}
        if any(c[3] != 255 for c in palette):
            last = max(i for i, c in enumerate(palette) if c[3] != 255)
            kw['transparency'] = tr[:last + 1]
        im.save(b, 'PNG', **kw)
    else:
        mode = 'L' if channels == 1 else ('RGBA' if alpha_used else 'RGB')
        im = Image.new(mode, (w, h))
        ch = {'L': 1, 'RGB': 3, 'RGBA': 4}[mode]
        im.putdata([c[0] if ch == 1 else tuple(c[:ch]) for c in px])
        im.save(b, 'PNG')
    return b.getvalue()

if __name__ == '__main__':
    print('// expected: name, color, depth, palette colours, trns length, raw length, raw adler32, zlib level 6 size of the raw stream')
    for name, kind, w, h, channels, alpha_used, interlace in CASES:
        px = gen(kind, w, h)
        color, depth, palette, raw = model(px, w, h, channels, alpha_used, interlace)
        trns = 0
        if palette:
            nz = [i for i, c in enumerate(palette) if c[3] != 255]
            trns = nz[-1] + 1 if nz else 0
        size = 0
        if not interlace:
            png = pillow_png(px, w, h, channels, alpha_used, color, depth, palette)
            praw, size = idat_raw(png)
            if color == 3:
                # libpng's default is filter None for indexed rows, Pillow filters them anyway: unfilter its rows.
                rb = (w * depth + 7) // 8
                un = bytearray(); prev = bytes(rb)
                for i in range(h):
                    k = praw[i * (rb + 1)]; row = praw[i * (rb + 1) + 1:(i + 1) * (rb + 1)]
                    cur = bytearray()
                    for j, v in enumerate(row):
                        a = cur[j - 1] if j else 0; b = prev[j]; c = prev[j - 1] if j else 0
                        cur.append((v + (0, a, b, (a + b) >> 1, paeth(a, b, c))[k]) & 255)
                    un += bytes(1) + cur; prev = bytes(cur)
                assert bytes(un) == raw, name + ': palette rows differ from Pillow'
            else:
                assert praw == raw, name + ': model differs from Pillow'
            assert png[24] == depth and png[25] == color, name
        print('%s %d %d %d %d %d %d %d  (Pillow zlib %d)' % (name, color, depth, len(palette or []), trns, len(raw), zlib.adler32(raw), len(zlib.compress(raw, 6)), size))
