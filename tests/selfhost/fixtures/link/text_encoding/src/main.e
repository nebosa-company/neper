// `e.text.encoding`: UTF-8 to and from UTF-16 and UTF-32 in both byte orders, BOMs
// written and detected, invalid and truncated input rejected or replaced, and the
// streaming decoder and encoder across split scalars and a too-small destination.
// Every check has its own exit code.
use e.os
use e.mem
use e.text.encoding as enc

fn bytes_equal(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn split_bom(encoding: enc.Encoding, first: []const u8, rest: []const u8) -> bool {
    var d = enc.decoder(encoding, .Reject, true)
    var out: [8]u8 = zero
    let (c1, w1, s1) = enc.decode(&d, first, out[0..], false)
    if s1 != ok || c1 != first.len || w1 != 0usize { ret false }
    let (c2, w2, s2) = enc.decode(&d, rest, out[0..], true)
    ret s2 == ok && c2 == rest.len && w2 == 1usize && out[0usize] == 65u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    // "aé€😀" in UTF-8: 61 C3A9 E282AC F09F9880
    let text: [10]u8 = [10]u8{ 97, 195, 169, 226, 130, 172, 240, 159, 152, 128 }
    let (u16le, e1) = enc.from_utf8(a, .Utf16Le, text[0..], false)
    if e1 != ok || u16le.len != 10usize { os.exit(1) }
    if u16le[0] != 97u8 || u16le[1] != 0u8 || u16le[2] != 233u8 || u16le[4] != 172u8 || u16le[5] != 32u8 || u16le[6] != 61u8 || u16le[7] != 216u8 || u16le[8] != 0u8 || u16le[9] != 222u8 { os.exit(2) }
    let (back, e2) = enc.to_utf8(a, .Utf16Le, u16le, .Reject)
    if e2 != ok || !bytes_equal(back, text[0..]) { os.exit(3) }
    let (u32be, e3) = enc.from_utf8(a, .Utf32Be, text[0..], true)
    if e3 != ok || u32be.len != 20usize || u32be[2] != 254u8 || u32be[3] != 255u8 || u32be[19] != 0u8 || u32be[18] != 246u8 || u32be[17] != 1u8 { os.exit(4) }
    let (bom, bom_len, has_bom) = enc.detect_bom(u32be)
    if !has_bom || bom != .Utf32Be || bom_len != 4usize { os.exit(5) }
    let (back32, e4) = enc.to_utf8(a, .Utf32Be, u32be, .Reject)
    if e4 != ok || !bytes_equal(back32, text[0..]) { os.exit(6) }
    let (u8bom, e5) = enc.from_utf8(a, .Utf8, text[0..], true)
    if e5 != ok || u8bom.len != 13usize || u8bom[0] != 239u8 { os.exit(7) }
    let (plain, e6) = enc.to_utf8(a, .Utf8, u8bom, .Reject)
    if e6 != ok || !bytes_equal(plain, text[0..]) { os.exit(8) }
    let bad: [3]u8 = [3]u8{ 97, 128, 98 }
    let (_, rejected) = enc.to_utf8(a, .Utf8, bad[0..], .Reject)
    if rejected != enc.Invalid { os.exit(9) }
    let (replaced, e7) = enc.to_utf8(a, .Utf8, bad[0..], .Replace)
    if e7 != ok || replaced.len != 5usize || replaced[1] != 239u8 || replaced[2] != 191u8 || replaced[3] != 189u8 || replaced[4] != 98u8 { os.exit(10) }
    let cut: [2]u8 = [2]u8{ 226, 130 }
    let (_, incomplete) = enc.to_utf8(a, .Utf8, cut[0..], .Reject)
    if incomplete != enc.Incomplete { os.exit(11) }
    let lone: [4]u8 = [4]u8{ 61, 216, 97, 0 }
    let (_, lone_error) = enc.to_utf8(a, .Utf16Le, lone[0..], .Reject)
    let (lone_replaced, e8) = enc.to_utf8(a, .Utf16Le, lone[0..], .Replace)
    if lone_error != enc.Invalid || e8 != ok || lone_replaced.len != 4usize || lone_replaced[3] != 97u8 { os.exit(12) }
    // Streaming: the euro sign split across two calls, and a too-small destination.
    var d = enc.decoder(.Utf8, .Reject, true)
    var out: [8]u8 = zero
    let (c1, w1, s1) = enc.decode(&d, text[0..4], out[0..], false)
    if s1 != ok || c1 != 4usize || w1 != 3usize { os.exit(13) }
    let (c2, w2, s2) = enc.decode(&d, text[4..], out[w1..], false)
    if s2 != enc.TooSmall || c2 != 2usize || w2 != 3usize { os.exit(14) }
    let (c3, w3, s3) = enc.decode(&d, text[6..], out[w1 + w2..], true)
    if s3 != enc.TooSmall || c3 != 0usize || w3 != 0usize { os.exit(15) }
    var rest: [4]u8 = zero
    let (c4, w4, s4) = enc.decode(&d, text[6..], rest[0..], true)
    if s4 != ok || c4 != 4usize || w4 != 4usize || rest[0] != 240u8 { os.exit(16) }
    if !bytes_equal(out[..6], text[..6]) { os.exit(17) }
    var e = enc.encoder(.Utf16Be, true)
    var wide: [16]u8 = zero
    let (ec1, ew1, es1) = enc.encode(&e, text[0..2], wide[0..], false)
    if es1 != ok || ec1 != 1usize || ew1 != 4usize || wide[0] != 254u8 || wide[1] != 255u8 || wide[3] != 97u8 { os.exit(18) }
    let (ec2, ew2, es2) = enc.encode(&e, text[1..], wide[ew1..], true)
    if es2 != ok || ec2 != 9usize || ew2 != 8usize || wide[4] != 0u8 || wide[5] != 233u8 { os.exit(19) }
    let (n16, e9) = enc.encoded_len(.Utf16Le, text[0..], false)
    let (n8, e10) = enc.decoded_len(.Utf16Le, u16le, .Reject)
    if e9 != ok || n16 != 10usize || e10 != ok || n8 != 10usize { os.exit(20) }
    let bom8a: [1]u8 = [1]u8{ 239 }
    let bom8b: [3]u8 = [3]u8{ 187, 191, 65 }
    let bom16lea: [1]u8 = [1]u8{ 255 }
    let bom16leb: [3]u8 = [3]u8{ 254, 65, 0 }
    let bom16le_taila: [3]u8 = [3]u8{ 255, 254, 65 }
    let bom16le_tailb: [1]u8 = [1]u8{ 0 }
    let bom16le_nul: [4]u8 = [4]u8{ 255, 254, 0, 0 }
    let bom16bea: [1]u8 = [1]u8{ 254 }
    let bom16beb: [3]u8 = [3]u8{ 255, 0, 65 }
    let bom32lea: [2]u8 = [2]u8{ 255, 254 }
    let bom32leb: [6]u8 = [6]u8{ 0, 0, 65, 0, 0, 0 }
    let bom32bea: [3]u8 = [3]u8{ 0, 0, 254 }
    let bom32beb: [5]u8 = [5]u8{ 255, 0, 0, 0, 65 }
    if !split_bom(.Utf8, bom8a[0..], bom8b[0..]) { os.exit(21) }
    if !split_bom(.Utf16Le, bom16lea[0..], bom16leb[0..]) { os.exit(22) }
    if !split_bom(.Utf16Be, bom16bea[0..], bom16beb[0..]) { os.exit(23) }
    if !split_bom(.Utf32Le, bom32lea[0..], bom32leb[0..]) { os.exit(24) }
    if !split_bom(.Utf32Be, bom32bea[0..], bom32beb[0..]) { os.exit(25) }
    if !split_bom(.Utf16Le, bom16le_taila[0..], bom16le_tailb[0..]) { os.exit(26) }
    var nul_decoder = enc.decoder(.Utf16Le, .Reject, true)
    var nul_out: [4]u8 = zero
    let (nul_consumed, nul_written, nul_error) = enc.decode(&nul_decoder, bom16le_nul[0..], nul_out[0..], true)
    if nul_error != ok || nul_consumed != 4usize || nul_written != 1usize || nul_out[0usize] != 0u8 { os.exit(27) }
    let (nul_len, nul_len_error) = enc.decoded_len(.Utf16Le, bom16le_nul[0..], .Reject)
    if nul_len_error != ok || nul_len != 1usize { os.exit(28) }
    os.exit(0)
    ret ok
}
