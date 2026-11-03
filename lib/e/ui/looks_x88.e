// Round 88, lane x: the Windows dialog bodies. dialog.e calls `body` with the id of a skin baked by scripts/gen_x88.py (lib/e/ui/windlg88.e):
// the chrome of v3's DevExpress controls as one run length coded tile (mapped by the dark look), its pictures (raw colours) and its labels
// (live text at the captured ink positions). Buttons, radios, check boxes and group boxes of a body are the live controls of dialog.e.

use e.mem
use e.gfx.paint
use e.ui.control
use e.ui.gridlook as gl
use e.ui.style
use e.ui.widget
use e.ui.windlg88 as skins

error TooLarge

fn hexval(c: u8) -> usize {
    if c >= 65u8 { ret usize(c - 55u8) }
    ret usize(c - 48u8)
}

// The skin `rle` (eight digits a run) as `w` x `h` pixels of six digits.
fn decode(a: *mem.Arena, rle: str, w: usize, h: usize) -> (str, err) {
    let (buf, buf_error) = mem.alloc[u8](a, w * h * 6usize)
    if buf_error != ok { ret ("", TooLarge) }
    var pos = 0usize
    var i = 0usize
    while i + 8usize <= rle.len && pos < w * h {
        let run = hexval(rle[i + 6usize]) * 16usize + hexval(rle[i + 7usize]) + 1usize
        var r = 0usize
        while r < run && pos < w * h {
            var d = 0usize
            while d < 6usize {
                buf[pos * 6usize + d] = rle[i + d]
                d += 1usize
            }
            pos += 1usize
            r += 1usize
        }
        i += 8usize
    }
    ret (buf[0usize..w * h * 6usize], ok)
}

fn one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn at(a: *mem.Arena, x: f32, y: f32, node: widget.Node) -> widget.Node {
    ret widget.positioned(0u64, x, y, style.defaults(), one(a, node))
}

// The label origin lies this far above and left of the ink box of its first glyph (Tahoma 11 and Segoe UI 12; measured, scripts/x88_adj.json corrects the rest)
fn ink_dy(face: u32, size: u32) -> f32 {
    ret 3.0 + f32(size) - 11.0
}

// Windows Dark: a dark ink of the capture (black text, v3's red and purple names) is lifted to read on the #202020 panels: grey inks to #E8E8E8, coloured
// inks toward white until their luma is 0.72 (the names keep their hue; 6 to 9 : 1)
fn dark_ink(v: u32) -> u32 {
    let r = f32((v >> 16u32) & 255u32)
    let g = f32((v >> 8u32) & 255u32)
    let b = f32(v & 255u32)
    let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    if luma >= 0.72 { ret v }
    var hi = r
    var lo = r
    if g > hi { hi = g }
    if b > hi { hi = b }
    if g < lo { lo = g }
    if b < lo { lo = b }
    if hi - lo < 40.0 {
        if luma < 0.5 { ret 0xE8E8E8u32 }
        ret v
    }
    let t = (0.72 - luma) / (1.0 - luma)
    let nr = u32(r + (255.0 - r) * t)
    let ng = u32(g + (255.0 - g) * t)
    let nb = u32(b + (255.0 - b) * t)
    ret (nr << 16u32) | (ng << 8u32) | nb
}

fn body(a: *mem.Arena, t: *const control.Theme, id: usize) -> (widget.Node, err) {
    let w = skins.skin_w(id)
    let h = skins.skin_h(id)
    let (skin_pix, skin_error) = decode(a, skins.skin(id), w, h)
    if skin_error != ok { ret (zero, skin_error) }
    let (skin_node, skin_node_error) = gl.pixels(a, skin_pix, f32(w), f32(h))
    if skin_node_error != ok { ret (zero, skin_node_error) }
    let pics = skins.pic_count(id)
    let labels = skins.label_count(id)
    let (parts, parts_error) = mem.alloc[widget.Node](a, pics + labels + 1usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = at(a, 0.0, 31.0, skin_node)
    var n = 1usize
    var k = 0usize
    while k < pics {
        let pw = usize(skins.pic_w(id, k))
        let ph = usize(skins.pic_h(id, k))
        let (pic_pix, pic_error) = decode(a, skins.pic(id, k), pw, ph)
        if pic_error != ok { ret (zero, pic_error) }
        let (pic_node, pic_node_error) = gl.pixels_raw(a, pic_pix, f32(pw), f32(ph))
        if pic_node_error != ok { ret (zero, pic_node_error) }
        parts[n] = at(a, skins.pic_x(id, k), skins.pic_y(id, k), pic_node)
        n += 1usize
        k += 1usize
    }
    k = 0usize
    while k < labels {
        let face = skins.label_face(id, k)
        var ink_value = skins.label_ink(id, k)
        if style.windows_dark_on() { ink_value = dark_ink(ink_value) }
        let ink = style.hex_raw(ink_value)
        let (label, label_error) = control.windows_label_faced(a, t, skins.label_text(id, k), f32(skins.label_size(id, k)), skins.label_weight(id, k), ink, skins.label_underline(id, k) == 1u32, 0.0, face, 0.0, 0.0, false)
        if label_error != ok { ret (zero, label_error) }
        // the Dark Segoe label is the native static (no inset, one row up, see control.windows_label_faced): put back where the Light one stands
        var shift_x: f32 = 0.0
        var shift_y: f32 = 0.0
        if style.windows_dark_on() && face == 7u32 {
            shift_x = 2.0
            shift_y = 1.0
        }
        parts[n] = at(a, skins.label_x(id, k) + shift_x, skins.label_y(id, k) - ink_dy(face, skins.label_size(id, k)) + shift_y, label)
        n += 1usize
        k += 1usize
    }
    ret (widget.stack(0u64, control.sized_style(f32(w), f32(h + 31usize)), parts[0usize..n]), ok)
}
