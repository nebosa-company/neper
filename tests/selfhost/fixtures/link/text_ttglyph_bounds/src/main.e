// Malformed glyf records must be rejected before ttglyph reads beyond their
// glyph range. The fixture shortens real Segoe UI glyph records in-place so
// both simple coordinate data and composite component arguments are truncated.

use e.fs
use e.io
use e.mem
use e.os
use e.text.tthint
use e.text.ttglyph

fn font_path() -> str { ret "C:/Windows/Fonts/segoeui.ttf" }

fn put_u16(bytes: []u8, at: usize, value: usize) {
    bytes[at] = u8(value / 256usize)
    bytes[at + 1usize] = u8(value % 256usize)
}

fn put_u32(bytes: []u8, at: usize, value: usize) {
    bytes[at] = u8(value / 16777216usize)
    bytes[at + 1usize] = u8((value / 65536usize) % 256usize)
    bytes[at + 2usize] = u8((value / 256usize) % 256usize)
    bytes[at + 3usize] = u8(value % 256usize)
}

fn glyph_start(h: *tthint.Hinter, gid: usize) -> usize {
    if h.long_loca { ret usize(tthint.rd32(h.data, h.loca + 4usize * gid)) }
    ret 2usize * usize(tthint.rd16(h.data, h.loca + 2usize * gid))
}

fn glyph_end(h: *tthint.Hinter, gid: usize) -> usize {
    if h.long_loca { ret usize(tthint.rd32(h.data, h.loca + 4usize * gid + 4usize)) }
    ret 2usize * usize(tthint.rd16(h.data, h.loca + 2usize * gid + 2usize))
}

fn set_glyph_end(bytes: []u8, h: *tthint.Hinter, gid: usize, relative: usize) {
    if h.long_loca {
        put_u32(bytes, h.loca + 4usize * gid + 4usize, relative)
    } else {
        put_u16(bytes, h.loca + 2usize * gid + 2usize, relative / 2usize)
    }
}

fn find_kind(h: *tthint.Hinter, composite: bool) -> (usize, bool) {
    var gid = 0usize
    while gid < h.glyph_count {
        let start = glyph_start(h, gid)
        let end = glyph_end(h, gid)
        if end > start && end - start > 14usize {
            let contours = tthint.rds16(h.data, h.glyf + start)
            if (composite && contours < 0i64) || (!composite && contours > 0i64) { ret (gid, true) }
        }
        gid += 1usize
    }
    ret (0usize, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (bytes, read_error) = fs.read_file(a, font_path(), 16777216usize)
    if read_error != ok {
        try io.print("skipped: the font is not present\n")
        ret ok
    }
    let (h, open_error) = tthint.open(a, bytes)
    if open_error != ok { ret open_error }
    let (simple_gid, has_simple) = find_kind(h, false)
    let (composite_gid, has_composite) = find_kind(h, true)
    if !has_simple || !has_composite {
        try io.print("skipped: the font has no test glyphs\n")
        ret ok
    }

    let simple_start = glyph_start(h, simple_gid)
    let simple_end = glyph_end(h, simple_gid)
    set_glyph_end(bytes, h, simple_gid, simple_start + 10usize)
    let (_, simple_error) = ttglyph.hint_glyph(h, a, 12i64, u32(simple_gid), false)
    if simple_error == ok { ret tthint.Trap }
    set_glyph_end(bytes, h, simple_gid, simple_end)

    let composite_start = glyph_start(h, composite_gid)
    let composite_end = glyph_end(h, composite_gid)
    set_glyph_end(bytes, h, composite_gid, composite_start + 14usize)
    let (_, composite_error) = ttglyph.hint_glyph(h, a, 12i64, u32(composite_gid), false)
    if composite_error == ok { ret tthint.Trap }
    set_glyph_end(bytes, h, composite_gid, composite_end)

    try io.print("ttglyph bounds ok\n")
    ret ok
}
