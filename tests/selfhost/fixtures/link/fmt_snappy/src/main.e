// `e.fmt.snappy`: a cramjam raw stream of a 300-byte repetitive text decodes
// to the text, a 3 KB LCG buffer with runs and repeats roundtrips below its
// size, an incompressible 50-byte buffer and an empty input roundtrip,
// `decoded_length` reads the preamble, the strict decoder refuses a bad copy
// and a short `dst`, and the framing format decodes a cramjam stream, checks
// the CRC32C vector and roundtrips. Each check exits with its own code.
use e.fmt.snappy as snappy
use e.io
use e.mem
use e.os

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn lcg(state: u64) -> u64 { ret state *% 6364136223846793005u64 +% 1442695040888963407u64 }

// A buffer of runs, back-references and random bytes from an LCG (mirrored in ref.py).
fn fill(out: []u8, seed: u64) {
    var state = seed
    var n = 0usize
    while n < out.len {
        state = lcg(state)
        let r = state >> 33u32
        let mode = r % 3u64
        if mode == 0u64 {
            let b = u8((r >> 8u32) & 255u64)
            var k = 8usize + usize((r >> 16u32) % 40u64)
            while k > 0usize && n < out.len {
                out[n] = b
                n += 1usize
                k -= 1usize
            }
        } else if mode == 1u64 && n >= 64usize {
            let off = 1usize + usize((r >> 8u32) % 60u64)
            var k = 4usize + usize((r >> 16u32) % 30u64)
            while k > 0usize && n < out.len {
                out[n] = out[n - off]
                n += 1usize
                k -= 1usize
            }
        } else {
            var k = 1usize + usize((r >> 16u32) % 12u64)
            while k > 0usize {
                state = lcg(state)
                if n < out.len {
                    out[n] = u8((state >> 33u32) & 255u64)
                    n += 1usize
                }
                k -= 1usize
            }
        }
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var table: [16384]u16 = zero
    let phrase = "the quick brown fox jumps over the lazy dog. "
    var text: [300]u8 = zero
    var i = 0usize
    while i < 300usize {
        text[i] = phrase[i % phrase.len]
        i += 1usize
    }
    let raw300: [60]u8 = [60]u8{ 172, 2, 120, 116, 104, 101, 32, 113, 117, 105, 99, 107, 32, 98, 114, 111, 119, 110, 32, 102, 111, 120, 32, 106, 117, 109, 112, 115, 32, 111, 118, 101, 114, 32, 1, 31, 32, 108, 97, 122, 121, 32, 100, 111, 103, 46, 5, 14, 254, 45, 0, 254, 45, 0, 254, 45, 0, 234, 45, 0 }

    // 1: decode the cramjam raw stream.
    var out: [4096]u8 = zero
    let (n1, e1) = snappy.decode(raw300[..], out[..])
    if e1 != ok || n1 != 300usize || !same(out[..300usize], text[..]) { os.exit(1i32) }

    // 2: roundtrip of the 3 KB LCG buffer, strictly smaller.
    var buf: [3072]u8 = zero
    fill(buf[..], 12345u64)
    var packed: [4096]u8 = zero
    let (n2, e2) = snappy.encode(buf[..], packed[..], table[..])
    if e2 != ok || n2 >= 3072usize { os.exit(2i32) }
    let (m2, d2) = snappy.decode(packed[..n2], out[..])
    if d2 != ok || m2 != 3072usize || !same(out[..3072usize], buf[..]) { os.exit(2i32) }

    // 3: incompressible 50 bytes and an empty input roundtrip.
    var inc: [50]u8 = zero
    var state = 999u64
    i = 0usize
    while i < 50usize {
        state = lcg(state)
        inc[i] = u8((state >> 33u32) & 255u64)
        i += 1usize
    }
    let (n3, e3) = snappy.encode(inc[..], packed[..], table[..])
    if e3 != ok || n3 != 52usize { os.exit(3i32) }
    let (m3, d3) = snappy.decode(packed[..n3], out[..])
    if d3 != ok || m3 != 50usize || !same(out[..50usize], inc[..]) { os.exit(3i32) }
    let (n0, e0) = snappy.encode(inc[..0usize], packed[..], table[..])
    if e0 != ok || n0 != 1usize || packed[0] != 0u8 { os.exit(3i32) }
    let (m0, d0) = snappy.decode(packed[..1usize], out[..0usize])
    if d0 != ok || m0 != 0usize { os.exit(3i32) }

    // 4: decoded_length and bound.
    let (len4, e4) = snappy.decoded_length(raw300[..])
    if e4 != ok || len4 != 300usize || snappy.bound(300usize) != 382usize { os.exit(4i32) }

    // 5: strictness: a copy before the start, a short dst, a truncated literal.
    var bad: [4]u8 = [4]u8{ 4, 1, 0, 0 }
    let (_, e5a) = snappy.decode(bad[..], out[..])
    if e5a != snappy.Invalid { os.exit(5i32) }
    let (_, e5b) = snappy.decode(raw300[..], out[..299usize])
    if e5b != snappy.TooSmall { os.exit(5i32) }
    let (_, e5c) = snappy.decode(raw300[..20usize], out[..])
    if e5c != snappy.Invalid { os.exit(5i32) }

    // 6: framing: the cramjam stream, the CRC32C vector, a flipped CRC byte, a roundtrip.
    if snappy.crc32c("123456789") != 3808858755u32 { os.exit(6i32) }
    var framed: [78]u8 = [78]u8{ 255, 6, 0, 0, 115, 78, 97, 80, 112, 89, 0, 64, 0, 0, 93, 11, 126, 196, 172, 2, 120, 116, 104, 101, 32, 113, 117, 105, 99, 107, 32, 98, 114, 111, 119, 110, 32, 102, 111, 120, 32, 106, 117, 109, 112, 115, 32, 111, 118, 101, 114, 32, 1, 31, 32, 108, 97, 122, 121, 32, 100, 111, 103, 46, 5, 14, 254, 45, 0, 254, 45, 0, 254, 45, 0, 234, 45, 0 }
    let (n6, e6) = snappy.decode_framed(framed[..], out[..])
    if e6 != ok || n6 != 300usize || !same(out[..300usize], text[..]) { os.exit(6i32) }
    framed[14] = framed[14] ^ 1u8
    let (_, e6b) = snappy.decode_framed(framed[..], out[..])
    if e6b != snappy.Checksum { os.exit(6i32) }
    let (n6c, e6c) = snappy.encode_framed(buf[..], packed[..], table[..])
    if e6c != ok || n6c >= 3072usize || packed[10] != 0u8 { os.exit(6i32) }
    let (m6, d6) = snappy.decode_framed(packed[..n6c], out[..])
    if d6 != ok || m6 != 3072usize || !same(out[..3072usize], buf[..]) { os.exit(6i32) }
    let (n6d, e6d) = snappy.encode_framed(inc[..], packed[..], table[..])
    if e6d != ok || n6d != 68usize || packed[10] != 1u8 { os.exit(6i32) }
    let (m6d, d6d) = snappy.decode_framed(packed[..n6d], out[..])
    if d6d != ok || m6d != 50usize || !same(out[..50usize], inc[..]) { os.exit(12i32) }

    try io.print("fmt snappy ok\n")
    ret ok
}
