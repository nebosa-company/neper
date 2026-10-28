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

    try io.print("fmt woff2 bounds ok\n")
    ret ok
}
