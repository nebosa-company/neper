// The v2 badges, empty states and banners (D971, widget plan P5-09,
// docs/ux/components/Badge, EmptyState, Banner) under the light theme: counts
// 16 tall in `error`, `primary` or `surface-container-highest`, a 6 `error` dot,
// "99+", a count anchored 2 above and 12 before an icon's end and a dot 3 in from
// its corner, the anchor's name with the badge's meaning, status labels 24 tall in
// their container pairs; an empty state centred at most 360 wide with its art in
// a 72 `secondary-container` circle and a filled and a text action, the compact
// form's 48 circle and one outlined button; banners on `surface-container-low`
// with the severity in a 40 well, the standard form's actions below, a Dismiss
// close, an error an assertive alert and the rest polite, full-bleed square.

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

type Store = struct { presses: usize, press: widget.Submit, acts: [2]widget.Submit, labels: [2]str }

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.presses += 1usize
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

fn swatch(key: widget.Key, side: f32, color: paint.Color) -> widget.Node {
    var s = control.sized_style(side, side)
    s.background = paint.Brush { Solid: color }
    ret widget.box(key, s, zero)
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (c1, e1) = control.badge_of(a, 11u64, t, "3", .Urgent)
    let (c2, e2) = control.badge_of(a, 12u64, t, "7", .Emphasis)
    let (c3, e3) = control.badge_of(a, 13u64, t, "128", .Neutral)
    let (c4, e4) = control.badge_of(a, 14u64, t, "", .Dot)
    let (c5, e5) = control.badge_of(a, 21u64, t, "2", .Urgent)
    let (c6, e6) = control.badge_of(a, 31u64, t, "", .Dot)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (zero, e1) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (anchored, e7) = control.badge_anchor(a, 20u64, swatch(22u64, 24.0, muted), 24.0, c5, false)
    let (dotted, e8) = control.badge_anchor(a, 30u64, swatch(32u64, 24.0, muted), 24.0, c6, true)
    let (tag1, e9) = control.status_label(a, 40u64, t, "Passed", .Success, true)
    let (tag2, e10) = control.status_label(a, 41u64, t, "Failed", .Error, true)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (zero, e7) }
    let (marks, marks_error) = mem.alloc[widget.Node](a, 8usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = c1
    marks[1usize] = c2
    marks[2usize] = c3
    marks[3usize] = c4
    marks[4usize] = anchored
    marks[5usize] = dotted
    marks[6usize] = tag1
    marks[7usize] = tag2
    var page_empty = control.empty_options()
    page_empty.action_label = "Clear filters"
    page_empty.action = &s.press
    page_empty.other_label = "New build"
    page_empty.other = &s.press
    page_empty.width = 400.0
    let (empty1, e11) = control.empty_state_of(a, 100u64, t, "No builds match", "Try another filter.", page_empty)
    var compact = control.empty_options()
    compact.compact = true
    compact.glyph = .Check
    compact.action_label = "Refresh"
    compact.action = &s.press
    compact.other_label = "Ignored"
    compact.other = &s.press
    compact.width = 300.0
    let (empty2, e12) = control.empty_state_of(a, 200u64, t, "All caught up", "Nothing waits.", compact)
    if e11 != ok || e12 != ok { ret (zero, e11) }
    var standard = control.banner_options()
    standard.standard = true
    standard.title = "Build failed"
    let (ban1, e13) = control.banner_of(a, 400u64, t, .Error, "3 tests failed on Linux.", s.labels[0usize..2usize], s.acts[0usize..2usize], &s.press, 480.0, standard)
    var no_labels: []const str = zero
    var no_actions: []const widget.Submit = zero
    let (ban2, e14) = control.banner(a, 500u64, t, .Info, "Builds run on both hosts.", no_labels, no_actions, 480.0)
    var bleed = control.banner_options()
    bleed.full_bleed = true
    let (ban3, e15) = control.banner_of(a, 600u64, t, .Warning, "Read-only mode.", no_labels, no_actions, zero, 480.0, bleed)
    if e13 != ok || e14 != ok || e15 != ok { ret (zero, e13) }
    let (items, items_error) = mem.alloc[widget.Node](a, 6usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 16.0 }, style.defaults(), marks[0usize..8usize])
    items[1usize] = empty1
    items[2usize] = empty2
    items[3usize] = ban1
    items[4usize] = ban2
    items[5usize] = ban3
    var page = style.defaults()
    page.width = style.Length { Px: 640.0 }
    page.height = style.Length { Px: 760.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..6usize]), ok)
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

fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 760u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.press = widget.Submit { ctx: mem.cast[*void](s), invoke: on_press }
    s.acts[0usize] = s.press
    s.acts[1usize] = s.press
    s.labels[0usize] = "Retry"
    s.labels[1usize] = "View log"
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    let ground = style.color(&tokens, .Background)
    // Counts: 16 tall and at least 16 wide, in their kinds' colours; the dot 6.
    let (urgent, has_urgent) = bounds(&harness, &runtime, 11u64)
    if !has_urgent || !near(urgent.height, 16.0) || !near(urgent.width, 16.0) || !is_color(shot, at(urgent.x + 8.0, urgent.y + 8.0), style.color(&tokens, .Error)) { os.exit(13i32) }
    let (emphasis, has_emphasis) = bounds(&harness, &runtime, 12u64)
    let (neutral, has_neutral) = bounds(&harness, &runtime, 13u64)
    if !has_emphasis || !has_neutral || !is_color(shot, at(emphasis.x + 8.0, emphasis.y + 8.0), style.color(&tokens, .Primary)) || !is_color(shot, at(neutral.x + 8.0, neutral.y + 8.0), style.color(&tokens, .SurfaceContainerHighest)) { os.exit(14i32) }
    let (dot, has_dot) = bounds(&harness, &runtime, 14u64)
    if !has_dot || !near(dot.width, 6.0) || !near(dot.height, 6.0) || !is_color(shot, at(dot.x + 3.0, dot.y + 3.0), style.color(&tokens, .Error)) { os.exit(15i32) }
    let (capped, capped_error) = control.badge_count(&f, 150i64)
    let (named, named_error) = control.badge_name(&f, "Builds", "2 failed")
    if capped_error != ok || named_error != ok || !same(capped, "99+") || !same(named, "Builds, 2 failed") { os.exit(16i32) }
    // Anchored: the count 2 above the icon and 12 before its end; the dot's
    // centre 3 in from the top end corner.
    let (icon, has_icon) = bounds(&harness, &runtime, 22u64)
    let (count, has_count) = bounds(&harness, &runtime, 21u64)
    if !has_icon || !has_count || !near(count.x - icon.x, 12.0) || !near(icon.y - count.y, 2.0) { os.exit(17i32) }
    let (dot_icon, has_dot_icon) = bounds(&harness, &runtime, 32u64)
    let (corner, has_corner) = bounds(&harness, &runtime, 31u64)
    if !has_dot_icon || !has_corner || !near(corner.x + 3.0, dot_icon.x + 21.0) || !near(corner.y + 3.0, dot_icon.y + 3.0) { os.exit(18i32) }
    // Status labels: 24 tall in their container pairs.
    let (passed, has_passed) = bounds(&harness, &runtime, 40u64)
    let (failed, has_failed) = bounds(&harness, &runtime, 41u64)
    if !has_passed || !has_failed || !near(passed.height, 24.0) || !is_color(shot, at(passed.x + 2.0, passed.y + 12.0), style.color(&tokens, .SuccessContainer)) || !is_color(shot, at(failed.x + 2.0, failed.y + 12.0), style.color(&tokens, .ErrorContainer)) { os.exit(19i32) }
    // The page empty state: 360 wide centred in 400, the 72 circle 40 down, the
    // two actions; a group named by the title with the message as its hint.
    let (view, has_view) = bounds(&harness, &runtime, 100u64)
    if !has_view || !near(view.width, 400.0) { os.exit(20i32) }
    let ex = view.x + 200.0
    let ey = view.y + 40.0 + 36.0
    if !is_color(shot, at(ex, ey - 30.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(ex - 40.0, ey), ground) { os.exit(21i32) }
    let (nothing, has_nothing) = find(tree, .Group, "No builds match")
    if !has_nothing || !same(nothing.hint, "Try another filter.") { os.exit(22i32) }
    if testing.by_key(&harness, 102u64).count != 1usize || !tap_key(&harness, &runtime, 101u64) || s.presses != 1usize { os.exit(23i32) }
    // Compact: a 48 circle 24 down and one outlined button (no text alternative).
    let (small, has_small) = bounds(&harness, &runtime, 200u64)
    if !has_small { os.exit(24i32) }
    let sx = small.x + 150.0
    let sy = small.y + 24.0 + 24.0
    if !is_color(shot, at(sx, sy - 20.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(sx, sy - 26.0), ground) { os.exit(25i32) }
    if testing.by_key(&harness, 201u64).count != 1usize || testing.by_key(&harness, 202u64).count != 0usize { os.exit(26i32) }
    // The standard error banner: `surface-container-low`, the 40 well in
    // `error-container`, an assertive alert named by the title, the actions below
    // the well, Dismiss 40 and pressing.
    let (failure, has_failure) = bounds(&harness, &runtime, 400u64)
    if !has_failure || !is_color(shot, at(failure.x + 100.0, failure.y + 4.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(27i32) }
    if !is_color(shot, at(failure.x + 22.0, failure.y + 36.0), style.color(&tokens, .ErrorContainer)) { os.exit(28i32) }
    let (alert, has_alert) = find(tree, .Alert, "Build failed")
    if !has_alert || alert.live != .Assertive { os.exit(29i32) }
    let (retry, has_retry) = bounds(&harness, &runtime, 402u64)
    if !has_retry || retry.y < failure.y + 56.0 || testing.by_key(&harness, 403u64).count != 1usize { os.exit(30i32) }
    let (dismiss, has_dismiss) = bounds(&harness, &runtime, 401u64)
    if !has_dismiss || !near(dismiss.width, 40.0) || testing.by_label(&harness, "Dismiss").count != 1usize || !tap_key(&harness, &runtime, 401u64) || s.presses != 2usize { os.exit(31i32) }
    // The inline info banner: polite, the well in `primary-container`.
    let (info, has_info) = bounds(&harness, &runtime, 500u64)
    let (hosts, has_hosts) = find(tree, .Status, "Builds run on both hosts.")
    if !has_info || !has_hosts || hosts.live != .Polite || !is_color(shot, at(info.x + 22.0, info.y + 32.0), style.color(&tokens, .PrimaryContainer)) { os.exit(32i32) }
    // Full-bleed: square corners.
    let (bleed, has_bleed) = bounds(&harness, &runtime, 600u64)
    if !has_bleed || !is_color(shot, at(bleed.x + 0.5, bleed.y + 0.5), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(info.x + 0.5, info.y + 0.5), ground) { os.exit(33i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(34i32) }
    try io.print("ui status3 v2 ok\n")
    ret ok
}
