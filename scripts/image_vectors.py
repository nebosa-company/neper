"""Generate tests/selfhost/fixtures/link/fmt_images/src/main.e (L124, D2524).

The oracle for BMP, GIF, TIFF, QOI and EXIF is Pillow (the reference image library for
Python) plus the `qoi` package: every image is written by one of them (or, for the BMP
variants Pillow cannot write -- 4 bit, 16 bit, bit fields, RLE, V4 alpha -- by the small
writer below, and the file is then decoded by Pillow too), and the expected pixels are what
Pillow decodes from the bytes, as RGBA, hashed with CRC-32.  GIF animation frames are
checked against the composition model of the format applied to the frames that were fed to
Pillow's writer, and against Pillow's own decoder.
Install with `python -m pip install --target DIR pillow qoi numpy` and run with PYLIBS=DIR.
"""
import io
import os
import random
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, os.environ.get('PYLIBS', ''))
import numpy as np  # noqa: E402
import qoi  # noqa: E402
from PIL import Image, TiffImagePlugin  # noqa: E402
from PIL.TiffImagePlugin import IFDRational  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests/selfhost/fixtures/link/fmt_images/src/main.e'
rng = random.Random(2424)
lines = []
counter = [1]


def esc(data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    out = []
    for b in data:
        if 48 <= b <= 57 or 65 <= b <= 90 or 97 <= b <= 122 or b in b'._-/ ':
            out.append(chr(b))
        else:
            out.append('\\x%02x' % b)
    return '"' + ''.join(out) + '"'


def check(expr):
    expr = expr.replace('(', '(a, ', 1)
    lines.append('    if !(%s) { die(%di32) }' % (expr, counter[0]))
    counter[0] += 1


def rgba(img):
    return img.convert('RGBA').tobytes()


def crc(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def noise_rgb(w, h, seed=0):
    r = random.Random(seed)
    return Image.frombytes('RGB', (w, h), bytes(r.randrange(256) for _ in range(w * h * 3)))


def gradient(w, h, alpha=False):
    arr = np.zeros((h, w, 4 if alpha else 3), dtype=np.uint8)
    for y in range(h):
        for x in range(w):
            arr[y, x, 0] = (x * 255) // max(1, w - 1)
            arr[y, x, 1] = (y * 255) // max(1, h - 1)
            arr[y, x, 2] = ((x + y) * 7) & 255
            if alpha:
                arr[y, x, 3] = 255 - (x * 255) // max(1, w - 1)
    return arr


# ---- QOI ----------------------------------------------------------------------------------
def qoi_case(arr):
    blob = qoi.encode(arr)
    h, w = arr.shape[:2]
    expected = arr if arr.shape[2] == 4 else np.concatenate([arr, np.full((h, w, 1), 255, np.uint8)], axis=2)
    check('qoi_ok(%s, %du32, %du32, %du32)' % (esc(blob), w, h, crc(expected.tobytes())))
    return blob


qoi_case(gradient(37, 23))
qoi_case(gradient(31, 19, alpha=True))
qoi_case(np.zeros((8, 40, 3), dtype=np.uint8))
qoi_case(np.array(noise_rgb(30, 20, 1)).reshape(20, 30, 3))
qoi_case(np.full((1, 1, 4), 7, dtype=np.uint8))
mix = gradient(64, 8, alpha=True)
mix[2:5, 10:50] = [200, 10, 10, 255]
mix[6, ::3] = [0, 0, 0, 0]
qoi_blob = qoi_case(mix)

# ---- BMP ----------------------------------------------------------------------------------


def pillow_bmp(img):
    buf = io.BytesIO()
    img.save(buf, 'BMP')
    return buf.getvalue()


def bmp_case(blob, intended=None):
    """`intended`: the RGBA bytes the writer meant, for files Pillow decodes wrongly (its RLE4
    reader drops a pixel from odd runs); otherwise Pillow's decode is the expectation."""
    with Image.open(io.BytesIO(blob)) as im:
        im.load()
        w, h = im.size
        expected = rgba(im)
    if intended is not None:
        expected = intended
    check('bmp_ok(%s, %du32, %du32, %du32)' % (esc(blob), w, h, crc(expected)))
    return blob


bmp_case(pillow_bmp(noise_rgb(13, 9, 2)))                        # 24 bit, rows padded
bmp_case(pillow_bmp(Image.fromarray(gradient(17, 11, alpha=True))))   # 32 bit with alpha
bmp_case(pillow_bmp(Image.fromarray(gradient(20, 10)[:, :, 0])))      # 8 bit grey (palette)
pal = Image.new('P', (21, 7))
pal.putpalette([c for i in range(256) for c in (i, (i * 3) & 255, 255 - i)])
pal.putdata([(x * 5 + y * 11) % 200 for y in range(7) for x in range(21)])
bmp_case(pillow_bmp(pal))
bw = Image.new('1', (19, 6))
bw.putdata([(x + y) % 3 == 0 for y in range(6) for x in range(19)])
bmp_case(pillow_bmp(bw))                                          # 1 bit


def write_bmp(width, height, bits, pixels, palette=None, compression=0, masks=None, top_down=False, v4=False, rle=b''):
    """pixels: rows (top to bottom) of values; palette: list of (r, g, b)."""
    pad = lambda n: (n + 3) // 4 * 4  # noqa: E731
    if rle:
        data = rle
    else:
        data = b''
        for row in (pixels if top_down else list(reversed(pixels))):
            acc = bytearray()
            if bits in (1, 4, 8):
                per = 8 // bits
                for i in range(0, len(row), per):
                    byte = 0
                    for j in range(per):
                        v = row[i + j] if i + j < len(row) else 0
                        byte |= v << (8 - bits * (j + 1))
                    acc.append(byte)
            elif bits == 16:
                for v in row:
                    acc += struct.pack('<H', v)
            elif bits == 24:
                for (r, g, b) in row:
                    acc += bytes([b, g, r])
            elif bits == 32:
                for v in row:
                    acc += struct.pack('<I', v)
            acc += bytes(pad(len(acc)) - len(acc))
            data += bytes(acc)
    colors = len(palette) if palette else 0
    pal_bytes = b''.join(bytes([b, g, r, 0]) for r, g, b in palette) if palette else b''
    mask_bytes = b''
    header_size = 40
    if masks and not v4:
        mask_bytes = b''.join(struct.pack('<I', m) for m in masks)
    if v4:
        header_size = 108
    h_field = -height if top_down else height
    dib = struct.pack('<IiiHHIIiiII', header_size, width, h_field, 1, bits, compression, len(data), 2835, 2835, colors, 0)
    if v4:
        m = masks or (0xFF0000, 0xFF00, 0xFF, 0xFF000000)
        dib += struct.pack('<IIII', *m) + struct.pack('<I', 0x73524742) + bytes(36) + struct.pack('<III', 0, 0, 0)
    offset = 14 + len(dib) + len(mask_bytes) + len(pal_bytes)
    return b'BM' + struct.pack('<IHHI', offset + len(data), 0, 0, offset) + dib + mask_bytes + pal_bytes + data


p16 = [(i * 9, (i * 5) & 255, 255 - i * 9) for i in range(16)]
rows4 = [[(x + y) % 16 for x in range(11)] for y in range(5)]
bmp_case(write_bmp(11, 5, 4, rows4, p16))
bmp_case(write_bmp(11, 5, 4, rows4, p16, top_down=True))
rows565 = [[((x * 3 + y) & 31) << 11 | ((x * 7 + y * 5) & 63) << 5 | ((x + y * 2) & 31) for x in range(9)] for y in range(6)]
bmp_case(write_bmp(9, 6, 16, rows565, compression=3, masks=(0xF800, 0x07E0, 0x001F)))
rows555 = [[((x * 3 + y) & 31) << 10 | ((x * 7 + y * 5) & 31) << 5 | ((x + y * 2) & 31) for x in range(9)] for y in range(6)]
bmp_case(write_bmp(9, 6, 16, rows555))
rows32 = [[(((x * 20 + y) & 255) << 24) | (((x * 9) & 255) << 16) | ((y * 40 & 255) << 8) | ((x + y) & 255) for x in range(7)] for y in range(4)]
bmp_case(write_bmp(7, 4, 32, rows32, v4=True, compression=3))
bmp_case(write_bmp(7, 4, 32, [[v & 0x00FFFFFF for v in row] for row in rows32]))           # BI_RGB, alpha byte zero: opaque
rows24 = [[((x * 30) & 255, (y * 50) & 255, ((x + y) * 20) & 255) for x in range(10)] for y in range(3)]
bmp_case(write_bmp(10, 3, 24, rows24, top_down=True))


def rle8(rows):
    out = bytearray()
    for row in rows:
        i = 0
        while i < len(row):
            run = 1
            while i + run < len(row) and row[i + run] == row[i] and run < 255:
                run += 1
            if run >= 3 or len(row) - i < 3:
                out += bytes([run, row[i]])
                i += run
            else:
                n = min(len(row) - i, 20)
                out += bytes([0, n]) + bytes(row[i:i + n]) + (b'\x00' if n % 2 else b'')
                i += n
        out += b'\x00\x00'
    out += b'\x00\x01'
    return bytes(out)


p256 = [(i, (i * 2) & 255, (i * 3) & 255) for i in range(256)]
rows8 = [[(x // 4 + y) % 40 if x % 9 else (x * 5) % 200 for x in range(30)] for y in range(6)]
bmp_case(write_bmp(30, 6, 8, rows8, p256, compression=1, rle=rle8(list(reversed(rows8)))))


def rle4(rows):
    out = bytearray()
    for row in rows:
        i = 0
        while i < len(row):
            run = 1
            while i + run < len(row) and row[i + run] == row[i] and run < 40:
                run += 1
            if run >= 3 or len(row) - i < 3:
                out += bytes([run, (row[i] << 4) | row[i]])
                i += run
            else:
                n = min(len(row) - i, 11)
                nibbles = row[i:i + n]
                packed = bytearray()
                for j in range(0, n, 2):
                    packed.append((nibbles[j] << 4) | (nibbles[j + 1] if j + 1 < n else 0))
                out += bytes([0, n]) + bytes(packed) + (b'\x00' if len(packed) % 2 else b'')
                i += n
        out += b'\x00\x00'
    out += b'\x00\x01'
    return bytes(out)


rows4r = [[(x // 3 + y) % 16 if x % 7 else x % 16 for x in range(25)] for y in range(5)]
bmp_case(write_bmp(25, 5, 4, rows4r, p16, compression=2, rle=rle4(list(reversed(rows4r)))),
         intended=b''.join(bytes(p16[v]) + bytes([255]) for row in rows4r for v in row))

# ---- TIFF ---------------------------------------------------------------------------------


def tiff_case(img, **save):
    buf = io.BytesIO()
    img.save(buf, 'TIFF', **save)
    blob = buf.getvalue()
    with Image.open(io.BytesIO(blob)) as im:
        im.load()
        w, h = im.size
        expected = rgba(im)
    check('tiff_ok(%s, %du32, %du32, %du32)' % (esc(blob), w, h, crc(expected)))
    return blob


rgb = noise_rgb(40, 30, 3)
smooth = Image.fromarray(gradient(70, 50))
for compression in (None, 'packbits', 'tiff_lzw', 'tiff_adobe_deflate'):
    save = {} if compression is None else {'compression': compression}
    tiff_case(smooth, **save)
    tiff_case(Image.fromarray(gradient(33, 21, alpha=True)), **save)
    tiff_case(Image.fromarray(gradient(25, 20)[:, :, 0]), **save)
tiff_case(rgb, compression='tiff_lzw')
tiff_case(noise_rgb(120, 90, 4), compression='tiff_lzw')                  # many strips, a full table
tiff_case(pal, compression='tiff_lzw')
tiff_case(pal)
tiff_case(bw)
tiff_case(bw, compression='packbits')
tiff_case(Image.new('LA', (9, 5), (80, 200)))
tiff_case(smooth, compression='tiff_lzw', tiffinfo={317: 2})              # horizontal predictor
big_endian = TiffImagePlugin.ImageFileDirectory_v2(ifh=b'MM\x00*\x00\x00\x00\x08')
tiff_case(smooth, compression='tiff_lzw', tiffinfo=big_endian)
tiff_case(smooth, tiffinfo=big_endian)

# ---- GIF ----------------------------------------------------------------------------------


def gif_palette(n=16):
    return [c for i in range(n) for c in ((i * 17) & 255, (i * 53) & 255, (i * 97) & 255)] + [0] * (768 - 3 * n)


def p_image(w, h, f, transparent=None):
    im = Image.new('P', (w, h))
    im.putpalette(gif_palette())
    im.putdata([f(x, y) for y in range(h) for x in range(w)])
    return im


def model_frames(frames, disposals, w, h, transparent):
    """The displayed canvas after each frame by the format's rules (the frames fill the screen)."""
    canvas = [(0, 0, 0, 0)] * (w * h)
    out = []
    saved = None
    prev = None
    pal = gif_palette()
    for index, frame in enumerate(frames):
        if prev is not None and prev == 2:
            canvas = [(0, 0, 0, 0)] * (w * h)
        elif prev == 3 and saved is not None:
            canvas = list(saved)
        saved = list(canvas)
        data = list(frame.getdata())
        for i, v in enumerate(data):
            if transparent is not None and v == transparent:
                continue
            canvas[i] = (pal[v * 3], pal[v * 3 + 1], pal[v * 3 + 2], 255)
        out.append(b''.join(bytes(p) for p in canvas))
        prev = disposals[index]
    return out


def gif_case(frames, durations, disposals, transparent=None, **extra):
    w, h = frames[0].size
    buf = io.BytesIO()
    kwargs = {'save_all': True, 'append_images': frames[1:], 'duration': durations, 'loop': 0, 'disposal': disposals, 'optimize': False}
    if len(frames) == 1:
        kwargs = {'duration': durations[0], 'disposal': disposals[0], 'optimize': False}
    if transparent is not None:
        kwargs['transparency'] = transparent
    kwargs.update(extra)
    frames[0].save(buf, 'GIF', **kwargs)
    blob = buf.getvalue()
    # Pillow's own decoder, frame by frame, as the second opinion
    pillow = []
    with Image.open(io.BytesIO(blob)) as im:
        for i in range(getattr(im, 'n_frames', 1)):
            im.seek(i)
            pillow.append(im.convert('RGBA').tobytes())
    record = b''
    expected = pillow
    if len(frames) > 1:
        model = model_frames(frames, [d if d is not None else 0 for d in disposals], w, h, transparent)
        # composition model of the format; Pillow's RGBA frames agree on the opaque pixels
        expected = model
        for m, p in zip(model, pillow):
            for i in range(0, len(m), 4):
                if m[i + 3] == 255 and p[i + 3] == 255:
                    assert m[i:i + 3] == p[i:i + 3], 'model and Pillow disagree'
    for frame_crc, delay, dis in zip([crc(e) for e in expected], durations, disposals):
        record += struct.pack('<IHB', frame_crc, delay // 10, dis or 0)
    check('gif_ok(%s, %du32, %du32, %du32, %s)' % (esc(blob), w, h, len(expected), esc(record)))
    return blob


f1 = p_image(24, 16, lambda x, y: (x + y) % 16)
f2 = p_image(24, 16, lambda x, y: (x * 2 + y) % 16)
f3 = p_image(24, 16, lambda x, y: 0 if (x // 3 + y // 3) % 2 else (x + 3 * y) % 16)
gif_case([f1], [100], [0])                                                       # one interlaced frame
gif_case([f1, f2, f3], [100, 150, 70], [1, 1, 1])
gif_case([f1, f3, f2], [30, 40, 50], [0, 0, 0], transparent=0)                  # transparency, frames left in place
gif_case([f1, f3, f2], [30, 40, 50], [2, 2, 2], transparent=0)                  # cleared after each frame
gif_case([f1, f3, f2], [30, 40, 50], [1, 3, 1], transparent=0)                  # restore previous
noise_gif = Image.new('P', (64, 64))
noise_gif.putpalette([c for i in range(256) for c in (i, 255 - i, (i * 7) & 255)])
noise_gif.putdata([rng.randrange(256) for _ in range(64 * 64)])
buf = io.BytesIO()
noise_gif.save(buf, 'GIF', optimize=False)
with Image.open(io.BytesIO(buf.getvalue())) as im:
    check('gif_ok(%s, 64u32, 64u32, 1u32, %s)' % (esc(buf.getvalue()), esc(struct.pack('<IHB', crc(rgba(im)), 0, 0))))   # table fills and resets

# ---- EXIF ---------------------------------------------------------------------------------
exif = Image.Exif()
exif[0x010F] = 'Neper Optics'
exif[0x0110] = 'NX-1 é'.encode('latin-1').decode('latin-1')
exif[0x0112] = 6
exif[0x0131] = 'fixture 1.0'
exif[0x0132] = '2026:10:11 12:34:56'
exif[0x011A] = IFDRational(72, 1)
exif[0x011B] = IFDRational(72, 1)
exif[0x0128] = 2
exif_ifd = exif.get_ifd(0x8769)
exif_ifd[0x829A] = IFDRational(1, 250)
exif_ifd[0x829D] = IFDRational(28, 5)
exif_ifd[0x8827] = 400
exif_ifd[0x9000] = b'0231'
exif_ifd[0x9003] = '2026:10:11 12:34:56'
gps = exif.get_ifd(0x8825)
gps[1] = 'N'
gps[2] = (IFDRational(52, 1), IFDRational(31, 1), IFDRational(25, 2))
gps[3] = 'E'
gps[4] = (IFDRational(13, 1), IFDRational(24, 1), IFDRational(21, 4))
blob_exif = exif.tobytes()
small = Image.new('RGB', (8, 8), (10, 120, 200))
jpeg = io.BytesIO()
small.save(jpeg, 'JPEG', exif=blob_exif)
png = io.BytesIO()
small.save(png, 'PNG', exif=blob_exif)
webp = io.BytesIO()
small.save(webp, 'WEBP', exif=blob_exif, lossless=True)
tif = io.BytesIO()
ti = TiffImagePlugin.ImageFileDirectory_v2()
small.save(tif, 'TIFF', exif=blob_exif)
with Image.open(io.BytesIO(jpeg.getvalue())) as im:
    read = im.getexif()
    read_exif = read.get_ifd(0x8769)
    read_gps = read.get_ifd(0x8825)
    assert read[0x010F] == 'Neper Optics' and read[0x0112] == 6
    assert abs(float(read_exif[0x829A]) - 1 / 250) < 1e-6
    assert [float(v) for v in read_gps[2]] == [52.0, 31.0, 12.5]


def rational(v):
    from fractions import Fraction
    f = Fraction(v).limit_denominator(1 << 24)
    return f.numerator, f.denominator


# the rationals as Pillow wrote them, read back from the block itself
for label, kind, data in (('jpeg', 0, jpeg.getvalue()), ('png', 1, png.getvalue()), ('webp', 2, webp.getvalue()), ('tiff', 3, tif.getvalue())):
    check('exif_text(%s, %du8, 0u8, 271u16, %s)' % (esc(data), kind, esc('Neper Optics')))
    check('exif_u32(%s, %du8, 0u8, 274u16, 0usize, 6u32)' % (esc(data), kind))
    check('exif_text(%s, %du8, 0u8, 305u16, %s)' % (esc(data), kind, esc('fixture 1.0')))
    check('exif_text(%s, %du8, 2u8, 36867u16, %s)' % (esc(data), kind, esc('2026:10:11 12:34:56')))
    check('exif_u32(%s, %du8, 2u8, 34855u16, 0usize, 400u32)' % (esc(data), kind))
    check('exif_rational(%s, %du8, 2u8, 33434u16, 0usize, 1u32, 250u32)' % (esc(data), kind))
    check('exif_rational(%s, %du8, 2u8, 33437u16, 0usize, 28u32, 5u32)' % (esc(data), kind))
    check('exif_text(%s, %du8, 3u8, 1u16, %s)' % (esc(data), kind, esc('N')))
    check('exif_rational(%s, %du8, 3u8, 2u16, 2usize, 25u32, 2u32)' % (esc(data), kind))
    check('exif_rational(%s, %du8, 3u8, 4u16, 2usize, 21u32, 4u32)' % (esc(data), kind))
    check('exif_orientation(%s, %du8, 6u32)' % (esc(data), kind))
check('exif_orientation(%s, 0u8, 1u32)' % esc(jpeg.getvalue()[:0] + io.BytesIO().getvalue() or b'\xff\xd8\xff\xd9'))
# a JPEG with no EXIF, a cyclic IFD chain and a wild count are refused or ignored, never followed
plain = io.BytesIO()
small.save(plain, 'JPEG')
check('exif_absent(%s)' % esc(plain.getvalue()))
check('exif_orientation(%s, 0u8, 1u32)' % esc(plain.getvalue()))
tiff_head = b'II*\x00\x08\x00\x00\x00'
loop = tiff_head + struct.pack('<H', 1) + struct.pack('<HHII', 0x010F, 2, 2, 0x4141) + struct.pack('<I', 8)   # next IFD is itself
check('exif_tags_fail(%s)' % esc(loop))
wild = tiff_head + struct.pack('<H', 1) + struct.pack('<HHII', 0x9286, 7, 0xFFFFFFFF, 0x00001000) + struct.pack('<I', 0)
check('exif_tags_fail(%s)' % esc(wild))
nest = tiff_head + struct.pack('<H', 1) + struct.pack('<HHII', 0x8769, 4, 1, 8) + struct.pack('<I', 0)       # exif IFD pointing back at IFD0
check('exif_tags_fail(%s)' % esc(nest))

# ---- hostile inputs: truncations and one-byte changes must not trap -----------------------------
check('survive_qoi(%s)' % esc(qoi_blob[:90]))
small_bmp = write_bmp(5, 3, 24, [[(i * 40 & 255, j * 60 & 255, 9) for i in range(5)] for j in range(3)])
check('survive_bmp(%s)' % esc(small_bmp))
small_rle = write_bmp(12, 3, 8, [[(i + j) % 5 for i in range(12)] for j in range(3)], p256, compression=1,
                      rle=rle8([[(i + j) % 5 for i in range(12)] for j in reversed(range(3))]))
check('survive_bmp(%s)' % esc(small_rle))
tiny_gif = io.BytesIO()
frames_tiny = [p_image(6, 5, lambda x, y: (x + y) % 8), p_image(6, 5, lambda x, y: (x * y) % 8)]
frames_tiny[0].save(tiny_gif, 'GIF', save_all=True, append_images=frames_tiny[1:], duration=[10, 10], loop=0, optimize=False, interlace=False)
check('survive_gif(%s)' % esc(tiny_gif.getvalue()))
tiny_tiff = io.BytesIO()
Image.fromarray(gradient(9, 7)).save(tiny_tiff, 'TIFF', compression='tiff_lzw')
check('survive_tiff(%s)' % esc(tiny_tiff.getvalue()))
tiny_packbits = io.BytesIO()
Image.fromarray(gradient(9, 7)[:, :, 0]).save(tiny_packbits, 'TIFF', compression='packbits')
check('survive_tiff(%s)' % esc(tiny_packbits.getvalue()))
check('survive_exif(%s)' % esc(blob_exif[:600]))
# declared dimensions past the limits are refused before any allocation
huge_bmp = bytearray(small_bmp)
struct.pack_into('<i', huge_bmp, 18, 1 << 30)
check('bmp_toolarge(%s)' % esc(bytes(huge_bmp)))
huge_qoi = bytearray(qoi_blob)
struct.pack_into('>II', huge_qoi, 4, 1 << 30, 1 << 30)
check('qoi_toolarge(%s)' % esc(bytes(huge_qoi)))
wide_gif = bytearray(tiny_gif.getvalue())
struct.pack_into('<HH', wide_gif, 6, 60000, 60000)
check('gif_toolarge(%s)' % esc(bytes(wide_gif)))
huge_tiff = bytearray(tiny_tiff.getvalue())
# patch ImageWidth (tag 256) to 1<<30 wherever it sits in the first IFD
ifd = struct.unpack('<I', huge_tiff[4:8])[0]
n = struct.unpack('<H', huge_tiff[ifd:ifd + 2])[0]
for i in range(n):
    e = ifd + 2 + i * 12
    if struct.unpack('<H', huge_tiff[e:e + 2])[0] == 256:
        struct.pack_into('<HHII', huge_tiff, e, 256, 4, 1, 1 << 30)
check('tiff_toolarge(%s)' % esc(bytes(huge_tiff)))

body = '\n'.join(lines)
template = (ROOT / 'scripts' / 'image_fixture_head.e').read_text(encoding='utf-8')
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(template.replace('@@CHECKS@@', body), encoding='utf-8', newline='\n')
print('wrote', OUT, 'checks', counter[0] - 1)
