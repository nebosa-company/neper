# Writes src/main.e: an archive from Python's zipfile (a stored text, a directory, a
# deflated 3000-byte pattern) and a hand-built one whose central directory uses ZIP64
# saturation, plus the refusal variants. Run from this directory after a change.
import io
import struct
import zipfile
import zlib

text = b"stored entry: the quick brown fox jumps over the lazy dog\n" * 3
pattern = bytes(((i * 7) & 255) ^ ((i >> 5) & 255) for i in range(3000))

buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w') as z:
    z.writestr(zipfile.ZipInfo('a.txt'), text, compress_type=zipfile.ZIP_STORED)
    z.writestr(zipfile.ZipInfo('dir/'), b'')
    z.writestr(zipfile.ZipInfo('dir/b.bin'), pattern, compress_type=zipfile.ZIP_DEFLATED)
archive = buf.getvalue()

# A one-entry archive with every ZIP64 field saturated.
data = b'zip64 stored payload'
crc = zlib.crc32(data)
local = struct.pack('<IHHHHHIIIHH', 0x04034b50, 45, 0, 0, 0, 0, crc, len(data), len(data), 5, 0) + b'z.txt' + data
z64_extra = struct.pack('<HHQQQ', 1, 24, len(data), len(data), 0)
central = struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 45, 45, 0, 0, 0, 0, crc, 0xFFFFFFFF, 0xFFFFFFFF, 5, len(z64_extra), 0, 0, 0, 0, 0xFFFFFFFF) + b'z.txt' + z64_extra
cd_offset = len(local)
z64_eocd = struct.pack('<IQHHIIQQQQ', 0x06064b50, 44, 45, 45, 0, 0, 1, 1, len(central), cd_offset)
z64_locator = struct.pack('<IIQI', 0x07064b50, 0, cd_offset + len(central), 1)
eocd = struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0)
zip64 = local + central + z64_eocd + z64_locator + eocd
with zipfile.ZipFile(io.BytesIO(zip64)) as check:
    assert check.read('z.txt') == data

# Refusals: an encrypted flag, a bzip2 method, a `..` name, a CRC that does not match.
def variant(name_bytes, flags=0, method=None, crc_delta=0):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as z:
        z.writestr(zipfile.ZipInfo('x.txt'), b'hello', compress_type=zipfile.ZIP_STORED)
    raw = bytearray(buf.getvalue())
    cd = raw.index(b'PK\x01\x02')
    if flags:
        struct.pack_into('<H', raw, cd + 8, flags)
    if method is not None:
        struct.pack_into('<H', raw, cd + 10, method)
    if crc_delta:
        struct.pack_into('<I', raw, cd + 16, struct.unpack_from('<I', raw, cd + 16)[0] ^ crc_delta)
    if name_bytes:
        raw[cd + 46:cd + 46 + 5] = name_bytes
    return bytes(raw)

encrypted = variant(None, flags=1)
bzip = variant(None, method=12)
dotdot = variant(b'../ab')
badcrc = variant(None, crc_delta=1)


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


HEADER = '''// `e.fmt.zip`: Python's archive (a stored text, a directory, a DEFLATE entry) opened
// over an in-memory seeker, its entries listed, the deflated one read through
// `entry_reader` in 700-byte pulls and the stored one through `extract`; a hand-built
// archive with every ZIP64 field saturated; refusals for an encrypted entry, a bzip2
// method, a `..` name, a CRC mismatch, an entry limit of two, a byte limit below the
// pattern, and a source that is not an archive. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.zip as zip

type Source = struct { data: []const u8, off: usize }

fn source_read(ctx: *void, dst: []u8) -> (usize, err) {
    var s = mem.cast[*Source](ctx)
    if s.off >= s.data.len { ret (0usize, io.End) }
    var take = dst.len
    if s.data.len - s.off < take { take = s.data.len - s.off }
    mem.copy[u8](dst[..take], s.data[s.off..s.off + take])
    s.off += take
    ret (take, ok)
}

fn source_seek(ctx: *void, off: i64, whence: os.SeekWhence) -> (u64, err) {
    var s = mem.cast[*Source](ctx)
    var base = 0i64
    if whence == .Current { base = i64(s.off) }
    if whence == .End { base = i64(s.data.len) }
    let target_at = base + off
    if target_at < 0i64 || target_at > i64(s.data.len) { ret (0u64, io.End) }
    s.off = usize(target_at)
    ret (u64(target_at), ok)
}

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn open_over(a: *mem.Arena, s: *Source, limits: zip.Limits) -> (zip.Archive, err) {
    let reader = io.Reader { ctx: mem.cast[*void](s), read: source_read }
    let seeker = io.Seeker { ctx: mem.cast[*void](s), seek: source_seek }
    let (archive, open_error) = zip.open(a, reader, seeker, limits)
    ret (archive, open_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
'''

BODY = '''    var pattern: [3000]u8 = zero
    var i = 0usize
    while i < 3000usize {
        pattern[i] = u8((i * 7usize) & 255usize) ^ u8((i >> 5u32) & 255usize)
        i += 1usize
    }
    var limits: zip.Limits = zero
    limits.entries = 16usize
    limits.name_bytes = 64usize
    limits.entry_bytes = 100000u64
    limits.total_bytes = 1000000u64
    var source = Source { data: archive, off: 0usize }
    let (ar0, e1) = open_over(a, &source, limits)
    if e1 != ok { os.exit(1) }
    var ar = ar0
    let listed = zip.entries(&ar)
    if listed.len != 3usize { os.exit(2) }
    if !str.eq(listed[0].name, "a.txt") || listed[0].method != 0u16 || listed[0].size != u64(text.len) || listed[0].directory { os.exit(3) }
    if !str.eq(listed[1].name, "dir/") || !listed[1].directory || listed[1].size != 0u64 { os.exit(4) }
    if !str.eq(listed[2].name, "dir/b.bin") || listed[2].method != 8u16 || listed[2].size != 3000u64 || listed[2].compressed_size >= 3000u64 { os.exit(5) }
    // The deflated entry through a reader in 700-byte pulls.
    let words = zip.entry_storage() / 8usize + 1usize
    let (aligned, s_error) = mem.alloc[u64](a, words)
    if s_error != ok { os.exit(6) }
    let storage = mem.view(a, a.off - words * 8usize, words * 8usize)
    let (r0, e2) = zip.entry_reader(storage, &ar, 2usize)
    if e2 != ok { os.exit(7) }
    var r = r0
    var out: [4096]u8 = zero
    var filled = 0usize
    while true {
        var end = filled + 700usize
        if end > out.len { end = out.len }
        let (count, read_error) = io.read(&r, out[filled..end])
        if read_error == io.End { break }
        if read_error != ok { os.exit(8) }
        filled += count
    }
    if !same(out[..filled], pattern[0..]) { os.exit(9) }
    // The stored entry and the directory through extract.
    let (stored, e3) = zip.extract(a, &ar, 0usize)
    if e3 != ok || !same(stored, text) { os.exit(10) }
    let (empty, e4) = zip.extract(a, &ar, 1usize)
    if e4 != ok || empty.len != 0usize { os.exit(11) }
    let (again, e5) = zip.extract(a, &ar, 2usize)
    if e5 != ok || !same(again, pattern[0..]) { os.exit(12) }
    // ZIP64.
    var source64 = Source { data: zip64, off: 0usize }
    let (big0, e6) = open_over(a, &source64, limits)
    if e6 != ok { os.exit(13) }
    var big = big0
    let listed64 = zip.entries(&big)
    if listed64.len != 1usize || !str.eq(listed64[0].name, "z.txt") || listed64[0].size != 20u64 { os.exit(14) }
    let (payload, e7) = zip.extract(a, &big, 0usize)
    if e7 != ok || !str.eq(payload, "zip64 stored payload") { os.exit(15) }
    // Refusals.
    var enc_source = Source { data: encrypted, off: 0usize }
    let (v1, e8) = open_over(a, &enc_source, limits)
    if e8 != zip.Unsupported { os.exit(16) }
    var bz_source = Source { data: bzip, off: 0usize }
    let (v2, e9) = open_over(a, &bz_source, limits)
    if e9 != zip.Unsupported { os.exit(17) }
    var dot_source = Source { data: dotdot, off: 0usize }
    let (v3, e10) = open_over(a, &dot_source, limits)
    if e10 != zip.Invalid { os.exit(18) }
    var crc_source = Source { data: badcrc, off: 0usize }
    let (v4, e11) = open_over(a, &crc_source, limits)
    if e11 != ok { os.exit(19) }
    var bad = v4
    let (broken, e12) = zip.extract(a, &bad, 0usize)
    if e12 != zip.Checksum { os.exit(20) }
    var few = limits
    few.entries = 2usize
    var few_source = Source { data: archive, off: 0usize }
    let (v5, e13) = open_over(a, &few_source, few)
    if e13 != zip.TooLarge { os.exit(21) }
    var small = limits
    small.entry_bytes = 2999u64
    var small_source = Source { data: archive, off: 0usize }
    let (v6, e14) = open_over(a, &small_source, small)
    if e14 != zip.TooLarge { os.exit(22) }
    var junk_source = Source { data: text, off: 0usize }
    let (v7, e15) = open_over(a, &junk_source, limits)
    if e15 != zip.Invalid { os.exit(23) }
    ret ok
}
'''

parts = ["    let text = " + literal(text), "    let archive = " + literal(archive), "    let zip64 = " + literal(zip64),
         "    let encrypted = " + literal(encrypted), "    let bzip = " + literal(bzip), "    let dotdot = " + literal(dotdot),
         "    let badcrc = " + literal(badcrc)]
open('src/main.e', 'w', encoding='utf-8', newline='\n').write(HEADER + "\n".join(parts) + "\n" + BODY)
print(len(archive), len(zip64))
