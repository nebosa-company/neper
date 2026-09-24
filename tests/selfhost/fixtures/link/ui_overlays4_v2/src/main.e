// The v2 command palette and window switcher (D978, widget plan P5-11,
// docs/ux/components/CommandPalette, WindowSwitcher) under the light theme: the
// palette over a 32% scrim, 560 wide and top-centred 64 down on
// `surface-container-high`, its 56 field then a 1px `outline-variant` divider,
// 40 rows 4 below it and 8 in, the active one `secondary-container`, the footer
// 32 tall under another divider; Up wraps from the first row to the last, Enter
// runs, typing reaches the caller; with no match, the empty state; the
// switcher's list form 480 wide and 64 down with no scrim, its rows 4 in from
// the top, Down and Up moving (and wrapping), Escape dismissing.

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
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { activations: usize, active: usize, runs: usize, ran: usize, typed: usize, dismisses: usize }

type Which = enum u8 { Palette, Empty, Switcher }

fn on_activate(ctx: *void, index: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.activations += 1usize
    log.active = index
    ret ok
}

fn on_run(ctx: *void, index: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.runs += 1usize
    log.ran = index
    ret ok
}

fn on_typed(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.typed = value.len
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dismisses += 1usize
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

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, dismiss: *const widget.Submit, buffer: []u8, which: Which, active: usize) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize)
    if items_error != ok { ret (zero, items_error) }
    var names: [3]str = zero
    names[0usize] = "Build"
    names[1usize] = "Test"
    names[2usize] = "Deploy"
    var shown: []const str = names[..]
    if which == .Empty { shown = names[0usize..0usize] }
    let activate = widget.Change[usize] { ctx: ctx, invoke: on_activate }
    let run = widget.Change[usize] { ctx: ctx, invoke: on_run }
    let (palette, e1) = navigation.command_palette(a, 100u64, t, "Commands", buffer, 0usize, widget.Change[str] { ctx: ctx, invoke: on_typed }, shown, active, which != .Switcher, activate, run, dismiss, 560.0)
    let (switcher, e2) = navigation.window_switcher(a, 200u64, t, "Windows", names[..], active, which == .Switcher, activate, run, dismiss, 480.0)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    items[0usize] = palette
    items[1usize] = switcher
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 640.0 }
    page_style.height = style.Length { Px: 480.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page_style, items[0usize..2usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 640usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn lifted(h: *testing.Harness, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = testing.overlay_of(h, testing.by_key(h, key).element)
    ret (b, found)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 800usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 40u16, max_commands: 8192usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 480u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (subs, subs_error) = mem.alloc[widget.Submit](a, 1usize)
    if subs_error != ok { os.exit(8i32) }
    subs[0usize] = widget.Submit { ctx: ctx, invoke: on_dismiss }
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { os.exit(9i32) }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(10i32) }
    var f = mem.arena_from(frame_storage)
    let page = style.color(&tokens, .Background)
    let dimmed = style.layer(page, style.color(&tokens, .Scrim), tokens.states.scrim)
    let high = style.color(&tokens, .SurfaceContainerHigh)
    // The palette, Test active: 560 wide, centred, 64 down over the scrim.
    let (root, build_error) = build(&f, &theme, ctx, &subs[0usize], buffer, .Palette, 1usize)
    if build_error != ok || testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(11i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(12i32) }
    let (panel, has_panel) = lifted(&harness, 100u64)
    if !has_panel || !near(panel.x, 40.0) || !near(panel.y, 64.0) || !near(panel.width, 560.0) { os.exit(13i32) }
    if !is_color(shot, at(5.0, 5.0), dimmed) || !is_color(shot, at(panel.x + 280.0, panel.y + 28.0), high) { os.exit(14i32) }
    // The divider under the 56 field; the rows 4 below it, 8 in, 40 tall; the
    // active one `secondary-container`; the footer's divider after the 8 below
    // the rows, then 32.
    if !is_color(shot, at(panel.x + 280.0, panel.y + 56.5), style.color(&tokens, .OutlineVariant)) { os.exit(15i32) }
    let (build_row, has_build_row) = bounds(&harness, &runtime, 103u64)
    let (test_row, has_test_row) = bounds(&harness, &runtime, 104u64)
    if !has_build_row || !has_test_row || !near(build_row.y, panel.y + 61.0) || !near(build_row.x, panel.x + 8.0) || !near(build_row.height, 40.0) || !near(test_row.y, build_row.y + 40.0) { os.exit(16i32) }
    if !is_color(shot, at(test_row.x + 20.0, test_row.y + 20.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(build_row.x + 20.0, build_row.y + 20.0), high) { os.exit(17i32) }
    if !is_color(shot, at(panel.x + 280.0, panel.y + 189.5), style.color(&tokens, .OutlineVariant)) || !near(panel.height, 222.0) { os.exit(18i32) }
    // The tree: a modal dialog, a text field, three list items with Test selected.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(19i32) }
    let (dialog, has_dialog) = find(tree, .Dialog, "Commands")
    let (test_node, has_test_node) = find(tree, .ListItem, "Test")
    if !has_dialog || !dialog.state.modal || testing.by_role(&harness, .TextField).count != 1usize || !has_test_node || !test_node.state.selected || testing.by_text(&harness, "Type a command").count != 1usize { os.exit(20i32) }
    // Typing reaches the caller; Down activates Deploy; Enter runs Test.
    if testing.type_text(&harness, "de") != ok || logs[0usize].typed != 2usize { os.exit(21i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || logs[0usize].active != 2usize { os.exit(22i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].runs != 1usize || logs[0usize].ran != 1usize { os.exit(23i32) }
    // From the first row, Up wraps to the last.
    let (root_2, build_2_error) = build(&f, &theme, ctx, &subs[0usize], buffer, .Palette, 0usize)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(24i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || logs[0usize].active != 2usize || logs[0usize].activations != 2usize { os.exit(25i32) }
    // With no match: the empty state, 24 above and below (142 in all).
    let (root_3, build_3_error) = build(&f, &theme, ctx, &subs[0usize], buffer, .Empty, 0usize)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(26i32) }
    let (empty, has_empty) = lifted(&harness, 100u64)
    if !has_empty || !near(empty.height, 142.0) || testing.by_text(&harness, "No matching commands").count != 1usize { os.exit(27i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].dismisses != 1usize { os.exit(28i32) }
    // The switcher's list form: 480 wide, 64 down, no scrim; rows 4 and 8 in;
    // Down moves on, Up from the first wraps, Escape dismisses.
    let (root_4, build_4_error) = build(&f, &theme, ctx, &subs[0usize], buffer, .Switcher, 0usize)
    if build_4_error != ok || testing.pump(&harness, root_4, time.Instant { nanos: 1300000000i64 }) != ok { os.exit(29i32) }
    let (shot_4, shot_4_error) = testing.snapshot(&harness, a)
    if shot_4_error != ok { os.exit(30i32) }
    let (list, has_list) = lifted(&harness, 200u64)
    let (first_row, has_first_row) = bounds(&harness, &runtime, 202u64)
    if !has_list || !has_first_row || !near(list.x, 80.0) || !near(list.y, 64.0) || !near(list.height, 128.0) || !near(first_row.y, list.y + 4.0) || !near(first_row.x, list.x + 8.0) { os.exit(31i32) }
    if !is_color(shot_4, at(5.0, 5.0), page) || !is_color(shot_4, at(first_row.x + 20.0, first_row.y + 20.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot_4, at(list.x + 240.0, list.y + 2.0), high) { os.exit(32i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || logs[0usize].active != 1usize { os.exit(33i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || logs[0usize].active != 2usize { os.exit(34i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].dismisses != 2usize { os.exit(35i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(36i32) }
    try io.print("ui overlays4 v2 ok\n")
    ret ok
}
