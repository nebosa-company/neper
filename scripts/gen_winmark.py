"""Generates lib/e/ui/winmark.e: the check box and radio button marks of the Windows look, baked pixel for
pixel from the live 100 % v3 captures (docs/ui/looks/ref/windows/states), as the button ring is.

  python -I scripts/gen_winmark.py

Each mark is a 14 x 14 window of the capture (the control's native box or disc, soft edges included). A pixel
the box shadows against the dialog (an anti-aliased outer pixel: a ray to the window's border meets
only background) is stored as the edge colour with the share it covers, so any background shows
through; every other pixel is stored opaque. A value is 0xAARRGGBB, alpha 0 meaning not painted.

The native theme bitmap is resampled with a sub-pixel phase that depends on where the control stands in its window
(looks5: measured on the Options pages, a check box at y 71 and at y 247 differ by up to 16 levels on their edge
rows, and the marks of every row in between are the straight blend of those two to within 1 level; the Filter
window's check boxes all share one phase). A family therefore holds two tables, A baked at the window y `ya` and B
at `yb`, and the mark is painted as A + (B - A) * (y - ya) / (yb - ya) for the y the sheet gives (a family with one
instance has B = A). Families are named by (context, kind); a context is one window's set of marks.
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATES = os.path.join(ROOT, "docs/ui/looks/ref/windows/states")

# kinds: 8 to 11 are the hover looks (check box off, on; radio off, on); 0 check box off rest, 1 off pressed, 2 on rest, 3 on pressed, 4 radio off rest, 5 off pressed, 6 on rest, 7 on pressed.
# contexts: 0 Options pages' check boxes, 1 Filter tab's check boxes, 2 Missing Set Cards' radios, 3 Search for Card's
# radio group, 4 Filter's Blocks / Formats / Editions row, 5 Filter's Match group, 6 Options Grids' radio groups,
# 7 Options Rules and Prices check lists, 8 Options Card Art check list.
P = "dialog-options-"
FAMILIES = {
    # (context, kind): (bg, (capture, x, y) of table A, (capture, x, y) of table B or None)
    (0, 0): (240, ("dialog-options-interface-rest@1x.png", 217, 78), ("dialog-options-grids-rest@1x.png", 226, 136)),
    (0, 1): (240, ("checkbox-pressed-options-hide-splash@1x.png", 217, 78), ("checkbox-pressed-options-show-filter-row@1x.png", 226, 136)),
    (0, 2): (240, ("dialog-options-morph-rest@1x.png", 217, 75), ("dialog-options-morph-rest@1x.png", 217, 251)),
    (0, 3): (240, ("checkbox-pressed-options-morph-use@1x.png", 217, 75), ("checkbox-pressed-options-show-tooltips@1x.png", 217, 159)),
    # hover (kinds 8 to 11: check box off, on, radio off, on): the pointer over a check box lightens or darkens its face;
    # over a radio there is no visible change (the captures are rest's, so a radio has no hover family but the Search
    # window's and Options groups' selected discs that the captures show differ by a level)
    (0, 8): (240, ("hover-checkbox-options-hide-splash@1x.png", 217, 78), ("hover-checkbox-options-show-filter-row@1x.png", 226, 136)),
    (0, 9): (240, ("hover-checkbox-options-morph-use@1x.png", 217, 75), ("hover-checkbox-options-card-preview-label@1x.png", 217, 132)),
    (1, 0): (249, ("tab-selected-filter-cards@1x.png", 55, 304), None),
    (2, 4): (240, ("dialog-missing-set-cards-rest@1x.png", 24, 398), ("dialog-missing-set-cards-rest@1x.png", 24, 422)),
    (2, 5): (240, ("radio-pressed-missing-set-cards-available@1x.png", 24, 398), None),
    (2, 6): (240, ("dialog-missing-set-cards-rest@1x.png", 24, 374), None),
    (3, 4): (240, ("dialog-search-rest@1x.png", 28, 176), None),
    (3, 5): (240, ("radio-pressed-search-collection@1x.png", 28, 176), None),
    (3, 6): (240, ("dialog-search-rest@1x.png", 28, 134), None),
    (3, 7): (240, ("radio-pressed-search-cards@1x.png", 28, 134), None),
    (4, 4): (249, ("dialog-filter-rest@1x.png", 109, 67), None),
    (4, 5): (249, ("radio-pressed-filter-formats@1x.png", 109, 67), None),
    (4, 6): (249, ("dialog-filter-rest@1x.png", 21, 67), None),
    (4, 7): (249, ("radio-pressed-filter-blocks@1x.png", 21, 67), None),
    (5, 4): (249, ("tab-selected-filter-cards@1x.png", 477, 352), ("tab-selected-filter-cards@1x.png", 477, 379)),
    (5, 6): (249, ("tab-selected-filter-cards@1x.png", 477, 325), None),
    (6, 4): (240, ("dialog-options-grids-rest@1x.png", 232, 268), ("dialog-options-grids-rest@1x.png", 232, 379)),
    (6, 5): (240, ("radio-pressed-options-search-within@1x.png", 232, 268), ("radio-pressed-options-move-next-row@1x.png", 232, 379)),
    (6, 6): (240, ("dialog-options-grids-rest@1x.png", 232, 226), ("dialog-options-grids-rest@1x.png", 232, 337)),
    (6, 7): (240, ("radio-pressed-options-search-from-start@1x.png", 232, 226), ("radio-focused-options-search-within@1x.png", 232, 268)),
    (7, 2): (255, ("dialog-options-rules-rest@1x.png", 218, 97), ("dialog-options-rules-rest@1x.png", 218, 352)),
    (8, 2): (255, ("dialog-options-cardart-rest@1x.png", 236, 75), ("dialog-options-cardart-rest@1x.png", 236, 93)),
}


def outer(px, bg, w, h, x, y):
    """True when a ray from (x, y) to a border of the window meets only background after it."""
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        cx, cy = x + dx, y + dy
        clear = True
        while 0 <= cx < w and 0 <= cy < h:
            if px[cx, cy] != bg:
                clear = False
                break
            cx += dx
            cy += dy
        if clear:
            return True
    return False


def bake(capture, x0, y0, bg_level, w=14, h=14):
    bg = (bg_level,) * 3
    im = Image.open(os.path.join(STATES, capture)).convert("RGB").crop((x0, y0, x0 + w, y0 + h))
    px = im.load()
    # the edge colour: the darkest pixel of the middle rows
    edge = min((px[x, y] for x in range(w) for y in range(h // 2 - 2, h // 2 + 2)), key=lambda c: sum(c))
    out = []
    for y in range(h):
        for x in range(w):
            v = px[x, y]
            if v == bg:
                out.append(0)
            elif outer(px, bg, w, h, x, y):
                num = sum((bg[i] - v[i]) * (bg[i] - edge[i]) for i in range(3))
                den = sum((bg[i] - edge[i]) ** 2 for i in range(3))
                share = max(0.0, min(1.0, num / den)) if den else 0.0
                a = int(round(share * 255))
                # looks5: keep the edge colour with its coverage only where that reproduces the capture's pixel to
                # within a level; a pixel whose hue is off that line (the halo of a blue disc) is stored as it is.
                back = [bg[i] + (edge[i] - bg[i]) * (a / 255.0) for i in range(3)]
                if a == 0 or max(abs(back[i] - v[i]) for i in range(3)) > 1.0:
                    out.append(0xFF000000 | (v[0] << 16) | (v[1] << 8) | v[2])
                else:
                    out.append((a << 24) | (edge[0] << 16) | (edge[1] << 8) | edge[2])
            else:
                out.append(0xFF000000 | (v[0] << 16) | (v[1] << 8) | v[2])
    return out


HEAD = """// The Windows look's check box and radio marks: v3's TcxCheckBox and TcxRadioButton as the native Windows 11
// theme draws them at 96 DPI, painted pixel for pixel from the live captures in docs/ui/looks/ref/windows/states
// (rest and pressed, unchecked and checked or unselected and selected). GENERATED by scripts/gen_winmark.py:
// edit the script, not this file. A value is 0xAARRGGBB, alpha 0 not painted; the edge pixels outside the
// shape carry the edge colour with their coverage so any dialog face shows through. Tables are 14 x 14.
// Kinds: 0 check box off rest, 1 off pressed, 2 on rest, 3 on pressed, 4 radio off rest, 5 off pressed,
// 6 on rest, 7 on pressed, 8 to 11 the hover looks (check box off, on, radio off, on). A family is (context * 16 + kind); a context is one window's set of marks (see the
// generator). The theme bitmap's sub-pixel phase follows the control's y in its window: a family holds a table A
// baked at window y `ya` and a table B at `yb`, painted as their blend for the y asked.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.winpx
use e.ui.widget
"""

TAIL = """
// The family to paint for (context, kind): the context's own when it has one, else the default context of the shape
// (0 for a check box; for a radio 3 for the pressed disc, 2 for the others). A hover (kinds 8 to 11) with no capture of
// its own is the rest look.
fn mark_resolve(context: u32, kind: u32) -> u32 {
    let own = context * 16u32 + kind
    if mark_has(own) { ret own }
    var base = kind
    if kind >= 8u32 { base = (kind - 8u32) * 2u32 }
    let rest = context * 16u32 + base
    if mark_has(rest) { ret rest }
    if base < 4u32 { ret base }
    if base == 7u32 { ret 3u32 * 16u32 + 7u32 }
    ret 2u32 * 16u32 + base
}

// The mark's width in px (14 for a check box, 13 for a radio) and its height.
fn mark_width(kind: u32) -> f32 {
    if (kind >= 4u32 && kind < 8u32) || kind >= 10u32 { ret 13.0 }
    ret 14.0
}

fn mark_height() -> f32 { ret 14.0 }

// `y` is the control's y in its window (negative: the family's table A).
type Mark = struct { id: u32, y: f32 }

fn mark_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// The coverage of pixel `i` of the blend of tables `ta` and `tb` at weight `w` (0 is A, 1 is B).
fn mark_alpha(ta: []const u32, tb: []const u32, w: f32, i: usize) -> f32 {
    let a = f32(ta[i] >> 24u32) / 255.0
    let b = f32(tb[i] >> 24u32) / 255.0
    ret a + (b - a) * w
}

fn mark_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let d = mem.cast[*Mark](ctx)
    let table_a = mark_a(d.id)
    let table_b = mark_b(d.id)
    let ta = table_a[0usize..196usize]
    let tb = table_b[0usize..196usize]
    let ya = mark_ya(d.id)
    let yb = mark_yb(d.id)
    var w: f32 = 0.0
    if d.y >= 0.0 && yb != ya {
        w = (d.y - ya) / (yb - ya)
        if w < -0.7 { w = -0.7 }
        if w > 1.7 { w = 1.7 }
    }
    let across = 14usize
    let legacy = scene.builder_scale(b) == 1.0
    // On whole pixels: a mark centred in a cell would otherwise straddle two rows and columns.
    let ox = f32(i32(area.x + 0.5))
    let oy = f32(i32(area.y + 0.5))
    var i = 0usize
    while i < 196usize {
        let alpha = mark_alpha(ta, tb, w, i)
        if alpha > 0.002 {
            let va = ta[i]
            let vb = tb[i]
            let wa = f32(va >> 24u32) / 255.0
            let wb = f32(vb >> 24u32) / 255.0
            // Premultiplied blend, so a pixel only one table paints keeps that table's colour.
            let r = (f32((va >> 16u32) & 255u32) * wa * (1.0 - w) + f32((vb >> 16u32) & 255u32) * wb * w) / alpha / 255.0
            let g = (f32((va >> 8u32) & 255u32) * wa * (1.0 - w) + f32((vb >> 8u32) & 255u32) * wb * w) / alpha / 255.0
            let bl = (f32(va & 255u32) * wa * (1.0 - w) + f32(vb & 255u32) * wb * w) / alpha / 255.0
            var cap = alpha
            if cap > 1.0 { cap = 1.0 }
            let c = paint.rgba(clamp_unit(r), clamp_unit(g), clamp_unit(bl), cap)
            // An opaque pixel reaches 0.5 under its opaque right and lower neighbours so that a scaled render shows no seams.
            var wide: f32 = 1.0
            var high: f32 = 1.0
            // At any other scale `winpx.fill` puts every pixel on whole device pixels, so no overlap is needed.
            if legacy && alpha > 0.996 {
                if i % across + 1usize < across && mark_alpha(ta, tb, w, i + 1usize) > 0.996 { wide = 1.5 }
                if i + across < 196usize && mark_alpha(ta, tb, w, i + across) > 0.996 { high = 1.5 }
            }
            try winpx.fill(b, ox + f32(i % across), oy + f32(i / across), wide, high, c)
        }
        i += 1usize
    }
    ret ok
}

fn clamp_unit(v: f32) -> f32 {
    if v < 0.0 { ret 0.0 }
    if v > 1.0 { ret 1.0 }
    ret v
}

// The mark of (`context`, `kind`) as a node of its own size, for a control `y` px down its window (negative: unknown).
fn mark_node(a: *mem.Arena, context: u32, kind: u32, y: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = Mark { id: mark_resolve(context, kind), y: y }
    var s = style.defaults()
    s.width = style.Length { Px: mark_width(kind) }
    s.height = style.Length { Px: mark_height() }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: s, children: none }, ok)
}
"""


def main():
    lines = []
    names = {}
    ids = sorted(FAMILIES)
    for (ctx, kind) in ids:
        bg, a, b = FAMILIES[(ctx, kind)]
        for tag, inst in (("a", a), ("b", b if b else a)):
            cap, x, y = inst
            table = bake(cap, x, y, bg)
            body = ", ".join("0x%08Xu32" % v for v in table)
            lines.append("// context %d kind %d table %s: %s at (%d, %d), bg %d\nfn mark_%d_%d_%s() -> [196]u32 { ret [196]u32{ %s } }" % (
                ctx, kind, tag.upper(), cap, x, y, bg, ctx, kind, tag, body))
    disp = []
    has = []
    for tag in ("a", "b"):
        disp.append("fn mark_%s(id: u32) -> [196]u32 {" % tag)
        for (ctx, kind) in ids:
            disp.append("    if id == %du32 { ret mark_%d_%d_%s() }" % (ctx * 16 + kind, ctx, kind, tag))
        disp.append("    ret mark_0_0_a()\n}\n")
    for tag, idx in (("ya", 1), ("yb", 2)):
        disp.append("fn mark_%s(id: u32) -> f32 {" % tag)
        for (ctx, kind) in ids:
            bg, a, b = FAMILIES[(ctx, kind)]
            inst = a if idx == 1 else (b if b else a)
            disp.append("    if id == %du32 { ret %d.0 }" % (ctx * 16 + kind, inst[2]))
        disp.append("    ret 0.0\n}\n")
    disp.append("fn mark_has(id: u32) -> bool {")
    for (ctx, kind) in ids:
        disp.append("    if id == %du32 { ret true }" % (ctx * 16 + kind))
    disp.append("    ret false\n}\n")
    out = HEAD + "\n" + "\n".join(lines) + "\n\n" + "\n".join(disp) + TAIL
    with open(os.path.join(ROOT, "lib/e/ui/winmark.e"), "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("wrote lib/e/ui/winmark.e (%d families)" % len(ids))


if __name__ == "__main__":
    main()
