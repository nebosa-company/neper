// Text for the NeperOS shell (D2204): a font is a TrueType file the program was handed (the lunar
// fonts in neperos/assets/fonts), registered with the scene renderer once, then a string is laid out
// with e.text.layout and pushed as a DrawText. The layout lives in the program's arena, because the
// command holds a pointer to it until the scene is compiled.
use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape

// Register `data` as font `id` with the renderer and return the shape.Font to lay text out in.
fn register(renderer: *scene.Renderer, id: u32, data: []const u8) -> (shape.Font, err) {
    let font = shape.Font { id: id, data: data, face_index: 0u32 }
    try scene.register_font(renderer, font)
    ret (font, ok)
}

// Lay `text` out at `size` dp in `font`. `width` > 0 wraps at words; `max_lines` > 0 ends the last line
// with an ellipsis. The layout comes back (its bounds say how big it is).
fn lay_out(a: *mem.Arena, font: shape.Font, size: f32, text: str, width: f32, max_lines: u32, align: layout.Align) -> (*layout.Layout, err) {
    let (choices, choices_error) = mem.alloc[layout.FontChoice](a, 1usize)
    if choices_error != ok { ret (zero, choices_error) }
    choices[0usize] = layout.FontChoice { font: font, size: size }
    var wrap = layout.Wrap.None
    if width > 0.0 { wrap = layout.Wrap.Word }
    let (value, layout_error) = layout.layout(a, text, layout.Style { fonts: choices[0usize..1usize], language: "en", line_height: 0.0 }, layout.Options { width: width, max_lines: max_lines, align: align, wrap: wrap, ellipsis: "\xE2\x80\xA6", notdef: false })
    if layout_error != ok { ret (zero, layout_error) }
    let (stored, stored_error) = mem.alloc[layout.Layout](a, 1usize)
    if stored_error != ok { ret (zero, stored_error) }
    stored[0usize] = value
    ret (&stored[0usize], ok)
}

// Draw `text` with its top-left corner at (x, y). Returns the laid-out size.
fn draw(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, text: str, x: f32, y: f32, width: f32, max_lines: u32, align: layout.Align, color: paint.Color) -> (geometry.Rect, err) {
    let (placed, place_error) = lay_out(a, font, size, text, width, max_lines, align)
    if place_error != ok { ret (zero, place_error) }
    try scene.push(builder, scene.Command { Text: scene.DrawText { layout: placed, origin: geometry.Point { x: x, y: y }, brush: paint.Brush { Solid: color } } })
    ret (placed.bounds, ok)
}

// The width `text` takes at `size` in `font`, for centring and right alignment.
fn measure(a: *mem.Arena, font: shape.Font, size: f32, text: str) -> f32 {
    let (placed, place_error) = lay_out(a, font, size, text, 0.0, 0u32, layout.Align.Start)
    if place_error != ok { ret 0.0 }
    ret placed.bounds.width
}

// The five lunar faces (D2204): Jost Bold for the clock, Jost Regular for labels, Sora Medium for
// headers, Space Grotesk Regular for technical text, Exo 2 Regular for body text.
type Faces = struct { jost_bold: shape.Font, jost: shape.Font, sora: shape.Font, grotesk: shape.Font, exo: shape.Font }

// Register the five fonts handed in as args[first .. first + 4] (the order above); false if there
// are not five or one will not register.
fn load_faces(renderer: *scene.Renderer, args: []str, first: usize) -> (Faces, bool) {
    var faces: Faces = zero
    if args.len < first + 5usize { ret (faces, false) }
    let (f1, r1) = register(renderer, 1u32, args[first])
    let (f2, r2) = register(renderer, 2u32, args[first + 1usize])
    let (f3, r3) = register(renderer, 3u32, args[first + 2usize])
    let (f4, r4) = register(renderer, 4u32, args[first + 3usize])
    let (f5, r5) = register(renderer, 5u32, args[first + 4usize])
    if r1 != ok || r2 != ok || r3 != ok || r4 != ok || r5 != ok { ret (faces, false) }
    ret (Faces { jost_bold: f1, jost: f2, sora: f3, grotesk: f4, exo: f5 }, true)
}
