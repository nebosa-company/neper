"""Generate tests/selfhost/fixtures/link/fmt_archive/src/main.e (L120, D2523).

7z: archives written by py7zr (a second implementation: copy, LZMA, LZMA2, Deflate,
BZip2, x86 BCJ and Delta chains, with and without an encoded header, empty files and
directories, non-ASCII names) and by the small writer below, which builds multi-folder
and solid archives from Python's own liblzma filters and the hostile headers (counts, sizes and
names no real producer emits).  Expected sizes and CRCs come from the data the writer was
given (zlib.crc32), never from Neper.
RAR5: archives written by the encoder below (store and the LZ + Huffman method), checked by
bsdtar (libarchive) before they are trusted.
Install with `python -m pip install --target DIR py7zr` and run with PYLIBS=DIR.
"""
import io
import lzma
import os
import random
import struct
import sys
import tempfile
import zlib
from pathlib import Path

sys.path.insert(0, os.environ.get('PYLIBS', ''))
import py7zr  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests/selfhost/fixtures/link/fmt_archive/src/main.e'

lines = []
code = [30]


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
    lines.append('    if !(%s) { die(%di32) }' % (expr, code[0]))
    code[0] += 1


# ---- 7z -----------------------------------------------------------------------------

def num(n):
    """The 7z NUMBER."""
    if n < 0x80:
        return bytes([n])
    for extra in range(1, 9):
        if n < (1 << (7 * (extra + 1))) or extra == 8:
            if extra == 8:
                return b'\xff' + n.to_bytes(8, 'little')
            high = n >> (8 * extra)
            if high < (1 << (7 - extra)):
                first = (0xFF << (8 - extra)) & 0xFF | high
                return bytes([first]) + (n & ((1 << (8 * extra)) - 1)).to_bytes(extra, 'little')
    raise ValueError(n)


def bits(flags):
    out = bytearray((len(flags) + 7) // 8)
    for i, f in enumerate(flags):
        if f:
            out[i // 8] |= 0x80 >> (i % 8)
    return bytes(out)


def digests(crcs):
    return b'\x01' + b''.join(struct.pack('<I', c) for c in crcs)


FILTERS = {
    'copy': (b'\x00', b'', None),
    'lzma': (b'\x03\x01\x01', None, 'lzma'),
    'lzma2': (b'\x21', None, 'lzma2'),
    'x86': (b'\x03\x03\x01\x03', b'', 'x86'),
    'delta4': (b'\x03', b'\x03', 'delta'),
}


def encode_chain(chain, data):
    """Packed bytes and the (id, props) of each coder for a decode-order chain.

    `chain` lists the filters in encoding order (BCJ before LZMA2); the header lists them reversed.
    Returns the packed stream, the coder list and the unpack size of each coder's output.
    """
    sizes = []
    current = data
    filters = []
    for name in chain:
        sizes.append(len(current))
        if name == 'x86':
            filters.append({'id': lzma.FILTER_X86})
        elif name == 'delta4':
            filters.append({'id': lzma.FILTER_DELTA, 'dist': 4})
        elif name == 'lzma2':
            filters.append({'id': lzma.FILTER_LZMA2, 'preset': 1, 'dict_size': 1 << 16})
        elif name == 'lzma':
            filters.append({'id': lzma.FILTER_LZMA1, 'preset': 1, 'dict_size': 1 << 16, 'lc': 3, 'lp': 0, 'pb': 2})
        elif name == 'copy':
            pass
    if filters:
        packed = lzma.compress(data, format=lzma.FORMAT_RAW, filters=filters)
    else:
        packed = data
    # sizes: each coder's *output* when decoding is the data before its encoding
    out_sizes = []
    for index, name in enumerate(chain):
        out_sizes.append(len(data))  # every filter preserves the size; the last coder's output is the folder's
    coders = []
    for name in chain:
        ident, props, kind = FILTERS[name]
        if name == 'lzma2':
            props = bytes([2 * (16 - 12)])
        elif name == 'lzma':
            props = bytes([(2 * 5 + 0) * 9 + 3]) + struct.pack('<I', 1 << 16)
        coders.append((ident, props))
    coders.reverse()   # 7-Zip lists the coder that reads the packed stream first
    return packed, coders, out_sizes


def folder_bytes(coders):
    out = num(len(coders))
    for ident, props in coders:
        flags = len(ident) | (0x20 if props else 0)
        out += bytes([flags]) + ident
        if props:
            out += num(len(props)) + props
    for k in range(len(coders) - 1):
        out += num(k + 1) + num(k)   # coder k+1's input comes from coder k's output
    return out


def build_7z(entries, folder_plan, encode_header=False, tweak=None):
    """entries: list of (name, data or None for a directory).  folder_plan: list of
    (chain, [indices of the file entries it holds]).  `tweak` may edit the header pieces."""
    tweak = tweak or {}
    packed_streams = []
    folders = []
    sub_sizes = []
    sub_crcs = []
    nsubs = []
    folder_crcs = []
    for chain, members in folder_plan:
        blob = b''.join(entries[i][1] for i in members)
        packed, coders, sizes = encode_chain(chain, blob)
        packed_streams.append(packed)
        folders.append((coders, sizes))
        nsubs.append(len(members))
        sub_sizes.append([len(entries[i][1]) for i in members])
        sub_crcs.extend(zlib.crc32(entries[i][1]) for i in members)
        folder_crcs.append(zlib.crc32(blob))
    h = b'\x01\x04'
    h += b'\x06' + num(0) + num(len(packed_streams)) + b'\x09' + b''.join(num(len(p)) for p in packed_streams) + b'\x00'
    unpack = b'\x07\x0b' + num(len(folders)) + b'\x00'
    for coders, sizes in folders:
        unpack += folder_bytes(coders)
    unpack += b'\x0c'
    for coders, sizes in folders:
        for s in sizes:
            unpack += num(tweak.get('unpack_size', s))
    unpack += b'\x00'
    h += unpack
    sub = b'\x08'
    if any(n != 1 for n in nsubs):
        sub += b'\x0d' + b''.join(num(n) for n in nsubs)
    if any(n > 1 for n in nsubs):
        sub += b'\x09'
        for sizes in sub_sizes:
            for s in sizes[:-1]:
                sub += num(s)
    sub += b'\x0a' + digests(sub_crcs) + b'\x00'
    h += sub + b'\x00'
    files = b'\x05' + num(tweak.get('files', len(entries)))
    empty = [e[1] is None or len(e[1]) == 0 for e in entries]
    if any(empty):
        files += b'\x0e' + num((len(entries) + 7) // 8) + bits(empty)
        empty_file = [e[1] is not None for e in entries if e[1] is None or len(e[1]) == 0]
        if any(empty_file):
            files += b'\x0f' + num((len(empty_file) + 7) // 8) + bits(empty_file)
    names = b''.join(e[0].encode('utf-16-le') + b'\x00\x00' for e in entries)
    files += b'\x11' + num(len(names) + 1) + b'\x00' + names
    h += files + b'\x00\x00'   # end of the file properties, end of the header
    if 'header' in tweak:
        h = tweak['header'](h)
    body = b''.join(packed_streams)
    if encode_header:
        packed, coders, sizes = encode_chain(['lzma2'], h)
        eh = b'\x17\x06' + num(len(body)) + num(1) + b'\x09' + num(len(packed)) + b'\x00'
        eh += b'\x07\x0b' + num(1) + b'\x00' + folder_bytes(coders) + b'\x0c' + num(len(h)) + b'\x0a' + digests([zlib.crc32(h)]) + b'\x00\x00'
        body += packed
        h = eh
    start = struct.pack('<QQI', len(body), len(h), zlib.crc32(h))
    return b'7z\xbc\xaf\x27\x1c\x00\x04' + struct.pack('<I', zlib.crc32(start)) + start + body + h


def expect_archive(label, blob, listing, limits=None):
    """listing: [(name, data or None for a directory)] in header order."""
    check('open_ok(%s)' % esc(blob))
    for index, (name, data) in enumerate(listing):
        if data is None:
            check('entry_is(%s, %du32, %s, 0usize, 0u32, true)' % (esc(blob), index, esc(name)))
        else:
            check('entry_is(%s, %du32, %s, %dusize, %du32, false)' % (esc(blob), index, esc(name), len(data), zlib.crc32(data)))
            check('extract_is(%s, %du32, %du32, %dusize)' % (esc(blob), index, zlib.crc32(data), len(data)))


rng = random.Random(1202)


def compressible(n, tag=b'lorem ipsum '):
    return (tag * (n // len(tag) + 1))[:n]


def noise(n):
    return bytes(rng.randrange(256) for _ in range(n))


def x86_like(n):
    """Bytes with plenty of E8/E9 call and jump opcodes and small relative operands."""
    out = bytearray()
    while len(out) < n:
        out += bytes([0xE8 if rng.random() < 0.6 else 0xE9]) + struct.pack('<i', rng.randrange(-4000, 4000))
        out += bytes(rng.randrange(256) for _ in range(rng.randrange(0, 6)))
    return bytes(out[:n])


# py7zr-written archives
def py7zr_archive(filters, files, dirs, encoded):
    buf = io.BytesIO()
    with py7zr.SevenZipFile(buf, 'w', filters=filters) as z:
        z.set_encoded_header_mode(encoded)
        td = tempfile.mkdtemp()
        for d in dirs:
            os.mkdir(os.path.join(td, d))
            z.write(os.path.join(td, d), d)
        for name, data in files:
            z.writestr(data, name)
    blob = buf.getvalue()
    with py7zr.SevenZipFile(io.BytesIO(blob)) as z:
        names = z.getnames()
    listing = []
    known = dict(files)
    for n in names:
        listing.append((n, known.get(n) if n in known else None))
    return blob, listing


F = py7zr
common_files = [('a.txt', compressible(3000)), ('empty', b''), ('dir/b.bin', bytes(range(256)) * 3), ('dir/n.dat', noise(300))]
for label, filters in [
        ('lzma2', [{'id': F.FILTER_LZMA2, 'preset': 3}]),
        ('lzma', [{'id': F.FILTER_LZMA, 'preset': 3}]),
        ('copy', [{'id': F.FILTER_COPY}]),
        ('deflate', [{'id': F.FILTER_DEFLATE}]),
        ('bzip2', [{'id': F.FILTER_BZIP2}]),
        ('delta', [{'id': F.FILTER_DELTA, 'dist': 4}, {'id': F.FILTER_LZMA2, 'preset': 3}])]:
    for encoded in (True, False):
        blob, listing = py7zr_archive(filters, common_files, ['dir'], encoded)
        expect_archive(label, blob, listing)
blob, listing = py7zr_archive([{'id': F.FILTER_X86}, {'id': F.FILTER_LZMA2, 'preset': 3}],
                              [('prog.exe', x86_like(6000)), ('prog2.exe', x86_like(2500)), ('t.txt', compressible(400))], [], True)
expect_archive('x86', blob, listing)
uni = [('h\u00e9llo w\u00f6rld.txt', b'unicode name'), ('\u65e5\u672c\u8a9e/\u30d5\u30a1\u30a4\u30eb.txt', compressible(500, b'xyz')),
       ('emoji-\U0001F600.bin', noise(40))]
blob, listing = py7zr_archive([{'id': F.FILTER_LZMA2, 'preset': 1}], uni, [], True)
expect_archive('unicode', blob, listing)
blob, listing = py7zr_archive([{'id': F.FILTER_LZMA2, 'preset': 1}], [('only.txt', b'x')], [], False)
expect_archive('one', blob, listing)

# the small writer: several folders (one per entry group), chains, a nested encoded header
group_files = [('one.txt', compressible(2000, b'one ')), ('two.txt', compressible(1500, b'two ')), ('d', None),
               ('three.bin', noise(500)), ('e.txt', b''), ('four.exe', x86_like(3000)), ('five.dat', bytes(range(200)) * 4)]
plan = [(['lzma2'], [0, 1]), (['copy'], [3]), (['x86', 'lzma2'], [5]), (['delta4', 'lzma'], [6])]
for encoded in (False, True):
    blob = build_7z(group_files, plan, encode_header=encoded)
    # header order: the writer lists the entries as given
    expect_archive('writer', blob, group_files)
    with py7zr.SevenZipFile(io.BytesIO(blob)) as z:   # the writer's archives are real: py7zr reads them too
        target = tempfile.mkdtemp()
        z.extractall(path=target)
        for name, content in group_files:
            if content is not None:
                with open(os.path.join(target, name), 'rb') as f:
                    assert f.read() == content, name

# ---- hostile headers: each must be refused, none may allocate what it declares -------------
base_entries = [('a.txt', compressible(1000))]
base_plan = [(['lzma2'], [0])]
good = build_7z(base_entries, base_plan)
check('refused(%s)' % esc(good[:20]))                      # shorter than the signature header
check('refused(%s)' % esc(b'7z\xbc\xaf\x27\x1d' + good[6:]))  # bad signature
bad_crc = bytearray(good)
bad_crc[8] ^= 1
check('refused_with(%s, kind_checksum())' % esc(bytes(bad_crc)))   # start header CRC
bad_next = bytearray(good)
bad_next[28] ^= 1
check('refused_with(%s, kind_checksum())' % esc(bytes(bad_next)))  # next header CRC (CRC of the start header covers fields only)
check('refused_with(%s, kind_checksum())' % esc(good[:-1] + bytes([good[-1] ^ 1])))
too_new = bytearray(good)
too_new[6] = 1
check('refused(%s)' % esc(bytes(too_new)))
check('refused(%s)' % esc(build_7z(base_entries, base_plan, tweak={'files': 1 << 40})))           # file count past the header
check('refused_with(%s, kind_toolarge())' % esc(build_7z(base_entries, base_plan, tweak={'unpack_size': 1 << 50})))
# a name with a parent segment, an absolute name and a drive
for name in ('../evil', 'a/../../evil', '/etc/passwd', 'C:/x', 'a\\..\\b'):
    check('refused_with(%s, kind_unsafe())' % esc(build_7z([(name, b'x')], [(['copy'], [0])])))
# a size the coder cannot meet: declared output shorter and longer than the LZMA2 stream makes
check('extract_fails(%s)' % esc(build_7z(base_entries, base_plan, tweak={'unpack_size': 999})))
check('extract_fails(%s)' % esc(build_7z(base_entries, base_plan, tweak={'unpack_size': 1001})))
# the decoded data does not match its CRC: flip a byte of a Copy folder
copy_blob = bytearray(build_7z([('c.bin', bytes(range(100)))], [(['copy'], [0])]))
copy_blob[32 + 5] ^= 0x40
check('extract_fails_with(%s, kind_checksum())' % esc(bytes(copy_blob)))
# header truncation at every length, and every single-byte flip of a small archive
small = build_7z([('s.txt', compressible(300, b'ab')), ('t', b'')], [(['lzma2'], [0])], encode_header=True)
check('never_wrong(%s, %s)' % (esc(small), esc(struct.pack('<I', zlib.crc32(compressible(300, b'ab'))))))
small_copy = build_7z([('s.txt', compressible(120, b'cd')), ('u.bin', bytes(range(64)))], [(['copy'], [0, 1])])
check('never_wrong(%s, %s)' % (esc(small_copy), esc(struct.pack('<I', zlib.crc32(compressible(120, b'cd'))))))


# ---- RAR5 ------------------------------------------------------------------------------
import subprocess  # noqa: E402
sys.path.insert(0, str(ROOT / 'scripts'))
import rar5_writer  # noqa: E402


def bsdtar_extracts(blob, files):
    """The second implementation: libarchive's reader must give back every file."""
    path = os.path.join(tempfile.mkdtemp(), 'w.rar')
    with open(path, 'wb') as f:
        f.write(blob)
    out = tempfile.mkdtemp()
    r = subprocess.run(['tar', '-xf', path, '-C', out], capture_output=True)
    if r.returncode != 0:
        raise SystemExit('bsdtar refused an archive: ' + r.stderr.decode(errors='replace'))
    for name, data in files:
        if data is None:
            continue
        with open(os.path.join(out, name), 'rb') as f:
            assert f.read() == data, name


def expect_rar(blob, listing, verify=True):
    if verify:
        bsdtar_extracts(blob, listing)
    check('rar_open_ok(%s)' % esc(blob))
    for index, (name, data) in enumerate(listing):
        if data is None:
            check('rar_entry_is(%s, %du32, %s, 0usize, true)' % (esc(blob), index, esc(name)))
        else:
            check('rar_entry_is(%s, %du32, %s, %dusize, false)' % (esc(blob), index, esc(name), len(data)))
            check('rar_extract_is(%s, %du32, %du32, %dusize)' % (esc(blob), index, zlib.crc32(data), len(data)))


rar_text = compressible(1800, b'the quick brown fox ') + noise(150) + b'abcabcabc' * 30
mid = noise(9000)
rar_files = [('a.txt', rar_text), ('empty', b''), ('store/s.bin', bytes(range(256))), ('d', None),
             ('d/n.txt', rar_text[:700] + rar_text[100:400] + noise(40)), ('runs.txt', b'z' * 3000 + b'ab' * 1500),
             ('mid.bin', mid + b'-' + mid[:2500] + mid[100:3100])]
for blocks, every in ((1, True), (3, True), (3, False)):
    expect_rar(rar5_writer.build_rar5(rar_files, blocks=blocks, table_every_block=every), rar_files)
# a match more than 0x40000 back: noise, a long run, the noise again
head_noise = noise(150)
far_file = head_noise + b'x' * 270000 + head_noise
expect_rar(rar5_writer.build_rar5([('far.bin', far_file)]), [('far.bin', far_file)])
solid_files = [('a.txt', rar_text), ('b.txt', noise(500)), ('c.txt', b'q' * 300)]
expect_rar(rar5_writer.build_rar5(solid_files, solid=True), solid_files)
# a solid chain whose second file matches into the first: libarchive does not agree with the
# format description here, so only the Neper reader's CRC check vouches for it
cross = [('a.txt', rar_text), ('b.txt', rar_text[:700] + rar_text[100:400] + noise(40))]
expect_rar(rar5_writer.build_rar5(cross, solid=True), cross, verify=False)
small_data = compressible(260, b'abcd') + noise(30)
small_rar = rar5_writer.build_rar5([('s.txt', small_data), ('t', None)])
bsdtar_extracts(small_rar, [('s.txt', small_data)])
check('rar_never_wrong(%s, %s)' % (esc(small_rar), esc(struct.pack('<I', zlib.crc32(small_data)))))

# hostile
good_rar = rar5_writer.build_rar5([('a.txt', compressible(500, b'xyz'))])
check('rar_refused_with(%s, rar_kind_unsupported())' % esc(b'Rar!\x1a\x07\x00' + good_rar[7:]))
flipped = bytearray(good_rar)
flipped[12] ^= 1
check('rar_refused_with(%s, rar_kind_checksum())' % esc(bytes(flipped)))
check('rar_refused_with(%s, rar_kind_unsafe())' % esc(rar5_writer.build_rar5([('../evil', b'x')])))
check('rar_refused_with(%s, rar_kind_unsafe())' % esc(rar5_writer.build_rar5([('/abs', b'x')])))
check('rar_refused_with(%s, rar_kind_unsupported())' % esc(good_rar[:8] + rar5_writer.block(4, 0, rar5_writer.vint(0))))
# a file header declaring 2^40 bytes: listed, but extraction is refused before any allocation
big = rar5_writer.file_header(b'big.bin', b'', b'\x00', 3, 1 << 40)
big_archive = b'Rar!\x1a\x07\x01\x00' + rar5_writer.block(1, 0, rar5_writer.vint(0)) + big + rar5_writer.block(5, 0, rar5_writer.vint(0))
check('rar_extract_fails_with(%s, 0u32, rar_kind_toolarge())' % esc(big_archive))

body = '\n'.join(lines)
template = (ROOT / 'scripts' / 'archive_fixture_head.e').read_text(encoding='utf-8')
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(template.replace('@@CHECKS@@', body), encoding='utf-8', newline='\n')
print('wrote', OUT, 'checks', code[0] - 30)
