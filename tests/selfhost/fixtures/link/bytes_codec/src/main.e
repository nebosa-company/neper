// `e.bytes`: numbers through bytes in both orders and every width, the bit operations, and the
// three encodings against the vectors their RFCs print. Each encoder is checked against a
// known answer and then round-tripped, since an encoder and decoder that agree with each other
// and with nothing else would pass the second check alone.

use e.mem
use e.os
use e.str
use e.bytes

fn main(a: *mem.Arena) -> err {
    // --- load and store, both orders, every width, signed and floating.
    var buffer: [16]u8 = zero
    if bytes.store[u32](buffer[..], 0usize, 305419896u32, .Little) != ok { os.exit(10i32) }
    if buffer[0usize] != 120u8 || buffer[1usize] != 86u8 || buffer[2usize] != 52u8 || buffer[3usize] != 18u8 { os.exit(11i32) }
    if bytes.store[u32](buffer[..], 4usize, 305419896u32, .Big) != ok { os.exit(12i32) }
    if buffer[4usize] != 18u8 || buffer[5usize] != 52u8 || buffer[6usize] != 86u8 || buffer[7usize] != 120u8 { os.exit(13i32) }
    let (little, little_error) = bytes.load[u32](buffer[..], 0usize, .Little)
    if little_error != ok || little != 305419896u32 { os.exit(14i32) }
    let (big, big_error) = bytes.load[u32](buffer[..], 4usize, .Big)
    if big_error != ok || big != 305419896u32 { os.exit(15i32) }
    // The same bytes read in the other order are the other number.
    let (swapped, swapped_error) = bytes.load[u32](buffer[..], 0usize, .Big)
    if swapped_error != ok || swapped != 2018915346u32 { os.exit(16i32) }
    // A negative narrow integer keeps its sign through the bytes.
    if bytes.store[i16](buffer[..], 8usize, -2i16, .Little) != ok { os.exit(17i32) }
    if buffer[8usize] != 254u8 || buffer[9usize] != 255u8 { os.exit(18i32) }
    let (minus_two, minus_two_error) = bytes.load[i16](buffer[..], 8usize, .Little)
    if minus_two_error != ok || minus_two != -2i16 { os.exit(19i32) }
    // A single byte has no order to speak of.
    if bytes.store[u8](buffer[..], 10usize, 200u8, .Big) != ok { os.exit(20i32) }
    let (byte, byte_error) = bytes.load[u8](buffer[..], 10usize, .Little)
    if byte_error != ok || byte != 200u8 { os.exit(21i32) }
    // The two floats, bit for bit.
    if bytes.store[f64](buffer[..], 0usize, 1.5f64, .Little) != ok { os.exit(22i32) }
    let (one_and_half, f64_error) = bytes.load[f64](buffer[..], 0usize, .Little)
    if f64_error != ok || one_and_half != 1.5f64 { os.exit(23i32) }
    if bytes.store[f32](buffer[..], 8usize, -0.25f32, .Big) != ok { os.exit(24i32) }
    let (quarter, f32_error) = bytes.load[f32](buffer[..], 8usize, .Big)
    if f32_error != ok || quarter != -0.25f32 { os.exit(25i32) }
    // Past the end is `End` for a load and `TooLarge` for a store, never a partial value.
    let (_, short_error) = bytes.load[u64](buffer[..], 12usize, .Little)
    if short_error != bytes.End { os.exit(26i32) }
    if bytes.store[u64](buffer[..], 12usize, 1u64, .Little) != bytes.TooLarge { os.exit(27i32) }

    // --- A reader and a writer over the same buffer, the writer first.
    var w = bytes.writer(buffer[..])
    if bytes.remaining_writer(&w) != 16usize { os.exit(30i32) }
    if bytes.write[u16](&w, 4660u16, .Big) != ok { os.exit(31i32) }
    if bytes.write[u32](&w, 7u32, .Little) != ok { os.exit(32i32) }
    if bytes.write_bytes(&w, "abc") != ok { os.exit(33i32) }
    if bytes.remaining_writer(&w) != 7usize { os.exit(34i32) }
    var r = bytes.reader(buffer[..])
    let (head, head_error) = bytes.read[u16](&r, .Big)
    if head_error != ok || head != 4660u16 { os.exit(35i32) }
    let (seven, seven_error) = bytes.read[u32](&r, .Little)
    if seven_error != ok || seven != 7u32 { os.exit(36i32) }
    let (text, text_error) = bytes.read_bytes(&r, 3usize)
    if text_error != ok || !str.eq(text, "abc") { os.exit(37i32) }
    if bytes.remaining_reader(&r) != 7usize { os.exit(38i32) }
    if bytes.skip(&r, 7usize) != ok { os.exit(39i32) }
    if bytes.remaining_reader(&r) != 0usize { os.exit(40i32) }
    let (_, past) = bytes.read[u8](&r, .Little)
    if past != bytes.End { os.exit(41i32) }
    if bytes.skip(&r, 1usize) != bytes.End { os.exit(42i32) }
    if bytes.write_bytes(&w, "12345678") != bytes.TooLarge { os.exit(43i32) }

    // --- Reversal, and the bit operations across widths.
    var run: [5]u8 = zero
    run[0usize] = 1u8
    run[1usize] = 2u8
    run[2usize] = 3u8
    run[3usize] = 4u8
    run[4usize] = 5u8
    bytes.reverse_in_place(run[..])
    if run[0usize] != 5u8 || run[2usize] != 3u8 || run[4usize] != 1u8 { os.exit(50i32) }
    if bytes.rotate_left[u8](129u8, 1u32) != 3u8 { os.exit(51i32) }
    if bytes.rotate_right[u8](3u8, 1u32) != 129u8 { os.exit(52i32) }
    if bytes.rotate_left[u32](2147483649u32, 1u32) != 3u32 { os.exit(53i32) }
    if bytes.rotate_left[u64](1u64, 64u32) != 1u64 { os.exit(54i32) }
    if bytes.rotate_right[u16](1u16, 1u32) != 32768u16 { os.exit(55i32) }
    if bytes.count_ones[u8](255u8) != 8u32 { os.exit(56i32) }
    if bytes.count_ones[u64](0u64) != 0u32 { os.exit(57i32) }
    if bytes.count_ones[u32](2863311530u32) != 16u32 { os.exit(58i32) }
    if bytes.leading_zeros[u8](1u8) != 7u32 { os.exit(59i32) }
    if bytes.leading_zeros[u32](0u32) != 32u32 { os.exit(60i32) }
    if bytes.leading_zeros[u64](1u64 << 63u32) != 0u32 { os.exit(61i32) }
    if bytes.trailing_zeros[u8](8u8) != 3u32 { os.exit(62i32) }
    if bytes.trailing_zeros[u16](0u16) != 16u32 { os.exit(63i32) }
    if bytes.trailing_zeros[u64](1u64 << 40u32) != 40u32 { os.exit(64i32) }

    // --- Base64, RFC 4648 section 10's vectors, padded and not, both alphabets.
    var out: [64]u8 = zero
    let (b64_len, b64_len_error) = bytes.base64_encoded_len(6usize, true)
    if b64_len_error != ok || b64_len != 8usize { os.exit(70i32) }
    let (b64_bare, b64_bare_error) = bytes.base64_encoded_len(4usize, false)
    if b64_bare_error != ok || b64_bare != 6usize { os.exit(71i32) }
    let (foobar, foobar_error) = bytes.base64_encode(out[..], "foobar", .Standard, true)
    if foobar_error != ok || !str.eq(foobar, "Zm9vYmFy") { os.exit(72i32) }
    let (fooba, fooba_error) = bytes.base64_encode(out[..], "fooba", .Standard, true)
    if fooba_error != ok || !str.eq(fooba, "Zm9vYmE=") { os.exit(73i32) }
    let (foob, foob_error) = bytes.base64_encode(out[..], "foob", .Standard, true)
    if foob_error != ok || !str.eq(foob, "Zm9vYg==") { os.exit(74i32) }
    let (foob_bare, foob_bare_error) = bytes.base64_encode(out[..], "foob", .Standard, false)
    if foob_bare_error != ok || !str.eq(foob_bare, "Zm9vYg") { os.exit(75i32) }
    let (nothing, nothing_error) = bytes.base64_encode(out[..], "", .Standard, true)
    if nothing_error != ok || nothing.len != 0usize { os.exit(76i32) }
    // The URL alphabet differs in the two characters that are not URL-safe.
    var high: [3]u8 = zero
    high[0usize] = 251u8
    high[1usize] = 255u8
    high[2usize] = 191u8
    let (std_high, std_high_error) = bytes.base64_encode(out[..], high[..], .Standard, true)
    if std_high_error != ok || !str.eq(std_high, "+/+/") { os.exit(77i32) }
    let (url_high, url_high_error) = bytes.base64_encode(out[..], high[..], .Url, true)
    if url_high_error != ok || !str.eq(url_high, "-_-_") { os.exit(78i32) }
    var back: [64]u8 = zero
    let (foobar_back, foobar_back_error) = bytes.base64_decode(back[..], "Zm9vYmFy", .Standard)
    if foobar_back_error != ok || !str.eq(foobar_back, "foobar") { os.exit(79i32) }
    let (foob_back, foob_back_error) = bytes.base64_decode(back[..], "Zm9vYg==", .Standard)
    if foob_back_error != ok || !str.eq(foob_back, "foob") { os.exit(80i32) }
    let (foob_bare_back, foob_bare_back_error) = bytes.base64_decode(back[..], "Zm9vYg", .Standard)
    if foob_bare_back_error != ok || !str.eq(foob_bare_back, "foob") { os.exit(81i32) }
    let (url_back, url_back_error) = bytes.base64_decode(back[..], "-_-_", .Url)
    if url_back_error != ok || url_back.len != 3usize || url_back[0usize] != 251u8 || url_back[2usize] != 191u8 { os.exit(82i32) }
    // A character outside the alphabet, a length no encoding produces, and a buffer too small.
    let (_, bad_char) = bytes.base64_decode(back[..], "Zm9v*mFy", .Standard)
    if bad_char != bytes.Invalid { os.exit(83i32) }
    let (_, bad_len) = bytes.base64_decode(back[..], "Zm9vY", .Standard)
    if bad_len != bytes.Invalid { os.exit(84i32) }
    var tiny: [2]u8 = zero
    let (_, too_small) = bytes.base64_decode(tiny[..], "Zm9vYmFy", .Standard)
    if too_small != bytes.TooLarge { os.exit(85i32) }
    let (_, no_room) = bytes.base64_encode(tiny[..], "foobar", .Standard, true)
    if no_room != bytes.TooLarge { os.exit(86i32) }

    // --- Base32, the same section's vectors, and the hex alphabet.
    let (b32_len, b32_len_error) = bytes.base32_encoded_len(6usize, true)
    if b32_len_error != ok || b32_len != 16usize { os.exit(90i32) }
    let (b32_bare, b32_bare_error) = bytes.base32_encoded_len(6usize, false)
    if b32_bare_error != ok || b32_bare != 10usize { os.exit(91i32) }
    let (foobar32, foobar32_error) = bytes.base32_encode(out[..], "foobar", .Standard, true)
    if foobar32_error != ok || !str.eq(foobar32, "MZXW6YTBOI======") { os.exit(92i32) }
    let (foo32, foo32_error) = bytes.base32_encode(out[..], "foo", .Standard, true)
    if foo32_error != ok || !str.eq(foo32, "MZXW6===") { os.exit(93i32) }
    let (foo32_bare, foo32_bare_error) = bytes.base32_encode(out[..], "foo", .Standard, false)
    if foo32_bare_error != ok || !str.eq(foo32_bare, "MZXW6") { os.exit(94i32) }
    let (foobar32hex, foobar32hex_error) = bytes.base32_encode(out[..], "foobar", .Hex, true)
    if foobar32hex_error != ok || !str.eq(foobar32hex, "CPNMUOJ1E8======") { os.exit(95i32) }
    let (foobar32_back, foobar32_back_error) = bytes.base32_decode(back[..], "MZXW6YTBOI======", .Standard)
    if foobar32_back_error != ok || !str.eq(foobar32_back, "foobar") { os.exit(96i32) }
    let (foo32_back, foo32_back_error) = bytes.base32_decode(back[..], "MZXW6", .Standard)
    if foo32_back_error != ok || !str.eq(foo32_back, "foo") { os.exit(97i32) }
    let (hex_back, hex_back_error) = bytes.base32_decode(back[..], "CPNMUOJ1E8", .Hex)
    if hex_back_error != ok || !str.eq(hex_back, "foobar") { os.exit(98i32) }
    let (_, bad32_len) = bytes.base32_decode(back[..], "MZX", .Standard)
    if bad32_len != bytes.Invalid { os.exit(99i32) }
    let (_, bad32_char) = bytes.base32_decode(back[..], "MZXW1===", .Standard)
    if bad32_char != bytes.Invalid { os.exit(100i32) }

    // --- Base85. ASCII85 on Wikipedia's vector, partial groups, the `z` shorthand on the way
    // in; Z85 on its specification's vector and its refusal of a partial group.
    let (a85, a85_error) = bytes.base85_encode(out[..], "Man ", .Ascii85)
    if a85_error != ok || !str.eq(a85, "9jqo^") { os.exit(110i32) }
    let (a85_partial, a85_partial_error) = bytes.base85_encode(out[..], "Man", .Ascii85)
    if a85_partial_error != ok || !str.eq(a85_partial, "9jqo") { os.exit(111i32) }
    let (a85_len, a85_len_error) = bytes.base85_encoded_len(7usize, .Ascii85)
    if a85_len_error != ok || a85_len != 9usize { os.exit(112i32) }
    let (a85_back, a85_back_error) = bytes.base85_decode(back[..], "9jqo^", .Ascii85)
    if a85_back_error != ok || !str.eq(a85_back, "Man ") { os.exit(113i32) }
    let (a85_partial_back, a85_partial_back_error) = bytes.base85_decode(back[..], "9jqo", .Ascii85)
    if a85_partial_back_error != ok || !str.eq(a85_partial_back, "Man") { os.exit(114i32) }
    let (zeros, zeros_error) = bytes.base85_decode(back[..], "z", .Ascii85)
    if zeros_error != ok || zeros.len != 4usize || zeros[0usize] != 0u8 || zeros[3usize] != 0u8 { os.exit(115i32) }
    let (_, a85_bad) = bytes.base85_decode(back[..], "9", .Ascii85)
    if a85_bad != bytes.Invalid { os.exit(116i32) }
    // A group that decodes past 2^32 names no bytes.
    let (_, a85_over) = bytes.base85_decode(back[..], "uuuuu", .Ascii85)
    if a85_over != bytes.Invalid { os.exit(117i32) }
    var z85_in: [8]u8 = zero
    z85_in[0usize] = 134u8
    z85_in[1usize] = 79u8
    z85_in[2usize] = 210u8
    z85_in[3usize] = 111u8
    z85_in[4usize] = 181u8
    z85_in[5usize] = 89u8
    z85_in[6usize] = 247u8
    z85_in[7usize] = 91u8
    let (z85, z85_error) = bytes.base85_encode(out[..], z85_in[..], .Z85)
    if z85_error != ok || !str.eq(z85, "HelloWorld") { os.exit(118i32) }
    let (z85_back, z85_back_error) = bytes.base85_decode(back[..], "HelloWorld", .Z85)
    if z85_back_error != ok || z85_back.len != 8usize || z85_back[0usize] != 134u8 || z85_back[7usize] != 91u8 { os.exit(119i32) }
    let (_, z85_partial_len) = bytes.base85_encoded_len(7usize, .Z85)
    if z85_partial_len != bytes.Invalid { os.exit(120i32) }
    let (_, z85_partial) = bytes.base85_encode(out[..], "Man", .Z85)
    if z85_partial != bytes.Invalid { os.exit(121i32) }
    let (_, z85_short) = bytes.base85_decode(back[..], "Hello", .Z85)
    if z85_short != ok { os.exit(122i32) }
    let (_, z85_ragged) = bytes.base85_decode(back[..], "HelloWorl", .Z85)
    if z85_ragged != bytes.Invalid { os.exit(123i32) }

    // --- Every encoding round-trips every byte value, which the vectors above do not cover.
    var all: [256]u8 = zero
    var fill = 0usize
    while fill < 256usize {
        all[fill] = u8(fill)
        fill += 1usize
    }
    var wide: [512]u8 = zero
    var wider: [512]u8 = zero
    let (all64, all64_error) = bytes.base64_encode(wide[..], all[..], .Url, false)
    if all64_error != ok { os.exit(130i32) }
    let (all64_back, all64_back_error) = bytes.base64_decode(wider[..], all64, .Url)
    if all64_back_error != ok || !str.eq(all64_back, all[..]) { os.exit(131i32) }
    let (all32, all32_error) = bytes.base32_encode(wide[..], all[..], .Hex, true)
    if all32_error != ok { os.exit(132i32) }
    let (all32_back, all32_back_error) = bytes.base32_decode(wider[..], all32, .Hex)
    if all32_back_error != ok || !str.eq(all32_back, all[..]) { os.exit(133i32) }
    let (all85, all85_error) = bytes.base85_encode(wide[..], all[..], .Z85)
    if all85_error != ok { os.exit(134i32) }
    let (all85_back, all85_back_error) = bytes.base85_decode(wider[..], all85, .Z85)
    if all85_back_error != ok || !str.eq(all85_back, all[..]) { os.exit(135i32) }
    let (all85a, all85a_error) = bytes.base85_encode(wide[..], all[0usize..255usize], .Ascii85)
    if all85a_error != ok { os.exit(136i32) }
    let (all85a_back, all85a_back_error) = bytes.base85_decode(wider[..], all85a, .Ascii85)
    if all85a_back_error != ok || !str.eq(all85a_back, all[0usize..255usize]) { os.exit(137i32) }
    ret ok
}
