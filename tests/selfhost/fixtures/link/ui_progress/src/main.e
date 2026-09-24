// `e.ui.control`'s progress (D822, widget plan P1-09) under the light theme: a bar
// fills three tenths of its track, an indeterminate bar draws two moving segments
// and asks for another frame, and a ring at a half paints its right side in the
// primary colour and its left in the track's; all three are progress in the tree.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
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
    ret d < 0.001 && d > -0.001
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 32usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 128usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 120u32, 120u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let frame_time = time.Instant { nanos: 500000000i64 }
    if testing.begin(&harness, frame_time) != ok { os.exit(24i32) }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(7i32) }
    var frame = mem.arena_from(frame_storage)
    let (items, items_error) = mem.alloc[widget.Node](&frame, 4usize)
    if items_error != ok { os.exit(8i32) }
    let (loading, loading_error) = control.progress_bar(&frame, 1u64, &theme, "Loading", 0.3, false, 100.0)
    if loading_error != ok { os.exit(9i32) }
    items[0usize] = loading
    let (waiting, waiting_error) = control.progress_bar(&frame, 3u64, &theme, "Waiting", 0.0, true, 100.0)
    if waiting_error != ok { os.exit(10i32) }
    items[1usize] = waiting
    let (spinning, spinning_error) = control.progress_ring(&frame, 5u64, &theme, "Half", 0.5, false, 40.0)
    if spinning_error != ok { os.exit(11i32) }
    items[2usize] = spinning
    var reduced_tokens = tokens
    reduced_tokens.motion.reduced = true
    let reduced_theme = control.Theme { tokens: &reduced_tokens, fonts: fonts, language: "", runtime: &runtime }
    let (reduced, reduced_error) = control.progress_bar(&frame, 20u64, &reduced_theme, "Reduced", 0.0, true, 100.0)
    if reduced_error != ok { os.exit(25i32) }
    items[3usize] = reduced
    var column = style.defaults()
    column.width = style.Length { Px: 120.0 }
    column.height = style.Length { Px: 120.0 }
    let root = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, items[0usize..4usize])
    if testing.pump(&harness, root, frame_time) != ok { os.exit(12i32) }
    if testing.by_role(&harness, .Progress).count != 4usize {
        try io.print("progress role count\n")
        os.exit(13i32)
    }
    // The bar's fill is three tenths of the 100 px track, 4 tall (v2, D970); the
    // indeterminate bar's two segments share one clock and leave another frame due.
    let (track, has_track) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    let (fill, has_fill) = widget.bounds_of(&runtime, testing.by_key(&harness, 2u64).element)
    if !has_track || !has_fill || !near(fill.width, 30.0) || !near(fill.x, track.x) || !near(fill.height, 4.0) { os.exit(14i32) }
    let (waiting_track, has_waiting) = widget.bounds_of(&runtime, testing.by_key(&harness, 3u64).element)
    let (segment, has_segment) = widget.bounds_of(&runtime, testing.by_key(&harness, 4u64).element)
    let (second, has_second) = widget.bounds_of(&runtime, testing.by_key(&harness, 5u64).element)
    if !has_waiting || !has_segment || !has_second || !near(segment.width, 27.5) || !near(second.width, 27.5) || !near(segment.x - waiting_track.x, 1.25) || !near(second.x - waiting_track.x, 71.25) || !widget.animation_frame_requested(&runtime) { os.exit(15i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(16i32) }
    var busy = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .Progress && tree.nodes[i].state.busy { busy += 1usize }
        i += 1usize
    }
    if busy != 2usize {
        try io.print("progress busy count\n")
        os.exit(17i32)
    }
    // The ring: 40 px, its stroke 40/12 wide about 18 px from the centre; at a half the
    // right side is the primary colour and the left the secondary container (v2).
    let (ring, has_ring) = widget.bounds_of(&runtime, testing.by_key(&harness, 6u64).element)
    if !has_ring || !near(ring.width, 40.0) { os.exit(18i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(19i32) }
    let primary = style.color(&tokens, .Primary)
    let variant = style.color(&tokens, .SecondaryContainer)
    let (reduced_track, has_reduced) = widget.bounds_of(&runtime, testing.by_key(&harness, 20u64).element)
    let (reduced_first, has_reduced_first) = widget.bounds_of(&runtime, testing.by_key(&harness, 21u64).element)
    let (reduced_second, has_reduced_second) = widget.bounds_of(&runtime, testing.by_key(&harness, 22u64).element)
    if !has_reduced || !has_reduced_first || !has_reduced_second || !near(reduced_first.x - reduced_track.x, 15.0) || !near(reduced_second.x - reduced_track.x, 60.0) || !near(reduced_first.width, 25.0) {
        try io.print("reduced progress bounds\n")
        os.exit(26i32)
    }
    let reduced_at = (usize(reduced_first.y + 2.0) * 120usize + usize(reduced_first.x + 12.0)) * 4usize
    let reduced_ink = style.layer(variant, primary, 0.69)
    if !close_to(shot.pixels[reduced_at], reduced_ink.red) || !close_to(shot.pixels[reduced_at + 1usize], reduced_ink.green) || !close_to(shot.pixels[reduced_at + 2usize], reduced_ink.blue) {
        try io.print("reduced progress colour\n")
        os.exit(27i32)
    }
    let cx = usize(ring.x + 20.0)
    let cy = usize(ring.y + 20.0)
    let right = (cy * 120usize + cx + 18usize) * 4usize
    let left = (cy * 120usize + cx - 18usize) * 4usize
    if !close_to(shot.pixels[right], primary.red) || !close_to(shot.pixels[right + 2usize], primary.blue) { os.exit(20i32) }
    if !close_to(shot.pixels[left], variant.red) || !close_to(shot.pixels[left + 1usize], variant.green) { os.exit(21i32) }
    // The centre is empty: a ring, not a disc.
    if shot.pixels[(cy * 120usize + cx) * 4usize + 3usize] != 0u8 { os.exit(22i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(23i32) }
    try io.print("ui progress ok\n")
    ret ok
}
