// `e.ui.control`'s content controls (D813, widget plan P1-01) under a theme with
// the square-glyph font: a text in the body role measures one line of the role's
// height and a heading taller (its two squares as wide as the body's four); a line
// budget with an ellipsis keeps a long text to one line; a selectable text is a read-only editor that selects and refuses typing;
// rich text lays its spans side by side and a linked span fires on a tap with the
// link role; an icon, a labelled image and a canvas are images in the tree while an
// unlabelled image is not; and the page renders.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

fn w16(d: []u8, at: usize, v: u32) {
    d[at] = u8((v >> 8u32) & 255u32)
    d[at + 1usize] = u8(v & 255u32)
}
fn w32(d: []u8, at: usize, v: u32) {
    w16(d, at, v >> 16u32)
    w16(d, at + 2usize, v & 65535u32)
}
fn record(d: []u8, slot: usize, tag: u32, at: usize, len: usize) {
    let r = 12usize + 16usize * slot
    w32(d, r, tag)
    w32(d, r + 8usize, u32(at))
    w32(d, r + 12usize, u32(len))
}

// The square-glyph font of the scene fixture, with a cmap mapping `a` to glyph 1.
fn synthetic_font(a: *mem.Arena) -> ([]u8, err) {
    let (d, d_error) = mem.alloc[u8](a, 512usize)
    if d_error != ok { ret (d, d_error) }
    var i = 0usize
    while i < 512usize {
        d[i] = 0u8
        i += 1usize
    }
    w32(d, 0usize, 65536u32)
    w16(d, 4usize, 7u32)
    record(d, 0usize, 1751474532u32, 128usize, 54usize)
    w16(d, 128usize + 18usize, 1000u32)
    record(d, 1usize, 1751672161u32, 192usize, 36usize)
    w16(d, 192usize + 4usize, 800u32)
    w16(d, 192usize + 34usize, 2u32)
    record(d, 2usize, 1752003704u32, 228usize, 8usize)
    w16(d, 228usize + 4usize, 600u32)
    record(d, 3usize, 1835104368u32, 236usize, 6usize)
    w16(d, 236usize + 4usize, 2u32)
    // cmap at 300: one encoding record (3, 1) to a format 4 subtable with one
    // segment, `a` (0x61) to glyph 1, and the 0xFFFF terminator.
    record(d, 4usize, 1668112752u32, 300usize, 44usize)
    w16(d, 300usize, 0u32)
    w16(d, 302usize, 1u32)
    w16(d, 304usize, 3u32)
    w16(d, 306usize, 1u32)
    w32(d, 308usize, 12u32)
    let sub = 312usize
    w16(d, sub, 4u32)
    w16(d, sub + 2usize, 32u32)
    w16(d, sub + 4usize, 0u32)
    w16(d, sub + 6usize, 4u32)
    w16(d, sub + 8usize, 4u32)
    w16(d, sub + 10usize, 1u32)
    w16(d, sub + 12usize, 0u32)
    w16(d, sub + 14usize, 97u32)
    w16(d, sub + 16usize, 65535u32)
    w16(d, sub + 18usize, 0u32)
    w16(d, sub + 20usize, 97u32)
    w16(d, sub + 22usize, 65535u32)
    w16(d, sub + 24usize, 65440u32)
    w16(d, sub + 26usize, 1u32)
    w16(d, sub + 28usize, 0u32)
    w16(d, sub + 30usize, 0u32)
    record(d, 5usize, 1819239265u32, 252usize, 6usize)
    record(d, 6usize, 1735162214u32, 260usize, 40usize)
    let g = 260usize
    w16(d, g, 1u32)
    w16(d, g + 2usize, 100u32)
    w16(d, g + 4usize, 100u32)
    w16(d, g + 6usize, 900u32)
    w16(d, g + 8usize, 900u32)
    w16(d, g + 10usize, 3u32)
    w16(d, g + 12usize, 0u32)
    var at = g + 14usize
    d[at] = 55u8
    d[at + 1usize] = 33u8
    d[at + 2usize] = 17u8
    d[at + 3usize] = 33u8
    at += 4usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    d[at + 3usize] = 252u8
    d[at + 4usize] = 224u8
    at += 5usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    at += 3usize
    w16(d, 252usize + 2usize, 0u32)
    w16(d, 252usize + 4usize, u32((at - g) / 2usize))
    ret (d, ok)
}

type Log = struct { links: usize }

fn on_link(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.links += 1usize
    ret ok
}

fn canvas_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 10.0, height: 10.0 }
}

fn canvas_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: area, brush: paint.Brush { Solid: paint.rgba(0.0, 1.0, 0.0, 1.0) } } })
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

type Page = struct { spans: [3]control.Span, selectable: [16]u8, selectable_len: usize, texture: scene.TextureId, log: Log }

fn build(a: *mem.Arena, t: *const control.Theme, page: *Page) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 8usize)
    if items_error != ok { ret (zero, items_error) }
    let (body_text, body_error) = control.text(a, 1u64, "aaaa", t, control.text_options())
    if body_error != ok { ret (zero, body_error) }
    items[0usize] = body_text
    var heading = control.text_options()
    heading.role = .Heading
    let (heading_text, heading_error) = control.text(a, 2u64, "aa", t, heading)
    if heading_error != ok { ret (zero, heading_error) }
    items[1usize] = heading_text
    var clipped = control.text_options()
    clipped.wrap = .Character
    clipped.max_lines = 1u32
    clipped.ellipsis = "a"
    let (long_text, long_error) = control.text(a, 3u64, "aaaaaaaaaaaa", t, clipped)
    if long_error != ok { ret (zero, long_error) }
    items[2usize] = long_text
    let (selectable, selectable_error) = control.selectable_text(a, 4u64, page.selectable[..], page.selectable_len, t, control.text_options())
    if selectable_error != ok { ret (zero, selectable_error) }
    items[3usize] = selectable
    let (rich, rich_error) = control.rich_text(a, 5u64, page.spans[..], t)
    if rich_error != ok { ret (zero, rich_error) }
    items[4usize] = rich
    let (an_icon, icon_error) = control.icon(a, 6u64, page.texture, 8.0, "star")
    if icon_error != ok { ret (zero, icon_error) }
    items[5usize] = an_icon
    let (an_image, image_error) = control.image(a, 7u64, page.texture, 16.0, 8.0, .Cover, "")
    if image_error != ok { ret (zero, image_error) }
    items[6usize] = an_image
    let (a_canvas, canvas_error) = control.canvas(a, 8u64, widget.Custom { ctx: zero, measure: canvas_measure, paint: canvas_paint, state: zero }, "plot")
    if canvas_error != ok { ret (zero, canvas_error) }
    items[7usize] = a_canvas
    var column = style.defaults()
    column.width = style.Length { Px: 64.0 }
    column.height = style.Length { Px: 200.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 2.0 }, column, items[0usize..8usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (font_bytes, font_error) = synthetic_font(a)
    if font_error != ok { os.exit(4i32) }
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 1usize)
    if fonts_error != ok { os.exit(5i32) }
    fonts[0usize] = shape.Font { id: 7u32, data: font_bytes, face_index: 0u32 }
    if scene.register_font(&renderer, fonts[0usize]) != ok { os.exit(6i32) }
    let tokens = style.reference(.Light)
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(7i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts[0usize..1usize], language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 64u32, 200u32, 1.0)
    if harness_error != ok { os.exit(8i32) }
    var harness = h
    // A 2x2 green texture for the icon and the image.
    var pixels: [16]u8 = zero
    var i = 0usize
    while i < 4usize {
        pixels[i * 4usize + 1usize] = 255u8
        pixels[i * 4usize + 3usize] = 255u8
        i += 1usize
    }
    let (view, view_error) = image.make_const(pixels[..], 2u32, 2u32, 8usize, .Rgba8, .Premultiplied)
    if view_error != ok { os.exit(9i32) }
    let (texture, upload_error) = scene.upload_image(&renderer, view)
    if upload_error != ok { os.exit(10i32) }
    let (pages, pages_error) = mem.alloc[Page](a, 1usize)
    if pages_error != ok { os.exit(11i32) }
    var page: Page = zero
    page.texture = texture
    page.selectable[0usize] = 97u8
    page.selectable[1usize] = 97u8
    page.selectable[2usize] = 97u8
    page.selectable_len = 3usize
    pages[0usize] = page
    pages[0usize].spans[0usize] = control.Span { value: "a", role: .Body, color: .Text, link: zero }
    pages[0usize].spans[1usize] = control.Span { value: "aa", role: .Body, color: .Primary, link: widget.Submit { ctx: mem.cast[*void](&pages[0usize].log), invoke: on_link } }
    pages[0usize].spans[2usize] = control.Span { value: "a", role: .Label, color: .TextMuted, link: zero }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(12i32) }
    var frame = mem.arena_from(frame_storage)
    let (root, build_error) = build(&frame, &theme, &pages[0usize])
    if build_error != ok { os.exit(13i32) }
    let now = time.Instant { nanos: 1000000000i64 }
    if testing.pump(&harness, root, now) != ok { os.exit(14i32) }
    // A body text is one line of its role's height, four squares wide; a heading is
    // taller and its two squares wider than the body's four.
    let (body_bounds, has_body) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    let (heading_bounds, has_heading) = widget.bounds_of(&runtime, testing.by_key(&harness, 2u64).element)
    if !has_body || !has_heading { os.exit(15i32) }
    if !near(body_bounds.height, tokens.text[0usize].line_height) || !near(body_bounds.width, 4.0 * 0.6 * tokens.text[0usize].size) { os.exit(16i32) }
    if !near(heading_bounds.height, tokens.text[3usize].line_height) || !near(heading_bounds.width, 2.0 * 0.6 * tokens.text[3usize].size) { os.exit(17i32) }
    // A long text with a line budget of one and an ellipsis stays one line tall.
    let (long_bounds, has_long) = widget.bounds_of(&runtime, testing.by_key(&harness, 3u64).element)
    if !has_long || !near(long_bounds.height, tokens.text[0usize].line_height) || !(long_bounds.width <= 64.0) { os.exit(18i32) }
    // The selectable text: a tap focuses it, Shift+End selects to the end, typing
    // changes nothing, and the tree says it is a read-only text field.
    let selectable = testing.by_key(&harness, 4u64)
    let (selectable_bounds, has_selectable) = widget.bounds_of(&runtime, selectable.element)
    if !has_selectable { os.exit(19i32) }
    if testing.tap(&harness, selectable_bounds.x + 1.0, selectable_bounds.y + selectable_bounds.height * 0.5) != ok { os.exit(20i32) }
    var shift: input.Modifiers = zero
    shift.shift = true
    if testing.press_key(&harness, 35u32, shift) != ok { os.exit(21i32) }
    let (sel_start, sel_end, has_selection) = widget.edit_selection(&runtime, selectable.element)
    if !has_selection || sel_start != 0usize || sel_end != 3usize { os.exit(22i32) }
    if testing.type_text(&harness, "b") != ok { os.exit(23i32) }
    let (kept, has_kept) = widget.edit_value(&runtime, selectable.element)
    if !has_kept || !same(kept, "aaa") { os.exit(24i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(25i32) }
    var read_only_field = false
    i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .TextField && tree.nodes[i].state.read_only { read_only_field = true }
        i += 1usize
    }
    if !read_only_field { os.exit(26i32) }
    // Rich text: the three spans side by side; the linked one is a link in the tree
    // and fires on a tap.
    let rich = testing.by_key(&harness, 5u64)
    let (rich_bounds, has_rich) = widget.bounds_of(&runtime, rich.element)
    if rich.count != 1usize || !has_rich || !near(rich_bounds.width, 3.0 * 0.6 * tokens.text[0usize].size + 0.6 * tokens.text[4usize].size) { os.exit(27i32) }
    let link = testing.by_role(&harness, .Link)
    let (link_bounds, has_link) = widget.bounds_of(&runtime, link.element)
    if link.count != 1usize || !has_link || !near(link_bounds.x, rich_bounds.x + 0.6 * tokens.text[0usize].size) { os.exit(28i32) }
    if testing.tap(&harness, link_bounds.x + 2.0, link_bounds.y + 2.0) != ok || pages[0usize].log.links != 1usize { os.exit(29i32) }
    // Images: the icon (and the image it holds), the canvas, and no unlabelled image.
    if testing.by_role(&harness, .Image).count != 3usize || testing.by_label(&harness, "star").count != 1usize || testing.by_label(&harness, "plot").count != 1usize { os.exit(30i32) }
    let (icon_bounds, has_icon) = widget.bounds_of(&runtime, testing.by_key(&harness, 6u64).element)
    if !has_icon || !near(icon_bounds.width, 8.0) || !near(icon_bounds.height, 8.0) { os.exit(31i32) }
    let (canvas_bounds, has_canvas) = widget.bounds_of(&runtime, testing.by_key(&harness, 8u64).element)
    if !has_canvas || !near(canvas_bounds.height, 10.0) { os.exit(32i32) }
    // The page renders and the canvas painted green where it sits.
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(33i32) }
    let cx = usize(canvas_bounds.x + 5.0)
    let cy = usize(canvas_bounds.y + 5.0)
    if shot.pixels[(cy * 64usize + cx) * 4usize + 1usize] != 255u8 { os.exit(34i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(35i32) }
    try io.print("ui content ok\n")
    ret ok
}
