// Whole pixel glyph advances, as v3 draws its text. v3 runs on GDI, which advances every glyph by the font's hinted
// width: the `hdmx` (horizontal device metrics) table of Tahoma and Segoe UI lists it for each pixel size. A run set with
// the unhinted `hmtx` advances (what the shaper uses) is a few pixels wider over a sentence ("Send email to Support"
// at 11 px: 107 against v3's 105, the sum of the hdmx widths). `advance` answers the hdmx width of one character.

use e.text.shape

fn tag_hdmx() -> u32 { ret 0x68646D78u32 }
fn tag_cmap() -> u32 { ret 0x636D6170u32 }

// The width in pixels of `scalar` at `ppem` in `font`, and whether the font has an hdmx record for that size and the
// character is in it.
fn advance(font: shape.Font, ppem: u32, scalar: u32) -> (u32, bool) {
    let (hdmx, has_hdmx) = shape.find_table(font, tag_hdmx())
    if !has_hdmx || hdmx.len < 8usize { ret (0u32, false) }
    let (cmap, has_cmap) = shape.find_table(font, tag_cmap())
    if !has_cmap { ret (0u32, false) }
    let d = font.data
    let (sub, has_sub) = shape.cmap_subtable(d, cmap)
    if !has_sub { ret (0u32, false) }
    let gid = shape.glyph_of(d, sub, scalar)
    if gid == 0u32 { ret (0u32, false) }
    let records = usize(shape.u16_at(d, hdmx.at + 2usize))
    let size = usize(shape.u32_at(d, hdmx.at + 4usize))
    var r = 0usize
    while r < records {
        let at = hdmx.at + 8usize + size * r
        if at + 2usize + usize(gid) >= d.len { ret (0u32, false) }
        if u32(d[at]) == ppem { ret (u32(d[at + 2usize + usize(gid)]), true) }
        r += 1usize
    }
    ret (0u32, false)
}
