// `e.ui.app` (D802): the scheduling primitive over the whole chain. `init` opens the
// device, the window, the renderer, the widget runtime and the input queue, and
// keeps the application's builder; `step` waits up to the timeout for input, drains
// it into dispatch, and when a frame is due -- the first step, an event delivered,
// an element invalidated, a resize -- resets the frame arena, builds the tree
// through the builder, reconciles it under the window's logical size, renders it
// into the window's target and shows it. `run` repeats `step`; `stop` ends it.
//
// The builder is generic over its context and the app is not: `init[Ctx]` keeps
// the context erased to `*void` and the build function's bits behind a pun a
// per-`Ctx` trampoline reads back, since a function value has no cast.
// ponytail: one window per app; `frame_arena_bytes` is taken whole from the
// application arena at `init`.

use e.gpu
use e.mem
use e.os
use e.os.shell
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.widget
use e.ui.window

type App = struct { state: *void }
type Builder[Ctx: type] = struct { ctx: *Ctx, build: fn(*Ctx, *widget.BuildContext) -> (widget.Node, err) }
type Options = struct { window: window.Options, widget_limits: widget.Limits, frame_arena_bytes: usize, event_capacity: usize, backend: gpu.Backend }
error Closed
error Failed

type Pun[Ctx: type] = union { typed: fn(*Ctx, *widget.BuildContext) -> (widget.Node, err), bits: usize }
type State = struct {
    arena: *mem.Arena,
    device: *gpu.Device,
    win: window.Window,
    renderer: scene.Renderer,
    runtime: widget.Runtime,
    events: input.Queue,
    frame_storage: []u8,
    ctx: *void,
    build_bits: usize,
    trampoline: fn(*void, usize, *widget.BuildContext) -> (widget.Node, err),
    frame_due: bool,
    stopped: bool,
    closed: bool,
    frames: u64,
}

// The per-context trampoline: the erased context and the build function's bits
// become the typed call.
fn call_builder[Ctx: type](ctx: *void, bits: usize, build_context: *widget.BuildContext) -> (widget.Node, err) {
    var pun: Pun[Ctx] = zero
    pun.bits = bits
    let (node, build_error) = pun.typed(mem.cast[*Ctx](ctx), build_context)
    ret (node, build_error)
}

fn init[Ctx: type](a: *mem.Arena, options: Options, builder: Builder[Ctx]) -> (App, err) {
    if options.frame_arena_bytes < 65536usize || options.event_capacity == 0usize { ret (zero, Failed) }
    let (device, open_error) = gpu.open(a, options.backend, 0u32)
    if open_error != ok { ret (zero, Failed) }
    let (win, window_error) = window.open(a, device, options.window)
    if window_error != ok {
        let abandoned = gpu.close(device)
        ret (zero, Failed)
    }
    var opened = win
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (zero, Failed) }
    let (renderer, renderer_error) = scene.renderer(a, device, queue, 4u32, 256u32)
    if renderer_error != ok { ret (zero, Failed) }
    let (states, states_error) = mem.alloc[State](a, 1usize)
    if states_error != ok { ret (zero, Failed) }
    var s: State = zero
    s.arena = a
    s.device = device
    s.win = opened
    s.renderer = renderer
    let (runtime, runtime_error) = widget.runtime(a, &states[0usize].renderer, options.widget_limits)
    if runtime_error != ok { ret (zero, Failed) }
    s.runtime = runtime
    let (events, events_error) = input.queue(a, options.event_capacity)
    if events_error != ok { ret (zero, Failed) }
    s.events = events
    let (frame_storage, storage_error) = mem.alloc[u8](a, options.frame_arena_bytes)
    if storage_error != ok { ret (zero, Failed) }
    s.frame_storage = frame_storage
    s.ctx = mem.cast[*void](builder.ctx)
    var pun: Pun[Ctx] = zero
    pun.typed = builder.build
    s.build_bits = pun.bits
    s.trampoline = call_builder[Ctx]
    s.frame_due = true
    states[0usize] = s
    ret (App { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn state_of(app: *App) -> (*State, err) {
    let s = mem.cast[*State](app.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, Closed) }
    ret (s, ok)
}

// One frame of the application: input, then a frame when one is due.
fn step(app: *App, timeout: time.Duration) -> (bool, err) {
    let (s, state_error) = state_of(app)
    if state_error != ok { ret (false, state_error) }
    if s.stopped { ret (false, ok) }
    var remaining = timeout
    var drained = 0usize
    while drained < 256usize {
        let (event, any, poll_error) = input.poll(&s.events, remaining)
        if poll_error != ok { ret (false, Failed) }
        if !any { break }
        remaining = time.Duration { nanos: 0i64 }
        drained += 1usize
        if event.tag == .Close {
            s.stopped = true
            ret (false, ok)
        }
        if event.tag == .Resize || event.tag == .Frame { s.frame_due = true }
        let dispatch_error = widget.dispatch(&s.runtime, event)
        if dispatch_error != ok { ret (false, dispatch_error) }
        s.frame_due = true
    }
    if !s.frame_due { ret (true, ok) }
    let frame_error = present_frame(s)
    if frame_error != ok { ret (false, frame_error) }
    ret (true, ok)
}

fn present_frame(s: *State) -> err {
    let (metrics, metrics_error) = window.metrics(&s.win)
    if metrics_error != ok { ret Failed }
    var frame = mem.arena_from(s.frame_storage)
    let (root, has_root) = widget.root_of(&s.runtime)
    var build_context = widget.BuildContext { runtime: &s.runtime, element: root, frame: s.frames }
    let (tree, build_error) = s.trampoline(s.ctx, s.build_bits, &build_context)
    if build_error != ok { ret build_error }
    let limits = ui_layout.Constraints { min_width: 0.0, max_width: metrics.logical_size.width, min_height: 0.0, max_height: metrics.logical_size.height }
    let (compiled, reconcile_error) = widget.reconcile(&s.runtime, &frame, tree, limits)
    if reconcile_error != ok { ret reconcile_error }
    let (canvas, canvas_error) = window.draw_target(&s.win)
    if canvas_error != ok { ret Failed }
    let render_error = scene.render(&s.renderer, compiled, canvas, metrics.logical_size)
    if render_error != ok { ret render_error }
    if window.request_frame(&s.win) != ok { ret Failed }
    s.frames += 1u64
    s.frame_due = false
    ret ok
}

fn run(app: *App) -> err {
    while true {
        let (more, step_error) = step(app, time.millis(16i64))
        if step_error != ok { ret step_error }
        if !more { ret ok }
    }
    ret ok
}

fn stop(app: *App) {
    let (s, state_error) = state_of(app)
    if state_error != ok { ret }
    s.stopped = true
}

fn close(app: *App) -> err {
    let (s, state_error) = state_of(app)
    if state_error != ok { ret state_error }
    let events_closed = input.close(&s.events)
    let runtime_closed = widget.close(&s.runtime)
    let renderer_closed = scene.close(&s.renderer)
    let window_closed = window.close(&s.win)
    let device_closed = gpu.close(s.device)
    s.closed = true
    ret ok
}

// The frames presented so far, for a test that steps by hand.
fn frames_of(app: *const App) -> u64 {
    let s = mem.cast[*State](app.state)
    if mem.address_of(s) == 0usize { ret 0u64 }
    ret s.frames
}

// ---------------------------------------------------------------- tray (D886)
//
// The system tray (widget plan P4-01) as a typed controller over `e.os.shell`: a
// `Tray` is the caller's icon, tooltip, badge and command menu under one id, and
// `tray_poll` turns the shell's activations into the caller's -- a context
// activation with a menu attached becomes the shell's popup menu at the pointer,
// and its choice a `.Command` with the item's id. The badge is composed into the
// icon here, since the shell has no badge of its own: a filled disc in the top
// right corner while the count is not zero. ponytail: a disc, not the number; a
// glyph needs a face the app does not hold at this level. Every call answers
// `shell.Unsupported` where the host has no tray, and `tray_supported` says so
// before one is opened.

type Tray = struct { id: u32, width: u32, height: u32, source: []const u32, composed: []u32, tooltip: str, badge: u32, menu: []const shell.MenuItem, open: bool }
type TrayActivationKind = enum u8 { Select, Open, Command, Dismissed }
type TrayActivation = struct { kind: TrayActivationKind, command: u32, x: i32, y: i32 }

const BADGE_COLOUR: u32 = 4293281869u32

fn tray_supported() -> bool {
    ret shell.capabilities().tray
}

fn composed_icon(t: *const Tray) -> shell.Icon {
    ret shell.Icon { width: t.width, height: t.height, pixels: t.composed[0usize..t.composed.len] }
}

// The source pixels, and the badge over them when the count is not zero: a disc
// of a quarter of the shorter side, its centre a radius in from the top right.
fn compose(t: *Tray) {
    let count = usize(t.width) * usize(t.height)
    var at = 0usize
    while at < count {
        t.composed[at] = t.source[at]
        at += 1usize
    }
    if t.badge == 0u32 { ret }
    var side = t.width
    if t.height < side { side = t.height }
    let radius = i32(side / 4u32)
    if radius == 0i32 { ret }
    let centre_x = i32(t.width) - radius
    let centre_y = radius
    var y = 0i32
    while y < i32(t.height) {
        var x = 0i32
        while x < i32(t.width) {
            let dx = x - centre_x
            let dy = y - centre_y
            if dx * dx + dy * dy <= radius * radius { t.composed[usize(y) * usize(t.width) + usize(x)] = BADGE_COLOUR }
            x += 1i32
        }
        y += 1i32
    }
}

fn tray_open(a: *mem.Arena, id: u32, icon: shell.Icon, tooltip: str) -> (Tray, err) {
    var t: Tray = zero
    if !tray_supported() { ret (t, shell.Unsupported) }
    if icon.width == 0u32 || icon.height == 0u32 || icon.pixels.len < usize(icon.width) * usize(icon.height) { ret (t, shell.Invalid) }
    let (composed, allocation_error) = mem.alloc[u32](a, usize(icon.width) * usize(icon.height))
    if allocation_error != ok { ret (t, allocation_error) }
    t.id = id
    t.width = icon.width
    t.height = icon.height
    t.source = icon.pixels
    t.composed = composed
    t.tooltip = tooltip
    compose(&t)
    let added = shell.tray_add(a, id, composed_icon(&t), tooltip)
    if added != ok { ret (t, added) }
    t.open = true
    ret (t, ok)
}

fn tray_push(a: *mem.Arena, t: *Tray) -> err {
    if !t.open { ret shell.NotFound }
    compose(t)
    ret shell.tray_update(a, t.id, composed_icon(t), t.tooltip)
}

// A new icon has to be the size the tray was opened with, since the composed
// pixels are allocated once.
fn tray_set_icon(a: *mem.Arena, t: *Tray, icon: shell.Icon) -> err {
    if icon.width != t.width || icon.height != t.height || icon.pixels.len < usize(icon.width) * usize(icon.height) { ret shell.Invalid }
    t.source = icon.pixels
    ret tray_push(a, t)
}

fn tray_set_tooltip(a: *mem.Arena, t: *Tray, tooltip: str) -> err {
    t.tooltip = tooltip
    ret tray_push(a, t)
}

fn tray_set_badge(a: *mem.Arena, t: *Tray, count: u32) -> err {
    t.badge = count
    ret tray_push(a, t)
}

// The menu the next context activation shows; the items are the caller's and
// have to outlive the tray. An empty menu means a context activation is reported
// as such and nothing is shown.
fn tray_set_menu(t: *Tray, items: []const shell.MenuItem) {
    t.menu = items
}

// The oldest activation of this tray, with a context activation resolved through
// the menu when one is attached: `.Command` names the chosen item, `.Dismissed`
// a menu closed without a choice. Activations of other trays are left in the queue's
// order and dropped, since a tray is the whole of its id.
fn tray_poll(a: *mem.Arena, t: *Tray) -> (TrayActivation, bool, err) {
    var none: TrayActivation = zero
    if !t.open { ret (none, false, shell.NotFound) }
    while true {
        let (event, any) = shell.tray_poll()
        if !any { ret (none, false, ok) }
        if event.id != t.id { continue }
        var activation: TrayActivation = zero
        activation.x = event.x
        activation.y = event.y
        if event.kind == .Select {
            activation.kind = .Select
            ret (activation, true, ok)
        }
        if event.kind == .Open {
            activation.kind = .Open
            ret (activation, true, ok)
        }
        if t.menu.len == 0usize {
            activation.kind = .Dismissed
            ret (activation, true, ok)
        }
        let (chosen, has_chosen, menu_error) = shell.popup_menu(a, t.menu, event.x, event.y)
        if menu_error != ok { ret (none, false, menu_error) }
        activation.kind = .Dismissed
        if has_chosen {
            activation.kind = .Command
            activation.command = chosen
        }
        ret (activation, true, ok)
    }
    ret (none, false, ok)
}

fn tray_close(a: *mem.Arena, t: *Tray) -> err {
    if !t.open { ret shell.NotFound }
    t.open = false
    ret shell.tray_remove(a, t.id)
}

// ------------------------------------------------- taskbar and jump list (D887)
//
// Widget plan P4-02, three thin controllers over `e.os.shell` for the app's own
// window: the taskbar button's progress and overlay, and the jump list's tasks.
// Each answers `shell.Unsupported` where the host has no taskbar or jump list,
// which `taskbar_supported` and `jump_list_supported` say first.

fn taskbar_supported() -> bool {
    ret shell.capabilities().taskbar
}

fn jump_list_supported() -> bool {
    ret shell.capabilities().jump_list
}

fn host_window(app: *App) -> (os.Window, err) {
    let (s, state_error) = state_of(app)
    if state_error != ok { ret (zero, state_error) }
    let (handle, host_error) = window.host_window(&s.win)
    if host_error != ok { ret (zero, Failed) }
    ret (handle, ok)
}

fn taskbar_progress(a: *mem.Arena, app: *App, state: shell.ProgressState, completed: u64, total: u64) -> err {
    let (handle, handle_error) = host_window(app)
    if handle_error != ok { ret handle_error }
    ret shell.taskbar_progress(a, handle, state, completed, total)
}

// An icon of no width clears the overlay.
fn taskbar_overlay(a: *mem.Arena, app: *App, icon: shell.Icon, description: str) -> err {
    let (handle, handle_error) = host_window(app)
    if handle_error != ok { ret handle_error }
    ret shell.taskbar_overlay(a, handle, icon, description)
}

// The application's jump list tasks, replaced whole; `jump_list_clear` removes it.
fn jump_list(a: *mem.Arena, tasks: []const shell.JumpTask) -> err {
    ret shell.jump_list(a, tasks)
}

fn jump_list_clear(a: *mem.Arena) -> err {
    ret shell.jump_list_clear(a)
}
