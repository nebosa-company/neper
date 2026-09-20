"""Regenerates the PNG vectors in src/main.e with Pillow as the independent codec.

Each vector is a small image Pillow encodes in one colour type and depth; the fixture
decodes it with e.fmt.png and compares every pixel with Pillow's own RGBA (or L)
rendering of the same file. Run from the repository root:

    python tests/selfhost/fixtures/link/fmt_png/reference.py
"""
import io
import os
import re

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def lit(b):
    out = []
    for c in b:
        if c == 34:
            out.append(chr(92) + '"')
        elif c == 92:
            out.append(chr(92) + chr(92))
        elif 32 <= c < 127:
            out.append(chr(c))
        else:
            out.append(chr(92) + 'x%02x' % c)
    return '"' + ''.join(out) + '"'


def gradient(w, h):
    img = Image.new('RGBA', (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = ((x * 37) % 256, (y * 59) % 256, (x * y) % 256, 255 if (x + y) % 3 else (x * 41) % 256)
    return img


def encode(img, **kw):
    buf = io.BytesIO()
    img.save(buf, format='PNG', **kw)
    return buf.getvalue()


def vectors():
    base = gradient(9, 7)
    out = []
    # name, png bytes, expected mode ('L' or 'RGBA')
    out.append(('rgba8', encode(base), 'RGBA'))
    out.append(('rgb8', encode(base.convert('RGB')), 'RGBA'))
    out.append(('gray8', encode(base.convert('L')), 'L'))
    out.append(('gray1', encode(base.convert('1')), 'L'))
    out.append(('gray4', encode(base.convert('L').point(lambda v: v // 16 * 17), bits=4), 'L'))
    pal = base.convert('RGB').quantize(colors=16)
    out.append(('indexed4', encode(pal, bits=4), 'RGBA'))
    palt = base.convert('RGBA').quantize(colors=8)
    out.append(('indexed_trns', encode(palt), 'RGBA'))
    out.append(('gray_alpha', encode(base.convert('LA')), 'RGBA'))
    out.append(('interlaced', encode(base, interlace=1), 'RGBA'))
    out.append(('gray16', encode(Image.frombytes('I;16', (6, 4), bytes((i * 11) % 256 for i in range(48)))), 'L16'))
    return out


def expected_pixels(png, mode):
    img = Image.open(io.BytesIO(png))
    if mode == 'L16':
        raw = img.tobytes()  # little-endian 16-bit samples
        return bytes(raw[i + 1] for i in range(0, len(raw), 2)), img.size
    return img.convert(mode).tobytes(), img.size


def main():
    text = open(os.path.join(HERE, 'src', 'main.e'), encoding='utf-8').read()
    names = []
    for name, png, mode in vectors():
        pixels, (w, h) = expected_pixels(png, mode)
        names.append((name, w, h, mode))
        text = re.sub(r'fn %s_png\(\) -> str \{ ret ".*?" \}' % name,
                      lambda m: 'fn %s_png() -> str { ret %s }' % (name, lit(png)), text, flags=re.S)
        text = re.sub(r'fn %s_pixels\(\) -> str \{ ret ".*?" \}' % name,
                      lambda m: 'fn %s_pixels() -> str { ret %s }' % (name, lit(pixels)), text, flags=re.S)
    open(os.path.join(HERE, 'src', 'main.e'), 'w', encoding='utf-8', newline='\n').write(text)
    for n in names:
        print(n)


if __name__ == '__main__':
    main()
