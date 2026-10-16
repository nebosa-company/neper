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

// round 11: the width of `scalar` at `ppem` as the linear advance rounded to a whole pixel (hmtx x ppem / unitsPerEm), which is how the
// grid header hint of v3 (Tahoma 11 px) is spaced in the capture: its 'i', 'l' and 'm' are 3, 3 and 9 wide where hdmx lists 2, 2 and 8.
fn advance_linear(font: shape.Font, ppem: u32, scalar: u32) -> (u32, bool) {
    let (hmtx, has_hmtx) = shape.find_table(font, shape.TAG_HMTX)
    let (head, has_head) = shape.find_table(font, shape.TAG_HEAD)
    let (hhea, has_hhea) = shape.find_table(font, shape.TAG_HHEA)
    let (cmap, has_cmap) = shape.find_table(font, tag_cmap())
    if !has_hmtx || !has_head || !has_hhea || !has_cmap { ret (0u32, false) }
    let d = font.data
    let (sub, has_sub) = shape.cmap_subtable(d, cmap)
    if !has_sub { ret (0u32, false) }
    let gid = shape.glyph_of(d, sub, scalar)
    if gid == 0u32 { ret (0u32, false) }
    let metrics = usize(shape.u16_at(d, hhea.at + 34usize))
    var row = usize(gid)
    if row >= metrics && metrics > 0usize { row = metrics - 1usize }
    let units = shape.u16_at(d, head.at + 18usize)
    if units == 0u32 { ret (0u32, false) }
    let adv = shape.u16_at(d, hmtx.at + 4usize * row)
    ret ((adv * ppem + units / 2u32) / units, true)
}
