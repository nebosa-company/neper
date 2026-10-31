// CFF/SFNT offsets are untrusted font bytes.  A broken INDEX must be rejected
// by the CFF parser rather than indexing past the caller's font buffer.

use e.io
use e.mem
use e.os
use e.fs
use e.text.cffhint

fn put_u32(bytes: []u8, at: usize, value: usize) {
    bytes[at] = u8(value / 16777216usize)
    bytes[at + 1usize] = u8((value / 65536usize) % 256usize)
    bytes[at + 2usize] = u8((value / 256usize) % 256usize)
    bytes[at + 3usize] = u8(value % 256usize)
}

fn tag(bytes: []u8, at: usize, value: usize) {
    put_u32(bytes, at, value)
}

fn malformed_index() -> bool {
    var bytes: [200]u8 = zero
    bytes[4usize] = 0u8
    bytes[5usize] = 3u8
    // CFF table: offset 160, length 40.
    tag(bytes[..], 12usize, 1128678944usize)
    put_u32(bytes[..], 20usize, 160usize)
    put_u32(bytes[..], 24usize, 40usize)
    // head table: offset 64, length 54, unitsPerEm 1000.
    tag(bytes[..], 28usize, 1751474532usize)
    put_u32(bytes[..], 36usize, 64usize)
    put_u32(bytes[..], 40usize, 54usize)
    bytes[82usize] = 3u8
    bytes[83usize] = 232u8
    // maxp table: offset 120, length 6, one glyph.
    tag(bytes[..], 44usize, 1835104368usize)
    put_u32(bytes[..], 52usize, 120usize)
    put_u32(bytes[..], 56usize, 6usize)
    bytes[124usize] = 0u8
    bytes[125usize] = 1u8
    // CFF header followed by an INDEX whose count is huge for this buffer.
    bytes[160usize] = 1u8
    bytes[162usize] = 4u8
    bytes[164usize] = 255u8
    bytes[165usize] = 255u8
    bytes[166usize] = 4u8
    var c: cffhint.Cff = zero
    ret !cffhint.open(&c, bytes[..])
}

fn malformed_table_offset() -> bool {
    var bytes: [32]u8 = zero
    bytes[4usize] = 0u8
    bytes[5usize] = 1u8
    tag(bytes[..], 12usize, 1128678944usize)
    put_u32(bytes[..], 20usize, 4294967295usize)
    put_u32(bytes[..], 24usize, 32usize)
    var c: cffhint.Cff = zero
    ret !cffhint.open(&c, bytes[..])
}

fn one_based_index_endpoint() -> bool {
    var bytes: [10]u8 = zero
    bytes[1usize] = 1u8
    bytes[2usize] = 1u8
    bytes[3usize] = 1u8
    bytes[4usize] = 6u8
    let (size, size_ok) = cffhint.index_size(bytes[..], 0usize, 10usize)
    if !size_ok || size != 10usize { ret false }
    let (start, end, range_ok) = cffhint.index_range(bytes[..], 0usize, 0usize, 10usize)
    if !range_ok || start != 5usize || end != 10usize { ret false }
    let (_, rejected, limited_ok) = cffhint.index_range(bytes[..], 0usize, 0usize, 9usize)
    if limited_ok || rejected != 0usize { ret false }
    let (empty_size, empty_ok) = cffhint.index_size(bytes[..], 8usize, 10usize)
    if !empty_ok || empty_size != 2usize { ret false }
    ret true
}

fn malformed_real() -> bool {
    var bytes: [2]u8 = zero
    bytes[0usize] = 30u8
    bytes[1usize] = 18u8
    let (_, used, _) = cffhint.dict_operand(bytes[..], 0usize, 2usize)
    ret used == 0usize
}

fn actual_cff_font(a: *mem.Arena) -> bool {
    let (data, read_error) = fs.read_file(a, "docs/ui/looks/ref/linux/fonts/Cantarell-Regular.otf", 16777216usize)
    if read_error != ok { ret false }
    var c: cffhint.Cff = zero
    ret cffhint.open(&c, data)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !malformed_index() { os.exit(1i32) }
    if !malformed_table_offset() { os.exit(2i32) }
    if !one_based_index_endpoint() { os.exit(3i32) }
    if !malformed_real() { os.exit(4i32) }
    if !actual_cff_font(a) { os.exit(5i32) }
    try io.print("cffhint bounds ok\n")
    ret ok
}
