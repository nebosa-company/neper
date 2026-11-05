// `e.fmt.woff2`: the declared file size and optional metadata/private layout
// are exact, and transformed table lengths cannot wrap the allocation bound.

use e.fmt.woff2
use e.io
use e.mem
use e.os

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, text: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, text.len / 2usize)
    if e != ok { os.exit(90i32) }
    var i = 0usize
    while i < text.len {
        out[i / 2usize] = (nibble(text[i]) << 4u8) | nibble(text[i + 1usize])
        i += 2usize
    }
    ret out
}

fn copy(dst: []u8, src: []const u8) {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
}

fn put32(dst: []u8, at: usize, value: u32) {
    dst[at] = u8(value >> 24u32)
    dst[at + 1usize] = u8((value >> 16u32) & 255u32)
    dst[at + 2usize] = u8((value >> 8u32) & 255u32)
    dst[at + 3usize] = u8(value & 255u32)
}

fn put16(dst: []u8, at: usize, value: u32) {
    dst[at] = u8(value >> 8u32)
    dst[at + 1usize] = u8(value & 255u32)
}

fn get16(src: []const u8, at: usize) -> u32 { ret (u32(src[at]) << 8u32) | u32(src[at + 1usize]) }

fn table_of(font: []const u8, tag: u32) -> (usize, usize, bool) {
    let count = (usize(font[4]) << 8usize) | usize(font[5])
    var i = 0usize
    while i < count {
        let at = 12usize + 16usize * i
        let found = (u32(font[at]) << 24u32) | (u32(font[at + 1usize]) << 16u32) | (u32(font[at + 2usize]) << 8u32) | u32(font[at + 3usize])
        if found == tag {
            let offset = (usize(font[at + 8usize]) << 24usize) | (usize(font[at + 9usize]) << 16usize) | (usize(font[at + 10usize]) << 8usize) | usize(font[at + 11usize])
            let length = (usize(font[at + 12usize]) << 24usize) | (usize(font[at + 13usize]) << 16usize) | (usize(font[at + 14usize]) << 8usize) | usize(font[at + 15usize])
            ret (offset, length, true)
        }
        i += 1usize
    }
    ret (0usize, 0usize, false)
}

// #287: a two-glyph transformed WOFF2 font: a four-byte (long) loca, a
// transformed hmtx with both lsb arrays dropped, one composite glyph with
// xMin -16 and one simple glyph with a single point at x = -5. `null_loca`
// encodes loca with the null transform, for the mismatched-pair case.
fn build_font(a: *mem.Arena, null_loca: bool) -> []u8 {
    var total = 222usize
    var compressed = 161u32
    var data_len = 157usize
    if null_loca {
        total = 233usize
        compressed = 173u32
        data_len = 169usize
    }
    let (font, fe) = mem.alloc[u8](a, total)
    if fe != ok { os.exit(90i32) }
    var q = 0usize
    while q < total {
        font[q] = 0u8
        q += 1usize
    }
    put32(font, 0usize, 0x774F4632u32)
    put32(font, 4usize, 0x00010000u32)
    put32(font, 8usize, u32(total))
    put16(font, 12usize, 5u32)
    put32(font, 20usize, compressed)
    put16(font, 24usize, 1u32)
    var at = 48usize
    font[at] = 1u8
    at += 1usize
    font[at] = 54u8
    at += 1usize
    font[at] = 2u8
    at += 1usize
    font[at] = 36u8
    at += 1usize
    font[at] = 67u8
    at += 1usize
    font[at] = 8u8
    at += 1usize
    font[at] = 5u8
    at += 1usize
    font[at] = 10u8
    at += 1usize
    font[at] = 32u8
    at += 1usize
    font[at] = 62u8
    at += 1usize
    if null_loca {
        font[at] = 203u8
        at += 1usize
        font[at] = 12u8
        at += 1usize
    } else {
        font[at] = 11u8
        at += 1usize
        font[at] = 12u8
        at += 1usize
        font[at] = 0u8
        at += 1usize
    }
    // One uncompressed Brotli meta-block carries every table, then an empty
    // last block closes the stream.
    let mlen = u32(data_len - 1usize)
    font[at] = u8((mlen & 15u32) << 4u32)
    at += 1usize
    font[at] = u8((mlen >> 4u32) & 255u32)
    at += 1usize
    font[at] = u8((mlen >> 12u32) | 16u32)
    at += 1usize
    // head is 54 zero bytes; hhea's numberOfHMetrics (offset 34) is 2.
    let hhea = at + 54usize
    put16(font, hhea + 34usize, 2u32)
    // Transformed hmtx: both lsb arrays dropped, so every lsb is the xMin.
    let hmtx = hhea + 36usize
    font[hmtx] = 3u8
    put16(font, hmtx + 1usize, 500u32)
    put16(font, hmtx + 3usize, 600u32)
    // Transformed glyf header: glyph_count 2, index_format 1 (four-byte loca).
    let gb = hmtx + 5usize
    put16(font, gb, 0u32)
    put16(font, gb + 2usize, 0u32)
    put16(font, gb + 4usize, 2u32)
    put16(font, gb + 6usize, 1u32)
    put32(font, gb + 8usize, 4u32)
    put32(font, gb + 12usize, 1u32)
    put32(font, gb + 16usize, 1u32)
    put32(font, gb + 20usize, 2u32)
    put32(font, gb + 24usize, 6u32)
    put32(font, gb + 28usize, 12u32)
    put32(font, gb + 32usize, 0u32)
    let s = gb + 36usize
    font[s] = 255u8
    font[s + 1usize] = 255u8
    font[s + 2usize] = 0u8
    font[s + 3usize] = 1u8
    font[s + 4usize] = 1u8
    font[s + 5usize] = 10u8
    font[s + 6usize] = 5u8
    font[s + 7usize] = 0u8
    font[s + 11usize] = 1u8
    font[s + 14usize] = 128u8
    font[s + 18usize] = 255u8
    font[s + 19usize] = 240u8
    font[s + 23usize] = 100u8
    font[s + 25usize] = 200u8
    if null_loca {
        put32(font, s + 26usize, 0u32)
        put32(font, s + 30usize, 16u32)
        put32(font, s + 34usize, 32u32)
    }
    font[at + data_len] = 3u8
    ret font
}

// #287: a one-table font that marks `head`, which has no transform, with
// transform version 1.
fn build_head_transform(a: *mem.Arena) -> []u8 {
    let total = 109usize
    let (font, fe) = mem.alloc[u8](a, total)
    if fe != ok { os.exit(90i32) }
    var q = 0usize
    while q < total {
        font[q] = 0u8
        q += 1usize
    }
    put32(font, 0usize, 0x774F4632u32)
    put32(font, 4usize, 0x00010000u32)
    put32(font, 8usize, 109u32)
    put16(font, 12usize, 1u32)
    put32(font, 20usize, 58u32)
    put16(font, 24usize, 1u32)
    font[48usize] = 65u8
    font[49usize] = 54u8
    font[50usize] = 54u8
    let mlen = 53u32
    font[51usize] = u8((mlen & 15u32) << 4u32)
    font[52usize] = u8((mlen >> 4u32) & 255u32)
    font[53usize] = u8((mlen >> 12u32) | 16u32)
    font[108usize] = 3u8
    ret font
}

fn main(a: *mem.Arena, args: []str) -> err {
    let hex = "774f463200010000000001010007000000000000000000c000010000000000000000000000000000000000000000000001360a8d2b470b0c0004060715022403061bc10000e4605cde1393dd1665451af1d3207bc0895f4a44cb5225743020e7917603db4cd4eda2b8e5f4d76ef6c1c69eff4949dd61e18886537ca4da768ba3559e0b9ab3e6e3d44fddec9013f5ae97c090f7c7c98c1d871000d030321339ffff6b401010de316004b0cee460b36776339ee20d2a2d2ebfa5efebcedb4ebd4f79525069d2d2b48f4055f79af87f858827774303fd644682e26597d2e3746ec812a7029469f31b68882a69146bd63536d665f7edb70b075e0c032249954e48ea00"
    let source = unhex(a, hex)
    let (_, source_error) = woff2.to_sfnt(a, source)
    if source_error != ok { os.exit(1i32) }

    // A header length that does not equal the byte slice and bytes appended
    // after the declared end are both invalid.
    var wrong_length: [257]u8 = zero
    copy(wrong_length[..], source)
    put32(wrong_length[..], 8usize, 256u32)
    let (_, wrong_length_error) = woff2.to_sfnt(a, wrong_length[..])
    if wrong_length_error != woff2.Invalid { os.exit(2i32) }
    var trailing: [258]u8 = zero
    copy(trailing[..], source)
    let (_, trailing_error) = woff2.to_sfnt(a, trailing[..])
    if trailing_error != woff2.Invalid { os.exit(3i32) }

    // Legal four-byte-aligned metadata and private data occupy the complete
    // declared file, rather than being mistaken for extraneous trailing data.
    var optional_blocks: [265]u8 = zero
    copy(optional_blocks[..], source)
    put32(optional_blocks[..], 8usize, 265u32)
    put32(optional_blocks[..], 28usize, 260u32)
    put32(optional_blocks[..], 32usize, 1u32)
    put32(optional_blocks[..], 36usize, 1u32)
    put32(optional_blocks[..], 40usize, 264u32)
    put32(optional_blocks[..], 44usize, 1u32)
    optional_blocks[260usize] = 77u8
    optional_blocks[264usize] = 80u8
    let (_, optional_blocks_error) = woff2.to_sfnt(a, optional_blocks[..])
    if optional_blocks_error != ok { os.exit(4i32) }

    // The checked transformed-length accumulator rejects a single oversize
    // table, a cumulative overrun, and values that would wrap on wasm32.
    let (_, oversize) = woff2.transformed_length_add(0usize, 268435457usize)
    let (_, cumulative) = woff2.transformed_length_add(268435456usize, 1usize)
    let (_, wrapped) = woff2.transformed_length_add(2147483648usize, 2147483648usize)
    if oversize || cumulative || wrapped { os.exit(5i32) }

    // A transformed glyf blob with its final, unused substream declared as
    // u32::MAX must not wrap its end back into this small input on wasm32.
    // The preceding empty-glyph streams make the blob otherwise complete.
    var wrapped_glyf: [42]u8 = zero
    wrapped_glyf[5usize] = 1u8
    put32(wrapped_glyf[..], 8usize, 2u32)
    put32(wrapped_glyf[..], 28usize, 4u32)
    put32(wrapped_glyf[..], 32usize, 4294967295u32)
    let (_, wrapped_glyf_error) = woff2.reconstruct_glyf(a, wrapped_glyf[..], 4usize)
    if wrapped_glyf_error != woff2.Invalid { os.exit(6i32) }

    // #287: a long-loca font takes its glyph count from the transformed glyf
    // header, and a composite glyph's dropped lsb is its bbox xMin, so the
    // hmtx lsbs are -16 (composite) and -5 (simple).
    let long_loca = build_font(a, false)
    let (long_font, long_error) = woff2.to_sfnt(a, long_loca)
    if long_error != ok { os.exit(7i32) }
    let (hmtx_at, hmtx_len, hmtx_found) = table_of(long_font, 0x686D7478u32)
    if !hmtx_found || hmtx_len != 8usize { os.exit(7i32) }
    if get16(long_font, hmtx_at) != 500u32 || get16(long_font, hmtx_at + 2usize) != 65520u32 { os.exit(7i32) }
    if get16(long_font, hmtx_at + 4usize) != 600u32 || get16(long_font, hmtx_at + 6usize) != 65531u32 { os.exit(7i32) }

    // #287: a transform version on a table that has no transform is refused
    // instead of being emitted as transform bytes.
    let transformed_head = build_head_transform(a)
    let (_, transformed_head_error) = woff2.to_sfnt(a, transformed_head)
    if transformed_head_error != woff2.Invalid { os.exit(8i32) }

    // #287: glyf transformed while loca is not is a mismatched transform pair.
    let mismatched = build_font(a, true)
    let (_, mismatched_error) = woff2.to_sfnt(a, mismatched)
    if mismatched_error != woff2.Invalid { os.exit(9i32) }

    try io.print("fmt woff2 bounds ok\n")
    ret ok
}
