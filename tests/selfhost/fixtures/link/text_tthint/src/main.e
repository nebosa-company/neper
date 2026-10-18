// `e.text.tthint` and `e.gfx.cleartype`: Segoe UI at 12 px hinted in both modes and drawn in ClearType, against the values
// the Python reference interpreter gave for the same font (a fixture-local copy of the font is never made: the font is read
// from the Windows font directory and the whole check passes when it is not there). The outline checksums cover every point of
// the nine glyphs "labelmoRS" and their advances; the image checksum covers the 36 x 83 pixels of "Sample label" in black on
// white after the gamma blend. Each check exits with its own code.

use e.fs
use e.gfx.cleartype
use e.mem
use e.text.shape
use e.text.tthint
use e.text.ttglyph

fn font_path() -> str { ret "C:/Windows/Fonts/segoeui.ttf" }

fn glyph_sum(h: *tthint.Hinter, a: *mem.Arena, bytes: []const u8, sub: usize, text: str, cleartype_mode: bool) -> i64 {
    var sum = 0i64
    var at = 0i64
    var k = 0usize
    while k < text.len {
        let gid = shape.glyph_of(bytes, sub, u32(text[k]))
        let (out, hint_error) = ttglyph.hint_glyph(h, a, 12i64, gid, cleartype_mode)
        if hint_error != ok { ret -1i64 }
        sum += (at % 251i64 + 1i64) * (i64(gid) & 65535i64)
        at += 1i64
        sum += (at % 251i64 + 1i64) * (i64(out.n) & 65535i64)
        at += 1i64
        sum += (at % 251i64 + 1i64) * (out.adv & 65535i64)
        at += 1i64
        sum += (at % 251i64 + 1i64) * (out.pp1x & 65535i64)
        at += 1i64
        var i = 0usize
        while i < out.n {
            sum += (at % 251i64 + 1i64) * (i64(i) & 65535i64)
            at += 1i64
            sum += (at % 251i64 + 1i64) * (out.cur[2usize * i] & 65535i64)
            at += 1i64
            sum += (at % 251i64 + 1i64) * (out.cur[2usize * i + 1usize] & 65535i64)
            at += 1i64
            i += 1usize
        }
        k += 1usize
    }
    ret sum
}

fn image_sum(h: *tthint.Hinter, a: *mem.Arena, bytes: []const u8, sub: usize, text: str) -> i64 {
    let (sc, sc_error) = cleartype.scratch(a)
    if sc_error != ok { ret -1i64 }
    var width = 16usize
    var k = 0usize
    while k < text.len {
        let gid = shape.glyph_of(bytes, sub, u32(text[k]))
        let (bw, bw_error) = ttglyph.hint_glyph(h, a, 12i64, gid, false)
        if bw_error != ok { ret -1i64 }
        width += usize(bw.adv / 64i64)
        k += 1usize
    }
    if !cleartype.begin(sc, 0i64, 0i64, width, 36usize) { ret -1i64 }
    var pen = 4i64
    k = 0usize
    while k < text.len {
        let gid = shape.glyph_of(bytes, sub, u32(text[k]))
        let (bw, bw_error) = ttglyph.hint_glyph(h, a, 12i64, gid, false)
        if bw_error != ok { ret -1i64 }
        let (out, hint_error) = ttglyph.hint_glyph(h, a, 12i64, gid, true)
        if hint_error != ok { ret -1i64 }
        if !cleartype.add_glyph(sc, &out, pen, 24i64) { ret -1i64 }
        pen += bw.adv / 64i64
        k += 1usize
    }
    var sum = 0i64
    var at = 0i64
    var y = 0usize
    while y < 36usize {
        var x = 0usize
        while x < width {
            var c = 0usize
            while c < 3usize {
                let v = cleartype.blend(1.0, 0.0, cleartype.coverage(sc, i64(x), i64(y), c))
                sum += (at % 251i64 + 1i64) * (i64(v * 255.0 + 0.5) & 65535i64)
                at += 1i64
                c += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (bytes, read_error) = fs.read_file(a, font_path(), 16777216usize)
    if read_error != ok { ret ok }
    let (h, open_error) = tthint.open(a, bytes)
    if open_error != ok { ret open_error }
    let font = shape.Font { id: 1u32, data: bytes, face_index: 0u32 }
    let (cmap, has_cmap) = shape.find_table(font, shape.TAG_CMAP)
    if !has_cmap { ret tthint.Unsupported }
    let (sub, has_sub) = shape.cmap_subtable(bytes, cmap)
    if !has_sub { ret tthint.Unsupported }
    // 'l' is a stem 62..132 wide and 576 tall in ClearType, three pixels advance.
    let lg = shape.glyph_of(bytes, sub, 108u32)
    let (l, l_error) = ttglyph.hint_glyph(h, a, 12i64, lg, true)
    if l_error != ok || l.n != 4usize || l.adv != 192i64 { ret tthint.Trap }
    if l.cur[0usize] != 132i64 || l.cur[2usize] != 62i64 || l.cur[5usize] != 576i64 { ret tthint.Trap }
    if glyph_sum(h, a, bytes, sub, "labelmoRS", true) != 15469979i64 { ret tthint.Trap }
    if glyph_sum(h, a, bytes, sub, "labelmoRS", false) != 15505486i64 { ret tthint.Trap }
    if image_sum(h, a, bytes, sub, "Sample label") != 272076851i64 { ret tthint.Trap }
    ret ok
}
