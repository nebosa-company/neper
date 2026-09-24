// `e.ui.control`'s feedback and disclosure (D832, widget plan P2-04) under the
// light theme: a gauge and a level are read-only progress with digits, the level
// invalid past its danger share; a snackbar shows the queue's head along the
// bottom with its action and its close, a toast at the top right; a banner is an
// alert for an error and a status otherwise (v2, D971), an info bar closes; a skeleton is
// busy; an empty state offers its action; an accordion opens one disclosure.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { undos: usize, dismisses: usize, settings: usize, closes: usize, starts: usize, toggles: usize, last_toggle: usize }
type Numbered = struct { log: *Log, index: usize }

fn on_undo(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.undos += 1usize
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dismisses += 1usize
    ret ok
}

fn on_settings(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.settings += 1usize
    ret ok
}

fn on_close(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.closes += 1usize
    ret ok
}

fn on_start(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.starts += 1usize
    ret ok
}

fn on_toggle(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.toggles += 1usize
    n.log.last_toggle = n.index
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

fn near(a: f32, b: f32, within: f32) -> bool {
    let d = a - b
    ret d < within && d > 0.0 - within
}

type Handlers = struct { settings: []widget.Submit, close: widget.Submit, start: widget.Submit }

fn build(a: *mem.Arena, t: *const control.Theme, notices: []const control.Notice, h: *const Handlers, toggles: []const widget.Submit, expanded: usize) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 9usize)
    if parts_error != ok { ret (zero, parts_error) }
    let (speed, speed_error) = control.gauge(a, 1u64, t, "Speed", 25.0, 0.0, 100.0, 48.0)
    if speed_error != ok { ret (zero, speed_error) }
    parts[0usize] = speed
    let (disk, disk_error) = control.level(a, 10u64, t, "Disk", 90.0, 0.0, 100.0, 0.5, 0.8, 200.0)
    if disk_error != ok { ret (zero, disk_error) }
    parts[1usize] = disk
    let (bottom, bottom_error) = control.snackbar(a, 20u64, t, notices, 280.0)
    if bottom_error != ok { ret (zero, bottom_error) }
    parts[2usize] = bottom
    let (top, top_error) = control.toast(a, 30u64, t, notices, 160.0)
    if top_error != ok { ret (zero, top_error) }
    parts[3usize] = top
    var labels: [1]str = zero
    labels[0usize] = "Settings"
    // The actions a control fires outlive the frame: they are the caller's.
    let (warning, warning_error) = control.banner(a, 40u64, t, .Warning, "Low battery", labels[..], h.settings, 300.0)
    if warning_error != ok { ret (zero, warning_error) }
    parts[4usize] = warning
    var no_labels: []const str = zero
    var no_actions: []const widget.Submit = zero
    let (tip, tip_error) = control.info_bar(a, 50u64, t, .Info, "Tip of the day", no_labels, no_actions, &h.close, 300.0)
    if tip_error != ok { ret (zero, tip_error) }
    parts[5usize] = tip
    let (bones, bones_error) = control.skeleton(a, 60u64, t, 200.0, 16.0, 0.0)
    if bones_error != ok { ret (zero, bones_error) }
    parts[6usize] = bones
    let (nothing, nothing_error) = control.empty_state(a, 70u64, t, zero, "No mail", "Nothing has arrived yet.", "Write one", &h.start, 300.0)
    if nothing_error != ok { ret (zero, nothing_error) }
    parts[7usize] = nothing
    var sections: [3]str = zero
    sections[0usize] = "First"
    sections[1usize] = "Second"
    sections[2usize] = "Third"
    var bodies: [3]widget.Node = zero
    let (first_body, first_error) = control.text(a, 0u64, "First body", t, control.text_options())
    if first_error != ok { ret (zero, first_error) }
    let (second_body, second_error) = control.text(a, 0u64, "Second body", t, control.text_options())
    if second_error != ok { ret (zero, second_error) }
    let (third_body, third_error) = control.text(a, 0u64, "Third body", t, control.text_options())
    if third_error != ok { ret (zero, third_error) }
    bodies[0usize] = first_body
    bodies[1usize] = second_body
    bodies[2usize] = third_body
    let (folded, folded_error) = control.accordion(a, 80u64, t, "Sections", sections[..], bodies[..], expanded, toggles)
    if folded_error != ok { ret (zero, folded_error) }
    parts[8usize] = folded
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    column.height = style.Length { Px: 800.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, parts[0usize..9usize]), ok)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn centre_of(h: *testing.Harness, runtime: *const widget.Runtime, key: widget.Key) -> (geometry.Point, bool) {
    let found = testing.by_key(h, key)
    if found.count != 1usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, found.element)
    if !has_area { ret (zero, false) }
    ret (geometry.Point { x: area.x + area.width * 0.5, y: area.y + area.height * 0.5 }, true)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 160usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 400usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 800u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (handlers, handlers_error) = mem.alloc[Handlers](a, 1usize)
    if handlers_error != ok { os.exit(8i32) }
    let (settings, settings_error) = mem.alloc[widget.Submit](a, 1usize)
    if settings_error != ok { os.exit(8i32) }
    settings[0usize] = widget.Submit { ctx: ctx, invoke: on_settings }
    handlers[0usize] = Handlers { settings: settings[0usize..1usize], close: widget.Submit { ctx: ctx, invoke: on_close }, start: widget.Submit { ctx: ctx, invoke: on_start } }
    let (notices, notices_error) = mem.alloc[control.Notice](a, 1usize)
    if notices_error != ok { os.exit(9i32) }
    notices[0usize] = control.Notice { text: "Saved", action_label: "Undo", action: widget.Submit { ctx: ctx, invoke: on_undo }, dismiss: widget.Submit { ctx: ctx, invoke: on_dismiss } }
    let (numbers, numbers_error) = mem.alloc[Numbered](a, 3usize)
    if numbers_error != ok { os.exit(10i32) }
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, 3usize)
    if toggles_error != ok { os.exit(11i32) }
    var i = 0usize
    while i < 3usize {
        numbers[i] = Numbered { log: &logs[0usize], index: i }
        toggles[i] = widget.Submit { ctx: mem.cast[*void](&numbers[i]), invoke: on_toggle }
        i += 1usize
    }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(12i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, notices[0usize..1usize], &handlers[0usize], toggles[0usize..3usize], 1usize)
    if build_error != ok { os.exit(13i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(14i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(15i32) }
    // The gauge and the level: progress with digits; the level past its danger
    // share is invalid and nine tenths filled.
    let (speed, has_speed) = find(tree, .Progress, "Speed")
    if !has_speed || !same(speed.value, "25") || testing.by_text(&harness, "25").count == 0usize { os.exit(16i32) }
    let (disk, has_disk) = find(tree, .Progress, "Disk")
    if !has_disk || !same(disk.value, "90") || !disk.state.invalid { os.exit(17i32) }
    let (fill_bounds, has_fill) = widget.bounds_of(&runtime, testing.by_key(&harness, 11u64).element)
    if !has_fill || !near(fill_bounds.width, 180.0, 0.5) { os.exit(18i32) }
    // The snackbar: the notice along the bottom, a polite status; Undo fires the
    // action, the close its dismiss. The toast: the same notice at the top right.
    let (saved, has_saved) = find(tree, .Status, "Saved")
    if !has_saved || saved.live != .Polite { os.exit(19i32) }
    let (bar_bounds, has_bar) = testing.overlay_of(&harness, testing.by_key(&harness, 20u64).element)
    if !has_bar || bar_bounds.y + bar_bounds.height < 760.0 || bar_bounds.y + bar_bounds.height > 800.0 { os.exit(20i32) }
    let (undo_at, has_undo) = centre_of(&harness, &runtime, 21u64)
    if !has_undo || testing.tap(&harness, undo_at.x, undo_at.y) != ok || logs[0usize].undos != 1usize { os.exit(21i32) }
    let (close_at, has_close) = centre_of(&harness, &runtime, 22u64)
    if !has_close || testing.tap(&harness, close_at.x, close_at.y) != ok || logs[0usize].dismisses != 1usize { os.exit(22i32) }
    let (toast_bounds, has_toast) = testing.overlay_of(&harness, testing.by_key(&harness, 30u64).element)
    if !has_toast || toast_bounds.y > 40.0 || toast_bounds.x + toast_bounds.width < 300.0 { os.exit(23i32) }
    // The banner: a warning is a polite status in v2 (D971); Settings fires. The info bar: a status whose
    // close fires the dismiss.
    let (battery, has_battery) = find(tree, .Status, "Low battery")
    if !has_battery || battery.live != .Polite { os.exit(24i32) }
    let (settings_at, has_settings) = centre_of(&harness, &runtime, 42u64)
    if !has_settings || testing.tap(&harness, settings_at.x, settings_at.y) != ok || logs[0usize].settings != 1usize { os.exit(25i32) }
    let (tip, has_tip) = find(tree, .Status, "Tip of the day")
    if !has_tip || tip.live != .Polite { os.exit(26i32) }
    let (tip_close_at, has_tip_close) = centre_of(&harness, &runtime, 51u64)
    if !has_tip_close || testing.tap(&harness, tip_close_at.x, tip_close_at.y) != ok || logs[0usize].closes != 1usize { os.exit(27i32) }
    // The skeleton is busy; the empty state is a group named by its title whose
    // button fires.
    var busy_seen = false
    i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .Group && tree.nodes[i].state.busy { busy_seen = true }
        i += 1usize
    }
    if !busy_seen { os.exit(28i32) }
    let (nothing, has_nothing) = find(tree, .Group, "No mail")
    if !has_nothing || testing.by_text(&harness, "Nothing has arrived yet.").count != 1usize { os.exit(29i32) }
    let (write_at, has_write) = centre_of(&harness, &runtime, 71u64)
    if !has_write || testing.tap(&harness, write_at.x, write_at.y) != ok || logs[0usize].starts != 1usize { os.exit(30i32) }
    // The accordion: the second open alone; the third header fires its toggle.
    if testing.by_text(&harness, "Second body").count != 1usize || testing.by_text(&harness, "First body").count != 0usize || testing.by_text(&harness, "Third body").count != 0usize { os.exit(31i32) }
    let (third_at, has_third) = centre_of(&harness, &runtime, 85u64)
    if !has_third || testing.tap(&harness, third_at.x, third_at.y) != ok || logs[0usize].toggles != 1usize || logs[0usize].last_toggle != 2usize { os.exit(32i32) }
    // An empty queue: no notice anywhere.
    var no_notices: []const control.Notice = zero
    let (root_2, build_2_error) = build(&frame, &theme, no_notices, &handlers[0usize], toggles[0usize..3usize], 2usize)
    if build_2_error != ok { os.exit(33i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(34i32) }
    if testing.by_text(&harness, "Saved").count != 0usize || testing.by_text(&harness, "Third body").count != 1usize { os.exit(35i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(36i32) }
    try io.print("ui feedback ok\n")
    ret ok
}
