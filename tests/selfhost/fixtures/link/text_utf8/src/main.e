// `e.text.utf8` (D299): strict decoding, encoding at every width boundary, counting and
// indexing by scalar, and the lossy iterator. Expected bytes and offsets were derived
// independently. Every check exits with its own number; 0 is every check passed.
use e.os
use e.mem
use e.str
use e.text.utf8

fn main(a: *mem.Arena, args: []str) -> err {
    // "héllo wörld €🎮": 14 scalars over 21 bytes, with a two-, three- and four-byte form.
    let text = "h\xc3\xa9llo w\xc3\xb6rld \xe2\x82\xac\xf0\x9f\x8e\xae"
    if text.len != 21usize { os.exit(1) }
    if !utf8.validate(text) { os.exit(2) }

    // --- decode --------------------------------------------------------------------------
    let (d0, e0) = utf8.decode(text, 0usize)
    if e0 != ok || d0.scalar != 104u32 || d0.width != 1u8 { os.exit(3) }
    let (d1, e1) = utf8.decode(text, 1usize)
    if e1 != ok || d1.scalar != 233u32 || d1.width != 2u8 { os.exit(4) }
    let (d14, e14) = utf8.decode(text, 14usize)
    if e14 != ok || d14.scalar != 8364u32 || d14.width != 3u8 { os.exit(5) }
    let (d17, e17) = utf8.decode(text, 17usize)
    if e17 != ok || d17.scalar != 127918u32 || d17.width != 4u8 { os.exit(6) }
    // A continuation byte is not a start.
    let (d2, e2) = utf8.decode(text, 2usize)
    if e2 != utf8.Invalid || d2.width != 0u8 { os.exit(7) }
    // Past the end.
    let (d21, e21) = utf8.decode(text, 21usize)
    if e21 != utf8.Invalid || d21.width != 0u8 { os.exit(8) }

    // Every malformed shape Unicode names, each refused at its first byte.
    let (o2, oe2) = utf8.decode("\xc0\x80", 0usize)
    if oe2 != utf8.Invalid { os.exit(9) }
    let (o3, oe3) = utf8.decode("\xe0\x80\x80", 0usize)
    if oe3 != utf8.Invalid { os.exit(10) }
    let (o4, oe4) = utf8.decode("\xf0\x80\x80\x80", 0usize)
    if oe4 != utf8.Invalid { os.exit(11) }
    let (sur, sure) = utf8.decode("\xed\xa0\x80", 0usize)
    if sure != utf8.Invalid { os.exit(12) }
    let (big, bige) = utf8.decode("\xf4\x90\x80\x80", 0usize)
    if bige != utf8.Invalid { os.exit(13) }
    let (f5, f5e) = utf8.decode("\xf5\x80\x80\x80", 0usize)
    if f5e != utf8.Invalid { os.exit(14) }
    let (lone, lonee) = utf8.decode("\x80", 0usize)
    if lonee != utf8.Invalid { os.exit(15) }
    let (trunc, trunce) = utf8.decode("\xe2\x82", 0usize)
    if trunce != utf8.Invalid { os.exit(16) }
    let (badc, badce) = utf8.decode("\xc3\x41", 0usize)
    if badce != utf8.Invalid { os.exit(17) }
    // The boundaries that are valid: the smallest of each width and the largest scalar.
    let (b80, b80e) = utf8.decode("\xc2\x80", 0usize)
    if b80e != ok || b80.scalar != 128u32 || b80.width != 2u8 { os.exit(18) }
    let (b800, b800e) = utf8.decode("\xe0\xa0\x80", 0usize)
    if b800e != ok || b800.scalar != 2048u32 || b800.width != 3u8 { os.exit(19) }
    let (b10000, b10000e) = utf8.decode("\xf0\x90\x80\x80", 0usize)
    if b10000e != ok || b10000.scalar != 65536u32 || b10000.width != 4u8 { os.exit(20) }
    let (bmax, bmaxe) = utf8.decode("\xf4\x8f\xbf\xbf", 0usize)
    if bmaxe != ok || bmax.scalar != 1114111u32 || bmax.width != 4u8 { os.exit(21) }
    if utf8.validate("\xed\xa0\x80") { os.exit(22) }
    if utf8.validate("ok\xc3") { os.exit(23) }
    if !utf8.validate("") { os.exit(24) }

    // --- encode ----------------------------------------------------------------------------
    var out: [4]u8 = zero
    let (w1, we1) = utf8.encode(65u32, out[..])
    if we1 != ok || w1 != 1u8 || out[0usize] != 65u8 { os.exit(25) }
    let (w2, we2) = utf8.encode(233u32, out[..])
    if we2 != ok || w2 != 2u8 || out[0usize] != 195u8 || out[1usize] != 169u8 { os.exit(26) }
    let (w3, we3) = utf8.encode(8364u32, out[..])
    if we3 != ok || w3 != 3u8 || out[0usize] != 226u8 || out[1usize] != 130u8 || out[2usize] != 172u8 { os.exit(27) }
    let (w4, we4) = utf8.encode(127918u32, out[..])
    if we4 != ok || w4 != 4u8 || out[0usize] != 240u8 || out[1usize] != 159u8 || out[2usize] != 142u8 || out[3usize] != 174u8 { os.exit(28) }
    // Width boundaries: the last scalar of each width and the first of the next.
    let (w7f, we7f) = utf8.encode(127u32, out[..])
    if we7f != ok || w7f != 1u8 || out[0usize] != 127u8 { os.exit(29) }
    let (w80, we80) = utf8.encode(128u32, out[..])
    if we80 != ok || w80 != 2u8 || out[0usize] != 194u8 || out[1usize] != 128u8 { os.exit(30) }
    let (w7ff, we7ff) = utf8.encode(2047u32, out[..])
    if we7ff != ok || w7ff != 2u8 || out[0usize] != 223u8 || out[1usize] != 191u8 { os.exit(31) }
    let (w800, we800) = utf8.encode(2048u32, out[..])
    if we800 != ok || w800 != 3u8 || out[0usize] != 224u8 || out[1usize] != 160u8 || out[2usize] != 128u8 { os.exit(32) }
    let (wffff, weffff) = utf8.encode(65535u32, out[..])
    if weffff != ok || wffff != 3u8 || out[0usize] != 239u8 || out[1usize] != 191u8 || out[2usize] != 191u8 { os.exit(33) }
    let (w10000, we10000) = utf8.encode(65536u32, out[..])
    if we10000 != ok || w10000 != 4u8 || out[0usize] != 240u8 || out[1usize] != 144u8 || out[2usize] != 128u8 || out[3usize] != 128u8 { os.exit(34) }
    let (wmax, wemax) = utf8.encode(1114111u32, out[..])
    if wemax != ok || wmax != 4u8 || out[0usize] != 244u8 || out[1usize] != 143u8 || out[2usize] != 191u8 || out[3usize] != 191u8 { os.exit(35) }
    // Not scalars: a surrogate and one past the last plane.
    let (wsur, wesur) = utf8.encode(55296u32, out[..])
    if wesur != utf8.Invalid || wsur != 0u8 { os.exit(36) }
    let (wover, weover) = utf8.encode(1114112u32, out[..])
    if weover != utf8.Invalid || wover != 0u8 { os.exit(37) }
    // Too small is measured against the width this scalar needs, not four.
    var small: [2]u8 = zero
    let (ws2, wes2) = utf8.encode(233u32, small[..])
    if wes2 != ok || ws2 != 2u8 { os.exit(38) }
    let (ws3, wes3) = utf8.encode(8364u32, small[..])
    if wes3 != utf8.TooSmall || ws3 != 0u8 { os.exit(39) }
    var none: [0]u8 = zero
    let (ws0, wes0) = utf8.encode(65u32, none[..])
    if wes0 != utf8.TooSmall { os.exit(40) }
    // Encoding what decode read reproduces the bytes.
    let (rt, rte) = utf8.encode(d17.scalar, out[..])
    if rte != ok || rt != 4u8 || out[0usize] != text[17usize] || out[3usize] != text[20usize] { os.exit(41) }

    // --- count and byte_offset ------------------------------------------------------------
    let (n, ne) = utf8.count(text)
    if ne != ok || n != 14usize { os.exit(42) }
    let (n0, n0e) = utf8.count("")
    if n0e != ok || n0 != 0usize { os.exit(43) }
    let (nbad, nbade) = utf8.count("ab\xffcd")
    if nbade != utf8.Invalid || nbad != 2usize { os.exit(44) }
    // Byte offsets by scalar index, across all three multi-byte widths.
    let (bo0, boe0) = utf8.byte_offset(text, 0usize)
    if boe0 != ok || bo0 != 0usize { os.exit(45) }
    let (bo1, boe1) = utf8.byte_offset(text, 1usize)
    if boe1 != ok || bo1 != 1usize { os.exit(46) }
    let (bo2, boe2) = utf8.byte_offset(text, 2usize)
    if boe2 != ok || bo2 != 3usize { os.exit(47) }
    let (bo8, boe8) = utf8.byte_offset(text, 8usize)
    if boe8 != ok || bo8 != 10usize { os.exit(48) }
    let (bo13, boe13) = utf8.byte_offset(text, 13usize)
    if boe13 != ok || bo13 != 17usize { os.exit(49) }
    // The count itself is the end, so a slice to it reaches the last byte.
    let (bo14, boe14) = utf8.byte_offset(text, 14usize)
    if boe14 != ok || bo14 != 21usize { os.exit(50) }
    let (bo15, boe15) = utf8.byte_offset(text, 15usize)
    if boe15 != utf8.Invalid { os.exit(51) }
    let (bobad, bobade) = utf8.byte_offset("a\xff", 2usize)
    if bobade != utf8.Invalid || bobad != 1usize { os.exit(52) }
    let (bo12, boe12) = utf8.byte_offset(text, 12usize)
    if boe12 != ok || !str.eq(text[bo12..bo14], "\xe2\x82\xac\xf0\x9f\x8e\xae") { os.exit(53) }

    // --- iterator ----------------------------------------------------------------------------
    var it = utf8.iterator(text)
    var seen = 0usize
    var last = 0u32
    while true {
        let (scalar, more) = utf8.iterator_next(&it)
        if !more { break }
        seen += 1usize
        last = scalar
    }
    if seen != 14usize || last != 127918u32 { os.exit(54) }
    if it.off != 21usize { os.exit(55) }
    // Lossy: a broken lead byte is one U+FFFD over one byte, and what follows still reads.
    var lossy = utf8.iterator("a\xc3\x28b")
    let (l0, lm0) = utf8.iterator_next(&lossy)
    if !lm0 || l0 != 97u32 { os.exit(56) }
    let (l1, lm1) = utf8.iterator_next(&lossy)
    if !lm1 || l1 != 65533u32 { os.exit(57) }
    let (l2, lm2) = utf8.iterator_next(&lossy)
    if !lm2 || l2 != 40u32 { os.exit(58) }
    let (l3, lm3) = utf8.iterator_next(&lossy)
    if !lm3 || l3 != 98u32 { os.exit(59) }
    let (l4, lm4) = utf8.iterator_next(&lossy)
    if lm4 { os.exit(60) }
    // One replacement per byte, so a truncated three-byte form is two.
    var cut = utf8.iterator("\xe2\x82")
    let (c0, cm0) = utf8.iterator_next(&cut)
    let (c1, cm1) = utf8.iterator_next(&cut)
    let (c2, cm2) = utf8.iterator_next(&cut)
    if !cm0 || c0 != 65533u32 || !cm1 || c1 != 65533u32 || cm2 { os.exit(61) }
    // Strict: the same input stops at the fault and leaves the offset on it.
    var strict = utf8.iterator("a\xc3\x28b")
    let (s0, sm0, se0) = utf8.iterator_next_err(&strict)
    if se0 != ok || !sm0 || s0 != 97u32 { os.exit(62) }
    let (s1, sm1, se1) = utf8.iterator_next_err(&strict)
    if se1 != utf8.Invalid || sm1 { os.exit(63) }
    if strict.off != 1usize { os.exit(64) }
    var strict_end = utf8.iterator("")
    let (s2, sm2, se2) = utf8.iterator_next_err(&strict_end)
    if se2 != ok || sm2 { os.exit(65) }
    ret ok
}

