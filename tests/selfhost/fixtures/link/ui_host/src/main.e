// `e.ui.window`'s host capability model (D811, widget plan P0-08): a desktop window
// reports a hovering fine pointer, a keyboard, no touch, its resizability and no
// insets; the safe and keyboard insets are none; the orientation follows the size;
// the screens come in logical pixels with a primary; the lifecycle follows the
// window's focus and visibility; `style.adapt` over the capabilities keeps the
// desktop metrics; and the lifecycle, insets and back events reach the widgets --
// back as Escape, the scope's cancel action. A host without windows says so.

use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.scene
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window

type Log = struct { cancels: usize }

fn on_cancel(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.cancels += 1usize
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let options = window.Options { title: "neper ui_host", width: 320u32, height: 200u32, min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: .Windowed }
    let (w, window_error) = window.open(a, device, options)
    if window_error == window.Unsupported {
        try io.print("ui host unsupported\n")
        ret ok
    }
    if window_error != ok { os.exit(2i32) }
    var win = w
    // Capabilities and insets of a desktop host.
    let (caps, caps_error) = window.capabilities(&win)
    if caps_error != ok || !caps.hover || !caps.fine_pointer || !caps.keyboard || caps.touch || caps.pen || caps.resizable || !caps.multi_window { os.exit(3i32) }
    if !near(caps.insets.top, 0.0) || !near(caps.insets.bottom, 0.0) { os.exit(4i32) }
    let (safe, safe_error) = window.safe_insets(&win)
    if safe_error != ok || !near(safe.left, 0.0) || !near(safe.right, 0.0) { os.exit(5i32) }
    let (keyboard, keyboard_error) = window.keyboard_insets(&win)
    if keyboard_error != ok || !near(keyboard.bottom, 0.0) { os.exit(6i32) }
    // Orientation from the size, the screens in logical pixels, the lifecycle from
    // the focus and visibility.
    let (facing, facing_error) = window.orientation(&win)
    if facing_error != ok || facing != .Landscape { os.exit(7i32) }
    let (found, screens_error) = window.screens(a, 4usize)
    if screens_error != ok || found.len == 0usize { os.exit(8i32) }
    var primaries = 0usize
    var i = 0usize
    while i < found.len {
        let s = found[i]
        if s.primary { primaries += 1usize }
        if !(s.bounds.width > 0.0) || !(s.bounds.height > 0.0) || !(s.scale > 0.0) { os.exit(9i32) }
        if !near(s.work_area.width, s.bounds.width) { os.exit(10i32) }
        i += 1usize
    }
    if primaries != 1usize { os.exit(11i32) }
    let (m, metrics_error) = window.metrics(&win)
    if metrics_error != ok { os.exit(12i32) }
    let (stage, stage_error) = window.lifecycle(&win)
    if stage_error != ok { os.exit(13i32) }
    var expected: window.Lifecycle = .Background
    if m.visible && !m.focused { expected = .Inactive }
    if m.visible && m.focused { expected = .Active }
    if stage != expected { os.exit(14i32) }
    // The theme adapted to this host keeps the desktop metrics.
    let light = style.reference(.Light)
    let adapted = style.adapt(&light, style.Adaptation { size: .Expanded, capabilities: caps, profile: .Neper })
    if !near(adapted.metrics.hit_target, light.metrics.hit_target) || !near(adapted.spacing.md, light.spacing.md) { os.exit(15i32) }
    // The events reach the widgets: lifecycle and insets are taken quietly, back
    // fires the scope's cancel action.
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(16i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 2u32, 2u32)
    if renderer_error != ok { os.exit(17i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 8usize, max_states: 4usize, state_bytes: 64usize, state_classes: 1u16, max_depth: 4u16, max_commands: 16usize })
    if runtime_error != ok { os.exit(18i32) }
    var runtime = rt
    var log: Log = zero
    var scope_style = style.defaults()
    scope_style.width = style.Length { Px: 32.0 }
    scope_style.height = style.Length { Px: 32.0 }
    let root = widget.scope(1u64, widget.Scope { traps_focus: false, shortcuts: zero, default_action: zero, cancel_action: widget.Submit { ctx: mem.cast[*void](&log), invoke: on_cancel }, keys: zero }, scope_style, zero)
    let (frame_storage, storage_error) = mem.alloc[u8](a, 65536usize)
    if storage_error != ok { os.exit(19i32) }
    var frame = mem.arena_from(frame_storage)
    let (compiled, reconcile_error) = widget.reconcile(&runtime, &frame, root, ui_layout.Constraints { min_width: 0.0, max_width: 32.0, min_height: 0.0, max_height: 32.0 })
    if reconcile_error != ok { os.exit(20i32) }
    if widget.dispatch(&runtime, input.Event { Lifecycle: input.LifecycleEvent { window: win.id, state: .Inactive } }) != ok { os.exit(21i32) }
    if widget.dispatch(&runtime, input.Event { Insets: input.InsetsEvent { window: win.id, safe: safe, keyboard: keyboard } }) != ok { os.exit(22i32) }
    if widget.dispatch(&runtime, input.Event { Back: win.id }) != ok || log.cancels != 1usize { os.exit(23i32) }
    if widget.close(&runtime) != ok || scene.close(&renderer) != ok { os.exit(24i32) }
    if window.close(&win) != ok || gpu.close(device) != ok { os.exit(25i32) }
    try io.print("ui host ok\n")
    ret ok
}
