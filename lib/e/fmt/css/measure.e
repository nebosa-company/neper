// The glue between a CSS layout and a font set (tracker 3.16): `e.fmt.css.layout` asks a `Measure` for the advance of
// a string, the font metrics of a style and the intrinsic size of replaced content; `e.fmt.css.paint` asks a
// `PaintEnv` for shaped text and images. `Host` answers the first two from an `e.text.fontset` by the style's
// `font-family`, `font-weight`, `font-style` and `font-size`, and leaves images to callbacks the host application
// supplies (it owns the decoders and the network).
//
// Memory: shaped runs for painting are allocated in `Host.arena` and stay until the arena is reset; measuring
// allocates nothing that survives.

use e.fmt.css.layout as layout
use e.fmt.css.paint as paint
use e.fmt.css.style as style
use e.fmt.html as html
use e.mem
use e.text.fontset as fontset
use e.text.layout as tl

type Host = struct {
    fonts: *fontset.Set, arena: *mem.Arena, ctx: *void,
    intrinsic: fn(*void, html.NodeId) -> layout.Intrinsic,
    image: fn(*void, html.NodeId) -> paint.ImageRef
}

fn is_italic(s: *const style.Style) -> bool { ret s.font_style != .Normal }

fn text_width(ctx: *void, s: *const style.Style, text: str) -> f64 {
    let h = mem.cast[*Host](ctx)
    ret fontset.width(h.fonts, s.font_family, s.font_weight, is_italic(s), s.font_size, text)
}

fn font_metrics(ctx: *void, s: *const style.Style) -> layout.FontMetrics {
    let h = mem.cast[*Host](ctx)
    let m = fontset.metrics(h.fonts, s.font_family, s.font_weight, is_italic(s), s.font_size)
    ret layout.FontMetrics { ascent: m.ascent, descent: m.descent, line_gap: m.line_gap, x_height: m.x_height }
}

fn intrinsic_of(ctx: *void, node: html.NodeId) -> layout.Intrinsic {
    let h = mem.cast[*Host](ctx)
    ret h.intrinsic(h.ctx, node)
}

// The `Measure` for `layout.layout_document`; `h` must outlive the layout.
fn measure_of(h: *Host) -> layout.Measure {
    ret layout.Measure { ctx: mem.cast[*void](h), width: text_width, metrics: font_metrics, intrinsic: intrinsic_of }
}

fn paint_text(ctx: *void, s: *const style.Style, text: str) -> *const tl.Layout {
    let h = mem.cast[*Host](ctx)
    let (lay, e) = fontset.layout_run(h.fonts, h.arena, s.font_family, s.font_weight, is_italic(s), s.font_size, text)
    if e != ok { ret zero }
    ret lay
}

fn paint_image(ctx: *void, node: html.NodeId) -> paint.ImageRef {
    let h = mem.cast[*Host](ctx)
    ret h.image(h.ctx, node)
}

// The `PaintEnv` for `paint.paint`; `h` must outlive the painting (and the scene compile that copies the layouts).
fn paint_env_of(h: *Host) -> paint.PaintEnv {
    ret paint.PaintEnv { ctx: mem.cast[*void](h), text: paint_text, image: paint_image }
}
