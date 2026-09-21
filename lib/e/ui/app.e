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
