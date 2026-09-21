// `e.ui.window` (D797): a top-level window as a logically linear handle over the
// reviewed `e.os` primitives, with a `scene.Target` to draw into. On the CPU device
// the target is an offscreen pair of images and `request_frame` is what shows the
// last rendered one in the window through `os.window_present`; a driver device
// would hand the window's native surface to `gpu.open_target` and present there.
// Coordinates above this module are logical pixels; `Metrics` carries both.
//
// Windows live in a bounded table so `e.ui.input` can name one by its `Id` from the
// host's handle; a closed window's slot is reused with a new generation.
// ponytail: `Mode` and `transparent` are accepted and recorded, not acted on --
// maximised and fullscreen windows wait on a host that can show them.

use e.gpu
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.scene
use e.ui.style

type Id = struct { slot: u32, generation: u32 }
type Window = struct { state: *void, id: Id }
type Mode = enum u8 { Windowed, Maximized, Fullscreen }
type Cursor = enum u8 { Arrow, Text, Hand, Crosshair, ResizeHorizontal, ResizeVertical, Hidden }
type Options = struct { title: str, width: u32, height: u32, min_width: u32, min_height: u32, resizable: bool, transparent: bool, mode: Mode }
type Metrics = struct { logical_size: geometry.Size, framebuffer_width: u32, framebuffer_height: u32, scale: f32, focused: bool, visible: bool }
// The host capability model (D811, widget plan P0-08): what a window's host can do
// as `style.Capabilities` for `style.adapt`, the safe and keyboard insets a mobile
// host would report (a desktop host has none), the orientation, the screens in
// logical pixels, and the window's lifecycle: active when focused and visible,
// inactive when visible without the focus, background when hidden, suspended
// only when a host says so.
type Lifecycle = enum u8 { Active, Inactive, Background, Suspended }
type Orientation = enum u8 { Landscape, Portrait }
type Screen = struct { bounds: geometry.Rect, work_area: geometry.Rect, scale: f32, primary: bool }
error Unsupported
error Invalid
error Closed

const MAX_WINDOWS: usize = 16usize

type State = struct {
    arena: *mem.Arena,
    handle: os.Window,
    scratch: []u32,
    queue: *gpu.Queue,
    frames: *gpu.Target,
    drawable: scene.Target,
    width: u32,
    height: u32,
    mode: Mode,
    transparent: bool,
    resizable: bool,
    frame_requested: bool,
    closed: bool,
}

var slots: [16]*State = zero
var generations: [16]u32 = zero
var live: [16]bool = zero

fn state_of(window: *const Window) -> (*State, err) {
    let s = mem.cast[*State](window.state)
    if mem.address_of(s) == 0usize { ret (s, Invalid) }
    if s.closed { ret (s, Closed) }
    ret (s, ok)
}

fn open(a: *mem.Arena, device: *gpu.Device, options: Options) -> (Window, err) {
    var none: Window = zero
    if options.width == 0u32 || options.height == 0u32 { ret (none, Invalid) }
    if options.min_width > options.width || options.min_height > options.height { ret (none, Invalid) }
    var slot = 0usize
    while slot < MAX_WINDOWS && live[slot] { slot += 1usize }
    if slot >= MAX_WINDOWS { ret (none, Invalid) }
    let (handle, open_error) = os.window_open(a, os.WindowOptions { title: options.title, width: options.width, height: options.height, resizable: options.resizable, visible: true })
    if open_error == os.Unsupported { ret (none, Unsupported) }
    if open_error != ok { ret (none, Invalid) }
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok {
        let abandoned = os.window_close(handle)
        ret (none, Invalid)
    }
    let (frames, frames_error) = gpu.open_target(queue, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, options.width, options.height, .Bgra8)
    if frames_error != ok {
        let abandoned = os.window_close(handle)
        ret (none, Invalid)
    }
    let (drawable, drawable_error) = scene.target_of(a, frames)
    if drawable_error != ok {
        let abandoned = os.window_close(handle)
        ret (none, Invalid)
    }
    let (states, states_error) = mem.alloc[State](a, 1usize)
    if states_error != ok {
        let abandoned = os.window_close(handle)
        ret (none, Invalid)
    }
    let (scratch, scratch_error) = mem.alloc[u32](a, usize(options.width) * usize(options.height))
    if scratch_error != ok {
        let abandoned = os.window_close(handle)
        ret (none, Invalid)
    }
    states[0usize] = State { arena: a, handle: handle, scratch: scratch, queue: queue, frames: frames, drawable: drawable, width: options.width, height: options.height, mode: options.mode, transparent: options.transparent, resizable: options.resizable, frame_requested: false, closed: false }
    generations[slot] += 1u32
    slots[slot] = &states[0usize]
    live[slot] = true
    ret (Window { state: mem.cast[*void](&states[0usize]), id: Id { slot: u32(slot), generation: generations[slot] } }, ok)
}

// The window a host handle names, for the input queue; `false` for a stranger.
fn id_of(handle: os.Window) -> (Id, bool) {
    var slot = 0usize
    while slot < MAX_WINDOWS {
        if live[slot] && slots[slot].handle.raw == handle.raw { ret (Id { slot: u32(slot), generation: generations[slot] }, true) }
        slot += 1usize
    }
    ret (zero, false)
}

// The state behind an id, for the input queue's capture calls.
fn state_by_id(id: Id) -> (*State, err) {
    var none: *State = zero
    if usize(id.slot) >= MAX_WINDOWS || !live[usize(id.slot)] || generations[usize(id.slot)] != id.generation { ret (none, Closed) }
    ret (slots[usize(id.slot)], ok)
}

// A frame request the input queue has not delivered yet, taken once.
fn take_frame_request() -> (Id, bool) {
    var slot = 0usize
    while slot < MAX_WINDOWS {
        if live[slot] && slots[slot].frame_requested {
            slots[slot].frame_requested = false
            ret (Id { slot: u32(slot), generation: generations[slot] }, true)
        }
        slot += 1usize
    }
    ret (zero, false)
}

fn metrics(window: *const Window) -> (Metrics, err) {
    var none: Metrics = zero
    let (s, state_error) = state_of(window)
    if state_error != ok { ret (none, state_error) }
    let (host, host_error) = os.window_metrics(s.handle)
    if host_error != ok { ret (none, Closed) }
    var scale = f32(host.scale_percent) / 100.0
    if !(scale > 0.0) { scale = 1.0 }
    // The target follows the client area.
    if host.width != s.width || host.height != s.height {
        if host.width != 0u32 && host.height != 0u32 && gpu.resize(s.frames, host.width, host.height) == ok {
            s.width = host.width
            s.height = host.height
        }
    }
    ret (Metrics { logical_size: geometry.Size { width: f32(host.width) / scale, height: f32(host.height) / scale }, framebuffer_width: host.width, framebuffer_height: host.height, scale: scale, focused: host.focused, visible: host.visible }, ok)
}

fn draw_target(window: *const Window) -> (scene.Target, err) {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret (zero, state_error) }
    ret (s.drawable, ok)
}

fn title(window: *Window, value: str) -> err {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret state_error }
    if os.window_title(s.handle, value) != ok { ret Invalid }
    ret ok
}

fn cursor(window: *Window, value: Cursor) -> err {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret state_error }
    var shape: os.CursorShape = .Arrow
    if value == .Text { shape = .Text }
    if value == .Hand { shape = .Hand }
    if value == .Crosshair { shape = .Crosshair }
    if value == .ResizeHorizontal { shape = .ResizeHorizontal }
    if value == .ResizeVertical { shape = .ResizeVertical }
    if value == .Hidden { shape = .Hidden }
    if os.window_cursor(s.handle, shape) != ok { ret Invalid }
    ret ok
}

fn visible(window: *Window, value: bool) -> err {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret state_error }
    if os.window_visible(s.handle, value) != ok { ret Invalid }
    ret ok
}

// Shows the last frame rendered into the target and queues a `Frame` event for
// the window: on the CPU device the presented offscreen image is read back and
// blitted through the host's software path.
fn request_frame(window: *Window) -> err {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret state_error }
    let (shown, shown_error) = gpu.presented(s.frames)
    if shown_error == ok {
        let count = usize(shown.width) * usize(shown.height)
        // ponytail: a frame larger than the last scratch takes a new one from the
        // window's arena and leaves the old; a resize storm is the case that pays.
        if s.scratch.len < count {
            let (scratch, scratch_error) = mem.alloc[u32](s.arena, count)
            if scratch_error != ok { ret Invalid }
            s.scratch = scratch
        }
        if gpu.read_image(s.queue, shown, s.scratch[0usize..count]) != ok { ret Invalid }
        if os.window_present(s.handle, s.scratch[0usize..count], shown.width, shown.height) != ok { ret Invalid }
    }
    s.frame_requested = true
    ret ok
}

fn clipboard_get(a: *mem.Arena, window: *Window) -> (str, err) {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret ("", state_error) }
    let (text, text_error) = os.clipboard_text(a)
    if text_error == os.Unsupported { ret ("", Unsupported) }
    if text_error != ok { ret ("", Invalid) }
    ret (text, ok)
}

fn clipboard_set(window: *Window, value: str) -> err {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret state_error }
    let set_error = os.set_clipboard_text(value)
    if set_error == os.Unsupported { ret Unsupported }
    if set_error != ok { ret Invalid }
    ret ok
}

// A desktop host: a fine pointer that hovers, a keyboard, no touch or pen, other
// windows beside this one, and no insets.
// ponytail: a touch or pen host waits on a host that reports one; every host today is a desktop.
fn capabilities(window: *const Window) -> (style.Capabilities, err) {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret (zero, state_error) }
    let (insets, insets_error) = safe_insets(window)
    if insets_error != ok { ret (zero, insets_error) }
    ret (style.Capabilities { hover: true, fine_pointer: true, keyboard: true, touch: false, pen: false, resizable: s.resizable, multi_window: true, insets: insets }, ok)
}

fn safe_insets(window: *const Window) -> (geometry.Insets, err) {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret (zero, state_error) }
    ret (geometry.Insets { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 }, ok)
}

fn keyboard_insets(window: *const Window) -> (geometry.Insets, err) {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret (zero, state_error) }
    ret (geometry.Insets { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 }, ok)
}

fn orientation(window: *const Window) -> (Orientation, err) {
    let (m, metrics_error) = metrics(window)
    if metrics_error != ok { ret (.Landscape, metrics_error) }
    if m.logical_size.height > m.logical_size.width { ret (.Portrait, ok) }
    ret (.Landscape, ok)
}

fn lifecycle(window: *const Window) -> (Lifecycle, err) {
    let (m, metrics_error) = metrics(window)
    if metrics_error != ok { ret (.Background, metrics_error) }
    if !m.visible { ret (.Background, ok) }
    if !m.focused { ret (.Inactive, ok) }
    ret (.Active, ok)
}

// The host's screens in logical pixels, from its monitors.
// ponytail: the work area is the screen; a host that reports its shell's reserved edges narrows it.
fn screens(a: *mem.Arena, limit: usize) -> ([]const Screen, err) {
    let (found, found_error) = os.monitors(a, limit)
    if found_error == os.Unsupported { ret (zero, Unsupported) }
    if found_error != ok { ret (zero, Invalid) }
    let (out, out_error) = mem.alloc[Screen](a, found.len)
    if out_error != ok { ret (zero, Invalid) }
    var i = 0usize
    while i < found.len {
        let m = found[i]
        var scale = f32(m.scale_percent) / 100.0
        if !(scale > 0.0) { scale = 1.0 }
        let bounds = geometry.Rect { x: f32(m.x) / scale, y: f32(m.y) / scale, width: f32(m.width) / scale, height: f32(m.height) / scale }
        out[i] = Screen { bounds: bounds, work_area: bounds, scale: scale, primary: m.primary }
        i += 1usize
    }
    ret (out, ok)
}

fn close(window: *Window) -> err {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret state_error }
    let slot = usize(window.id.slot)
    if slot < MAX_WINDOWS && live[slot] && generations[slot] == window.id.generation { live[slot] = false }
    let target_closed = gpu.close_target(s.frames)
    let host_closed = os.window_close(s.handle)
    s.closed = true
    if host_closed != ok { ret Invalid }
    ret ok
}
