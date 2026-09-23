// The focus ring (D940, widget plan P5-02) under the light theme: Tab paints a
// `focus_ring`-wide ring in the focus-ring colour `focus_offset` outside the focused
// button, the gap between them left as the page; Tab again moves it to the next
// button; a pointer press focuses without a ring; a button its clipping container
// fills takes the ring just inside its bounds; and a hovered button's state layer
// is its label colour over its fill.

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
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { presses: usize }
type Actions = struct { press: widget.Submit }

fn on_press(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.presses += 1usize
    ret ok
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 3.0 && e - v < 3.0
}

fn build(a: *mem.Arena, t: *const control.Theme, actions: *const Actions) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize)
    if items_error != ok { ret (zero, items_error) }
    let (save, save_error) = control.button(a, 1u64, t, "Save", &actions.press, control.button_options())
    if save_error != ok { ret (zero, save_error) }
    items[0usize] = save
    let (open, open_error) = control.button(a, 2u64, t, "Open", &actions.press, control.button_options())
    if open_error != ok { ret (zero, open_error) }
    items[1usize] = open
    let (wrap, wrap_error) = control.button(a, 3u64, t, "Wrap", &actions.press, control.button_options())
    if wrap_error != ok { ret (zero, wrap_error) }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = wrap
    var clipping = style.defaults()
    clipping.overflow = .Clip
    items[2usize] = widget.box(4u64, clipping, inner[0usize..1usize])
    var page = style.defaults()
    page.width = style.Length { Px: 160.0 }
    page.height = style.Length { Px: 200.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..3usize]), ok)
}

fn pixel(shot: image.Image, x: f32, y: f32) -> usize {
    ret (usize(y) * 160usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, at: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[at], c.red) && close_to(shot.pixels[at + 1usize], c.green) && close_to(shot.pixels[at + 2usize], c.blue)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 160u32, 200u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let (actions, actions_error) = mem.alloc[Actions](a, 1usize)
    if actions_error != ok { os.exit(8i32) }
    actions[0usize] = Actions { press: widget.Submit { ctx: mem.cast[*void](&logs[0usize]), invoke: on_press } }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(9i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &actions[0usize])
    if build_error != ok { os.exit(10i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    let ring = style.color(&tokens, .FocusRing)
    let page = style.color(&tokens, .Background)
    let reach = tokens.metrics.focus_offset + tokens.metrics.focus_ring
    let (save, has_save) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    let (open, has_open) = widget.bounds_of(&runtime, testing.by_key(&harness, 2u64).element)
    let (wrap, has_wrap) = widget.bounds_of(&runtime, testing.by_key(&harness, 3u64).element)
    if !has_save || !has_open || !has_wrap { os.exit(12i32) }
    let save_mid = save.y + save.height * 0.5
    let open_mid = open.y + open.height * 0.5
    // At rest, no ring anywhere.
    let (rest, rest_error) = testing.snapshot(&harness, a)
    if rest_error != ok { os.exit(13i32) }
    if !is_color(rest, pixel(rest, save.x - reach + 1.0, save_mid), page) { os.exit(14i32) }
    // Tab focuses Save and the next frame rings it: the ring's band is the focus
    // colour, the gap inside it the page.
    if testing.tab(&harness, false) != ok { os.exit(15i32) }
    let (root_2, build_2_error) = build(&frame, &theme, &actions[0usize])
    if build_2_error != ok { os.exit(16i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(17i32) }
    let (tabbed, tabbed_error) = testing.snapshot(&harness, a)
    if tabbed_error != ok { os.exit(18i32) }
    if !is_color(tabbed, pixel(tabbed, save.x - reach + 1.0, save_mid), ring) { os.exit(19i32) }
    if !is_color(tabbed, pixel(tabbed, save.x - 1.0, save_mid), page) { os.exit(20i32) }
    if !is_color(tabbed, pixel(tabbed, save.x + save.width + reach - 2.0, save_mid), ring) { os.exit(21i32) }
    if !is_color(tabbed, pixel(tabbed, open.x - reach + 1.0, open_mid), page) { os.exit(22i32) }
    // Tab again: the ring moves to Open.
    if testing.tab(&harness, false) != ok { os.exit(23i32) }
    let (root_3, build_3_error) = build(&frame, &theme, &actions[0usize])
    if build_3_error != ok { os.exit(24i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(25i32) }
    let (moved, moved_error) = testing.snapshot(&harness, a)
    if moved_error != ok { os.exit(26i32) }
    if !is_color(moved, pixel(moved, open.x - reach + 1.0, open_mid), ring) || !is_color(moved, pixel(moved, save.x - reach + 1.0, save_mid), page) { os.exit(27i32) }
    // Tab to Wrap, which its clipping box fills: the ring lies just inside it.
    if testing.tab(&harness, false) != ok { os.exit(28i32) }
    let (root_4, build_4_error) = build(&frame, &theme, &actions[0usize])
    if build_4_error != ok { os.exit(29i32) }
    if testing.pump(&harness, root_4, now) != ok { os.exit(30i32) }
    let (inset, inset_error) = testing.snapshot(&harness, a)
    if inset_error != ok { os.exit(31i32) }
    if !is_color(inset, pixel(inset, wrap.x + 1.0, wrap.y + wrap.height * 0.5), ring) { os.exit(32i32) }
    // A pointer press focuses Save and presses it, with no ring.
    if testing.tap(&harness, save.x + save.width * 0.5, save_mid) != ok || logs[0usize].presses != 1usize { os.exit(33i32) }
    let (focus_now, has_focus) = testing.focused(&harness)
    if !has_focus || focus_now.slot != testing.by_key(&harness, 1u64).element.slot { os.exit(34i32) }
    let (root_5, build_5_error) = build(&frame, &theme, &actions[0usize])
    if build_5_error != ok { os.exit(35i32) }
    if testing.pump(&harness, root_5, now) != ok { os.exit(36i32) }
    let (tapped, tapped_error) = testing.snapshot(&harness, a)
    if tapped_error != ok { os.exit(37i32) }
    if !is_color(tapped, pixel(tapped, save.x - reach + 1.0, save_mid), page) { os.exit(38i32) }
    // The state layer: hovered, the fill is the label colour over it at the hover
    // opacity.
    if testing.hover(&harness, open.x + open.width * 0.5, open_mid) != ok { os.exit(39i32) }
    let (root_6, build_6_error) = build(&frame, &theme, &actions[0usize])
    if build_6_error != ok { os.exit(40i32) }
    if testing.pump(&harness, root_6, now) != ok { os.exit(41i32) }
    let (hovered, hovered_error) = testing.snapshot(&harness, a)
    if hovered_error != ok { os.exit(42i32) }
    let fill = style.color(&tokens, .Primary)
    let label = style.color(&tokens, .OnPrimary)
    let o = tokens.states.hover
    let expected = paint.rgba(fill.red + (label.red - fill.red) * o, fill.green + (label.green - fill.green) * o, fill.blue + (label.blue - fill.blue) * o, 1.0)
    if !is_color(hovered, pixel(hovered, open.x + 3.0, open_mid), expected) { os.exit(43i32) }
    try io.print("ui focus ring ok\n")
    ret ok
}
