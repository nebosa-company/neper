// The v2 dividers, cards, group boxes, disclosure, expander and accordion
// (D965, widget plan P5-08, docs/ux/components) under the light theme at
// pointer density: a divider is a 1px `outline-variant` line, inset by its start;
// a card is `radius-md` with 16 padding, elevated `surface-container-low`, filled
// `surface-container-highest`, selected in a 2px `primary` outline with a 24
// `primary` check disc 8 in from the top end, and a pressable card is a Button
// firing its action; a group box sets its rows 48 tall on `surface` in a 1px
// `outline-variant` edge with a divider between them, 8 under the title, and an
// invalid one wears a 2px `error` edge; a disclosure's header is 40 tall with the
// content 40 in and 4 below, Left shutting it; an expander is a 56 header in a
// 1px `outline-variant` edge; an accordion is `surface-container-low` with 48
// headers (64 with a supporting line), several open at once, 1px dividers between
// sections, and Down and End moving focus between headers.

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

type Hit = struct { store: *Store, index: usize }
type Store = struct { hits: [8]u32, targets: [8]Hit, actions: [8]widget.Submit, words: [3]str, lines: [3]str, open: [3]bool }

fn on_hit(ctx: *void) -> err {
    let h = mem.cast[*Hit](ctx)
    h.store.hits[h.index] += 1u32
    ret ok
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

fn blank(w: f32, h: f32) -> widget.Node {
    ret widget.box(0u64, control.sized_style(w, h), zero)
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 12usize)
    if items_error != ok { ret (zero, items_error) }
    let (fillers, fillers_error) = mem.alloc[widget.Node](a, 8usize)
    if fillers_error != ok { ret (zero, fillers_error) }
    var i = 0usize
    while i < 8usize {
        fillers[i] = blank(20.0, 10.0)
        i += 1usize
    }
    fillers[3usize] = blank(20.0, 20.0)
    // Dividers: full and inset by 56.
    var full = control.divider_options()
    full.length = 200.0
    let (one, e1) = control.divider_of(a, 10u64, t, full)
    var inset = full
    inset.start = 56.0
    let (two, e2) = control.divider_of(a, 11u64, t, inset)
    // Cards.
    var lifted = control.card_options()
    lifted.width = 120.0
    let (three, e3) = control.card_of(a, 20u64, t, lifted, fillers[0usize..1usize])
    var filled = lifted
    filled.variant = .Filled
    filled.title = "Open"
    filled.action = &s.actions[0usize]
    let (four, e4) = control.card_of(a, 21u64, t, filled, fillers[1usize..2usize])
    var chosen = lifted
    chosen.variant = .Outlined
    chosen.selected = true
    let (five, e5) = control.card_of(a, 22u64, t, chosen, fillers[3usize..4usize])
    // Group boxes.
    var boxed = control.group_options()
    boxed.width = 200.0
    let (six, e6) = control.group_box_of(a, 30u64, t, "Build", boxed, fillers[4usize..6usize])
    var wrong = boxed
    wrong.message = "Choose one"
    let (seven, e7) = control.group_box_of(a, 31u64, t, "Targets", wrong, fillers[6usize..7usize])
    // A disclosure, open; an expander, shut; an accordion with two open.
    let (eight, e8) = control.disclosure(a, 40u64, t, "Details", true, &s.actions[1usize], widget.box(45u64, control.sized_style(20.0, 10.0), zero))
    var wide = control.disclosure_options()
    wide.width = 200.0
    let (nine, e9) = control.expander_of(a, 50u64, t, "More", false, &s.actions[2usize], wide, fillers[7usize])
    var folded = control.accordion_options()
    folded.width = 200.0
    folded.supporting = s.lines[0usize..3usize]
    let (contents, contents_error) = mem.alloc[widget.Node](a, 3usize)
    if contents_error != ok { ret (zero, contents_error) }
    contents[0usize] = blank(20.0, 10.0)
    contents[1usize] = blank(20.0, 10.0)
    contents[2usize] = blank(20.0, 10.0)
    let (ten, e10) = control.accordion_of(a, 60u64, t, "Sections", s.words[0usize..3usize], contents[0usize..3usize], s.open[0usize..3usize], s.actions[3usize..6usize], folded)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (zero, e1) }
    items[0usize] = one
    items[1usize] = two
    items[2usize] = three
    items[3usize] = four
    items[4usize] = five
    items[5usize] = six
    items[6usize] = seven
    items[7usize] = eight
    items[8usize] = nine
    items[9usize] = ten
    var page = style.defaults()
    page.width = style.Length { Px: 300.0 }
    page.height = style.Length { Px: 900.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..10usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 300usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn focused_is(h: *testing.Harness, key: widget.Key) -> bool {
    let (id, has) = testing.focused(h)
    ret has && id.slot == testing.by_key(h, key).element.slot
}

fn main(a: *mem.Arena, args: []str) -> err {
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 240usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 20u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 300u32, 900u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    var i = 0usize
    while i < 8usize {
        stores[0usize].targets[i] = Hit { store: &stores[0usize], index: i }
        stores[0usize].actions[i] = widget.Submit { ctx: mem.cast[*void](&stores[0usize].targets[i]), invoke: on_hit }
        i += 1usize
    }
    stores[0usize].words[0usize] = "Build"
    stores[0usize].words[1usize] = "Members"
    stores[0usize].words[2usize] = "Access"
    stores[0usize].lines[0usize] = ""
    stores[0usize].lines[1usize] = "4 people"
    stores[0usize].lines[2usize] = ""
    stores[0usize].open[0usize] = true
    stores[0usize].open[2usize] = true
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, &stores[0usize])
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let page = style.color(&tokens, .Background)
    let edge = style.color(&tokens, .OutlineVariant)
    let primary = style.color(&tokens, .Primary)
    // Dividers: 1px of outline-variant; the inset one starts 56 in.
    let (full, has_full) = bounds(&harness, &runtime, 10u64)
    let (inset, has_inset) = bounds(&harness, &runtime, 11u64)
    if !has_full || !has_inset || !near(full.height, 1.0) || !near(full.width, 200.0) { os.exit(12i32) }
    if !is_color(shot, at(full.x + 100.0, full.y + 0.5), edge) || !is_color(shot, at(inset.x + 30.0, inset.y + 0.5), page) || !is_color(shot, at(inset.x + 100.0, inset.y + 0.5), edge) { os.exit(13i32) }
    // Cards: 16 padding, the elevated one surface-container-low, the filled one
    // surface-container-highest, the selected one in the 2px primary outline with
    // its primary check disc 8 in from the top end.
    let (lifted, has_lifted) = bounds(&harness, &runtime, 20u64)
    let (filled, has_filled) = bounds(&harness, &runtime, 21u64)
    let (chosen, has_chosen) = bounds(&harness, &runtime, 22u64)
    if !has_lifted || !has_filled || !has_chosen || !near(lifted.width, 120.0) || !near(lifted.height, 42.0) || !near(chosen.height, 52.0) { os.exit(14i32) }
    if !is_color(shot, at(lifted.x + 60.0, lifted.y + 21.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(filled.x + 60.0, filled.y + 21.0), style.color(&tokens, .SurfaceContainerHighest)) { os.exit(15i32) }
    if !is_color(shot, at(chosen.x + 1.0, chosen.y + 26.0), primary) || !is_color(shot, at(chosen.x + 60.0, chosen.y + 26.0), page) || !is_color(shot, at(chosen.x + 120.0 - 8.0 - 21.0, chosen.y + 8.0 + 12.0), primary) { os.exit(16i32) }
    // The pressable card is a Button named by its title, and fires on a tap.
    if testing.by_label(&harness, "Open").count != 1usize || testing.by_role(&harness, .Button).count == 0usize { os.exit(17i32) }
    if testing.tap(&harness, filled.x + 60.0, filled.y + 21.0) != ok || stores[0usize].hits[0usize] != 1u32 { os.exit(18i32) }
    // Group boxes: the box 8 under the title, two 48 rows and a 1px divider in a
    // 1px outline-variant edge on surface; the invalid one's edge 2px error.
    let (group, has_group) = bounds(&harness, &runtime, 30u64)
    let (wrong, has_wrong) = bounds(&harness, &runtime, 31u64)
    if !has_group || !has_wrong || !near(group.height, 8.0 + 97.0) || !near(group.width, 200.0) { os.exit(19i32) }
    if !is_color(shot, at(group.x + 0.5, group.y + 8.0 + 24.0), edge) || !is_color(shot, at(group.x + 100.0, group.y + 8.0 + 24.0), page) || !is_color(shot, at(group.x + 100.0, group.y + 8.0 + 48.5), edge) { os.exit(20i32) }
    if !is_color(shot, at(wrong.x + 1.0, wrong.y + 8.0 + 24.0), style.color(&tokens, .Error)) || !near(wrong.height, 8.0 + 48.0 + 8.0 + 16.0) { os.exit(21i32) }
    // The disclosure: a 40 header, the content 40 in and 4 below; open, the
    // header says expanded, and Left on it (focused by the tap) shuts it.
    let (head, has_head) = bounds(&harness, &runtime, 40u64)
    let (shown, has_shown) = bounds(&harness, &runtime, 45u64)
    if !has_head || !has_shown || !near(head.height, 40.0) || !near(shown.x - head.x, 40.0) || !near(shown.y - head.y, 44.0) { os.exit(22i32) }
    if testing.tap(&harness, head.x + 10.0, head.y + 20.0) != ok || stores[0usize].hits[1usize] != 1u32 { os.exit(23i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || stores[0usize].hits[1usize] != 2u32 { os.exit(24i32) }
    // The expander: a 56 header 200 wide inside a 1px outline-variant edge.
    let (more, has_more) = bounds(&harness, &runtime, 50u64)
    if !has_more || !near(more.height, 56.0) || !near(more.width, 200.0) { os.exit(25i32) }
    if !is_color(shot, at(more.x + 0.5, more.y + 28.0), edge) { os.exit(26i32) }
    // The accordion: surface-container-low, a 48 header, the second 64 with its
    // supporting line after the first's open content and a 1px divider.
    let (first, has_first) = bounds(&harness, &runtime, 61u64)
    let (second, has_second) = bounds(&harness, &runtime, 63u64)
    let (third, has_third) = bounds(&harness, &runtime, 65u64)
    let (inside, has_inside) = bounds(&harness, &runtime, 66u64)
    if !has_first || !has_second || !has_third || !has_inside || !near(first.height, 48.0) || !near(second.height, 64.0) || !near(first.width, 200.0) { os.exit(27i32) }
    if !near(second.y - first.y, 48.0 + 26.0 + 1.0) || !near(inside.y - third.y, 48.0) || testing.by_key(&harness, 64u64).count != 0usize { os.exit(28i32) }
    if !is_color(shot, at(first.x + 100.0, first.y + 24.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(first.x + 100.0, second.y - 0.5), edge) { os.exit(29i32) }
    // A tap on the second header fires its toggle; Down moves focus to the third,
    // Home to the first.
    if testing.tap(&harness, second.x + 100.0, second.y + 32.0) != ok || stores[0usize].hits[4usize] != 1u32 { os.exit(30i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 65u64) { os.exit(31i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !focused_is(&harness, 61u64) { os.exit(32i32) }
    // Horizontal start/end insets follow reading direction: the 56px blank
    // moves from the left edge to the right edge in RTL.
    tokens.direction = .RightToLeft
    let (rtl_root, rtl_build_error) = build(&f, &theme, &stores[0usize])
    if rtl_build_error != ok { os.exit(34i32) }
    if testing.pump(&harness, rtl_root, time.Instant { nanos: 2000000000i64 }) != ok { os.exit(35i32) }
    let (rtl_shot, rtl_shot_error) = testing.snapshot(&harness, a)
    if rtl_shot_error != ok { os.exit(36i32) }
    let (rtl_inset, has_rtl_inset) = bounds(&harness, &runtime, 11u64)
    if !has_rtl_inset || !is_color(rtl_shot, at(rtl_inset.x + 30.0, rtl_inset.y + 0.5), edge) || !is_color(rtl_shot, at(rtl_inset.x + 170.0, rtl_inset.y + 0.5), page) { os.exit(37i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(33i32) }
    try io.print("ui containers v2 ok\n")
    ret ok
}
