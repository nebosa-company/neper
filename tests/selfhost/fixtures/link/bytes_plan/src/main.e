// `e.bytes` beyond the codec fixture: the bit operations docs/algos.md names, hex, base58 and
// the chunked base64 pair. Expected values come from a Python reference (binascii, struct,
// int.bit_length and an integer-division base58), never from hand arithmetic.

use e.io
use e.mem
use e.os
use e.str
use e.bytes

fn main(a: *mem.Arena) -> err {
    // --- byte_swap, reverse_bits, swap_bits, parity.
    if bytes.byte_swap[u16](4660u16) != 13330u16 { os.exit(1i32) }
    if bytes.byte_swap[u32](305419896u32) != 2018915346u32 { os.exit(2i32) }
    if bytes.byte_swap[u64](81985529216486895u64) != 17279655951921914625u64 { os.exit(3i32) }
    if bytes.byte_swap[u8](200u8) != 200u8 { os.exit(4i32) }
    if bytes.reverse_bits[u32](305419896u32) != 510274632u32 { os.exit(5i32) }
    if bytes.reverse_bits[u8](1u8) != 128u8 { os.exit(6i32) }
    if bytes.reverse_bits[u64](81985529216486895u64) != 17848844570815808640u64 { os.exit(7i32) }
    if bytes.reverse_bits[u16](4660u16) != 11336u16 { os.exit(8i32) }
    if bytes.swap_bits[u8](10u8, 0u32, 1u32) != 9u8 { os.exit(9i32) }
    if bytes.swap_bits[u8](10u8, 1u32, 3u32) != 10u8 { os.exit(10i32) }
    if bytes.swap_bits[u64](1u64, 0u32, 63u32) != 9223372036854775808u64 { os.exit(11i32) }
    if bytes.parity[u8](0u8) != 0u32 || bytes.parity[u8](1u8) != 1u32 || bytes.parity[u8](3u8) != 0u32 { os.exit(12i32) }
    if bytes.parity[u8](7u8) != 1u32 || bytes.parity[u8](255u8) != 0u32 { os.exit(13i32) }
    if bytes.parity[u64](81985529216486895u64) != 0u32 { os.exit(14i32) }

    // --- has_zero_byte and has_byte.
    if bytes.has_zero_byte(81985529216486895u64) { os.exit(15i32) }
    if !bytes.has_zero_byte(81985086834855407u64) { os.exit(16i32) }
    if bytes.has_zero_byte(18446744073709551615u64) { os.exit(17i32) }
    if !bytes.has_zero_byte(255u64) { os.exit(18i32) }
    if !bytes.has_zero_byte(18374686479671623680u64) { os.exit(19i32) }
    if !bytes.has_byte(81985529216486895u64, 171u8) { os.exit(20i32) }
    if bytes.has_byte(81985529216486895u64, 172u8) { os.exit(21i32) }

    // --- ilog2 and next_power_of_two.
    let (_, log_zero) = bytes.ilog2[u32](0u32)
    if log_zero != bytes.Invalid { os.exit(22i32) }
    let (log_one, log_one_error) = bytes.ilog2[u32](1u32)
    if log_one_error != ok || log_one != 0u32 { os.exit(23i32) }
    let (log_three, _) = bytes.ilog2[u8](3u8)
    if log_three != 1u32 { os.exit(24i32) }
    let (log_256, _) = bytes.ilog2[u64](256u64)
    if log_256 != 8u32 { os.exit(25i32) }
    let (log_255, _) = bytes.ilog2[u64](255u64)
    if log_255 != 7u32 { os.exit(26i32) }
    let (log_max, _) = bytes.ilog2[u64](18446744073709551615u64)
    if log_max != 63u32 { os.exit(27i32) }
    let (p0, p0_ok) = bytes.next_power_of_two[u64](0u64)
    if !p0_ok || p0 != 1u64 { os.exit(28i32) }
    let (p1, p1_ok) = bytes.next_power_of_two[u64](1u64)
    if !p1_ok || p1 != 1u64 { os.exit(29i32) }
    let (p2, p2_ok) = bytes.next_power_of_two[u64](2u64)
    if !p2_ok || p2 != 2u64 { os.exit(30i32) }
    let (p3, p3_ok) = bytes.next_power_of_two[u64](3u64)
    if !p3_ok || p3 != 4u64 { os.exit(31i32) }
    let (p5, p5_ok) = bytes.next_power_of_two[u32](5u32)
    if !p5_ok || p5 != 8u32 { os.exit(32i32) }
    let (p63, p63_ok) = bytes.next_power_of_two[u64](9223372036854775808u64)
    if !p63_ok || p63 != 9223372036854775808u64 { os.exit(33i32) }
    let (_, p63_over) = bytes.next_power_of_two[u64](9223372036854775809u64)
    if p63_over { os.exit(34i32) }
    let (_, pmax_over) = bytes.next_power_of_two[u64](18446744073709551615u64)
    if pmax_over { os.exit(35i32) }
    let (p128, p128_ok) = bytes.next_power_of_two[u8](128u8)
    if !p128_ok || p128 != 128u8 { os.exit(36i32) }
    let (_, p129_over) = bytes.next_power_of_two[u8](129u8)
    if p129_over { os.exit(37i32) }

    // --- sign_extend.
    if bytes.sign_extend(255u64, 8u32) != -1i64 { os.exit(38i32) }
    if bytes.sign_extend(127u64, 8u32) != 127i64 { os.exit(39i32) }
    if bytes.sign_extend(128u64, 8u32) != -128i64 { os.exit(40i32) }
    if bytes.sign_extend(4095u64, 12u32) != -1i64 { os.exit(41i32) }
    if bytes.sign_extend(2048u64, 12u32) != -2048i64 { os.exit(42i32) }
    if bytes.sign_extend(305419896u64, 32u32) != 305419896i64 { os.exit(43i32) }
    if bytes.sign_extend(2452903544u64, 32u32) != -1842063752i64 { os.exit(44i32) }
    if bytes.sign_extend(18446744073709551615u64, 64u32) != -1i64 { os.exit(45i32) }
    if bytes.sign_extend(5u64, 3u32) != -3i64 { os.exit(46i32) }

    // --- Gray code 0..16, and the decode of every one of them.
    let gray = [17]u8{ 0u8, 1u8, 3u8, 2u8, 6u8, 7u8, 5u8, 4u8, 12u8, 13u8, 15u8, 14u8, 10u8, 11u8, 9u8, 8u8, 24u8 }
    var g = 0usize
    while g < 17usize {
        if bytes.gray_encode[u8](u8(g)) != gray[g] { os.exit(47i32) }
        if bytes.gray_decode[u8](gray[g]) != u8(g) { os.exit(48i32) }
        g += 1usize
    }
    if bytes.gray_decode[u64](bytes.gray_encode[u64](81985529216486895u64)) != 81985529216486895u64 { os.exit(49i32) }

    // --- Hex.
    var run: [6]u8 = zero
    run[0usize] = 222u8
    run[1usize] = 173u8
    run[2usize] = 190u8
    run[3usize] = 239u8
    run[4usize] = 0u8
    run[5usize] = 127u8
    var text: [64]u8 = zero
    let (lower, lower_error) = bytes.hex_encode(text[..], run[..], false)
    if lower_error != ok || !str.eq(lower, "deadbeef007f") { os.exit(50i32) }
    let (upper, upper_error) = bytes.hex_encode(text[..], run[..], true)
    if upper_error != ok || !str.eq(upper, "DEADBEEF007F") { os.exit(51i32) }
    var back: [64]u8 = zero
    let (decoded, decoded_error) = bytes.hex_decode(back[..], "deadBEEF007f")
    if decoded_error != ok || decoded.len != 6usize || !str.eq(decoded, run[..]) { os.exit(52i32) }
    let (_, odd_error) = bytes.hex_decode(back[..], "abc")
    if odd_error != bytes.Invalid { os.exit(53i32) }
    let (_, digit_error) = bytes.hex_decode(back[..], "zz")
    if digit_error != bytes.Invalid { os.exit(54i32) }
    let (_, room_error) = bytes.hex_encode(text[0usize..11usize], run[..], false)
    if room_error != bytes.TooLarge { os.exit(55i32) }
    let (empty_hex, empty_hex_error) = bytes.hex_encode(text[..], run[0usize..0usize], false)
    if empty_hex_error != ok || empty_hex.len != 0usize { os.exit(56i32) }

    // --- Base58.
    var lead: [5]u8 = zero
    lead[2usize] = 1u8
    lead[3usize] = 2u8
    lead[4usize] = 3u8
    let (b58_lead, b58_lead_error) = bytes.base58_encode(text[..], lead[..])
    if b58_lead_error != ok || !str.eq(b58_lead, "11Ldp") { os.exit(57i32) }
    let (b58_hello, b58_hello_error) = bytes.base58_encode(text[..], "hello world")
    if b58_hello_error != ok || !str.eq(b58_hello, "StV1DL6CwTryKyV") { os.exit(58i32) }
    let (b58_empty, b58_empty_error) = bytes.base58_encode(text[..], run[0usize..0usize])
    if b58_empty_error != ok || b58_empty.len != 0usize { os.exit(59i32) }
    let (b58_zero, b58_zero_error) = bytes.base58_encode(text[..], lead[0usize..1usize])
    if b58_zero_error != ok || !str.eq(b58_zero, "1") { os.exit(60i32) }
    var ff: [5]u8 = zero
    ff[3usize] = 255u8
    ff[4usize] = 255u8
    let (b58_ff, b58_ff_error) = bytes.base58_encode(text[..], ff[..])
    if b58_ff_error != ok || !str.eq(b58_ff, "111LUv") { os.exit(61i32) }
    let (b58_back, b58_back_error) = bytes.base58_decode(back[..], "11Ldp")
    if b58_back_error != ok || !str.eq(b58_back, lead[..]) { os.exit(62i32) }
    let (b58_hello_back, b58_hello_back_error) = bytes.base58_decode(back[..], "StV1DL6CwTryKyV")
    if b58_hello_back_error != ok || !str.eq(b58_hello_back, "hello world") { os.exit(63i32) }
    let (b58_ff_back, b58_ff_back_error) = bytes.base58_decode(back[..], "111LUv")
    if b58_ff_back_error != ok || !str.eq(b58_ff_back, ff[..]) { os.exit(64i32) }
    let (_, b58_bad) = bytes.base58_decode(back[..], "0OIl")
    if b58_bad != bytes.Invalid { os.exit(65i32) }
    let (_, b58_room) = bytes.base58_encode(text[0usize..4usize], "hello world")
    if b58_room != bytes.TooLarge { os.exit(66i32) }
    // Nine bytes with no leading zero, and back.
    var nine: [9]u8 = zero
    var n = 0usize
    while n < 9usize {
        nine[n] = u8(n + 1usize)
        n += 1usize
    }
    let (b58_nine, b58_nine_error) = bytes.base58_encode(text[..], nine[..])
    if b58_nine_error != ok || !str.eq(b58_nine, "kA3B2yGe2z4") { os.exit(67i32) }
    let (b58_nine_back, b58_nine_back_error) = bytes.base58_decode(back[..], b58_nine)
    if b58_nine_back_error != ok || !str.eq(b58_nine_back, nine[..]) { os.exit(68i32) }

    // --- Chunked base64 against the one-shot pair, over every chunk size 1..7 of 36 bytes.
    var msg: [36]u8 = zero
    var m = 0usize
    while m < 36usize {
        msg[m] = u8(m * 7usize)
        m += 1usize
    }
    let (whole, whole_error) = bytes.base64_encode(text[..], msg[..], .Standard, true)
    if whole_error != ok || !str.eq(whole, "AAcOFRwjKjE4P0ZNVFtiaXB3foWMk5qhqK+2vcTL0tng5+71") { os.exit(69i32) }
    var streamed: [64]u8 = zero
    var chunk = 1usize
    while chunk <= 7usize {
        var enc = bytes.base64_encoder(.Standard, true)
        var fed = 0usize
        var out = 0usize
        while fed < 36usize {
            var stop = fed + chunk
            if stop > 36usize { stop = 36usize }
            let (wrote, wrote_error) = bytes.base64_encoder_update(&enc, streamed[out..], msg[fed..stop])
            if wrote_error != ok { os.exit(70i32) }
            out += wrote
            fed = stop
        }
        let (tail, tail_error) = bytes.base64_encoder_finish(&enc, streamed[out..])
        if tail_error != ok { os.exit(71i32) }
        out += tail
        if !str.eq(streamed[0usize..out], whole) { os.exit(72i32) }
        // And the text back through the decoder in the same chunks.
        var dec = bytes.base64_decoder(.Standard)
        var read = 0usize
        var got = 0usize
        while read < whole.len {
            var stop = read + chunk
            if stop > whole.len { stop = whole.len }
            let (wrote, wrote_error) = bytes.base64_decoder_update(&dec, back[got..], whole[read..stop])
            if wrote_error != ok { os.exit(73i32) }
            got += wrote
            read = stop
        }
        let (tail_bytes, tail_bytes_error) = bytes.base64_decoder_finish(&dec, back[got..])
        if tail_bytes_error != ok { os.exit(74i32) }
        got += tail_bytes
        if got != 36usize || !str.eq(back[0usize..36usize], msg[..]) { os.exit(75i32) }
        chunk += 1usize
    }
    // A padded tail fed one character at a time, and an unpadded url tail through finish.
    var enc7 = bytes.base64_encoder(.Standard, true)
    let (w7, w7_error) = bytes.base64_encoder_update(&enc7, streamed[..], msg[0usize..7usize])
    if w7_error != ok || w7 != 8usize { os.exit(76i32) }
    let (f7, f7_error) = bytes.base64_encoder_finish(&enc7, streamed[w7..])
    if f7_error != ok || !str.eq(streamed[0usize..w7 + f7], "AAcOFRwjKg==") { os.exit(77i32) }
    var url7 = bytes.base64_encoder(.Url, false)
    let (u7, u7_error) = bytes.base64_encoder_update(&url7, streamed[..], msg[0usize..7usize])
    if u7_error != ok { os.exit(78i32) }
    let (uf7, uf7_error) = bytes.base64_encoder_finish(&url7, streamed[u7..])
    if uf7_error != ok || !str.eq(streamed[0usize..u7 + uf7], "AAcOFRwjKg") { os.exit(79i32) }
    var dec7 = bytes.base64_decoder(.Standard)
    var d7 = 0usize
    var c = 0usize
    while c < 12usize {
        let (wrote, wrote_error) = bytes.base64_decoder_update(&dec7, back[d7..], "AAcOFRwjKg=="[c..c + 1usize])
        if wrote_error != ok { os.exit(80i32) }
        d7 += wrote
        c += 1usize
    }
    let (df7, df7_error) = bytes.base64_decoder_finish(&dec7, back[d7..])
    if df7_error != ok || d7 + df7 != 7usize || !str.eq(back[0usize..7usize], msg[0usize..7usize]) { os.exit(81i32) }
    var udec = bytes.base64_decoder(.Url)
    let (ud, ud_error) = bytes.base64_decoder_update(&udec, back[..], "AAcOFRwjKg")
    if ud_error != ok || ud != 6usize { os.exit(82i32) }
    let (udf, udf_error) = bytes.base64_decoder_finish(&udec, back[ud..])
    if udf_error != ok || udf != 1usize || !str.eq(back[0usize..7usize], msg[0usize..7usize]) { os.exit(83i32) }
    // One character left over is what no encoding produces.
    var bad = bytes.base64_decoder(.Standard)
    let (_, bad_update) = bytes.base64_decoder_update(&bad, back[..], "QUJDA")
    if bad_update != ok { os.exit(84i32) }
    let (_, bad_finish) = bytes.base64_decoder_finish(&bad, back[..])
    if bad_finish != bytes.Invalid { os.exit(85i32) }

    try io.print("bytes plan ok\n")
    ret ok
}
