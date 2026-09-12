# Writes src/main.e: Python's bz2 output for a seeded text with long runs (RLE1) at
# level 1 so that 250 KB spans three blocks, plus a small stream, and the checks.
import bz2
import random

random.seed(11)
words = ["neper", "burrows", "wheeler", "huffman", "move", "front", "block", "stream", "crc", "runs"]
parts = []
for i in range(36000):
    parts.append(random.choice(words))
    if i % 300 == 0:
        parts.append("a" * random.randint(5, 600))
text = (" ".join(parts)).encode()
big = bz2.compress(text, 1)
small_text = b"hello bzip2 hello bzip2 hello bzip2\n"
small = bz2.compress(small_text, 1)
assert len(text) > 200000


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


HEADER = '''// `e.fmt.bzip2`: Python's bz2 stream of a %d-byte text with long runs at level 1
// (three blocks; reference.py beside this fixture) read back in 7000-byte pulls and
// compared, a small stream read in 5-byte pulls, and the refusals: a flipped
// data byte (Checksum), a bad stream header and a truncated stream (Invalid), storage
// too small for the block size (TooLarge), an output limit below the text (TooLarge).
// Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.bzip2 as bzip2

fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

// Reads everything through a reader over `packed` in `pull`-byte pulls.
fn inflate(storage: []u8, packed: []const u8, out: []u8, pull: usize, limit: u64) -> (usize, err) {
    var source_state = io.SliceReader { data: packed, off: 0usize }
    let (r0, reader_error) = bzip2.reader(storage, io.slice_reader(&source_state), limit)
    if reader_error != ok { ret (0usize, reader_error) }
    var r = r0
    var total = 0usize
    while true {
        var stop = total + pull
        if stop > out.len { stop = out.len }
        let (count, read_error) = bzip2.read(&r, out[total..stop])
        if read_error == io.End { break }
        if read_error != ok { ret (total, read_error) }
        total += count
        if total == out.len { ret (total, io.TooSmall) }
    }
    ret (total, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
''' % len(text)

BODY = '''    let (needed, e1) = bzip2.storage_required(100000usize)
    if e1 != ok { os.exit(1) }
    let (storage, e2) = aligned(a, needed)
    if e2 != ok { os.exit(2) }
    let (out, e3) = mem.alloc[u8](a, text.len + 1usize)
    if e3 != ok { os.exit(3) }
    let (n1, e4) = inflate(storage, big, out, 7000usize, 10000000u64)
    if e4 != ok { os.exit(4) }
    if n1 != text.len || !str.eq(out[..n1], text) { os.exit(5) }
    let (n2, e5) = inflate(storage, small, out, 5usize, 10000000u64)
    if e5 != ok || !str.eq(out[..n2], small_text) { os.exit(6) }
    // Refusals.
    let (flipped, f_error) = mem.alloc[u8](a, big.len)
    if f_error != ok { os.exit(7) }
    mem.copy[u8](flipped, big)
    flipped[200] = flipped[200] ^ 1u8
    let (n3, e6) = inflate(storage, flipped, out, 7000usize, 10000000u64)
    if e6 != bzip2.Checksum && e6 != bzip2.Invalid { os.exit(8) }
    let (n4, e7) = inflate(storage, "BZx91AY&SY", out, 7000usize, 10000000u64)
    if e7 != bzip2.Invalid { os.exit(9) }
    let (n5, e8) = inflate(storage, big[..big.len / 2usize], out, 7000usize, 10000000u64)
    if e8 != bzip2.Invalid { os.exit(10) }
    let (small_needed, e9) = bzip2.storage_required(50000usize)
    if e9 != ok { os.exit(11) }
    let (n6, e10) = inflate(storage[..small_needed], big, out, 7000usize, 10000000u64)
    if e10 != bzip2.TooLarge { os.exit(12) }
    let (n7, e11) = inflate(storage, big, out, 7000usize, 1000u64)
    if e11 != bzip2.TooLarge { os.exit(13) }
    let (none, e12) = bzip2.storage_required(0usize)
    if e12 != bzip2.Invalid { os.exit(14) }
    let (huge, e13) = bzip2.storage_required(1000000usize)
    if e13 != bzip2.TooLarge { os.exit(15) }
    ret ok
}
'''

source = HEADER + "    let text = " + literal(text) + "\n    let big = " + literal(big) + "\n    let small_text = " + literal(small_text) + "\n    let small = " + literal(small) + "\n" + BODY
open('src/main.e', 'w', encoding='utf-8', newline='\n').write(source)
print(len(text), len(big), len(small))
