// `e.ui.widget`'s overlays (D810, widget plan P0-07): an overlay leaves the flow and
// paints at the root level over what is under it, placed below its anchor, and
// takes the presses inside it while those outside pass through; one placed to the
// right is kept inside the window; a modal overlay centres itself, takes the focus
// when it appears, bounds Tab to itself, keeps a press outside from what is under
// and fires its dismiss action instead, and gives the focus back when it goes.

use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window

type Log = struct { taps_3: usize, taps_5: usize, taps_7: usize, dismissed: usize }

fn on_3(ctx: *void, g: widget.Gesture) -> err {
    let log = mem.cast[*Log](ctx)
    if g.tag == .Tap { log.taps_3 += 1usize }
    ret ok
}

fn on_5(ctx: *void, g: widget.Gesture) -> err {
    let log = mem.cast[*Log](ctx)
    if g.tag == .Tap { log.taps_5 += 1usize }
    ret ok
}

fn on_7(ctx: *void, g: widget.Gesture) -> err {
    let log = mem.cast[*Log](ctx)
    if g.tag == .Tap { log.taps_7 += 1usize }
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dismissed += 1usize
    ret ok
}

fn sized(width: f32, height: f32, r: f32, g: f32, b: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    s.background = paint.Brush { Solid: paint.rgba(r, g, b, 1.0) }
    ret s
}

fn pointer(x: f32, y: f32) -> input.Pointer {
    ret input.Pointer { window: window.Id { slot: 0u32, generation: 0u32 }, device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: x, y: y }, buttons: 1u32, changed: .Primary }
}

fn press(runtime: *widget.Runtime, x: f32, y: f32, code: i32) {
    if widget.dispatch(runtime, input.Event { PointerDown: pointer(x, y) }) != ok { os.exit(code) }
    if widget.dispatch(runtime, input.Event { PointerUp: pointer(x, y) }) != ok { os.exit(code) }
}

fn tab() -> input.Event {
    ret input.Event { KeyDown: input.KeyEvent { window: window.Id { slot: 0u32, generation: 0u32 }, key: input.Key { physical: 9u32, logical: 9u32 }, modifiers: zero, repeat: false } }
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

// The tree: a plain box, a tap region, an overlay below the box holding a red tap
// region, an overlay to the right of the box kept inside the window, and -- when
// asked -- a modal overlay in the centre holding a green focusable region.
fn build(a: *mem.Arena, ctx: *void, with_modal: bool) -> (widget.Node, err) {
    let (popup, popup_error) = mem.alloc[widget.Node](a, 1usize)
    if popup_error != ok { ret (zero, popup_error) }
    popup[0usize] = widget.region(5u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_5 }, gestures: 1u8, enabled: true, focusable: false }, sized(30.0, 10.0, 1.0, 0.0, 0.0), zero)
    let (aside, aside_error) = mem.alloc[widget.Node](a, 1usize)
    if aside_error != ok { ret (zero, aside_error) }
    aside[0usize] = widget.box(9u64, sized(40.0, 5.0, 0.0, 0.0, 0.0), zero)
    let (dialog, dialog_error) = mem.alloc[widget.Node](a, 1usize)
    if dialog_error != ok { ret (zero, dialog_error) }
    dialog[0usize] = widget.region(7u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_7 }, gestures: 1u8, enabled: true, focusable: true }, sized(20.0, 20.0, 0.0, 1.0, 0.0), zero)
    var count = 4usize
    if with_modal { count = 5usize }
    let (children, children_error) = mem.alloc[widget.Node](a, count)
    if children_error != ok { ret (zero, children_error) }
    children[0usize] = widget.box(2u64, sized(40.0, 20.0, 0.5, 0.5, 0.5), zero)
    children[1usize] = widget.region(3u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_3 }, gestures: 1u8, enabled: true, focusable: true }, sized(40.0, 20.0, 0.0, 0.0, 1.0), zero)
    children[2usize] = widget.overlay(4u64, widget.Overlay { anchor: 2u64, placement: .Below, offset: zero, modal: false, dismiss: zero }, style.defaults(), popup[0usize..1usize])
    children[3usize] = widget.overlay(8u64, widget.Overlay { anchor: 2u64, placement: .Right, offset: zero, modal: false, dismiss: zero }, style.defaults(), aside[0usize..1usize])
    if with_modal { children[4usize] = widget.overlay(6u64, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: true, dismiss: widget.Submit { ctx: ctx, invoke: on_dismiss } }, style.defaults(), dialog[0usize..1usize]) }
    var column = style.defaults()
    column.width = style.Length { Px: 64.0 }
    column.height = style.Length { Px: 64.0 }
    ret (widget.flex(1u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, children[0usize..count]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (t, target_error) = gpu.open_target(q, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, 64u32, 64u32, .Rgba8)
    if target_error != ok { os.exit(3i32) }
    let (canvas, canvas_error) = scene.target_of(a, t)
    if canvas_error != ok { os.exit(4i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(5i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 32usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 128usize })
    if runtime_error != ok { os.exit(6i32) }
    var runtime = rt
    var log: Log = zero
    let ctx = mem.cast[*void](&log)
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(7i32) }
    var frame = mem.arena_from(frame_storage)
    let limits = ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 64.0 }
    let (root, build_error) = build(&frame, ctx, false)
    if build_error != ok { os.exit(8i32) }
    let (first_scene, first_error) = widget.reconcile(&runtime, &frame, root, limits)
    if first_error != ok { os.exit(9i32) }
    if scene.render(&renderer, first_scene, canvas, geometry.Size { width: 64.0, height: 64.0 }) != ok { os.exit(10i32) }
    let (shown, shown_error) = gpu.presented(t)
    if shown_error != ok { os.exit(11i32) }
    var pixels: [4096]u32 = zero
    if gpu.read_image(q, shown, pixels[0..]) != ok { os.exit(12i32) }
    // The popup paints over the blue region below the box: red at (5,25), blue at (35,25).
    if pixels[25usize * 64usize + 5usize] != 4278190335u32 { os.exit(13i32) }
    if pixels[25usize * 64usize + 35usize] != 4294901760u32 { os.exit(14i32) }
    let state = mem.cast[*widget.State](runtime.state)
    let (popup_id, _) = widget.find_by_key(state, 4u64)
    let (aside_id, _) = widget.find_by_key(state, 8u64)
    let (region_3, _) = widget.find_by_key(state, 3u64)
    let (popup_bounds, has_popup) = widget.overlay_bounds_of(&runtime, popup_id)
    if !has_popup || !near(popup_bounds.x, 0.0) || !near(popup_bounds.y, 20.0) || !near(popup_bounds.width, 30.0) || !near(popup_bounds.height, 10.0) { os.exit(15i32) }
    // To the right of a 40 px box a 40 px overlay would leave the window: kept at 24.
    let (aside_bounds, has_aside) = widget.overlay_bounds_of(&runtime, aside_id)
    if !has_aside || !near(aside_bounds.x, 24.0) || !near(aside_bounds.y, 0.0) { os.exit(16i32) }
    // A press inside the popup taps it, not the region under; outside, the region.
    press(&runtime, 10.0, 25.0, 17i32)
    if log.taps_5 != 1usize || log.taps_3 != 0usize { os.exit(18i32) }
    press(&runtime, 35.0, 25.0, 19i32)
    if log.taps_5 != 1usize || log.taps_3 != 1usize { os.exit(20i32) }
    let (focus_1, has_focus_1) = widget.focused(&runtime)
    if !has_focus_1 || focus_1.slot != region_3.slot { os.exit(21i32) }
    // The modal appears centred and takes the focus from the region.
    let (root_2, build_2_error) = build(&frame, ctx, true)
    if build_2_error != ok { os.exit(22i32) }
    let (second_scene, second_error) = widget.reconcile(&runtime, &frame, root_2, limits)
    if second_error != ok { os.exit(23i32) }
    let (modal_id, _) = widget.find_by_key(state, 6u64)
    let (region_7, _) = widget.find_by_key(state, 7u64)
    let (modal_bounds, has_modal) = widget.overlay_bounds_of(&runtime, modal_id)
    if !has_modal || !near(modal_bounds.x, 22.0) || !near(modal_bounds.y, 22.0) { os.exit(24i32) }
    let (focus_2, has_focus_2) = widget.focused(&runtime)
    if !has_focus_2 || focus_2.slot != region_7.slot { os.exit(25i32) }
    if scene.render(&renderer, second_scene, canvas, geometry.Size { width: 64.0, height: 64.0 }) != ok { os.exit(26i32) }
    let (shown_2, shown_2_error) = gpu.presented(t)
    if shown_2_error != ok { os.exit(27i32) }
    if gpu.read_image(q, shown_2, pixels[0..]) != ok { os.exit(28i32) }
    if pixels[30usize * 64usize + 30usize] != 4278255360u32 { os.exit(29i32) }
    // A press outside the modal -- even on the popup -- is dismissed and taps nothing;
    // inside it taps the dialog's region; Tab stays within the modal.
    press(&runtime, 10.0, 25.0, 30i32)
    if log.dismissed != 1usize || log.taps_5 != 1usize || log.taps_3 != 1usize { os.exit(31i32) }
    press(&runtime, 30.0, 30.0, 32i32)
    if log.taps_7 != 1usize { os.exit(33i32) }
    if widget.dispatch(&runtime, tab()) != ok { os.exit(34i32) }
    let (focus_3, has_focus_3) = widget.focused(&runtime)
    if !has_focus_3 || focus_3.slot != region_7.slot { os.exit(35i32) }
    // The modal goes; the focus returns to the region that had it.
    let (root_3, build_3_error) = build(&frame, ctx, false)
    if build_3_error != ok { os.exit(36i32) }
    let (third_scene, third_error) = widget.reconcile(&runtime, &frame, root_3, limits)
    if third_error != ok { os.exit(37i32) }
    let (_, modal_count) = widget.find_by_key(state, 6u64)
    if modal_count != 0usize { os.exit(38i32) }
    let (focus_4, has_focus_4) = widget.focused(&runtime)
    if !has_focus_4 || focus_4.slot != region_3.slot { os.exit(39i32) }
    press(&runtime, 10.0, 25.0, 40i32)
    if log.taps_5 != 2usize || log.dismissed != 1usize { os.exit(41i32) }
    if scene.render(&renderer, third_scene, canvas, geometry.Size { width: 64.0, height: 64.0 }) != ok { os.exit(42i32) }
    if widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(43i32) }
    try io.print("ui overlay ok\n")
    ret ok
}
