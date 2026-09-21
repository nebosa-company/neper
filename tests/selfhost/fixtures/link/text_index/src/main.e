// `e.text.index`: an inverted index of four small documents lists its terms
// in byte order with sorted postings, lookups hit and miss, AND and OR
// combine lists, and Elias-Fano packs a sorted list into the expected bytes
// and unpacks it, for a worked example and for a random list. Each check
// exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.os
use e.text.index

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var docs: [4]str = zero
    docs[0usize] = "b a c"
    docs[1usize] = "a a d"
    docs[2usize] = "c b"
    docs[3usize] = ""

    // 1: the index.
    let (x, build_error) = index.build(a, docs[..])
    if build_error != ok || x.terms.len != 4usize || x.documents != 4usize || x.postings.len != 7usize { os.exit(1i32) }
    if !same(x.terms[0usize], "a") || !same(x.terms[1usize], "b") || !same(x.terms[2usize], "c") || !same(x.terms[3usize], "d") { os.exit(1i32) }
    let pa = index.lookup(&x, "a")
    if pa.len != 2usize || pa[0usize] != 0u32 || pa[1usize] != 1u32 { os.exit(1i32) }
    let pb = index.lookup(&x, "b")
    if pb.len != 2usize || pb[0usize] != 0u32 || pb[1usize] != 2u32 { os.exit(1i32) }
    let pd = index.lookup(&x, "d")
    if pd.len != 1usize || pd[0usize] != 1u32 { os.exit(1i32) }
    if index.lookup(&x, "z").len != 0usize || index.lookup(&x, "").len != 0usize || index.lookup(&x, "aa").len != 0usize { os.exit(1i32) }
    let (empty, empty_error) = index.build(a, docs[..0usize])
    if empty_error != ok || empty.terms.len != 0usize || index.lookup(&empty, "a").len != 0usize { os.exit(1i32) }

    // 2: combining lists.
    var out: [8]u32 = zero
    let (both, both_error) = index.intersect(pb, index.lookup(&x, "c"), out[..])
    if both_error != ok || both != 2usize || out[0usize] != 0u32 || out[1usize] != 2u32 { os.exit(2i32) }
    let (none, none_error) = index.intersect(pd, pb, out[..])
    if none_error != ok || none != 0usize { os.exit(2i32) }
    let (either, either_error) = index.unite(pa, pd, out[..])
    if either_error != ok || either != 2usize || out[0usize] != 0u32 || out[1usize] != 1u32 { os.exit(2i32) }
    let (all, all_error) = index.unite(pb, pd, out[..])
    if all_error != ok || all != 3usize || out[0usize] != 0u32 || out[1usize] != 1u32 || out[2usize] != 2u32 { os.exit(2i32) }
    let (_, room) = index.unite(pb, pd, out[..2usize])
    if room != index.TooSmall { os.exit(2i32) }

    // 3: Elias-Fano on the worked example: six values below 32 take 27 bits.
    var values: [6]u32 = zero
    values[0usize] = 1u32
    values[1usize] = 5u32
    values[2usize] = 8u32
    values[3usize] = 12u32
    values[4usize] = 20u32
    values[5usize] = 21u32
    var bytes: [64]u8 = zero
    if index.elias_fano_size(6usize, 32u32) != 4usize { os.exit(3i32) }
    let (size, encode_error) = index.elias_fano_encode(values[..], 32u32, bytes[..])
    if encode_error != ok || size != 4usize { os.exit(3i32) }
    // Low bits (two each): 1 1 0 0 0 1 -> 01 01 00 00 00 01 packed LSB first.
    if bytes[0usize] != 0x05u8 || (bytes[1usize] & 0x0fu8) != 0x04u8 { os.exit(3i32) }
    var back: [6]u32 = zero
    if index.elias_fano_decode(bytes[..], 6usize, 32u32, back[..]) != ok { os.exit(3i32) }
    var i = 0usize
    while i < 6usize {
        if back[i] != values[i] { os.exit(3i32) }
        i += 1usize
    }
    values[2usize] = 4u32
    let (_, unsorted) = index.elias_fano_encode(values[..], 32u32, bytes[..])
    if unsorted != index.Invalid { os.exit(3i32) }
    values[2usize] = 40u32
    let (_, too_big) = index.elias_fano_encode(values[..], 32u32, bytes[..])
    if too_big != index.Invalid { os.exit(3i32) }
    let (_, no_room) = index.elias_fano_encode(values[..], 64u32, bytes[..3usize])
    if no_room != index.TooSmall { os.exit(3i32) }
    let (zero_size, zero_error) = index.elias_fano_encode(values[..0usize], 32u32, bytes[..])
    if zero_error != ok || zero_size != 0usize { os.exit(3i32) }

    // 4: a random sorted list of a hundred ids below a million round-trips.
    var r = rand.pcg64(4u64, 4u64)
    let (many, many_error) = mem.alloc[u32](a, 100usize)
    if many_error != ok { ret many_error }
    var v = 0u32
    i = 0usize
    while i < 100usize {
        v += 1u32 + u32(rand.pcg64_bounded(&r, 9000u64))
        many[i] = v
        i += 1usize
    }
    let (packed, pack_error) = mem.alloc[u8](a, index.elias_fano_size(100usize, 1000000u32))
    if pack_error != ok { ret pack_error }
    // 100 values below a million: 13 low bits each plus 100 + 122 + 1 high bits: 1523 bits.
    if packed.len != 191usize { os.exit(4i32) }
    let (used, many_encode) = index.elias_fano_encode(many, 1000000u32, packed)
    if many_encode != ok || used != 191usize { os.exit(4i32) }
    let (unpacked, unpack_error) = mem.alloc[u32](a, 100usize)
    if unpack_error != ok { ret unpack_error }
    if index.elias_fano_decode(packed, 100usize, 1000000u32, unpacked) != ok { os.exit(4i32) }
    i = 0usize
    while i < 100usize {
        if unpacked[i] != many[i] { os.exit(4i32) }
        i += 1usize
    }
    if index.elias_fano_decode(packed[..100usize], 100usize, 1000000u32, unpacked) != index.TooSmall { os.exit(4i32) }

    try io.print("text index ok\n")
    ret ok
}
