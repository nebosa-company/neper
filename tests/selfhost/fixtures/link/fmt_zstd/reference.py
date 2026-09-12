# Writes src/main.e: frames from the zstandard package (libzstd) at three levels of a
# seeded text with runs, a small frame, an RLE-heavy frame, plus the checks; the
# module's own writer output is read back and also verified by libzstd during
# development. Run from this directory after a change.
import random

import zstandard

random.seed(5)
words = ["neper", "zstandard", "frame", "block", "huffman", "fse", "sequence", "literal", "offset", "repeat", "window", "checksum"]
parts = []
for i in range(40000):
    parts.append(random.choice(words))
    if i % 500 == 0:
        parts.append("z" * random.randint(3, 400))
text = (" ".join(parts)).encode()
frames = {}
for level in (1, 3, 19):
    frames[level] = zstandard.ZstdCompressor(level=level, write_checksum=True, write_content_size=True).compress(text)
small_text = b"hello hello hello hello zstd"
small = zstandard.ZstdCompressor(level=3, write_checksum=False).compress(small_text)
runs = zstandard.ZstdCompressor(level=1, write_checksum=True).compress(b"a" * 5000 + b"b" * 3 + b"a" * 5000)
assert len(text) > 250000


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


HEADER = '''// `e.fmt.zstd`: libzstd's frames of a %d-byte text at levels 1, 3 and 19 -- raw,
// RLE and compressed blocks with Huffman literals in one and four streams and every
// sequence mode -- read back in 9000-byte pulls (reference.py beside this fixture);
// a small frame without a checksum; an RLE-heavy frame; the writer's raw frame read
// back; refusals for a flipped byte (Checksum or Invalid), a bad magic, a skippable
// frame, a truncated frame, a window past the storage, an output limit below the
// text. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.zstd as zstd

fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

fn inflate(storage: []u8, packed: []const u8, out: []u8, pull: usize, limit: u64) -> (usize, err) {
    var source_state = io.SliceReader { data: packed, off: 0usize }
    let (r0, reader_error) = zstd.reader(storage, io.slice_reader(&source_state), limit)
    if reader_error != ok { ret (0usize, reader_error) }
    var r = r0
    var total = 0usize
    while true {
        var stop = total + pull
        if stop > out.len { stop = out.len }
        let (count, read_error) = zstd.read(&r, out[total..stop])
        if read_error == io.End { break }
        if read_error != ok { ret (total, read_error) }
        total += count
        if total == out.len { ret (total, io.TooSmall) }
    }
    ret (total, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
''' % len(text)

BODY = '''    let (needed, e1) = zstd.reader_storage(2097152usize)
    if e1 != ok { os.exit(1) }
    let (storage, e2) = aligned(a, needed)
    if e2 != ok { os.exit(2) }
    let (out, e3) = mem.alloc[u8](a, text.len + 1usize)
    if e3 != ok { os.exit(3) }
    let (n1, e4) = inflate(storage, level1, out, 9000usize, 10000000u64)
    if e4 != ok { os.exit(4) }
    if n1 != text.len || !str.eq(out[..n1], text) { os.exit(5) }
    let (n3, e5) = inflate(storage, level3, out, 9000usize, 10000000u64)
    if e5 != ok || !str.eq(out[..n3], text) { os.exit(6) }
    let (n19, e6) = inflate(storage, level19, out, 9000usize, 10000000u64)
    if e6 != ok || !str.eq(out[..n19], text) { os.exit(7) }
    let (n4, e7) = inflate(storage, small, out, 5usize, 10000000u64)
    if e7 != ok || !str.eq(out[..n4], small_text) { os.exit(8) }
    let (n5, e8) = inflate(storage, runs, out, 4096usize, 10000000u64)
    if e8 != ok || n5 != 10003usize || out[0] != 97u8 || out[5000] != 98u8 || out[10002] != 97u8 { os.exit(9) }
    // The writer, read back.
    let (packed, p_error) = mem.alloc[u8](a, text.len + 64usize)
    if p_error != ok { os.exit(10) }
    var sink_state = io.SliceWriter { data: packed, off: 0usize }
    let (w_storage, w_error) = aligned(a, zstd.writer_storage(.Balanced))
    if w_error != ok { os.exit(11) }
    let (w0, e9) = zstd.writer(w_storage, io.slice_writer(&sink_state), .Balanced)
    if e9 != ok { os.exit(12) }
    var w = w0
    let (c1, e10) = zstd.write(&w, text[..100000])
    if e10 != ok || c1 != 100000usize { os.exit(13) }
    let (c2, e11) = zstd.write(&w, text[100000..])
    if e11 != ok { os.exit(14) }
    if zstd.finish(&w) != ok { os.exit(15) }
    if packed[0] != 40u8 || packed[1] != 181u8 || packed[2] != 47u8 || packed[3] != 253u8 { os.exit(16) }
    let (n6, e12) = inflate(storage, packed[..sink_state.off], out, 9000usize, 10000000u64)
    if e12 != ok || !str.eq(out[..n6], text) { os.exit(17) }
    // Refusals.
    let (flipped, f_error) = mem.alloc[u8](a, level3.len)
    if f_error != ok { os.exit(18) }
    mem.copy[u8](flipped, level3)
    flipped[level3.len / 2usize] = flipped[level3.len / 2usize] ^ 1u8
    let (n7, e13) = inflate(storage, flipped, out, 9000usize, 10000000u64)
    if e13 != zstd.Checksum && e13 != zstd.Invalid { os.exit(19) }
    let (n8, e14) = inflate(storage, "\\x29\\xb5\\x2f\\xfd\\x04\\x38\\x01\\x00\\x00", out, 9000usize, 10000000u64)
    if e14 != zstd.Invalid { os.exit(20) }
    let (n9, e15) = inflate(storage, "\\x50\\x2a\\x4d\\x18\\x00\\x00\\x00\\x00", out, 9000usize, 10000000u64)
    if e15 != zstd.Unsupported { os.exit(21) }
    let (n10, e16) = inflate(storage, level3[..level3.len / 2usize], out, 9000usize, 10000000u64)
    if e16 != zstd.Invalid { os.exit(22) }
    let (small_needed, e17) = zstd.reader_storage(1024usize)
    if e17 != ok { os.exit(23) }
    let (n11, e18) = inflate(storage[..small_needed], level3, out, 9000usize, 10000000u64)
    if e18 != zstd.Unsupported { os.exit(24) }
    let (n12, e19) = inflate(storage, level3, out, 9000usize, 1000u64)
    if e19 != zstd.Invalid { os.exit(25) }
    let (none, e20) = zstd.reader_storage(0usize)
    if e20 != zstd.Invalid { os.exit(26) }
    ret ok
}
'''

source = (HEADER + "    let text = " + literal(text) + "\n    let level1 = " + literal(frames[1]) + "\n    let level3 = " + literal(frames[3])
          + "\n    let level19 = " + literal(frames[19]) + "\n    let small_text = " + literal(small_text) + "\n    let small = " + literal(small)
          + "\n    let runs = " + literal(runs) + "\n" + BODY)
open('src/main.e', 'w', encoding='utf-8', newline='\n').write(source)
print(len(text), {k: len(v) for k, v in frames.items()}, len(small), len(runs))
