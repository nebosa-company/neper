"""Generate the net_grpccodec fixture: gRPC message bodies compressed by Python's gzip and zlib, read back by Neper.

Oracle: Python's own gzip and zlib modules compress the bodies (so the compressed bytes are an independent implementation's
output) and the expected answer is the original body; corrupted and mismatched inputs expect the codec's error.

    python scripts/grpccodec_vectors.py
"""
import gzip
import os
import random
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x6772706)
FIXTURE_DIR = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_grpccodec')


def pay(p):
    if len(p) <= 1024:
        return p.hex()
    h = 0
    for b in p:
        h = (h * 31 + b) & 0xFFFFFFFF
    return 'L%d.%d' % (len(p), h)


lines = []


def add(name, encoding, data, limit, want):
    lines.append('\t'.join(['Z', name, encoding, data.hex(), str(limit), want]))


def bodies():
    out = [b'', b'x', b'hello hello hello hello', bytes(range(256)), b'compress me ' * 40, bytes((i * 7) & 255 for i in range(70000)),
           bytes(rng.randrange(256) for _ in range(900)), (b'abc' * 5000), b'\x00' * 3000]
    for _ in range(4):
        words = [bytes(rng.randrange(97, 123) for _ in range(rng.randrange(2, 9))) for _ in range(rng.randrange(1, 20))]
        out.append(b' '.join(rng.choice(words) for _ in range(rng.randrange(1, 400))))
    return out


for i, body in enumerate(bodies()):
    for level in (0, 1, 6, 9):
        add('gzip%d.%d' % (i, level), 'gzip', gzip.compress(body, compresslevel=level, mtime=0), 1 << 20, 'ok:' + pay(body))
        add('deflate%d.%d' % (i, level), 'deflate', zlib.compress(body, level), 1 << 20, 'ok:' + pay(body))
    add('identity%d' % i, 'identity', body, 1 << 20, 'ok:' + pay(body))

# a gzip member with a file name, produced by the module's own header form
member = bytearray(gzip.compress(b'named member ' * 20, mtime=0))
member[3] |= 8
member[10:10] = b'name.txt\x00'
add('gzip-fname', 'gzip', bytes(member), 1 << 20, 'ok:' + pay(b'named member ' * 20))

good_gzip = gzip.compress(b'checksums matter ' * 30, mtime=0)
good_zlib = zlib.compress(b'checksums matter ' * 30)
flip = bytearray(good_gzip)
flip[-6] ^= 1
add('gzip-crc', 'gzip', bytes(flip), 1 << 20, 'gzip.Checksum')
size = bytearray(good_gzip)
size[-1] ^= 1
add('gzip-isize', 'gzip', bytes(size), 1 << 20, 'gzip.Checksum')
magic = bytearray(good_gzip)
magic[1] = 140
add('gzip-magic', 'gzip', bytes(magic), 1 << 20, 'gzip.Invalid')
add('gzip-truncated', 'gzip', good_gzip[:len(good_gzip) // 2], 1 << 20, 'gzip.Invalid')
add('gzip-limit', 'gzip', good_gzip, 100, 'TooLarge')
adler = bytearray(good_zlib)
adler[-1] ^= 1
add('zlib-adler', 'deflate', bytes(adler), 1 << 20, 'zlib.Checksum')
header = bytearray(good_zlib)
header[0] = 0x79
add('zlib-header', 'deflate', bytes(header), 1 << 20, 'zlib.Invalid')
add('zlib-truncated', 'deflate', good_zlib[:len(good_zlib) // 2], 1 << 20, 'zlib.Invalid')
add('zlib-limit', 'deflate', good_zlib, 100, 'TooLarge')
add('snappy', 'snappy', b'abc', 1 << 20, 'Unsupported')
add('zstd', 'zstd', b'abc', 1 << 20, 'Unsupported')

step = 6
chunks = []
for i in range(0, len(lines), step):
    body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in lines[i:i + step]) + '\n'
    chunks.append('"' + body.replace('\n', BS + 'n') + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 1 + i) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'grpccodec_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
text = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
os.makedirs(os.path.join(FIXTURE_DIR, 'src'), exist_ok=True)
with open(os.path.join(FIXTURE_DIR, 'src', 'main.e'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(text)
print('%d vectors in %d chunks -> net_grpccodec' % (len(lines), len(chunks)))
