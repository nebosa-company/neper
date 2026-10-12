"""Generate the net_grpccompress fixture: the send side of gRPC message compression (`e.net.grpccodec.compress`).

Oracle: the bodies are defined by formulas this script and the fixture both evaluate; Python's zlib computes the CRC-32
and Adler-32 the trailers must carry, and Python's gzip and zlib modules decompress what Neper wrote (the `dump` argument
of the built fixture prints each compressed message as hex; `python scripts/grpccompress_vectors.py --check DUMP`
decompresses them and compares with the body, which is the independent half of the evidence).

    python scripts/grpccompress_vectors.py                # write the fixture
    fixture.exe dump > dump.txt && python scripts/grpccompress_vectors.py --check dump.txt
"""
import gzip
import os
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_grpccompress', 'src', 'main.e')

# (kind, length): 0 = (i * 7) & 255, 1 = a linear congruential stream, 2 = "abc" repeated, 3 = zeros, 4 = words
CASES = [(0, 0), (0, 1), (0, 23), (0, 256), (0, 1000), (0, 70000), (1, 1), (1, 900), (1, 5000), (1, 65535), (1, 65536), (1, 200000),
         (2, 15000), (3, 3000), (3, 100000), (4, 400), (4, 20000)]


def body(kind, n):
    out = bytearray()
    state = 12345
    for i in range(n):
        if kind == 0:
            out.append((i * 7) & 255)
        elif kind == 1:
            state = (state * 1103515245 + 12345) & 0x7FFFFFFF
            out.append((state >> 16) & 255)
        elif kind == 2:
            out.append(97 + i % 3)
        elif kind == 3:
            out.append(0)
        else:
            words = (b'alpha ', b'beta ', b'gamma ', b'delta ', b'epsilon ')
            state = (state * 1103515245 + 12345) & 0x7FFFFFFF
            w = words[(state >> 16) % 5]
            out.append(w[i % len(w)])
    return bytes(out)


def check(path):
    bad = 0
    for line in open(path):
        parts = line.split()
        if len(parts) != 5 or parts[0] != 'Z':
            continue
        _, kind, n, encoding, data = parts
        want = body(int(kind), int(n))
        raw = bytes.fromhex(data)
        got = gzip.decompress(raw) if encoding == 'gzip' else zlib.decompress(raw)
        if got != want:
            print('MISMATCH', kind, n, encoding)
            bad += 1
    print('checked, %d mismatches' % bad)
    return 1 if bad else 0


if len(sys.argv) == 3 and sys.argv[1] == '--check':
    sys.exit(check(sys.argv[2]))

rows = []
for kind, n in CASES:
    b = body(kind, n)
    rows.append('%d %d %08x %08x' % (kind, n, zlib.crc32(b) & 0xFFFFFFFF, zlib.adler32(b) & 0xFFFFFFFF))
vectors = '\\n'.join(rows) + '\\n'

source = r'''// `e.net.grpccodec` send side (`compress`, `compress_message`, `choose_encoding`): scripts/grpccompress_vectors.py defines
// the bodies by formula and Python's zlib computes the CRC-32 and Adler-32 each trailer must carry. A message in `gzip`
// starts with the fixed header and ends with the CRC-32 and the length; one in `deflate` is a zlib stream that ends with
// the Adler-32; both are read back by `inflate`; a message under the threshold goes as it is, flag clear; the choice of
// encoding follows the peer's list. `dump` as the argument prints every compressed message as hex so the Python modules
// can decompress them. Generated; do not edit.
use e.io
use e.mem
use e.net.grpccodec as codec
use e.os
use e.str

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(90) }
    ret out
}

fn digit(c: u8) -> u64 {
    if c >= 97u8 { ret u64(c) - 87u64 }
    ret u64(c) - 48u64
}

fn parse_number(s: str, base: u64) -> u64 {
    var v = 0u64
    var at = 0usize
    while at < s.len {
        v = v * base + digit(s[at])
        at += 1usize
    }
    ret v
}

fn hex_char(n: u8) -> u8 {
    if n < 10u8 { ret 48u8 + n }
    ret 87u8 + n
}

fn body(a: *mem.Arena, kind: u64, n: usize) -> []u8 {
    let (out, e) = mem.alloc[u8](a, n + 1usize)
    if e != ok { os.exit(91) }
    var state = 12345u64
    var i = 0usize
    while i < n {
        if kind == 0u64 {
            out[i] = u8((i * 7usize) & 255usize)
        } else if kind == 1u64 {
            state = (state * 1103515245u64 + 12345u64) & 2147483647u64
            out[i] = u8((state >> 16u32) & 255u64)
        } else if kind == 2u64 {
            out[i] = u8(97usize + i % 3usize)
        } else if kind == 3u64 {
            out[i] = 0u8
        } else {
            state = (state * 1103515245u64 + 12345u64) & 2147483647u64
            let pick = (state >> 16u32) % 5u64
            var word = "alpha "
            if pick == 1u64 { word = "beta " }
            if pick == 2u64 { word = "gamma " }
            if pick == 3u64 { word = "delta " }
            if pick == 4u64 { word = "epsilon " }
            out[i] = word[i % word.len]
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn same(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn u32_at(b: []const u8, at: usize, big: bool) -> u32 {
    if big {
        ret (u32(b[at]) << 24u32) | (u32(b[at + 1usize]) << 16u32) | (u32(b[at + 2usize]) << 8u32) | u32(b[at + 3usize])
    }
    ret (u32(b[at + 3usize]) << 24u32) | (u32(b[at + 2usize]) << 16u32) | (u32(b[at + 1usize]) << 8u32) | u32(b[at])
}

fn dump_hex(a: *mem.Arena, b: []const u8) -> str {
    let (out, e) = mem.alloc[u8](a, b.len * 2usize + 1usize)
    if e != ok { os.exit(92) }
    var i = 0usize
    while i < b.len {
        out[i * 2usize] = hex_char(b[i] / 16u8)
        out[i * 2usize + 1usize] = hex_char(b[i] % 16u8)
        i += 1usize
    }
    ret out[0usize..b.len * 2usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var dumping = false
    if args.len > 1usize && str.eq(args[1], "dump") { dumping = true }
    let table = "@@VECTORS@@"
    var start = 0usize
    var at = 0usize
    var count = 0usize
    while at < table.len {
        if table[at] == 10u8 {
            let line = table[start..at]
            start = at + 1usize
            let mark = mem.mark(a)
            // kind length crc adler
            var fields: [4]str = zero
            var f = 0usize
            var from = 0usize
            var k = 0usize
            while k <= line.len {
                if k == line.len || line[k] == 32u8 {
                    if f < 4usize { fields[f] = line[from..k] }
                    f += 1usize
                    from = k + 1usize
                }
                k += 1usize
            }
            let kind = parse_number(fields[0], 10u64)
            let n = usize(parse_number(fields[1], 10u64))
            let crc = u32(parse_number(fields[2], 16u64))
            let adler = u32(parse_number(fields[3], 16u64))
            let original = body(a, kind, n)
            // gzip
            let (gz, gz_error) = codec.compress(a, "gzip", original)
            if gz_error != ok { os.exit(10) }
            if gz.len < 18usize { os.exit(11) }
            if gz[0] != 31u8 || gz[1] != 139u8 || gz[2] != 8u8 || gz[3] != 0u8 { os.exit(12) }
            if u32_at(gz, gz.len - 8usize, false) != crc { os.exit(13) }
            if u32_at(gz, gz.len - 4usize, false) != u32(n) { os.exit(14) }
            let (back_gz, back_gz_error) = codec.inflate(a, "gzip", gz, 1usize << 20u32)
            if back_gz_error != ok || !same(back_gz, original) { os.exit(15) }
            // deflate (a zlib stream)
            let (zl, zl_error) = codec.compress(a, "deflate", original)
            if zl_error != ok { os.exit(20) }
            if zl.len < 6usize { os.exit(21) }
            if (u32(zl[0]) & 15u32) != 8u32 || ((u32(zl[0]) * 256u32 + u32(zl[1])) % 31u32) != 0u32 { os.exit(22) }
            if u32_at(zl, zl.len - 4usize, true) != adler { os.exit(23) }
            let (back_zl, back_zl_error) = codec.inflate(a, "deflate", zl, 1usize << 20u32)
            if back_zl_error != ok || !same(back_zl, original) { os.exit(24) }
            if dumping {
                let one = io.print(cat(a, cat(a, cat(a, "Z ", cat(a, fields[0], cat(a, " ", cat(a, fields[1], " gzip ")))), dump_hex(a, gz)), "\n"))
                let two = io.print(cat(a, cat(a, cat(a, "Z ", cat(a, fields[0], cat(a, " ", cat(a, fields[1], " deflate ")))), dump_hex(a, zl)), "\n"))
            }
            // the message-level helper: below the threshold as it is, at or above it compressed and flagged
            let (small, small_error) = codec.compress_message(a, "gzip", original, n + 1usize)
            if small_error != ok || small.compressed || !same(small.body, original) { os.exit(30) }
            let (big, big_error) = codec.compress_message(a, "gzip", original, n)
            if big_error != ok || !big.compressed || !same(big.body, gz) { os.exit(31) }
            let (plain, plain_error) = codec.compress_message(a, "identity", original, 0usize)
            if plain_error != ok || plain.compressed || !same(plain.body, original) { os.exit(32) }
            let (none, none_error) = codec.compress_message(a, "", original, 0usize)
            if none_error != ok || none.compressed { os.exit(33) }
            count += 1usize
            mem.reset(a, mark)
        }
        at += 1usize
    }
    if count != @@COUNT@@usize { os.exit(40) }
    // an encoding this codec does not write
    let (unsupported, unsupported_error) = codec.compress(a, "br", "x")
    if unsupported_error != codec.Unsupported { os.exit(41) }
    // the choice of encoding follows the peer's order and skips what is not written here
    if !str.eq(codec.choose_encoding("gzip, deflate"), "gzip") { os.exit(50) }
    if !str.eq(codec.choose_encoding("deflate,gzip"), "deflate") { os.exit(51) }
    if !str.eq(codec.choose_encoding("br, zstd, gzip"), "gzip") { os.exit(52) }
    if !str.eq(codec.choose_encoding("  gzip  "), "gzip") { os.exit(53) }
    if !str.eq(codec.choose_encoding("br,identity"), "identity") { os.exit(54) }
    if !str.eq(codec.choose_encoding(""), "identity") { os.exit(55) }
    if !str.eq(codec.choose_encoding("gzipx,deflate"), "deflate") { os.exit(56) }
    if !dumping { try io.print("net grpccompress ok") }
    ret ok
}
'''
source = source.replace('@@VECTORS@@', vectors).replace('@@COUNT@@', str(len(CASES)))
os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
with open(FIXTURE, 'w', encoding='utf-8', newline='\n') as f:
    f.write(source)
print('%d cases -> net_grpccompress' % len(CASES))
