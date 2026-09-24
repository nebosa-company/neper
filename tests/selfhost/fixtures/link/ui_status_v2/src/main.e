// The v2 meters (D970, widget plan P5-09, docs/ux/components/ProgressBar,
// ProgressRing, Gauge, Level) under the light theme at pointer density: a 4 tall
// progress bar whose indicator stands 4 clear of the `secondary-container` track
// with a `primary` stop dot at its end (2 in on the 8 thick bar), the buffered
// segment `primary` 32% over the track, the error tone in `error`; rings whose
// round-capped `primary` arc keeps a gap clear of the track, the percent inside at
// 64, no track when indeterminate; a 270-degree gauge with the warning band and a
// `warning` arc past the threshold; levels whose fill stands 4 clear of the
// `surface-container-highest` rest, with the limit mark, a 4 minimum fill, the
// error fill past danger, segments and rising bars.

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

fn build(a: *mem.Arena, t: *const control.Theme) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 16usize)
    if items_error != ok { ret (zero, items_error) }
    var thick = control.progress_options()
    thick.thick = true
    var buffered = control.progress_options()
    buffered.buffer = 0.6
    var failed = control.progress_options()
    failed.tone = .Error
    let (b1, e1) = control.progress_bar(a, 100u64, t, "Upload", 0.3, false, 200.0)
    let (b2, e2) = control.progress_bar_of(a, 110u64, t, "Import", 0.3, false, 200.0, thick)
    let (b3, e3) = control.progress_bar_of(a, 120u64, t, "Play", 0.3, false, 200.0, buffered)
    let (b4, e4) = control.progress_bar_of(a, 130u64, t, "Sync", 0.3, false, 200.0, failed)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (zero, e1) }
    let (r1, e5) = control.progress_ring(a, 200u64, t, "Tests", 0.25, false, 48.0)
    let (r2, e6) = control.progress_ring(a, 210u64, t, "Setup", 0.25, false, 64.0)
    let (r3, e7) = control.progress_ring(a, 220u64, t, "Loading", 0.0, true, 48.0)
    if e5 != ok || e6 != ok || e7 != ok { ret (zero, e5) }
    let (rings, rings_error) = mem.alloc[widget.Node](a, 3usize)
    if rings_error != ok { ret (zero, rings_error) }
    rings[0usize] = r1
    rings[1usize] = r2
    rings[2usize] = r3
    var limits = control.gauge_options()
    limits.warn = 0.8
    limits.critical = 0.95
    limits.unit = "% of 32 GB"
    let (g1, e8) = control.gauge_of(a, 300u64, t, "Memory", 85.0, 0.0, 100.0, 160.0, limits)
    if e8 != ok { ret (zero, e8) }
    var limited = control.level_options()
    limited.limit = true
    limited.value_text = "30 of 100 GB"
    limited.status = "70 GB free"
    let (l1, e9) = control.level_of(a, 400u64, t, "Storage", 30.0, 0.0, 100.0, 0.8, 0.95, 200.0, limited)
    let (l2, e10) = control.level(a, 410u64, t, "Quota", 96.0, 0.0, 100.0, 0.8, 0.95, 200.0)
    let (l3, e11) = control.level(a, 420u64, t, "Cache", 1.0, 0.0, 100.0, 0.8, 0.95, 200.0)
    var segmented = control.level_options()
    segmented.segments = 4u32
    segmented.status = "Fair"
    let (l4, e12) = control.level_of(a, 430u64, t, "Strength", 2.0, 0.0, 4.0, 2.0, 2.0, 200.0, segmented)
    var bars = control.level_options()
    bars.bars = true
    let (l5, e13) = control.level_of(a, 440u64, t, "Signal", 4.0, 0.0, 4.0, 2.0, 2.0, 200.0, bars)
    var small = control.level_options()
    small.small = true
    let (l6, e14) = control.level_of(a, 450u64, t, "Row", 50.0, 0.0, 100.0, 0.8, 0.95, 160.0, small)
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret (zero, e9) }
    items[0usize] = b1
    items[1usize] = b2
    items[2usize] = b3
    items[3usize] = b4
    items[4usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 16.0 }, style.defaults(), rings[0usize..3usize])
    items[5usize] = g1
    items[6usize] = l1
    items[7usize] = l2
    items[8usize] = l3
    items[9usize] = l4
    items[10usize] = l5
    items[11usize] = l6
    var page = style.defaults()
    page.width = style.Length { Px: 640.0 }
    page.height = style.Length { Px: 660.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..12usize]), ok)
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

fn find(tree: accessibility.Tree, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .Progress && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
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
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 660u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(7i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme)
    if build_error != ok { os.exit(8i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(9i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(10i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(11i32) }
    let primary = style.color(&tokens, .Primary)
    let track = style.color(&tokens, .SecondaryContainer)
    let ground = style.color(&tokens, .Background)
    let rest = style.color(&tokens, .SurfaceContainerHighest)
    // The bar: a 60 wide, 4 tall indicator, 4 clear of the track, the stop dot at
    // the end; the value is the percent.
    let (fill, has_fill) = bounds(&harness, &runtime, 101u64)
    if !has_fill || !near(fill.width, 60.0) || !near(fill.height, 4.0) { os.exit(12i32) }
    let mid = fill.y + 2.0
    if !is_color(shot, at(fill.x + 30.0, mid), primary) || !is_color(shot, at(fill.x + 62.0, mid), ground) || !is_color(shot, at(fill.x + 80.0, mid), track) { os.exit(13i32) }
    if !is_color(shot, at(fill.x + 197.5, mid), primary) || !is_color(shot, at(fill.x + 190.0, mid), track) { os.exit(14i32) }
    let (upload, has_upload) = find(tree, "Upload")
    if !has_upload || !same(upload.value, "30%") { os.exit(15i32) }
    // Thick: 8 tall, the stop dot 2 in from the end.
    let (thick, has_thick) = bounds(&harness, &runtime, 111u64)
    if !has_thick || !near(thick.height, 8.0) { os.exit(16i32) }
    if !is_color(shot, at(thick.x + 196.0, thick.y + 4.0), primary) || !is_color(shot, at(thick.x + 199.0, thick.y + 4.0), track) { os.exit(17i32) }
    // Buffer: the buffered segment between the indicator and the track.
    let (played, has_played) = bounds(&harness, &runtime, 121u64)
    if !has_played || !is_color(shot, at(played.x + 90.0, played.y + 2.0), style.layer(track, primary, 0.32)) || !is_color(shot, at(played.x + 150.0, played.y + 2.0), track) { os.exit(18i32) }
    // Error: `error` on `error-container`.
    let (broken, has_broken) = bounds(&harness, &runtime, 131u64)
    if !has_broken || !is_color(shot, at(broken.x + 30.0, broken.y + 2.0), style.color(&tokens, .Error)) || !is_color(shot, at(broken.x + 100.0, broken.y + 2.0), style.color(&tokens, .ErrorContainer)) { os.exit(19i32) }
    // The 48 ring at a quarter: the arc at 45 degrees, the track at the bottom, the
    // gap clear just past the arc's end (stroke 4, radius 22).
    let (ring, has_ring) = bounds(&harness, &runtime, 201u64)
    if !has_ring || !near(ring.width, 48.0) { os.exit(20i32) }
    let cx = ring.x + 24.0
    let cy = ring.y + 24.0
    if !is_color(shot, at(cx + 15.5, cy - 15.5), primary) || !is_color(shot, at(cx, cy + 22.0), track) { os.exit(21i32) }
    if !is_color(shot, at(cx + 21.6, cy + 4.2), ground) { os.exit(22i32) }
    // 64: the percent inside. Indeterminate: busy, a quarter arc, no track.
    let (setup, has_setup) = find(tree, "Setup")
    if !has_setup || !same(setup.value, "25%") || testing.by_text(&harness, "25%").count != 1usize { os.exit(23i32) }
    let (spinner, has_spinner) = bounds(&harness, &runtime, 221u64)
    let (loading, has_loading) = find(tree, "Loading")
    if !has_spinner || !has_loading || !loading.state.busy { os.exit(24i32) }
    if !is_color(shot, at(spinner.x + 24.0 + 15.5, spinner.y + 24.0 - 15.5), primary) || !is_color(shot, at(spinner.x + 24.0, spinner.y + 46.0), ground) { os.exit(25i32) }
    // The gauge: radius 64 (40% of 160), stroke 16; at 85 past the 80 threshold the
    // arc is `warning` through the top, the band `warning-container` beyond the
    // value, and the bottom open.
    let (dial, has_dial) = bounds(&harness, &runtime, 301u64)
    if !has_dial || !near(dial.width, 144.0) { os.exit(26i32) }
    let gx = dial.x + 72.0
    let gy = dial.y + 72.0
    if !is_color(shot, at(gx, gy - 64.0), style.color(&tokens, .Warning)) { os.exit(27i32) }
    // At 0.9 of the sweep: 108 degrees clockwise from the top.
    if !is_color(shot, at(gx + 60.9, gy + 19.8), style.color(&tokens, .WarningContainer)) || !is_color(shot, at(gx, gy + 64.0), ground) { os.exit(28i32) }
    let (memory, has_memory) = find(tree, "Memory")
    if !has_memory || !same(memory.value, "85") || !same(memory.hint, "High") || testing.by_text(&harness, "High").count != 1usize || testing.by_text(&harness, "% of 32 GB").count != 1usize { os.exit(29i32) }
    // The level: the fill 60 wide, 4 clear of the rest, the limit mark at 160
    // standing above the bar; the value text and status.
    let (stored, has_stored) = bounds(&harness, &runtime, 401u64)
    if !has_stored || !near(stored.width, 60.0) || !near(stored.height, 8.0) { os.exit(30i32) }
    if !is_color(shot, at(stored.x + 30.0, stored.y + 4.0), primary) || !is_color(shot, at(stored.x + 62.0, stored.y + 4.0), ground) || !is_color(shot, at(stored.x + 100.0, stored.y + 4.0), rest) { os.exit(31i32) }
    if !is_color(shot, at(stored.x + 160.0, stored.y - 3.0), style.color(&tokens, .OnSurfaceVariant)) { os.exit(32i32) }
    let (storage, has_storage) = find(tree, "Storage")
    if !has_storage || !same(storage.value, "30 of 100 GB") || !same(storage.hint, "70 GB free") { os.exit(33i32) }
    // Past danger the fill is `error` and the level invalid; a small use keeps 4.
    let (quota_fill, has_quota) = bounds(&harness, &runtime, 411u64)
    let (quota, has_quota_node) = find(tree, "Quota")
    if !has_quota || !has_quota_node || !quota.state.invalid || !is_color(shot, at(quota_fill.x + 50.0, quota_fill.y + 4.0), style.color(&tokens, .Error)) { os.exit(34i32) }
    let (cache, has_cache) = bounds(&harness, &runtime, 421u64)
    if !has_cache || !near(cache.width, 4.0) { os.exit(35i32) }
    // Segmented: two of four lit in `warning`; bars: all four lit in `success`, 18 tall.
    let (segments, has_segments) = bounds(&harness, &runtime, 431u64)
    if !has_segments || !near(segments.width, 140.0) || !is_color(shot, at(segments.x + 16.0, segments.y + 3.0), style.color(&tokens, .Warning)) || !is_color(shot, at(segments.x + 88.0, segments.y + 3.0), rest) { os.exit(36i32) }
    let (signal, has_signal) = bounds(&harness, &runtime, 441u64)
    if !has_signal || !near(signal.height, 18.0) || !near(signal.width, 36.0) || !is_color(shot, at(signal.x + 33.0, signal.y + 2.0), style.color(&tokens, .Success)) { os.exit(37i32) }
    // Small: 4 tall.
    let (row, has_row) = bounds(&harness, &runtime, 451u64)
    if !has_row || !near(row.height, 4.0) || !near(row.width, 80.0) { os.exit(38i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(39i32) }
    try io.print("ui status v2 ok\n")
    ret ok
}
