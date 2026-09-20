"""Regenerates the JPEG vectors in src/main.e with Pillow (libjpeg) as the independent
codec: baseline 4:4:4 and 4:2:0, progressive, greyscale, restart intervals. The fixture
decodes each with e.fmt.jpeg and compares every sample with libjpeg's within a small
tolerance (IDCT and upsampling rounding differ by design). Run from the repository
root:

    python tests/selfhost/fixtures/link/fmt_jpeg/reference.py
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


def scene(w, h):
    img = Image.new('RGB', (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = (int(255 * x / max(1, w - 1)), int(255 * y / max(1, h - 1)), 128 + (60 if (x // 5 + y // 5) % 2 else -60))
    return img


def encode(img, **kw):
    buf = io.BytesIO()
    img.save(buf, format='JPEG', **kw)
    return buf.getvalue()


def vectors():
    base = scene(23, 17)
    out = []
    out.append(('baseline444', encode(base, quality=92, subsampling=0), 'RGBA'))
    out.append(('baseline420', encode(base, quality=80, subsampling=2), 'RGBA'))
    out.append(('progressive', encode(base, quality=85, subsampling=2, progressive=True), 'RGBA'))
    out.append(('gray', encode(base.convert('L'), quality=90), 'L'))
    out.append(('gray_progressive', encode(base.convert('L'), quality=70, progressive=True), 'L'))
    out.append(('restarts', encode(base, quality=88, subsampling=0, restart_marker_blocks=2), 'RGBA'))
    return out


def main():
    text = open(os.path.join(HERE, 'src', 'main.e'), encoding='utf-8').read()
    for name, jpg, mode in vectors():
        img = Image.open(io.BytesIO(jpg))
        img.load()
        pixels = img.convert(mode).tobytes()
        print(name, img.size, mode, len(jpg), 'bytes')
        text = re.sub(r'fn %s_jpg\(\) -> str \{ ret ".*?" \}' % name,
                      lambda m: 'fn %s_jpg() -> str { ret %s }' % (name, lit(jpg)), text, flags=re.S)
        text = re.sub(r'fn %s_pixels\(\) -> str \{ ret ".*?" \}' % name,
                      lambda m: 'fn %s_pixels() -> str { ret %s }' % (name, lit(pixels)), text, flags=re.S)
    open(os.path.join(HERE, 'src', 'main.e'), 'w', encoding='utf-8', newline='\n').write(text)


if __name__ == '__main__':
    main()
