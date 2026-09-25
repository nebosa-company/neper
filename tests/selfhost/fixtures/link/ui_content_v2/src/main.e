// The v2 content controls (D962, widget plan P5-07, docs/ux/components) under the
// light theme at pointer density. Icons are vector glyphs of the shared set at the
// token sizes 18, 24 and 36, tinted by their colour role and `on-surface` at 38%
// disabled, left out of the tree unnamed. Avatars are 24-72 discs (8-cornered
// squares for teams): initials on the container the account's stable hash picks,
// a cover-fitted picture, or the `person` mark on `surface-container-highest`,
// with the presence mark at the bottom end ringed 2 in the ground and named in the
// label. Images are frames of a width and an aspect ratio, 12-cornered (8 under 48
// wide), clipping over `surface-container-highest`, with loading, error (Retry)
// and empty states. Canvases are framed in `surface-container-lowest` with a 1px
// `outline-variant` edge and 12 corners, inset by their padding, at least 48 each
// way, bare without a frame and at 38% disabled. A title-medium text is a Heading
// at level 4.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct { retry: widget.Submit, retries: u32 }

fn on_retry(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.retries += 1u32
    ret ok
}

fn canvas_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn canvas_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: area, brush: paint.Brush { Solid: paint.rgba(0.0, 1.0, 0.0, 1.0) } } })
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
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

fn row(a: *mem.Arena, items: []const widget.Node) -> widget.Node {
    ret widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 16.0 }, style.defaults(), items)
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, texture: scene.TextureId) -> (widget.Node, err) {
    let (n, n_error) = mem.alloc[widget.Node](a, 24usize)
    if n_error != ok { ret (zero, n_error) }
    // Icons: 24 by default, 20 snapped to 18, a named error alert at 36, the same
    // disabled, and an unnamed one.
    var o = control.icon_options()
    let (i1, e1) = control.icon_of(a, 10u64, t, .ChevronRight, o)
    if e1 != ok { ret (zero, e1) }
    n[0usize] = i1
    o.size = 20.0
    o.label = "Search"
    let (i2, e2) = control.icon_of(a, 11u64, t, .Search, o)
    if e2 != ok { ret (zero, e2) }
    n[1usize] = i2
    o.size = 30.0
    o.color = .Error
    o.label = "Failed"
    let (i3, e3) = control.icon_of(a, 12u64, t, .Alert, o)
    if e3 != ok { ret (zero, e3) }
    n[2usize] = i3
    o.enabled = false
    o.label = "Off"
    let (i4, e4) = control.icon_of(a, 13u64, t, .Alert, o)
    if e4 != ok { ret (zero, e4) }
    n[3usize] = i4
    let (i5, e5) = control.icon_of(a, 14u64, t, .ArrowBack, control.icon_options())
    if e5 != ok { ret (zero, e5) }
    n[4usize] = i5
    // Avatars: initials online at 40, a busy team square with the person mark at
    // 56, a picture away at 32, and an unnamed offline one at 24.
    var v = control.avatar_options()
    v.initials = "AL"
    v.account = "ada"
    v.presence = .Online
    v.label = "Ada Lovelace"
    let none: scene.TextureId = zero
    let (a1, f1) = control.avatar_of(a, 20u64, t, none, v)
    if f1 != ok { ret (zero, f1) }
    n[5usize] = a1
    var w = control.avatar_options()
    w.size = 56.0
    w.square = true
    w.presence = .Busy
    w.label = "Build team"
    let (a2, f2) = control.avatar_of(a, 21u64, t, none, w)
    if f2 != ok { ret (zero, f2) }
    n[6usize] = a2
    var x = control.avatar_options()
    x.size = 30.0
    x.presence = .Away
    x.label = "Mina"
    let (a3, f3) = control.avatar_of(a, 22u64, t, texture, x)
    if f3 != ok { ret (zero, f3) }
    n[7usize] = a3
    var y = control.avatar_options()
    y.size = 20.0
    y.initials = "J"
    y.presence = .Offline
    let (a4, f4) = control.avatar_of(a, 23u64, t, none, y)
    if f4 != ok { ret (zero, f4) }
    n[8usize] = a4
    // Images: a loaded 16:9 at 160 with a caption, a failed square at 160 with
    // Retry, an empty square at 40, and a loading 4:3 at 64.
    var m = control.image_options()
    m.label = "Build farm"
    m.caption = "Rack 3"
    let (m1, g1) = control.framed_image(a, 30u64, t, texture, m)
    if g1 != ok { ret (zero, g1) }
    n[9usize] = m1
    var f = control.image_options()
    f.aspect = 1.0
    f.status = .Failed
    f.retry = &s.retry
    let (m2, g2) = control.framed_image(a, 31u64, t, texture, f)
    if g2 != ok { ret (zero, g2) }
    n[10usize] = m2
    var e = control.image_options()
    e.width = 40.0
    e.aspect = 1.0
    e.status = .Empty
    let (m3, g3) = control.framed_image(a, 32u64, t, texture, e)
    if g3 != ok { ret (zero, g3) }
    n[11usize] = m3
    var l = control.image_options()
    l.width = 64.0
    l.aspect = 4.0 / 3.0
    l.status = .Loading
    l.label = "Preview"
    let (m4, g4) = control.framed_image(a, 33u64, t, texture, l)
    if g4 != ok { ret (zero, g4) }
    n[12usize] = m4
    // Canvases: a framed 200 x 100 chart with 16 padding, and a bare disabled one
    // asked for 20 x 20.
    let custom = widget.Custom { ctx: zero, measure: canvas_measure, paint: canvas_paint, state: zero }
    var c = control.canvas_options()
    c.width = 200.0
    c.height = 100.0
    c.padding = 16.0
    c.label = "Build time last week"
    let (c1, h1) = control.framed_canvas(a, 40u64, t, custom, c)
    if h1 != ok { ret (zero, h1) }
    n[13usize] = c1
    var d = control.canvas_options()
    d.width = 20.0
    d.height = 20.0
    d.bare = true
    d.enabled = false
    let (c2, h2) = control.framed_canvas(a, 41u64, t, custom, d)
    if h2 != ok { ret (zero, h2) }
    n[14usize] = c2
    // Texts: a title-medium heading and body copy.
    var heading = control.text_options()
    heading.role = .TitleMedium
    let (t1, k1) = control.text(a, 50u64, "Recent files", t, heading)
    if k1 != ok { ret (zero, k1) }
    n[15usize] = t1
    let (t2, k2) = control.text(a, 51u64, "Body", t, control.text_options())
    if k2 != ok { ret (zero, k2) }
    n[16usize] = t2
    n[17usize] = row(a, n[0usize..5usize])
    n[18usize] = row(a, n[5usize..9usize])
    n[19usize] = row(a, n[9usize..13usize])
    n[20usize] = row(a, n[13usize..15usize])
    n[21usize] = row(a, n[15usize..17usize])
    var page = style.defaults()
    page.width = style.Length { Px: 600.0 }
    page.height = style.Length { Px: 520.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 24.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 24.0 }, page, n[17usize..22usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 600usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn over(top: paint.Color, alpha: f32, under: paint.Color) -> paint.Color {
    ret paint.rgba(top.red * alpha + under.red * (1.0 - alpha), top.green * alpha + under.green * (1.0 - alpha), top.blue * alpha + under.blue * (1.0 - alpha), 1.0)
}

fn bounds(h: *const testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> geometry.Rect {
    let (b, has) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    if !has { os.exit(90i32) }
    ret b
}

fn main(a: *mem.Arena, args: []str) -> err {
    if control.account_hash("ada") != 943263163u32 { os.exit(40i32) }
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    var tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 1024usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 24u16, max_commands: 8192usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 600u32, 520u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    var pixels: [16]u8 = zero
    var i = 0usize
    while i < 4usize {
        pixels[i * 4usize + 1usize] = 255u8
        pixels[i * 4usize + 3usize] = 255u8
        i += 1usize
    }
    let (view, view_error) = image.make_const(pixels[..], 2u32, 2u32, 8usize, .Rgba8, .Premultiplied)
    if view_error != ok { os.exit(7i32) }
    let (texture, upload_error) = scene.upload_image(&renderer, view)
    if upload_error != ok { os.exit(8i32) }
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(9i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.retry = widget.Submit { ctx: mem.cast[*void](s), invoke: on_retry }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(10i32) }
    var fr = mem.arena_from(frame_storage)
    let (root, build_error) = build(&fr, &theme, s, texture)
    if build_error != ok { os.exit(11i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(12i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(13i32) }
    let page = style.color(&tokens, .Background)
    let green = paint.rgba(0.0, 1.0, 0.0, 1.0)
    let highest = style.color(&tokens, .SurfaceContainerHighest)
    // Icons: 24, 18 and 36 squares; the 36 alert's ring, 6 in from its start on
    // its middle row, is `error`, and disabled `on-surface` at 38%.
    let i1 = bounds(&harness, &runtime, 10u64)
    let i2 = bounds(&harness, &runtime, 11u64)
    let i3 = bounds(&harness, &runtime, 12u64)
    let i4 = bounds(&harness, &runtime, 13u64)
    let i5 = bounds(&harness, &runtime, 14u64)
    if !near(i1.width, 24.0) || !near(i1.height, 24.0) { os.exit(14i32) }
    if !near(i2.width, 18.0) || !near(i2.height, 18.0) { os.exit(15i32) }
    if !near(i3.width, 36.0) || !near(i3.height, 36.0) { os.exit(16i32) }
    if !is_color(shot, at(i3.x + 6.0, i3.y + 18.0), style.color(&tokens, .Error)) { os.exit(17i32) }
    if !is_color(shot, at(i4.x + 6.0, i4.y + 18.0), over(style.color(&tokens, .OnSurface), tokens.states.disabled_content, page)) { os.exit(18i32) }
    if !is_color(shot, at(i3.x + 12.0, i3.y + 18.0), page) { os.exit(19i32) }
    if testing.by_label(&harness, "Failed").count != 1usize || testing.by_label(&harness, "Search").count != 1usize { os.exit(20i32) }
    // Avatars: the 40 disc on the container "ada" hashes to, its online mark 12 at
    // the bottom end in `success` ringed in the page; the 56 team square's corner
    // 3 in is `surface-container-highest` and its busy mark an `error` disc with an
    // `on-error` bar; the 32 picture's away ring is `warning` round the page.
    let v1 = bounds(&harness, &runtime, 20u64)
    if !near(v1.width, 40.0) || !near(v1.height, 40.0) { os.exit(21i32) }
    if !is_color(shot, at(v1.x + 16.0, v1.y + 16.0), style.color(&tokens, .SecondaryContainer)) { os.exit(22i32) }
    if !is_color(shot, at(v1.x + 32.0, v1.y + 32.0), style.color(&tokens, .Success)) { os.exit(23i32) }
    if !is_color(shot, at(v1.x + 25.0, v1.y + 32.0), page) { os.exit(24i32) }
    if !is_color(shot, at(v1.x + 1.0, v1.y + 1.0), page) { os.exit(25i32) }
    if testing.by_label(&harness, "Ada Lovelace, online").count != 1usize { os.exit(26i32) }
    let v2 = bounds(&harness, &runtime, 21u64)
    if !near(v2.width, 56.0) || !is_color(shot, at(v2.x + 3.0, v2.y + 3.0), highest) { os.exit(27i32) }
    if !is_color(shot, at(v2.x + 47.0, v2.y + 47.0), style.color(&tokens, .OnError)) || !is_color(shot, at(v2.x + 47.0, v2.y + 42.0), style.color(&tokens, .Error)) { os.exit(28i32) }
    if testing.by_label(&harness, "Build team, do not disturb").count != 1usize { os.exit(29i32) }
    let v3 = bounds(&harness, &runtime, 22u64)
    if !near(v3.width, 32.0) || !is_color(shot, at(v3.x + 12.0, v3.y + 12.0), green) { os.exit(30i32) }
    if !is_color(shot, at(v3.x + 21.0, v3.y + 25.0), style.color(&tokens, .Warning)) || !is_color(shot, at(v3.x + 25.0, v3.y + 25.0), page) { os.exit(31i32) }
    let v4 = bounds(&harness, &runtime, 23u64)
    if !near(v4.width, 24.0) { os.exit(32i32) }
    // Images: the 160 x 90 frame clips the picture to 12 corners with the caption
    // 8 below; the failed square shows its ground and a Retry that fires; the 40
    // square is 8-cornered; the loading frame is busy on the ground.
    let m1 = bounds(&harness, &runtime, 30u64)
    if !near(m1.width, 160.0) || !near(m1.height, 98.0) { os.exit(33i32) }
    if !is_color(shot, at(m1.x + 80.0, m1.y + 45.0), green) || !is_color(shot, at(m1.x + 5.0, m1.y + 5.0), green) || !is_color(shot, at(m1.x + 1.0, m1.y + 1.0), page) { os.exit(34i32) }
    let m2 = bounds(&harness, &runtime, 31u64)
    if !near(m2.width, 160.0) || !near(m2.height, 160.0) || !is_color(shot, at(m2.x + 6.0, m2.y + 80.0), highest) { os.exit(35i32) }
    let retry = testing.by_label(&harness, "Retry")
    let (retry_bounds, has_retry) = widget.bounds_of(&runtime, retry.element)
    if retry.count == 0usize || !has_retry { os.exit(36i32) }
    if testing.tap(&harness, retry_bounds.x + retry_bounds.width * 0.5, retry_bounds.y + retry_bounds.height * 0.5) != ok || s.retries != 1u32 { os.exit(37i32) }
    let m3 = bounds(&harness, &runtime, 32u64)
    if !near(m3.width, 40.0) || !near(m3.height, 40.0) || !is_color(shot, at(m3.x + 3.0, m3.y + 3.0), highest) || !is_color(shot, at(m3.x + 20.0, m3.y + 1.0), highest) { os.exit(38i32) }
    let m4 = bounds(&harness, &runtime, 33u64)
    if !near(m4.width, 64.0) || !near(m4.height, 48.0) || !is_color(shot, at(m4.x + 32.0, m4.y + 24.0), highest) { os.exit(39i32) }
    // Canvases: the 200 x 100 frame's edge is `outline-variant`, its padding
    // `surface-container-lowest`, its paint green; the bare disabled one is 48
    // square and green at 38% to its corner.
    let c1 = bounds(&harness, &runtime, 40u64)
    if !near(c1.width, 200.0) || !near(c1.height, 100.0) { os.exit(41i32) }
    if !is_color(shot, at(c1.x, c1.y + 50.0), style.color(&tokens, .OutlineVariant)) { os.exit(42i32) }
    if !is_color(shot, at(c1.x + 8.0, c1.y + 50.0), style.color(&tokens, .SurfaceContainerLowest)) || !is_color(shot, at(c1.x + 100.0, c1.y + 50.0), green) || !is_color(shot, at(c1.x + 17.0, c1.y + 17.0), green) { os.exit(43i32) }
    let c2 = bounds(&harness, &runtime, 41u64)
    if !near(c2.width, 48.0) || !near(c2.height, 48.0) || !is_color(shot, at(c2.x, c2.y), over(green, tokens.states.disabled_content, page)) { os.exit(44i32) }
    // The tree: the decorative icon and avatar are left out, the loading image is
    // busy, the failed one says why, and the title-medium text is a level 4 Heading.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(45i32) }
    let quiet_icon = testing.by_key(&harness, 14u64).element
    let quiet_avatar = testing.by_key(&harness, 23u64).element
    let loading = testing.by_key(&harness, 33u64).element
    var headings = 0usize
    var busy = false
    var said = false
    i = 0usize
    while i < tree.nodes.len {
        let node = tree.nodes[i]
        if node.id.slot == quiet_icon.slot || node.id.slot == quiet_avatar.slot { os.exit(46i32) }
        if node.id.slot == loading.slot && node.state.busy { busy = true }
        if same(node.value, "Couldn't load") { said = true }
        if node.role == .Heading {
            headings += 1usize
            if node.level != 4u8 || !same(node.label, "Recent files") { os.exit(47i32) }
        }
        i += 1usize
    }
    if headings != 1usize { os.exit(48i32) }
    if !busy { os.exit(50i32) }
    if !said { os.exit(51i32) }
    // Directional icons mirror in RTL; neutral icons above retain their shapes.
    tokens.direction = .RightToLeft
    let (rtl_root, rtl_error) = build(&fr, &theme, s, texture)
    if rtl_error != ok || testing.pump(&harness, rtl_root, time.Instant { nanos: 2000000000i64 }) != ok { os.exit(52i32) }
    let (rtl_shot, rtl_shot_error) = testing.snapshot(&harness, a)
    if rtl_shot_error != ok { os.exit(53i32) }
    let rtl_chevron = bounds(&harness, &runtime, 10u64)
    let rtl_back = bounds(&harness, &runtime, 14u64)
    let directional = style.color(&tokens, .OnSurfaceVariant)
    if !is_color(shot, at(i1.x + 14.0, i1.y + 12.0), directional) || is_color(shot, at(i1.x + 10.0, i1.y + 12.0), directional) { os.exit(54i32) }
    if !is_color(rtl_shot, at(rtl_chevron.x + 10.0, rtl_chevron.y + 12.0), directional) || is_color(rtl_shot, at(rtl_chevron.x + 14.0, rtl_chevron.y + 12.0), directional) { os.exit(55i32) }
    if is_color(shot, at(i5.x + 8.0, i5.y + 10.0), page) || !is_color(shot, at(i5.x + 16.0, i5.y + 10.0), page) { os.exit(56i32) }
    if is_color(rtl_shot, at(rtl_back.x + 16.0, rtl_back.y + 10.0), page) || !is_color(rtl_shot, at(rtl_back.x + 8.0, rtl_back.y + 10.0), page) { os.exit(57i32) }
    // (D1227) An avatar group: three 32 faces ringed 36 and stepping 28, then "+4",
    // one Group named for the people; two faces with an open action are a Button.
    var faces: [3]control.AvatarOptions = zero
    faces[0usize] = control.avatar_options()
    faces[0usize].initials = "AL"
    faces[0usize].label = "Ada"
    faces[1usize] = control.avatar_options()
    faces[1usize].initials = "MK"
    faces[1usize].label = "Mina"
    faces[2usize] = control.avatar_options()
    faces[2usize].initials = "JR"
    faces[2usize].label = "Jon"
    var no_textures: []const scene.TextureId = zero
    var no_open: *const widget.Submit = zero
    fr = mem.arena_from(frame_storage)
    let (crowd, crowd_error) = control.avatar_group(&fr, 700u64, &theme, faces[..], no_textures, 7usize, 32.0, no_open)
    if crowd_error != ok || testing.pump(&harness, crowd, time.Instant { nanos: 2000000000i64 }) != ok { os.exit(91i32) }
    let crowd_box = bounds(&harness, &runtime, 700u64)
    let (crowd_tree, crowd_tree_error) = testing.semantics(&harness)
    if crowd_tree_error != ok || crowd_box.width < 119.5 || crowd_box.width > 120.5 || crowd_box.height < 35.5 || crowd_box.height > 36.5 || testing.by_text(&harness, "+4").count == 0usize { os.exit(92i32) }
    var named_crowd = false
    var n = 0usize
    while n < crowd_tree.nodes.len {
        if crowd_tree.nodes[n].role == .Group && mem.eq[u8](crowd_tree.nodes[n].label, "Ada, Mina, Jon and 4 others") { named_crowd = true }
        if crowd_tree.nodes[n].role == .Image { os.exit(93i32) }
        n += 1usize
    }
    if !named_crowd { os.exit(94i32) }
    fr = mem.arena_from(frame_storage)
    let (pair, pair_error) = control.avatar_group(&fr, 710u64, &theme, faces[0usize..2usize], no_textures, 2usize, 32.0, &s.retry)
    if pair_error != ok || testing.pump(&harness, pair, time.Instant { nanos: 2100000000i64 }) != ok { os.exit(95i32) }
    let pair_box = bounds(&harness, &runtime, 710u64)
    let (pair_tree, pair_tree_error) = testing.semantics(&harness)
    if pair_tree_error != ok { os.exit(96i32) }
    var named_pair = false
    n = 0usize
    while n < pair_tree.nodes.len {
        if pair_tree.nodes[n].role == .Button && mem.eq[u8](pair_tree.nodes[n].label, "Ada and Mina") { named_pair = true }
        n += 1usize
    }
    let retries_before = s.retries
    if !named_pair || testing.tap(&harness, pair_box.x + 10.0, pair_box.y + 18.0) != ok || s.retries != retries_before + 1u32 { os.exit(97i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(49i32) }
    try io.print("ui content v2 ok\n")
    ret ok
}
