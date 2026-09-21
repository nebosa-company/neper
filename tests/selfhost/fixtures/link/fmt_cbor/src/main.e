// `e.fmt.cbor`: the RFC 8949 Appendix A examples encoded into one stream that must equal, byte
// for byte, what Python's `cbor2` writes for the same values (plus the indefinite and simple
// forms typed from the RFC table), then read back item by item through the typed helpers;
// half-precision floats decoded from their bit patterns; `skip` over nesting and indefinite
// text; and the four refusals. Each check exits with its own code; the stream comparison prints
// the first differing offset.

use e.fmt.cbor
use e.io
use e.mem
use e.os
use e.str

// A module-scope `const` of type `str` does not type check (D134), so the expectation is a call.
fn expected_hex() -> str {
    ret "00010a171818181918641903e81a000f42401b000000e8d4a510001bffffffffffffffff202938633903e73bfffffffffffffffffb3ff199999999999afb7e37e43c8800759cfbc010666666666666fa47c35000f5f4f6f74401020304644945544662c3bc63e6b0b44060830102038301820203820405a26161016162820203c11a514b67b0d74401020304d82076687474703a2f2f7777772e6578616d706c652e636f6d80a098190102030405060708090a0b0c0d0e0f1011121314151617181818199f010203ffbf616101fff0f8ff"
}

fn hex_nibble(b: u8) -> u8 {
    if b >= 97u8 { ret b - 87u8 }
    ret b - 48u8
}

fn unhex(hex: str, out: []u8) -> usize {
    var at = 0usize
    while at * 2usize < hex.len {
        out[at] = (hex_nibble(hex[at * 2usize]) << 4u32) | hex_nibble(hex[at * 2usize + 1usize])
        at += 1usize
    }
    ret at
}

fn print_usize(value: usize) -> err {
    var digits: [24]u8 = zero
    var n = 0usize
    var v = value
    while true {
        digits[n] = 48u8 + u8(v % 10usize)
        n += 1usize
        v = v / 10usize
        if v == 0usize { break }
    }
    while n > 0usize {
        n -= 1usize
        try io.print(digits[n..n + 1usize])
    }
    ret io.print("\n")
}

fn encode_all(e: *cbor.Encoder) -> err {
    try cbor.encode_uint(e, 0u64)
    try cbor.encode_uint(e, 1u64)
    try cbor.encode_uint(e, 10u64)
    try cbor.encode_uint(e, 23u64)
    try cbor.encode_uint(e, 24u64)
    try cbor.encode_uint(e, 25u64)
    try cbor.encode_uint(e, 100u64)
    try cbor.encode_uint(e, 1000u64)
    try cbor.encode_uint(e, 1000000u64)
    try cbor.encode_uint(e, 1000000000000u64)
    try cbor.encode_uint(e, 18446744073709551615u64)
    try cbor.encode_int(e, -1i64)
    try cbor.encode_int(e, -10i64)
    try cbor.encode_int(e, -100i64)
    try cbor.encode_int(e, -1000i64)
    try cbor.encode_negative(e, 18446744073709551615u64)
    try cbor.encode_f64(e, 1.1f64)
    try cbor.encode_f64(e, 1.0e300f64)
    try cbor.encode_f64(e, -4.1f64)
    try cbor.encode_f32(e, 100000.0f32)
    try cbor.encode_bool(e, true)
    try cbor.encode_bool(e, false)
    try cbor.encode_null(e)
    try cbor.encode_undefined(e)
    var four: [4]u8 = zero
    four[0] = 1u8
    four[1] = 2u8
    four[2] = 3u8
    four[3] = 4u8
    try cbor.encode_bytes(e, four[..])
    try cbor.encode_text(e, "IETF")
    try cbor.encode_text(e, "\xc3\xbc")
    try cbor.encode_text(e, "\xe6\xb0\xb4")
    try cbor.encode_bytes(e, four[..0usize])
    try cbor.encode_text(e, "")
    try cbor.encode_array(e, 3usize)
    try cbor.encode_uint(e, 1u64)
    try cbor.encode_uint(e, 2u64)
    try cbor.encode_uint(e, 3u64)
    try cbor.encode_array(e, 3usize)
    try cbor.encode_uint(e, 1u64)
    try cbor.encode_array(e, 2usize)
    try cbor.encode_uint(e, 2u64)
    try cbor.encode_uint(e, 3u64)
    try cbor.encode_array(e, 2usize)
    try cbor.encode_uint(e, 4u64)
    try cbor.encode_uint(e, 5u64)
    try cbor.encode_map(e, 2usize)
    try cbor.encode_text(e, "a")
    try cbor.encode_uint(e, 1u64)
    try cbor.encode_text(e, "b")
    try cbor.encode_array(e, 2usize)
    try cbor.encode_uint(e, 2u64)
    try cbor.encode_uint(e, 3u64)
    try cbor.encode_tag(e, 1u64)
    try cbor.encode_uint(e, 1363896240u64)
    try cbor.encode_tag(e, 23u64)
    try cbor.encode_bytes(e, four[..])
    try cbor.encode_tag(e, 32u64)
    try cbor.encode_text(e, "http://www.example.com")
    try cbor.encode_array(e, 0usize)
    try cbor.encode_map(e, 0usize)
    try cbor.encode_array(e, 25usize)
    var i = 1u64
    while i <= 25u64 {
        try cbor.encode_uint(e, i)
        i += 1u64
    }
    try cbor.begin_array(e)
    try cbor.encode_uint(e, 1u64)
    try cbor.encode_uint(e, 2u64)
    try cbor.encode_uint(e, 3u64)
    try cbor.encode_break(e)
    try cbor.begin_map(e)
    try cbor.encode_text(e, "a")
    try cbor.encode_uint(e, 1u64)
    try cbor.encode_break(e)
    try cbor.encode_simple(e, 16u8)
    try cbor.encode_simple(e, 255u8)
    ret ok
}

fn expect_uint(d: *cbor.Decoder, want: u64, code: i32) {
    let (got, decode_error) = cbor.decode_uint(d)
    if decode_error != ok || got != want { os.exit(code) }
}

fn expect_int(d: *cbor.Decoder, want: i64, code: i32) {
    let (got, decode_error) = cbor.decode_int(d)
    if decode_error != ok || got != want { os.exit(code) }
}

fn expect_f64_bits(d: *cbor.Decoder, want: u64, code: i32) {
    let (got, decode_error) = cbor.decode_f64(d)
    if decode_error != ok || mem.bitcast[u64](got) != want { os.exit(code) }
}

fn expect_text(d: *cbor.Decoder, want: str, code: i32) {
    let (got, decode_error) = cbor.decode_text(d)
    if decode_error != ok || !str.eq(got, want) { os.exit(code) }
}

fn expect_array(d: *cbor.Decoder, want: usize, code: i32) {
    let (got, indefinite, decode_error) = cbor.decode_array_len(d)
    if decode_error != ok || indefinite || got != want { os.exit(code) }
}

fn expect_simple(d: *cbor.Decoder, want: u64, code: i32) {
    let (item, decode_error) = cbor.decode_head(d)
    if decode_error != ok || item.major != 7u8 || item.value != want { os.exit(code) }
}

fn decode_half(hex: str) -> (f64, err) {
    var raw: [3]u8 = zero
    let n = unhex(hex, raw[..])
    var d = cbor.decoder(raw[..n])
    let (value, decode_error) = cbor.decode_f64(&d)
    ret (value, decode_error)
}

fn half_bits(hex: str, want: u64, code: i32) {
    let (value, decode_error) = decode_half(hex)
    if decode_error != ok || mem.bitcast[u64](value) != want { os.exit(code) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: the stream is byte-equal to cbor2's.
    var expected: [256]u8 = zero
    let expected_len = unhex(expected_hex(), expected[..])
    var storage: [256]u8 = zero
    var e = cbor.encoder(storage[..])
    let encode_error = encode_all(&e)
    if encode_error != ok { os.exit(1i32) }
    let got = cbor.encoded(&e)
    var at = 0usize
    while at < expected_len && at < got.len && got[at] == expected[at] { at += 1usize }
    if got.len != expected_len || at != expected_len {
        try io.print("stream differs at offset ")
        try print_usize(at)
        os.exit(2i32)
    }

    // 2: read back through the typed helpers.
    var d = cbor.decoder(got)
    expect_uint(&d, 0u64, 3i32)
    expect_uint(&d, 1u64, 3i32)
    expect_uint(&d, 10u64, 3i32)
    expect_uint(&d, 23u64, 3i32)
    expect_uint(&d, 24u64, 4i32)
    expect_uint(&d, 25u64, 4i32)
    expect_uint(&d, 100u64, 4i32)
    expect_uint(&d, 1000u64, 5i32)
    expect_uint(&d, 1000000u64, 6i32)
    expect_uint(&d, 1000000000000u64, 7i32)
    expect_uint(&d, 18446744073709551615u64, 8i32)
    expect_int(&d, -1i64, 9i32)
    expect_int(&d, -10i64, 9i32)
    expect_int(&d, -100i64, 10i32)
    expect_int(&d, -1000i64, 11i32)
    let (negative, negative_error) = cbor.decode_head(&d)
    if negative_error != ok || negative.major != 1u8 || negative.value != 18446744073709551615u64 { os.exit(12i32) }
    expect_f64_bits(&d, 4607632778762754458u64, 13i32)
    expect_f64_bits(&d, 9094988921128908188u64, 14i32)
    expect_f64_bits(&d, 13839674244900218470u64, 15i32)
    expect_f64_bits(&d, 4681608360884174848u64, 16i32)
    let (yes, yes_error) = cbor.decode_bool(&d)
    if yes_error != ok || !yes { os.exit(17i32) }
    let (no, no_error) = cbor.decode_bool(&d)
    if no_error != ok || no { os.exit(18i32) }
    if cbor.decode_null(&d) != ok { os.exit(19i32) }
    expect_simple(&d, 23u64, 20i32)
    let (bytes, bytes_error) = cbor.decode_bytes(&d)
    if bytes_error != ok || bytes.len != 4usize || bytes[0] != 1u8 || bytes[3] != 4u8 { os.exit(21i32) }
    expect_text(&d, "IETF", 22i32)
    expect_text(&d, "\xc3\xbc", 23i32)
    expect_text(&d, "\xe6\xb0\xb4", 24i32)
    let (empty_bytes, empty_bytes_error) = cbor.decode_bytes(&d)
    if empty_bytes_error != ok || empty_bytes.len != 0usize { os.exit(25i32) }
    expect_text(&d, "", 26i32)
    expect_array(&d, 3usize, 27i32)
    expect_uint(&d, 1u64, 27i32)
    expect_uint(&d, 2u64, 27i32)
    expect_uint(&d, 3u64, 27i32)
    expect_array(&d, 3usize, 28i32)
    expect_uint(&d, 1u64, 28i32)
    expect_array(&d, 2usize, 28i32)
    expect_uint(&d, 2u64, 28i32)
    expect_uint(&d, 3u64, 28i32)
    expect_array(&d, 2usize, 28i32)
    expect_uint(&d, 4u64, 28i32)
    expect_uint(&d, 5u64, 28i32)
    let (pairs, pairs_indefinite, pairs_error) = cbor.decode_map_len(&d)
    if pairs_error != ok || pairs_indefinite || pairs != 2usize { os.exit(29i32) }
    expect_text(&d, "a", 29i32)
    expect_uint(&d, 1u64, 29i32)
    expect_text(&d, "b", 29i32)
    expect_array(&d, 2usize, 29i32)
    expect_uint(&d, 2u64, 29i32)
    expect_uint(&d, 3u64, 29i32)
    let (epoch_tag, epoch_tag_error) = cbor.decode_tag(&d)
    if epoch_tag_error != ok || epoch_tag != 1u64 { os.exit(30i32) }
    expect_uint(&d, 1363896240u64, 30i32)
    let (bytes_tag, bytes_tag_error) = cbor.decode_tag(&d)
    if bytes_tag_error != ok || bytes_tag != 23u64 { os.exit(31i32) }
    if cbor.skip(&d) != ok { os.exit(31i32) }
    let (uri_tag, uri_tag_error) = cbor.decode_tag(&d)
    if uri_tag_error != ok || uri_tag != 32u64 { os.exit(32i32) }
    expect_text(&d, "http://www.example.com", 32i32)
    expect_array(&d, 0usize, 33i32)
    let (none, none_indefinite, none_error) = cbor.decode_map_len(&d)
    if none_error != ok || none_indefinite || none != 0usize { os.exit(34i32) }
    // The 25-item array is one `skip`.
    let before = d.at
    if cbor.skip(&d) != ok || d.at - before != 29usize { os.exit(35i32) }
    let (open_count, open, open_error) = cbor.decode_array_len(&d)
    if open_error != ok || !open || open_count != 0usize { os.exit(36i32) }
    var sum = 0u64
    while !cbor.at_break(&d) {
        let (item, item_error) = cbor.decode_uint(&d)
        if item_error != ok { os.exit(37i32) }
        sum += item
    }
    let (closing, closing_error) = cbor.decode_head(&d)
    if closing_error != ok || closing.major != 7u8 || closing.info != 31u8 || sum != 6u64 { os.exit(38i32) }
    let (open_pairs, open_map, open_map_error) = cbor.decode_map_len(&d)
    if open_map_error != ok || !open_map || open_pairs != 0usize { os.exit(39i32) }
    expect_text(&d, "a", 39i32)
    expect_uint(&d, 1u64, 39i32)
    if !cbor.at_break(&d) { os.exit(40i32) }
    let (map_closing, map_closing_error) = cbor.decode_head(&d)
    if map_closing_error != ok { os.exit(40i32) }
    expect_simple(&d, 16u64, 41i32)
    expect_simple(&d, 255u64, 42i32)
    if cbor.remaining(&d) != 0usize { os.exit(43i32) }

    // 3: half precision, from the RFC's own examples.
    half_bits("f93e00", 4609434218613702656u64, 44i32)
    half_bits("f97bff", 4679235614791434240u64, 45i32)
    half_bits("f90001", 4499096027743125504u64, 46i32)
    half_bits("f98000", 9223372036854775808u64, 47i32)
    half_bits("f97c00", 9218868437227405312u64, 48i32)

    // 4: `skip` walks an indefinite text and a tagged nested map as one item each.
    var raw: [32]u8 = zero
    let skip_len = unhex("7f6261626163ffd9d9f7a1616182f4f5", raw[..])
    var s = cbor.decoder(raw[..skip_len])
    if cbor.skip(&s) != ok || s.at != 7usize { os.exit(49i32) }
    if cbor.skip(&s) != ok || cbor.remaining(&s) != 0usize { os.exit(50i32) }

    // 5: refusals.
    let short_len = unhex("1a0001", raw[..])
    var short = cbor.decoder(raw[..short_len])
    let (short_value, short_error) = cbor.decode_uint(&short)
    if short_error != cbor.Truncated { os.exit(51i32) }
    let reserved_len = unhex("1c", raw[..])
    var reserved = cbor.decoder(raw[..reserved_len])
    let (reserved_item, reserved_error) = cbor.decode_head(&reserved)
    if reserved_error != cbor.Invalid { os.exit(52i32) }
    let wrong_len = unhex("20", raw[..])
    var wrong = cbor.decoder(raw[..wrong_len])
    let (wrong_value, wrong_error) = cbor.decode_uint(&wrong)
    if wrong_error != cbor.Mismatch { os.exit(53i32) }
    var tiny: [2]u8 = zero
    var full = cbor.encoder(tiny[..])
    if cbor.encode_uint(&full, 1000u64) != cbor.TooSmall { os.exit(54i32) }
    let bad_simple_len = unhex("f810", raw[..])
    var bad_simple = cbor.decoder(raw[..bad_simple_len])
    let (bad_item, bad_simple_error) = cbor.decode_head(&bad_simple)
    if bad_simple_error != cbor.Invalid { os.exit(55i32) }

    try io.print("fmt cbor ok\n")
    ret ok
}
