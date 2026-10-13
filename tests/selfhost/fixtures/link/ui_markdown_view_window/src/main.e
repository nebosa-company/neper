// `e.ui.markdown_view` at the window (L066, D4607): the viewer's spans shown by `control.paragraph` in a widget runtime
// under the harness, with the square-glyph font of the content fixture (every word is `a`s). A tap on a safe link of a
// host-activated viewer runs its action once; the same words display-only, a `javascript:` link, a `data:` link have no
// pressable link and a tap does nothing; a raw-HTML anchor is text. Then what a pointer drag over the viewer's items selects
// -- the whole document and a part, an inverted range being refused -- goes through the runtime's clipboard and comes back as the
// same text. Each check exits with its own code.

use e.fmt.markdown
use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.markdown_view as mv
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

// The square-glyph font of the content fixture, whose cmap maps both the space
// and `a` to the square glyph 1.
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
    // cmap at 300: one encoding record (3, 1) to a format 4 subtable with three
    // segments, the space and `a` to glyph 1, and the 0xFFFF terminator.
    record(d, 4usize, 1668112752u32, 300usize, 52usize)
    w16(d, 300usize, 0u32)
    w16(d, 302usize, 1u32)
    w16(d, 304usize, 3u32)
    w16(d, 306usize, 1u32)
    w32(d, 308usize, 12u32)
    let sub = 312usize
    w16(d, sub, 4u32)
    w16(d, sub + 2usize, 40u32)
    w16(d, sub + 4usize, 0u32)
    w16(d, sub + 6usize, 6u32)
    w16(d, sub + 8usize, 4u32)
    w16(d, sub + 10usize, 1u32)
    w16(d, sub + 12usize, 2u32)
    w16(d, sub + 14usize, 32u32)
    w16(d, sub + 16usize, 97u32)
    w16(d, sub + 18usize, 65535u32)
    w16(d, sub + 20usize, 0u32)
    w16(d, sub + 22usize, 32u32)
    w16(d, sub + 24usize, 97u32)
    w16(d, sub + 26usize, 65535u32)
    w16(d, sub + 28usize, 65505u32)
    w16(d, sub + 30usize, 65440u32)
    w16(d, sub + 32usize, 1u32)
    w16(d, sub + 34usize, 0u32)
    w16(d, sub + 36usize, 0u32)
    w16(d, sub + 38usize, 0u32)
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


// What the window's controls wrote: how many times each paragraph's link action ran.
type Clicks = struct { count: u32 }

fn on_link(ctx: *void) -> err {
    let c = mem.cast[*Clicks](ctx)
    c.count += 1u32
    ret ok
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

fn centre(r: geometry.Rect) -> geometry.Point {
    ret geometry.Point { x: r.x + r.width * 0.5, y: r.y + r.height * 0.5 }
}

fn metrics(width: f32) -> mv.Metrics {
    ret mv.Metrics { width: width, char_w: 8.0, line_h: 16.0, gap: 8.0, indent: 16.0, pad: 4.0, bar: 2.0 }
}

// One document laid out by the viewer, its first paragraph's spans shown by `control.paragraph` in the window under the
// given policy, and a tap on where the link word is. Answers how many times the link ran (and whether any of the
// paragraph's elements is pressable at all).
fn tap_link(a: *mem.Arena, harness: *testing.Harness, runtime: *widget.Runtime, theme: *const control.Theme, st: mv.Storage, src: str, policy: mv.LinkPolicy, clicks: *Clicks) -> (u32, bool) {
    clicks.count = 0u32
    let (v, build_error) = mv.build(src, st, metrics(200.0), policy)
    if build_error != ok || v.fallback { os.exit(20i32) }
    var spans: [16]control.RichSpan = zero
    let action = widget.Submit { ctx: mem.cast[*void](clicks), invoke: on_link }
    let (n, spans_error) = mv.rich_spans(&v, 0usize, spans[..], action)
    if spans_error != ok { os.exit(21i32) }
    var link_index = n
    var i = 0usize
    while i < n {
        if spans[i].kind == .Link && link_index == n { link_index = i }
        i += 1usize
    }
    if link_index == n { os.exit(22i32) }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(23i32) }
    var frame = mem.arena_from(frame_storage)
    var options = control.rich_options(theme)
    options.width = 200.0
    let (para, para_error) = control.paragraph(&frame, 10u64, theme, spans[0usize..n], options)
    if para_error != ok { os.exit(24i32) }
    var page = style.defaults()
    page.width = style.Length { Px: 240.0 }
    page.height = style.Length { Px: 120.0 }
    let (items, items_error) = mem.alloc[widget.Node](&frame, 1usize)
    if items_error != ok { os.exit(25i32) }
    items[0usize] = para
    let root = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page, items[0usize..1usize])
    if testing.pump(harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(26i32) }
    let link = testing.by_key(harness, 11u64 + u64(link_index))
    let pressable = link.count == 1usize
    // The link word's place is where the safe document puts it; a tap there is the user's.
    let (bounds, has_bounds) = widget.bounds_of(runtime, link.element)
    var at = geometry.Point { x: 32.0, y: 10.0 }
    if pressable && has_bounds { at = centre(bounds) }
    if testing.tap(harness, at.x, at.y) != ok { os.exit(27i32) }
    ret (clicks.count, pressable)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 256usize, max_states: 32usize, state_bytes: 1024usize, state_classes: 8u16, max_depth: 16u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(7i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts[0usize..1usize], language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 120u32, 1.0)
    if harness_error != ok { os.exit(8i32) }
    var harness = h

    var items: [512]mv.Item = zero
    var nodes: [64]mv.Node = zero
    var links: [16]mv.Link = zero
    var store: [4096]u8 = zero
    var scratch: [1024]u8 = zero
    var blocks: [128]markdown.Block = zero
    var inlines: [128]markdown.Inline = zero
    var words: [128]mv.Word = zero
    let st = mv.Storage { items: items[..], nodes: nodes[..], links: links[..], store: store[..], scratch: scratch[..], blocks: blocks[..], inlines: inlines[..], words: words[..] }
    var clicks: Clicks = zero

    // A safe link in a host-activated viewer runs its action once, on a tap.
    let (safe_clicks, safe_pressable) = tap_link(a, &harness, &runtime, &theme, st, "aa [aaa](https://example.org/a) aa", .HostActivated, &clicks)
    if !safe_pressable || safe_clicks != 1u32 { os.exit(10i32) }
    // The same words under a display-only policy have no pressable link and a tap does nothing.
    let (display_clicks, display_pressable) = tap_link(a, &harness, &runtime, &theme, st, "aa [aaa](https://example.org/a) aa", .DisplayOnly, &clicks)
    if display_pressable || display_clicks != 0u32 { os.exit(11i32) }
    // Unsafe schemes are not activatable even host-activated: `javascript:` and `data:`.
    let (js_clicks, js_pressable) = tap_link(a, &harness, &runtime, &theme, st, "aa [aaa](javascript:alert(1)) aa", .HostActivated, &clicks)
    if js_pressable || js_clicks != 0u32 { os.exit(12i32) }
    let (data_clicks, data_pressable) = tap_link(a, &harness, &runtime, &theme, st, "aa [aaa](data:text/html,x) aa", .HostActivated, &clicks)
    if data_pressable || data_clicks != 0u32 { os.exit(13i32) }
    // A raw-HTML anchor is literal text, never a link: the viewer finds one link, the markdown one, and its spans carry
    // a single pressable word.
    let (html, html_error) = mv.build("aa [aaa](https://example.org/a) <a href=\"javascript:x\">aa</a>", st, metrics(200.0), .HostActivated)
    if html_error != ok || html.fallback || html.link_count != 1usize { os.exit(14i32) }
    var html_spans: [16]control.RichSpan = zero
    let (html_n, html_spans_error) = mv.rich_spans(&html, 0usize, html_spans[..], widget.Submit { ctx: mem.cast[*void](&clicks), invoke: on_link })
    if html_spans_error != ok { os.exit(15i32) }
    var pressable_spans = 0usize
    var k = 0usize
    while k < html_n {
        if widget.submit_set(html_spans[k].action.invoke) { pressable_spans += 1usize }
        k += 1usize
    }
    if pressable_spans != 1usize { os.exit(16i32) }

    // The selection a pointer drag makes over the viewer's own items reaches the clipboard whole and in part, and what the
    // clipboard answers is the text, not a rendering of it.
    let (view, view_error) = mv.build("aa **aaa** `a`\n\naa a", st, metrics(200.0), .HostActivated)
    if view_error != ok || view.fallback { os.exit(30i32) }
    var out: [128]u8 = zero
    // From the word under the first point to the word under the second, in either direction.
    let (first, has_first) = mv.item_at(&view, 4.0, 8.0)
    let (last, has_last) = mv.item_at(&view, 30.0, 8.0)
    if !has_first || !has_last { os.exit(31i32) }
    let (whole_n, whole_error) = mv.selected_text(&view, 0usize, view.item_count - 1usize, out[..])
    if whole_error != ok { os.exit(32i32) }
    let whole: str = out[0usize..whole_n]
    if !same(whole, "aa aaa a\naa a") { os.exit(33i32) }
    if widget.clipboard_set(&runtime, whole) != ok { os.exit(34i32) }
    let (back, back_error) = widget.clipboard_get(&runtime, a)
    if back_error != ok || !same(back, "aa aaa a\naa a") { os.exit(35i32) }
    let (part_n, part_error) = mv.selected_text(&view, first, last, out[..])
    if part_error != ok { os.exit(36i32) }
    let part: str = out[0usize..part_n]
    if part.len == 0usize || part.len >= whole.len { os.exit(37i32) }
    if widget.clipboard_set(&runtime, part) != ok { os.exit(38i32) }
    let (back2, back2_error) = widget.clipboard_get(&runtime, a)
    if back2_error != ok || !same(back2, part) { os.exit(39i32) }
    // A drag made backwards is the host's to order: an inverted range is refused, ordered it is the same part.
    let (inverted_n, inverted_error) = mv.selected_text(&view, last, first, out[..])
    if first < last && inverted_error != mv.Invalid { os.exit(40i32) }
    let (ordered_n, ordered_error) = mv.selected_text(&view, first, last, out[..])
    if ordered_error != ok || !same(out[0usize..ordered_n], part) { os.exit(41i32) }

    try io.print("ui markdown view window ok\n")
    ret ok
}
