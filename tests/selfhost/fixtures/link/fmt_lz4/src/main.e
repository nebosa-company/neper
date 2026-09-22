// `e.fmt.lz4`: cramjam's block of a 300-byte repetitive text decoded back, the xxHash32
// vectors, a 2 KB LCG buffer with runs and repeats (FNV-pinned against reference.py
// beside this fixture) round-tripped strictly smaller, an incompressible 64-byte
// buffer and the empty input round-tripped, cramjam's frame (dependent blocks, block
// and content checksums) decoded, our own frame round-tripped, and three refusals.
// Our block of the buffer is pinned by FNV: those bytes decode with cramjam.
// Every check has its own exit code.
use e.algo.hash as hash
use e.fmt.lz4 as lz4
use e.io
use e.mem
use e.os

fn text() -> str { ret "the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over the lazy dog; the quick brown fox jumps over" }
fn block() -> str { ret "\xf0\x10\x74\x68\x65\x20\x71\x75\x69\x63\x6b\x20\x62\x72\x6f\x77\x6e\x20\x66\x6f\x78\x20\x6a\x75\x6d\x70\x73\x20\x6f\x76\x65\x72\x20\x1f\x00\x91\x6c\x61\x7a\x79\x20\x64\x6f\x67\x3b\x0e\x00\x0f\x2d\x00\xe3\x50\x20\x6f\x76\x65\x72" }
fn frame() -> str { ret "\x04\x22\x4d\x18\x54\x40\xae\x37\x00\x00\x00\xf0\x10\x74\x68\x65\x20\x71\x75\x69\x63\x6b\x20\x62\x72\x6f\x77\x6e\x20\x66\x6f\x78\x20\x6a\x75\x6d\x70\x73\x20\x6f\x76\x65\x72\x20\x1f\x00\xaf\x6c\x61\x7a\x79\x20\x64\x6f\x67\x3b\x20\x2d\x00\xe7\x50\x20\x6f\x76\x65\x72\x4b\x71\x9d\xab\x00\x00\x00\x00\x22\xe8\x51\x80" }

fn bytes_equal(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn lcg(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

// Mirrors gen(2048) in reference.py: runs, copies of earlier bytes, and literals.
fn generate(out: []u8, n: usize) -> usize {
    var len = 0usize
    var state = 42u64
    while len < n {
        let r = lcg(&state)
        let kind = r % 4u64
        if kind == 0u64 {
            let v = u8(lcg(&state) & 255u64)
            let count = 5usize + usize(r % 20u64)
            var k = 0usize
            while k < count {
                out[len + k] = v
                k += 1usize
            }
            len += count
        } else if kind == 1u64 && len > 16usize {
            let start = usize((r >> 8u32) % u64(len - 8usize))
            var count = 8usize + usize((r >> 4u32) % 24u64)
            if start + count > len { count = len - start }
            var k = 0usize
            while k < count {
                out[len + k] = out[start + k]
                k += 1usize
            }
            len += count
        } else {
            let count = 1usize + usize(r % 8u64)
            var k = 0usize
            while k < count {
                out[len + k] = u8(lcg(&state) & 255u64)
                k += 1usize
            }
            len += count
        }
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    var table: [4096]u32 = zero
    var out: [4096]u8 = zero
    var packed: [4096]u8 = zero

    // 1: cramjam's block decodes to the text.
    let (n1, e1) = lz4.decode(block(), out[..])
    if e1 != ok || !bytes_equal(out[..n1], text()) { os.exit(1i32) }

    // 2: xxHash32 vectors (Python xxhash).
    if lz4.xxh32("", 0u32) != 46947589u32 || lz4.xxh32("a", 0u32) != 1426945110u32 || lz4.xxh32(text(), 0u32) != 2152851490u32 { os.exit(2i32) }

    // 3: the LCG buffer matches the reference generator.
    var buf: [2112]u8 = zero
    let buf_len = generate(buf[..], 2048usize)
    if hash.fnv1a64(buf[..buf_len]) != 2491127703899124676u64 || lz4.xxh32(buf[..buf_len], 0u32) != 3755585349u32 { os.exit(3i32) }

    // 4: it compresses strictly smaller ...
    if lz4.table_required() != 4096usize || lz4.bound(2048usize) < 2048usize { os.exit(4i32) }
    let (p4, e4) = lz4.encode(buf[..buf_len], packed[..], table[..])
    // (these 1017 bytes decode with cramjam to the buffer; reference.py's conformance step)
    if e4 != ok || p4 != 1017usize || hash.fnv1a64(packed[..p4]) != 10476816903218057689u64 { os.exit(4i32) }
    // 5: ... and round-trips.
    let (n5, e5) = lz4.decode(packed[..p4], out[..])
    if e5 != ok || !bytes_equal(out[..n5], buf[..buf_len]) { os.exit(5i32) }

    // 6: 64 incompressible bytes are a token, one extension byte and the literals.
    var inc: [64]u8 = zero
    var state = 7u64
    var i = 0usize
    while i < 64usize {
        inc[i] = u8(lcg(&state) & 255u64)
        i += 1usize
    }
    if lz4.xxh32(inc[..], 0u32) != 593587182u32 { os.exit(6i32) }
    let (p6, e6) = lz4.encode(inc[..], packed[..], table[..])
    if e6 != ok || p6 != 66usize { os.exit(6i32) }
    let (n6, e6b) = lz4.decode(packed[..p6], out[..])
    if e6b != ok || !bytes_equal(out[..n6], inc[..]) { os.exit(6i32) }
    // 7: the empty input is the single zero token.
    let (p7, e7) = lz4.encode(inc[..0usize], packed[..], table[..])
    if e7 != ok || p7 != 1usize || packed[0] != 0u8 { os.exit(7i32) }
    let (n7, e7b) = lz4.decode(packed[..p7], out[..])
    if e7b != ok || n7 != 0usize { os.exit(7i32) }

    // 8: cramjam's frame (dependent blocks, block and content checksums).
    let (n8, e8) = lz4.decode_frame(frame(), out[..])
    if e8 != ok || !bytes_equal(out[..n8], text()) { os.exit(8i32) }
    // 9: our own frame round-trips.
    let (p9, e9) = lz4.encode_frame(buf[..buf_len], packed[..], table[..])
    if e9 != ok || p9 > lz4.frame_bound(buf_len) { os.exit(9i32) }
    let (n9, e9b) = lz4.decode_frame(packed[..p9], out[..])
    if e9b != ok || !bytes_equal(out[..n9], buf[..buf_len]) { os.exit(9i32) }

    // 10: a truncated block is Invalid; 11: a short destination is TooSmall.
    let (_, e10) = lz4.decode(block()[..30usize], out[..])
    if e10 != lz4.Invalid { os.exit(10i32) }
    let (_, e11) = lz4.decode(block(), out[..100usize])
    if e11 != lz4.TooSmall { os.exit(11i32) }
    var corrupt: [78]u8 = zero
    i = 0usize
    while i < 78usize {
        corrupt[i] = frame()[i]
        i += 1usize
    }
    corrupt[77] ^= 1u8
    let (_, e12) = lz4.decode_frame(corrupt[..], out[..])
    if e12 != lz4.Invalid { os.exit(12i32) }

    try io.print("fmt lz4 ok\n")
    ret ok
}
