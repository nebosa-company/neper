"""Generate the net_http2 fixture: vectors from the python-hyper libraries (hpack, hyperframe).

Oracle, decode side: `hpack.Encoder` writes the header blocks (Huffman on and off, dynamic table size changes,
never-indexed fields) and `hyperframe.frame` serialises every frame type; Neper must read back what went in.
Oracle, encode side: Neper's `encode_block` output is produced by running the compiler (`--compiler PATH`, or the
NEPER_SELF environment variable) on an emitter built from the same scenarios, then checked here with
`hpack.Decoder` before it is written into the fixture as the golden bytes it is compared with.

    PYTHONPATH=DIR python scripts/http2_vectors.py --compiler neper-self.exe
"""
import argparse
import os
import random
import subprocess
import sys
import tempfile

import hpack
from hpack import huffman_constants as hc
from hpack.hpack import encode_integer
from hpack.huffman import HuffmanEncoder
from hyperframe import frame as hf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x48325041)
FIXTURE_DIR = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_http2')


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


NAMES = [':method', ':path', ':scheme', ':authority', 'content-type', 'user-agent', 'te', 'grpc-timeout', 'x-custom', 'cookie', 'accept',
         'content-length', 'authorization', 'x-' + 'a' * 20, 'etag', 'vary']
VALUES = ['GET', 'POST', '/', '/index.html', 'https', 'http', 'application/grpc', 'trailers', 'example.com', '127.0.0.1:50051', '100m', 'gzip, deflate',
          '', 'a', 'café'.encode('utf-8').decode('latin-1'), 'x' * 100, 'v' + '=' * 30, 'Bearer abcdef0123456789']


def header_list(n=None):
    n = n if n is not None else rng.randrange(0, 8)
    return [(rng.choice(NAMES), rng.choice(VALUES)) for _ in range(n)]


def tup(name, value):
    return (name.encode('latin-1'), value.encode('latin-1'))


lines = []


def add(*f):
    lines.append('\t'.join(str(x) for x in f))


# ---- header blocks written by hpack.Encoder, read by Neper
def hdr_text(headers):
    return ','.join(hx(n.encode('latin-1')) + '=' + hx(v.encode('latin-1')) for n, v in headers) or '-'


for case in range(40):
    table = rng.choice([4096, 4096, 256, 100, 0, 1024])
    enc = hpack.Encoder()
    enc.header_table_size = table
    huffman = rng.random() < 0.6
    blocks = []
    for b in range(rng.randrange(1, 5)):
        headers = header_list()
        if b > 0 and rng.random() < 0.4:
            enc.header_table_size = rng.choice([4096, 64, 512, 0, 4096])
        items = []
        for name, value in headers:
            if name in ('authorization', 'cookie') and rng.random() < 0.7:
                items.append(hpack.NeverIndexedHeaderTuple(name.encode('latin-1'), value.encode('latin-1')))
            else:
                items.append((name.encode('latin-1'), value.encode('latin-1')))
        block = enc.encode(items, huffman=huffman)
        # sanity: the library's decoder reads its own block the way the model says
        dec = hpack.Decoder()
        blocks.append((bytes(block), headers))
    # The decoder must follow the sequence, so check the whole sequence with one library decoder.
    dec = hpack.Decoder()
    dec.max_allowed_table_size = 4096
    for block, headers in blocks:
        got = [(bytes(n), bytes(v)) for n, v in dec.decode(block, raw=True)]
        assert got == [tup(n, v) for n, v in headers], (got, headers)
    add('H', table, ';'.join(hx(block) + ':' + hdr_text(headers) for block, headers in blocks))

# ---- invalid blocks (each refused by the library decoder too)
BAD = [bytes([0x80]), bytes([0xFF, 0x7F]), bytes([0xC0 | 0x3F, 0x00]), bytes([0x82, 0x20]), bytes([0x40, 0x03, 0x61]),
       bytes([0x40, 0x81, 0xFF, 0x00]), bytes([0x40, 0x84, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]), bytes([0x3F]), bytes([0x82, 0x3F, 0xE1, 0x1F]),
       bytes([0x00, 0x82, 0x1F, 0xFF, 0x00]), bytes([0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F])]
for block in BAD:
    try:
        hpack.Decoder().decode(block, raw=True)
        lib_refuses = False
    except Exception:
        lib_refuses = True
    add('E', hx(block), 'Compression' if lib_refuses else 'ok')

# ---- Huffman strings and integers
henc = HuffmanEncoder(hc.REQUEST_CODES, hc.REQUEST_CODES_LENGTH)
samples = [b'', b'a', b'www.example.com', b'no-cache', b'custom-key', b'custom-value', bytes(range(256)), b'\x00\xff' * 20, b'Mon, 21 Oct 2013 20:13:21 GMT']
samples += [bytes(rng.randrange(256) for _ in range(rng.randrange(1, 60))) for _ in range(15)]
for s in samples:
    add('U', hx(s), hx(henc.encode(s)))
for prefix in (1, 4, 5, 6, 7, 8):
    for value in (0, 1, 2 ** prefix - 2, 2 ** prefix - 1, 2 ** prefix, 127, 128, 255, 1337, 16384, 65535, 1 << 20, 2 ** 32 - 1):
        add('I', prefix, value, hx(bytes(encode_integer(value, prefix))))

# ---- frames (hyperframe)
def frame_bytes(f):
    return f.serialize()


def mk_frames():
    out = []
    out.append(hf.DataFrame(stream_id=3, data=bytes(rng.randrange(256) for _ in range(rng.randrange(0, 50))), flags=['END_STREAM'] if rng.random() < 0.5 else []))
    out.append(hf.DataFrame(stream_id=5, data=b'padded', pad_length=rng.randrange(0, 10), flags=['PADDED']))
    out.append(hf.HeadersFrame(stream_id=1, data=bytes(rng.randrange(256) for _ in range(rng.randrange(1, 30))), flags=['END_HEADERS', 'END_STREAM']))
    h = hf.HeadersFrame(stream_id=7, data=b'\x82\x86', flags=['END_HEADERS', 'PADDED', 'PRIORITY'], pad_length=3, depends_on=5, stream_weight=15, exclusive=True)
    out.append(h)
    out.append(hf.PriorityFrame(stream_id=9, depends_on=7, stream_weight=200, exclusive=False))
    out.append(hf.RstStreamFrame(stream_id=11, error_code=8))
    out.append(hf.SettingsFrame(settings={hf.SettingsFrame.HEADER_TABLE_SIZE: 4096, hf.SettingsFrame.ENABLE_PUSH: 0, hf.SettingsFrame.MAX_CONCURRENT_STREAMS: 100,
                                          hf.SettingsFrame.INITIAL_WINDOW_SIZE: 1 << 20, hf.SettingsFrame.MAX_FRAME_SIZE: 32768}))
    out.append(hf.SettingsFrame(flags=['ACK']))
    out.append(hf.PushPromiseFrame(stream_id=1, promised_stream_id=2, data=b'\x82', flags=['END_HEADERS']))
    out.append(hf.PingFrame(stream_id=0, opaque_data=b'12345678', flags=['ACK'] if rng.random() < 0.5 else []))
    out.append(hf.GoAwayFrame(stream_id=0, last_stream_id=13, error_code=2, additional_data=b'bye'))
    out.append(hf.WindowUpdateFrame(stream_id=0, window_increment=65535))
    out.append(hf.WindowUpdateFrame(stream_id=15, window_increment=1))
    out.append(hf.ContinuationFrame(stream_id=1, data=b'\x84', flags=['END_HEADERS']))
    return out


for f in mk_frames():
    raw = frame_bytes(f)
    flags = raw[4]
    add('F', hx(raw), raw[3], flags, int.from_bytes(raw[5:9], 'big') & 0x7FFFFFFF, hx(raw[9:]))
# a run of frames, and partial / oversize inputs
run = b''.join(frame_bytes(f) for f in mk_frames()[:5])
add('R', hx(run), 5)
whole = frame_bytes(hf.DataFrame(stream_id=1, data=b'x' * 40))
for cut in (0, 4, 8, 9, 20, len(whole) - 1):
    add('P', hx(whole[:cut]), 'Incomplete')
add('P', hx(whole), 'ok')
add('P', hx(b'\x00\x80\x00\x00\x00\x00\x00\x00\x01'), 'FrameSize')

# ---- settings payloads
for _ in range(8):
    n = rng.randrange(0, 6)
    pairs = [(rng.choice([1, 2, 3, 4, 5, 6, 8]), rng.randrange(0, 2 ** 31)) for _ in range(n)]
    payload = b''.join(i.to_bytes(2, 'big') + v.to_bytes(4, 'big') for i, v in pairs)
    add('S', hx(payload), ','.join('%d=%d' % p for p in pairs) or '-')
add('S', hx(b'\x00\x01\x00'), 'FrameSize')


# ---- encoder goldens (Neper's output, checked by hpack.Decoder)
def x_cases():
    cases = []
    for case in range(24):
        table = 4096
        huffman = rng.random() < 0.6
        sensitive = rng.choice([[], [], ['authorization'], ['cookie', 'authorization']])
        blocks = []
        for b in range(rng.randrange(1, 5)):
            h = header_list()
            if b == 0 and rng.random() < 0.3:
                h = [(':method', 'GET'), (':scheme', 'http'), (':path', '/'), (':authority', 'www.example.com')]
            blocks.append(h)
        announce = [None] * len(blocks)
        if rng.random() < 0.3:
            announce[0] = rng.choice([0, 256, 1024])
        if len(blocks) > 1 and rng.random() < 0.5:
            announce[1] = rng.choice([0, 64, 512, 4096])
            if len(blocks) > 2 and rng.random() < 0.5:
                announce[2] = rng.choice([4096, 100])
        cases.append((table, huffman, sensitive, blocks, announce))
    return cases


def x_line(index, case, goldens):
    table, huffman, sensitive, blocks, announce = case
    parts = []
    for i, h in enumerate(blocks):
        parts.append('%s:%s:%s' % ('-' if announce[i] is None else announce[i], hdr_text(h), ('g' + goldens[i]) if goldens else ''))
    return 'X\t%d\t%d\t%d\t%s\t%s' % (index, table, int(huffman),','.join(hx(s) for s in sensitive) or '-', ';'.join(parts))


CASES = x_cases()


def build(goldens_for):
    out = list(lines)
    for i, case in enumerate(CASES):
        out.append(x_line(i, case, goldens_for[i] if goldens_for else None))
    return out


def write_fixture(path, vector_lines, template_name='net_http2_template.e'):
    chunks, step = [], 25
    for i in range(0, len(vector_lines), step):
        body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in vector_lines[i:i + step]) + '\n'
        chunks.append('"' + body.replace('\n', BS + 'n') + '"')
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 100 + i) for i in range(len(chunks)))
    with open(os.path.join(ROOT, 'scripts', 'http2_fixture_template.e'), encoding='utf-8') as f:
        template = f.read()
    text = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', default=os.environ.get('NEPER_SELF', ''))
    args = ap.parse_args()
    if not args.compiler or not os.path.exists(args.compiler):
        sys.exit('--compiler (or NEPER_SELF) must name neper-self: the encode goldens are produced by running it')
    # pass 1: no goldens; the fixture prints the bytes it encodes
    tmp = tempfile.mkdtemp(prefix='neper-http2-')
    src = os.path.join(tmp, 'main.e')
    write_fixture(src, build(None))
    exe = os.path.join(tmp, 'emit.exe')
    r = subprocess.run([args.compiler, 'emit-executable', src, ROOT, 'x64', 'windows', exe], capture_output=True, text=True)
    if 'executable written' not in r.stdout:
        sys.exit('compile failed: ' + r.stdout + r.stderr)
    r = subprocess.run([exe], capture_output=True, text=True)
    goldens = {}
    for line in r.stdout.splitlines():
        if line.startswith('GOLD\t'):
            _, i, j, h = line.split('\t')
            goldens.setdefault(int(i), {})[int(j)] = h
    assert len(goldens) == len(CASES), (len(goldens), r.returncode, r.stdout[:400], r.stderr[:300])
    # check with the library decoder: every block must decode to the model's header list, in sequence
    final = {}
    for i, case in enumerate(CASES):
        table, huffman, sensitive, blocks, announce = case
        dec = hpack.Decoder()
        dec.max_allowed_table_size = 4096
        golds = []
        for j, h in enumerate(blocks):
            block = bytes.fromhex(goldens[i][j])
            got = [(bytes(n), bytes(v)) for n, v in dec.decode(block, raw=True)]
            assert got == [tup(n, v) for n, v in h], (i, j, got, h)
            golds.append(goldens[i][j])
        final[i] = golds
    write_fixture(os.path.join(FIXTURE_DIR, 'src', 'main.e'), build(final))
    print('%d vectors (%d encode goldens verified by hpack) -> net_http2' % (len(lines) + len(CASES), len(CASES)))


main()
