"""Regenerates the WebP vectors in src/main.e with Pillow (libwebp) as the independent
codec: lossless RGBA (with transforms and a colour cache as libwebp chooses them), lossy
4:2:0 with and without an ALPH plane, and an animation for `inspect`. The fixture
decodes each with e.fmt.webp and compares every sample with libwebp's: exactly for
lossless, within a small tolerance for lossy (upsampling and colour conversion rounding
differ by design). Run from the repository root:

    python tests/selfhost/fixtures/link/fmt_webp/reference.py
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


def scene(w, h, alpha=False):
    img = Image.new('RGBA' if alpha else 'RGB', (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            c = (int(255 * x / max(1, w - 1)), int(255 * y / max(1, h - 1)), 128 + (60 if (x // 5 + y // 5) % 2 else -60))
            px[x, y] = c + ((x * 11 + y * 7) % 256,) if alpha else c
    return img


def encode(img, **kw):
    buf = io.BytesIO()
    img.save(buf, format='WEBP', **kw)
    return buf.getvalue()


def vectors():
    out = []
    out.append(('lossless', encode(scene(23, 17, True), lossless=True, quality=100), 'RGBA'))
    out.append(('lossless_small', encode(scene(23, 17, True).quantize(4).convert('RGBA'), lossless=True, quality=100), 'RGBA'))
    out.append(('lossy', encode(scene(23, 17), quality=90), 'RGBA'))
    out.append(('lossy_alpha', encode(scene(23, 17, True), quality=90), 'RGBA'))
    out.append(('lossy_big', encode(scene(40, 33), quality=75, method=6), 'RGBA'))
    frames = [scene(9, 7), scene(9, 7).transpose(Image.FLIP_LEFT_RIGHT), scene(9, 7).rotate(180)]
    buf = io.BytesIO()
    frames[0].save(buf, format='WEBP', save_all=True, append_images=frames[1:], duration=100, lossless=True)
    out.append(('animated', buf.getvalue(), 'RGBA'))
    return out


def main():
    text = open(os.path.join(HERE, 'src', 'main.e'), encoding='utf-8').read()
    for name, webp, mode in vectors():
        img = Image.open(io.BytesIO(webp))
        img.load()
        pixels = img.convert(mode).tobytes()
        print(name, img.size, mode, len(webp), 'bytes', getattr(img, 'n_frames', 1), 'frames')
        text = re.sub(r'fn %s_webp\(\) -> str \{ ret ".*?" \}' % name,
                      lambda m: 'fn %s_webp() -> str { ret %s }' % (name, lit(webp)), text, flags=re.S)
        text = re.sub(r'fn %s_pixels\(\) -> str \{ ret ".*?" \}' % name,
                      lambda m: 'fn %s_pixels() -> str { ret %s }' % (name, lit(pixels)), text, flags=re.S)
    open(os.path.join(HERE, 'src', 'main.e'), 'w', encoding='utf-8', newline='\n').write(text)


if __name__ == '__main__':
    main()
