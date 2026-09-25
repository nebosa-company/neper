// Typed actions, gesture regions and scopes (D806, widget plan P0-02/P0-03): a tap
// and a drag settled by the arena from the raw pointer events, hover entering and
// leaving, a press past the slop on a tap-only region released, focus travelling by
// Tab within a trapping scope and wrapping, a shortcut, Enter and Escape reaching
// the scope's actions from the focused element, and typed change and submit
// actions firing or staying quiet when unset.

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

type Log = struct { taps: usize, double_taps: usize, drag_starts: usize, drag_moves: usize, drag_ends: usize, hovers: usize, hover_ends: usize, last_x: f32, submits: usize, cancels: usize, saves: usize, changes: usize, last_value: i32 }

fn on_gesture(ctx: *void, g: widget.Gesture) -> err {
    let log = mem.cast[*Log](ctx)
    switch g {
    case .Tap as p:
        log.taps += 1usize
        log.last_x = p.x
    case .DoubleTap as p:
        log.double_taps += 1usize
        log.last_x = p.x
    case .DragStart as p:
        log.drag_starts += 1usize
    case .DragMove as d:
        log.drag_moves += 1usize
        log.last_x = d.position.x
    case .DragEnd as p:
        log.drag_ends += 1usize
    case .Hover as p:
        log.hovers += 1usize
    case .HoverEnd:
        log.hover_ends += 1usize
    case .Drop as d:
        log.taps += 0usize
    }
    ret ok
}

fn on_submit(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.submits += 1usize
    ret ok
}

fn on_cancel(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.cancels += 1usize
    ret ok
}

fn on_save(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.saves += 1usize
    ret ok
}

fn on_change(ctx: *void, value: i32) -> err {
    let log = mem.cast[*Log](ctx)
    log.changes += 1usize
    log.last_value = value
    ret ok
}

fn sized(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    ret s
}

fn pointer(x: f32, y: f32) -> input.Pointer {
    ret input.Pointer { window: window.Id { slot: 0u32, generation: 0u32 }, device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: x, y: y }, buttons: 1u32, changed: .Primary }
}

fn key(code: u32, shift: bool, control: bool) -> input.Event {
    ret input.Event { KeyDown: input.KeyEvent { window: window.Id { slot: 0u32, generation: 0u32 }, key: input.Key { physical: code, logical: code }, modifiers: input.Modifiers { shift: shift, control: control, alt: false, meta: false, caps_lock: false, num_lock: false }, repeat: false } }
}

fn key_up(code: u32) -> input.Event {
    ret input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: code, logical: code }, modifiers: zero, repeat: false } }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 2u32, 2u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 32usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 64usize })
    if runtime_error != ok { os.exit(4i32) }
    var runtime = rt
    var log: Log = zero
    let ctx = mem.cast[*void](&log)
    // A trapping scope with a Ctrl+S shortcut, Enter and Escape actions, holding a
    // tap region (0..40 x 0..20), a drag+hover region (0..40 x 30..50) and a focusable
    // tap region (0..40 x 60..80).
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 1usize)
    if shortcuts_error != ok { os.exit(5i32) }
    shortcuts[0usize] = widget.Shortcut { key: 83u32, modifiers: input.Modifiers { shift: false, control: true, alt: false, meta: false, caps_lock: false, num_lock: false }, action: widget.Submit { ctx: ctx, invoke: on_save } }
    let (children, children_error) = mem.alloc[widget.Node](a, 3usize)
    if children_error != ok { os.exit(6i32) }
    children[0usize] = widget.region(1u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_gesture }, gestures: 1u8, enabled: true, focusable: true }, sized(40.0, 20.0), zero)
    children[1usize] = widget.region(2u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_gesture }, gestures: 2u8 | 4u8, enabled: true, focusable: false }, sized(40.0, 20.0), zero)
    children[2usize] = widget.region(3u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_gesture }, gestures: 1u8, enabled: true, focusable: true }, sized(40.0, 20.0), zero)
    var column = style.defaults()
    column.width = style.Length { Px: 64.0 }
    column.height = style.Length { Px: 100.0 }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { os.exit(7i32) }
    column_node[0usize] = widget.flex(4u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 10.0 }, column, children[0usize..3usize])
    let root = widget.scope(5u64, widget.Scope { traps_focus: true, shortcuts: shortcuts[0usize..1usize], default_action: widget.Submit { ctx: ctx, invoke: on_submit }, cancel_action: widget.Submit { ctx: ctx, invoke: on_cancel }, keys: zero }, sized(64.0, 100.0), column_node[0usize..1usize])
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(8i32) }
    var frame = mem.arena_from(frame_storage)
    let (compiled, reconcile_error) = widget.reconcile(&runtime, &frame, root, ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 100.0 })
    if reconcile_error != ok { os.exit(9i32) }
    // Physical modifier transitions are shared with pointer gesture callbacks;
    // X keysyms normalize to the same held state as Windows virtual keys.
    if widget.dispatch(&runtime, key(65505u32, false, false)) != ok || !widget.modifiers(&runtime).shift { os.exit(49i32) }
    if widget.dispatch(&runtime, key_up(65505u32)) != ok || widget.modifiers(&runtime).shift { os.exit(50i32) }
    // A tap: down and up inside the first region; it takes the focus.
    if widget.dispatch(&runtime, input.Event { PointerDown: pointer(10.0, 10.0) }) != ok { os.exit(10i32) }
    if widget.dispatch(&runtime, input.Event { PointerUp: pointer(12.0, 11.0) }) != ok { os.exit(11i32) }
    if log.taps != 1usize || log.last_x != 12.0 { os.exit(12i32) }
    let (focus_now, has_focus) = widget.focused(&runtime)
    let (first_id, first_count) = widget.find_by_key(mem.cast[*widget.State](runtime.state), 1u64)
    if !has_focus || first_count != 1usize || focus_now.slot != first_id.slot { os.exit(13i32) }
    // The next tap in the same region is still a Tap and additionally completes
    // one DoubleTap pair.
    if widget.dispatch(&runtime, input.Event { PointerDown: pointer(10.0, 10.0) }) != ok || widget.dispatch(&runtime, input.Event { PointerUp: pointer(12.0, 11.0) }) != ok { os.exit(47i32) }
    if log.taps != 2usize || log.double_taps != 1usize || log.last_x != 12.0 { os.exit(48i32) }
    // A press that wanders past the slop on a tap-only region is not a tap.
    if widget.dispatch(&runtime, input.Event { PointerDown: pointer(10.0, 10.0) }) != ok { os.exit(14i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(30.0, 12.0) }) != ok { os.exit(15i32) }
    if widget.dispatch(&runtime, input.Event { PointerUp: pointer(30.0, 12.0) }) != ok { os.exit(16i32) }
    if log.taps != 2usize || log.drag_starts != 0usize { os.exit(17i32) }
    // A drag on the second region: start once past the slop, moves after, an end.
    if widget.dispatch(&runtime, input.Event { PointerDown: pointer(5.0, 35.0) }) != ok { os.exit(18i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(8.0, 36.0) }) != ok { os.exit(19i32) }
    if log.drag_starts != 0usize { os.exit(20i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(20.0, 36.0) }) != ok { os.exit(21i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(30.0, 37.0) }) != ok { os.exit(22i32) }
    if widget.dispatch(&runtime, input.Event { PointerUp: pointer(31.0, 37.0) }) != ok { os.exit(23i32) }
    if log.drag_starts != 1usize || log.drag_moves != 1usize || log.drag_ends != 1usize || log.last_x != 30.0 { os.exit(24i32) }
    // Hover: moving over the second region enters it, moving off leaves it.
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(20.0, 40.0) }) != ok { os.exit(25i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(22.0, 41.0) }) != ok { os.exit(26i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(50.0, 41.0) }) != ok { os.exit(27i32) }
    if log.hovers != 2usize || log.hover_ends != 1usize { os.exit(28i32) }
    // Focus: Tab from the first region reaches the third (the second is not
    // focusable), Tab again wraps within the trapping scope, Shift+Tab goes back.
    if widget.dispatch(&runtime, input.Event { PointerDown: pointer(10.0, 10.0) }) != ok || widget.dispatch(&runtime, input.Event { PointerUp: pointer(10.0, 10.0) }) != ok { os.exit(29i32) }
    if widget.dispatch(&runtime, key(9u32, false, false)) != ok { os.exit(30i32) }
    let (third_id, third_count) = widget.find_by_key(mem.cast[*widget.State](runtime.state), 3u64)
    let (after_tab, tab_focus) = widget.focused(&runtime)
    if !tab_focus || third_count != 1usize || after_tab.slot != third_id.slot { os.exit(31i32) }
    if widget.dispatch(&runtime, key(9u32, false, false)) != ok { os.exit(32i32) }
    let (wrapped, wrap_focus) = widget.focused(&runtime)
    if !wrap_focus || wrapped.slot != first_id.slot { os.exit(33i32) }
    if widget.dispatch(&runtime, key(9u32, true, false)) != ok { os.exit(34i32) }
    let (back, back_focus) = widget.focused(&runtime)
    if !back_focus || back.slot != third_id.slot { os.exit(35i32) }
    // Shortcuts and the two actions, from the focused element up to the scope.
    if widget.dispatch(&runtime, key(83u32, false, true)) != ok || log.saves != 1usize { os.exit(36i32) }
    if widget.dispatch(&runtime, key(83u32, false, false)) != ok || log.saves != 1usize { os.exit(37i32) }
    // Enter and Space on the focused tap region tap it (D818); with the focus on
    // the scope itself, Enter is its default action.
    if widget.dispatch(&runtime, key(13u32, false, false)) != ok || log.taps != 4usize || log.submits != 0usize { os.exit(38i32) }
    if widget.dispatch(&runtime, key(32u32, false, false)) != ok || log.taps != 5usize { os.exit(44i32) }
    let (scope_id, scope_count) = widget.find_by_key(mem.cast[*widget.State](runtime.state), 5u64)
    if scope_count != 1usize || widget.focus(&runtime, scope_id) != ok { os.exit(45i32) }
    if widget.dispatch(&runtime, key(13u32, false, false)) != ok || log.submits != 1usize { os.exit(46i32) }
    if widget.dispatch(&runtime, key(27u32, false, false)) != ok || log.cancels != 1usize { os.exit(39i32) }
    // Typed actions: a change carries its value; an unset one is quiet.
    let change = widget.Change[i32] { ctx: ctx, invoke: on_change }
    if widget.fire_change[i32](change, 42i32) != ok || log.changes != 1usize || log.last_value != 42i32 { os.exit(40i32) }
    var unset: widget.Change[i32] = zero
    if widget.fire_change[i32](unset, 7i32) != ok || log.changes != 1usize { os.exit(41i32) }
    var quiet: widget.Submit = zero
    if widget.fire_submit(quiet) != ok { os.exit(42i32) }
    if widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(43i32) }
    try io.print("ui gesture ok\n")
    ret ok
}
