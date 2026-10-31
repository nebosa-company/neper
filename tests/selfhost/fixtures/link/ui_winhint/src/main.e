// hdmx records must end inside their declared table. The four bytes after the
// short hdmx below look like a valid record, but belong to another table.
use e.os
use e.text.shape
use e.ui.winhint

type Builder = struct { bytes: []u8, at: usize }

fn w8(b: *Builder, value: u32) {
    b.bytes[b.at] = u8(value & 255u32)
    b.at += 1usize
}

fn w16(b: *Builder, value: u32) {
    w8(b, value >> 8u32)
    w8(b, value)
}

fn w32(b: *Builder, value: u32) {
    w16(b, value >> 16u32)
    w16(b, value & 65535u32)
}

fn patch32(b: *Builder, at: usize, value: u32) {
    b.bytes[at] = u8((value >> 24u32) & 255u32)
    b.bytes[at + 1usize] = u8((value >> 16u32) & 255u32)
    b.bytes[at + 2usize] = u8((value >> 8u32) & 255u32)
    b.bytes[at + 3usize] = u8(value & 255u32)
}

fn table(b: *Builder, slot: usize, tag: u32, at: usize, length: usize) {
    let record = 12usize + 16usize * slot
    patch32(b, record, tag)
    patch32(b, record + 8usize, u32(at))
    patch32(b, record + 12usize, u32(length))
}

fn main() {
    var raw: [128]u8 = zero
    var b = Builder { bytes: raw[0..], at: 0usize }
    // Offset table plus three directory slots.
    w32(&b, 65536u32)
    w16(&b, 3u32)
    w16(&b, 0u32)
    w16(&b, 0u32)
    w16(&b, 0u32)
    while b.at < 60usize { w8(&b, 0u32) }

    let hdmx_at = b.at
    w16(&b, 0u32)
    w16(&b, 1u32)
    w32(&b, 4u32)

    // If read as a record, this says ppem 12 and glyph 1 width 9. It is a
    // separate four-byte table after the declared eight-byte hdmx table.
    let other_at = b.at
    w8(&b, 12u32)
    w8(&b, 0u32)
    w8(&b, 0u32)
    w8(&b, 9u32)

    // A minimal cmap format 4 mapping U+0041 to glyph 1.
    let cmap_at = b.at
    w16(&b, 0u32)
    w16(&b, 1u32)
    w16(&b, 3u32)
    w16(&b, 1u32)
    w32(&b, 12u32)
    w16(&b, 4u32)
    w16(&b, 32u32)
    w16(&b, 0u32)
    w16(&b, 4u32)
    w16(&b, 4u32)
    w16(&b, 1u32)
    w16(&b, 0u32)
    w16(&b, 65u32)
    w16(&b, 65535u32)
    w16(&b, 0u32)
    w16(&b, 65u32)
    w16(&b, 65535u32)
    w16(&b, 65472u32)
    w16(&b, 1u32)
    w16(&b, 0u32)
    w16(&b, 0u32)

    table(&b, 0usize, 0x68646D78u32, hdmx_at, 8usize)
    table(&b, 1usize, 0x6F746872u32, other_at, 4usize)
    table(&b, 2usize, 0x636D6170u32, cmap_at, b.at - cmap_at)
    let font = shape.Font { id: 1u32, data: raw[0..b.at], face_index: 0u32 }
    let (width, has_width) = winhint.advance(font, 12u32, 65u32)
    if has_width || width != 0u32 { os.exit(1) }
    os.exit(0)
}
