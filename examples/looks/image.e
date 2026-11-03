// Round 62 c: the image in all ten looks: the sample picture (looks_c, a drawn landscape of 96 by 64 standing in for a
// photograph) fitted three ways into a 120 by 80 frame (contain, cover, fill), unscaled, with rounded corners, with a
// border. Derived from the shared tokens, no platform capture. Run from the repository root.

use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_c
use e.ui.style
use e.ui.widget

fn framed(a: *mem.Arena, key: u64, t: *const control.Theme, picture: scene.TextureId, fit: widget.Fit, w: f32, h: f32, rounded: bool, bordered: bool) -> (widget.Node, err) {
    let (photo, photo_error) = control.image(a, key + 1u64, picture, w, h, fit, "Picture")
    if photo_error != ok { ret (zero, photo_error) }
    let (kids, kids_error) = mem.alloc[widget.Node](a, 1usize)
    if kids_error != ok { ret (zero, kids_error) }
    kids[0usize] = photo
    var frame = style.defaults()
    frame.width = style.Length { Px: w }
    frame.height = style.Length { Px: h }
    frame.background = paint_ground(t)
    if rounded {
        frame.radius = t.tokens.radii.md
        frame.overflow = .Clip
    }
    if bordered { frame.border = style.Border { width: 1.0, color: style.color(t.tokens, .Outline) } }
    if bordered && t.tokens.profile == .MaterialLike {
        // Android: the outline is drawn over the picture (it sat under it and never showed).
        frame.border = style.Border { width: 0.0, color: style.color(t.tokens, .Outline) }
        let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
        if layers_error != ok { ret (zero, layers_error) }
        var edge = style.defaults()
        edge.width = style.Length { Px: w }
        edge.height = style.Length { Px: h }
        edge.border = style.Border { width: 1.0, color: style.color(t.tokens, .Outline) }
        var no_children: []const widget.Node = zero
        layers[0usize] = photo
        layers[1usize] = widget.positioned(0u64, 0.0, 0.0, edge, no_children)
        ret (widget.stack(key, frame, layers[0usize..2usize]), ok)
    }
    ret (widget.box(key, frame, kids[0usize..1usize]), ok)
}

fn paint_ground(t: *const control.Theme) -> paint.Brush {
    ret paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Contain", "Cover", "Fill", "None (unscaled)", "Rounded", "Bordered", "Small 48", "No texture" }
    var i = 0usize
    while i < 8usize {
        let key = u64((i + 1usize) * 16usize)
        var fit: widget.Fit = .Contain
        var w: f32 = 120.0
        var h: f32 = 80.0
        var picture = looks_c.picture
        if i == 1usize { fit = .Cover }
        if i == 2usize { fit = .Fill }
        if i == 3usize { fit = .None }
        if i == 6usize {
            w = 48.0
            h = 48.0
            fit = .Cover
        }
        if i == 7usize {
            var none: scene.TextureId = zero
            picture = none
        }
        let (node, node_error) = framed(a, key, t, picture, fit, w, h, i == 4usize, i == 5usize)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "image", cells: 8usize, columns: 4usize, cell_w: 170.0, cell_h: 130.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
