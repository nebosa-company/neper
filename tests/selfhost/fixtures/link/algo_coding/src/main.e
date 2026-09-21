// `e.algo.coding`: run-length, LEB128 and VLQ integers against known bytes,
// ZigZag at the extremes, delta and delta-of-delta round trips, bit packing and
// frame-of-reference, Elias gamma and Rice codes through one bit cursor,
// move-to-front and Burrows-Wheeler of "banana", and canonical Huffman codes that
// round-trip text, honour a length limit and refuse what they cannot read. Each
// check exits with its own code.

use e.algo.coding
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var out: [512]u8 = zero
    var back: [512]u8 = zero

    // 1: run-length.
    let (rle_len, rle_error) = coding.rle_encode("aaabccdddd", out[..])
    if rle_error != ok || rle_len != 8usize { os.exit(1i32) }
    if out[0usize] != 97u8 || out[1usize] != 3u8 || out[2usize] != 98u8 || out[3usize] != 1u8 || out[7usize] != 4u8 { os.exit(1i32) }
    let (rle_back, rle_back_error) = coding.rle_decode(out[..rle_len], back[..])
    if rle_back_error != ok || rle_back != 10usize || !mem.eq[u8](back[..10usize], "aaabccdddd") { os.exit(1i32) }
    var long_run: [300]u8 = zero
    let (long_len, long_error) = coding.rle_encode(long_run[..], out[..])
    if long_error != ok || long_len != 4usize || out[1usize] != 255u8 || out[3usize] != 45u8 { os.exit(1i32) }
    let (_, tight) = coding.rle_decode(out[..long_len], back[..100usize])
    if tight != coding.TooSmall { os.exit(1i32) }
    let (_, odd) = coding.rle_decode(out[..3usize], back[..])
    if odd != coding.Invalid { os.exit(1i32) }
    let (_, no_room) = coding.rle_encode("abc", back[..4usize])
    if no_room != coding.TooSmall { os.exit(1i32) }

    // 2: LEB128 and VLQ.
    let (v300, v300_error) = coding.varint_encode(300u64, out[..])
    if v300_error != ok || v300 != 2usize || out[0usize] != 172u8 || out[1usize] != 2u8 { os.exit(2i32) }
    let (d300, d300_used, d300_error) = coding.varint_decode(out[..v300])
    if d300_error != ok || d300 != 300u64 || d300_used != 2usize { os.exit(2i32) }
    let (vmax, vmax_error) = coding.varint_encode(18446744073709551615u64, out[..])
    if vmax_error != ok || vmax != 10usize || out[9usize] != 1u8 { os.exit(2i32) }
    let (dmax, _, dmax_error) = coding.varint_decode(out[..vmax])
    if dmax_error != ok || dmax != 18446744073709551615u64 { os.exit(2i32) }
    let (_, v_short) = coding.varint_encode(300u64, out[..1usize])
    if v_short != coding.TooSmall { os.exit(2i32) }
    let (_, _, d_cut) = coding.varint_decode(out[..1usize])
    if d_cut != coding.Invalid { os.exit(2i32) }
    let (q300, q300_error) = coding.vlq_encode(300u64, out[..])
    if q300_error != ok || q300 != 2usize || out[0usize] != 130u8 || out[1usize] != 44u8 { os.exit(2i32) }
    let (r300, r300_used, r300_error) = coding.vlq_decode(out[..q300])
    if r300_error != ok || r300 != 300u64 || r300_used != 2usize { os.exit(2i32) }
    let (qmax, qmax_error) = coding.vlq_encode(18446744073709551615u64, out[..])
    if qmax_error != ok || qmax != 10usize || out[0usize] != 129u8 || out[9usize] != 127u8 { os.exit(2i32) }
    let (rmax, _, rmax_error) = coding.vlq_decode(out[..qmax])
    if rmax_error != ok || rmax != 18446744073709551615u64 { os.exit(2i32) }
    let (q0, q0_error) = coding.vlq_encode(0u64, out[..])
    if q0_error != ok || q0 != 1usize || out[0usize] != 0u8 { os.exit(2i32) }

    // 3: ZigZag.
    if coding.zigzag_encode(0i64) != 0u64 || coding.zigzag_encode(0i64 - 1i64) != 1u64 { os.exit(3i32) }
    if coding.zigzag_encode(1i64) != 2u64 || coding.zigzag_encode(0i64 - 2i64) != 3u64 { os.exit(3i32) }
    if coding.zigzag_encode(9223372036854775807i64) != 18446744073709551614u64 { os.exit(3i32) }
    if coding.zigzag_encode(0i64 - 9223372036854775807i64 - 1i64) != 18446744073709551615u64 { os.exit(3i32) }
    var z = 0i64 - 1000i64
    while z <= 1000i64 {
        if coding.zigzag_decode(coding.zigzag_encode(z)) != z { os.exit(3i32) }
        z += 7i64
    }
    if coding.zigzag_decode(18446744073709551615u64) != 0i64 - 9223372036854775807i64 - 1i64 { os.exit(3i32) }

    // 4: delta and delta-of-delta.
    var series: [6]i64 = zero
    series[0usize] = 100i64
    series[1usize] = 110i64
    series[2usize] = 120i64
    series[3usize] = 130i64
    series[4usize] = 145i64
    series[5usize] = 140i64
    coding.delta_encode(series[..])
    if series[0usize] != 100i64 || series[1usize] != 10i64 || series[4usize] != 15i64 || series[5usize] != 0i64 - 5i64 { os.exit(4i32) }
    coding.delta_decode(series[..])
    if series[3usize] != 130i64 || series[5usize] != 140i64 { os.exit(4i32) }
    coding.delta_delta_encode(series[..])
    if series[0usize] != 100i64 || series[1usize] != 10i64 || series[2usize] != 0i64 || series[3usize] != 0i64 || series[4usize] != 5i64 || series[5usize] != 0i64 - 20i64 { os.exit(4i32) }
    coding.delta_delta_decode(series[..])
    if series[0usize] != 100i64 || series[4usize] != 145i64 || series[5usize] != 140i64 { os.exit(4i32) }
    var single: [1]i64 = zero
    single[0usize] = 9i64
    coding.delta_delta_encode(single[..])
    coding.delta_delta_decode(single[..])
    if single[0usize] != 9i64 { os.exit(4i32) }

    // 5: bit packing and frame of reference.
    var values: [10]u64 = zero
    var i = 0usize
    while i < 10usize {
        values[i] = 1000u64 + u64(i * i)
        i += 1usize
    }
    if coding.bit_width(values[..]) != 11u32 { os.exit(5i32) }
    let (packed, packed_error) = coding.bit_pack(values[..], 11u32, out[..])
    if packed_error != ok || packed != 14usize { os.exit(5i32) }
    var unpacked: [10]u64 = zero
    if coding.bit_unpack(out[..packed], 11u32, unpacked[..]) != ok { os.exit(5i32) }
    i = 0usize
    while i < 10usize {
        if unpacked[i] != values[i] { os.exit(5i32) }
        i += 1usize
    }
    if coding.bit_unpack(out[..13usize], 11u32, unpacked[..]) != coding.Invalid { os.exit(5i32) }
    let (_, pack_room) = coding.bit_pack(values[..], 11u32, out[..13usize])
    if pack_room != coding.TooSmall { os.exit(5i32) }
    let (framed, framed_error) = coding.for_encode(values[..], out[..])
    // 1000 as a varint (2 bytes), a width byte (7 bits), 70 bits packed (9 bytes).
    if framed_error != ok || framed != 12usize || out[2usize] != 7u8 { os.exit(5i32) }
    var restored: [10]u64 = zero
    if coding.for_decode(out[..framed], restored[..]) != ok { os.exit(5i32) }
    i = 0usize
    while i < 10usize {
        if restored[i] != values[i] { os.exit(5i32) }
        i += 1usize
    }
    var same: [4]u64 = zero
    same[0usize] = 77u64
    same[1usize] = 77u64
    same[2usize] = 77u64
    same[3usize] = 77u64
    let (flat, flat_error) = coding.for_encode(same[..], out[..])
    if flat_error != ok || flat != 2usize || out[1usize] != 0u8 { os.exit(5i32) }
    if coding.for_decode(out[..flat], restored[..4usize]) != ok || restored[3usize] != 77u64 { os.exit(5i32) }
    var no_values: [0]u64 = zero
    let (nothing, nothing_error) = coding.for_encode(no_values[..], out[..])
    if nothing_error != ok || nothing != 2usize { os.exit(5i32) }

    // 6: Elias gamma and Rice through one cursor.
    var w = coding.bit_writer(out[..])
    if coding.elias_gamma_write(&w, 1u64) != ok || coding.elias_gamma_write(&w, 2u64) != ok { os.exit(6i32) }
    if coding.elias_gamma_write(&w, 3u64) != ok || coding.elias_gamma_write(&w, 4u64) != ok { os.exit(6i32) }
    // 1 010 011 00100 = 1010 0110 0100 -> 0xA6 0x40 after 12 bits.
    if w.bits != 12usize || out[0usize] != 166u8 || out[1usize] != 64u8 { os.exit(6i32) }
    if coding.elias_gamma_write(&w, 0u64) != coding.Invalid { os.exit(6i32) }
    if coding.rice_write(&w, 13u64, 2u32) != ok { os.exit(6i32) }
    // 13 = 3 * 4 + 1: 1110 then 01.
    if w.bits != 18usize { os.exit(6i32) }
    if coding.rice_write(&w, 18446744073709551615u64, 60u32) != ok { os.exit(6i32) }
    if coding.rice_write(&w, 1u64, 64u32) != coding.Invalid { os.exit(6i32) }
    let used = coding.written(&w)
    var r = coding.bit_reader(out[..used])
    let (g1, g1_error) = coding.elias_gamma_read(&r)
    let (g2, g2_error) = coding.elias_gamma_read(&r)
    let (g3, g3_error) = coding.elias_gamma_read(&r)
    let (g4, g4_error) = coding.elias_gamma_read(&r)
    if g1_error != ok || g2_error != ok || g3_error != ok || g4_error != ok { os.exit(6i32) }
    if g1 != 1u64 || g2 != 2u64 || g3 != 3u64 || g4 != 4u64 { os.exit(6i32) }
    let (r13, r13_error) = coding.rice_read(&r, 2u32)
    if r13_error != ok || r13 != 13u64 { os.exit(6i32) }
    let (rbig, rbig_error) = coding.rice_read(&r, 60u32)
    if rbig_error != ok || rbig != 18446744073709551615u64 { os.exit(6i32) }
    if coding.bits_left(&r) >= 8usize { os.exit(6i32) }
    var empty_reader = coding.bit_reader(out[..0usize])
    let (_, starved) = coding.elias_gamma_read(&empty_reader)
    if starved != coding.Invalid { os.exit(6i32) }
    var tight_writer = coding.bit_writer(out[..1usize])
    if coding.write_bits(&tight_writer, 5u64, 9u32) != coding.TooSmall { os.exit(6i32) }

    // 7: move-to-front and Burrows-Wheeler of "banana".
    if coding.move_to_front_encode("banana", out[..6usize]) != ok { os.exit(7i32) }
    if out[0usize] != 98u8 || out[1usize] != 98u8 || out[2usize] != 110u8 || out[3usize] != 1u8 || out[4usize] != 1u8 || out[5usize] != 1u8 { os.exit(7i32) }
    if coding.move_to_front_decode(out[..6usize], back[..6usize]) != ok || !mem.eq[u8](back[..6usize], "banana") { os.exit(7i32) }
    if coding.move_to_front_encode("banana", out[..5usize]) != coding.TooSmall { os.exit(7i32) }
    var scratch: [128]usize = zero
    let (row, bwt_error) = coding.bwt_encode("banana", out[..], scratch[..])
    if bwt_error != ok || row != 3usize || !mem.eq[u8](out[..6usize], "nnbaaa") { os.exit(7i32) }
    if coding.bwt_decode(out[..6usize], row, back[..], scratch[..]) != ok || !mem.eq[u8](back[..6usize], "banana") { os.exit(7i32) }
    let text = "the quick brown fox jumps over the lazy dog and the quick brown cat"
    let (row2, bwt2_error) = coding.bwt_encode(text, out[..], scratch[..])
    if bwt2_error != ok { os.exit(7i32) }
    if coding.bwt_decode(out[..text.len], row2, back[..], scratch[..]) != ok || !mem.eq[u8](back[..text.len], text) { os.exit(7i32) }
    if coding.bwt_decode(out[..6usize], 6usize, back[..], scratch[..]) != coding.Invalid { os.exit(7i32) }
    let (_, bwt_room) = coding.bwt_encode("banana", out[..3usize], scratch[..])
    if bwt_room != coding.TooSmall { os.exit(7i32) }

    // 8: canonical Huffman.
    var frequencies: [256]u64 = zero
    i = 0usize
    while i < text.len {
        frequencies[usize(text[i])] += 1u64
        i += 1usize
    }
    let (h, h_error) = coding.huffman_build(frequencies[..], 16u32)
    if h_error != ok { os.exit(8i32) }
    // The most frequent byte (space) has the shortest code, an unused byte none.
    if h.lengths[32usize] == 0u8 || h.lengths[32usize] > h.lengths[122usize] || h.lengths[33usize] != 0u8 { os.exit(8i32) }
    // Kraft equality: canonical lengths of a full tree sum to exactly one.
    var kraft = 0u64
    i = 0usize
    while i < 256usize {
        if h.lengths[i] != 0u8 { kraft += 1u64 << (32u64 - u64(h.lengths[i])) }
        i += 1usize
    }
    if kraft != 1u64 << 32u64 { os.exit(8i32) }
    var hw = coding.bit_writer(out[..])
    if coding.huffman_encode(&h, text, &hw) != ok { os.exit(8i32) }
    let encoded = coding.written(&hw)
    if encoded >= text.len { os.exit(8i32) }
    var hr = coding.bit_reader(out[..encoded])
    if coding.huffman_decode(&h, &hr, back[..text.len]) != ok || !mem.eq[u8](back[..text.len], text) { os.exit(8i32) }
    if coding.huffman_encode(&h, "!", &hw) != coding.Invalid { os.exit(8i32) }
    var cut = coding.bit_reader(out[..encoded / 2usize])
    if coding.huffman_decode(&h, &cut, back[..text.len]) != coding.Invalid { os.exit(8i32) }
    // A length limit below the natural depth still yields a valid prefix code.
    var skewed: [256]u64 = zero
    i = 0usize
    while i < 20usize {
        skewed[i] = 1u64 << u64(i)
        i += 1usize
    }
    let (limited, limited_error) = coding.huffman_build(skewed[..], 8u32)
    if limited_error != ok { os.exit(8i32) }
    kraft = 0u64
    i = 0usize
    while i < 20usize {
        if limited.lengths[i] == 0u8 || limited.lengths[i] > 8u8 { os.exit(8i32) }
        kraft += 1u64 << (32u64 - u64(limited.lengths[i]))
        i += 1usize
    }
    if kraft > 1u64 << 32u64 { os.exit(8i32) }
    // One symbol gets a one-bit code; no symbols, no codes.
    var lone: [256]u64 = zero
    lone[65usize] = 9u64
    let (only, only_error) = coding.huffman_build(lone[..], 16u32)
    if only_error != ok || only.lengths[65usize] != 1u8 || only.lengths[66usize] != 0u8 { os.exit(8i32) }
    var ow = coding.bit_writer(out[..])
    if coding.huffman_encode(&only, "AAAA", &ow) != ok || ow.bits != 4usize { os.exit(8i32) }
    var or = coding.bit_reader(out[..1usize])
    if coding.huffman_decode(&only, &or, back[..4usize]) != ok || !mem.eq[u8](back[..4usize], "AAAA") { os.exit(8i32) }
    var silent: [256]u64 = zero
    let (none, none_error) = coding.huffman_build(silent[..], 16u32)
    if none_error != ok || none.lengths[0usize] != 0u8 { os.exit(8i32) }
    let (_, bad_limit) = coding.huffman_build(silent[..], 0u32)
    if bad_limit != coding.Invalid { os.exit(8i32) }

    try io.print("algo coding ok\n")
    ret ok
}
