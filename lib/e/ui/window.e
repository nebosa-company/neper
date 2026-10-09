// `e.ui.window` (D797): a top-level window as a logically linear handle over the
// reviewed `e.os` primitives, with a `scene.Target` to draw into. On the CPU device
// the target is an offscreen pair of images and `request_frame` is what shows the
// last rendered one in the window through `os.window_present`; a driver device
// would hand the window's native surface to `gpu.open_target` and present there.
// Coordinates above this module are logical pixels; `Metrics` carries both.
//
// Windows live in a bounded table so `e.ui.input` can name one by its `Id` from the
// host's handle; a closed window's slot is reused with a new generation.
// ponytail: `transparent` is accepted and recorded, not acted on; an alpha-capable
// native surface and compositor path are the upgrade when transparent windows matter.

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
    accessibility: []os.AccessibleNode,
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
    damage: geometry.Rect,
    damaged: bool,
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
    var mode: os.WindowMode = .Windowed
    if options.mode == .Maximized { mode = .Maximized }
    if options.mode == .Fullscreen { mode = .Fullscreen }
    let (handle, open_error) = os.window_open(a, os.WindowOptions { title: options.title, width: options.width, height: options.height, resizable: options.resizable, visible: true, mode: mode })
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
    states[0usize] = State { arena: a, handle: handle, scratch: scratch, accessibility: zero, queue: queue, frames: frames, drawable: drawable, width: options.width, height: options.height, mode: options.mode, transparent: options.transparent, resizable: options.resizable, frame_requested: false, closed: false, damage: zero, damaged: false }
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

fn accessibility_storage(id: Id, count: usize) -> ([]os.AccessibleNode, err) {
    var nothing: []os.AccessibleNode = zero
    let (s, state_error) = state_by_id(id)
    if state_error != ok { ret (nothing, state_error) }
    if s.accessibility.len < count {
        // ponytail: a larger semantic tree leaves the prior arena slice behind;
        // geometric or caller-sized storage is the upgrade if repeated growth matters.
        let (grown, grown_error) = mem.alloc[os.AccessibleNode](s.arena, count)
        if grown_error != ok { ret (nothing, Invalid) }
        s.accessibility = grown
    }
    ret (s.accessibility[0usize..count], ok)
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

// The host's own window, for the shell services that take one (D887).
fn host_window(window: *const Window) -> (os.Window, err) {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret (zero, state_error) }
    ret (s.handle, ok)
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
    s.damaged = false
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

// The host's screens and shell work areas in logical pixels, from its monitors.
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
        let work_area = geometry.Rect { x: f32(m.work_x) / scale, y: f32(m.work_y) / scale, width: f32(m.work_width) / scale, height: f32(m.work_height) / scale }
        out[i] = Screen { bounds: bounds, work_area: work_area, scale: scale, primary: m.primary }
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

// ------------------------------------------------ damage tracking (D904)

// A region invalidated since the last frame, unioned with the others; the
// next `request_frame` presents and clears it.
fn damage(window: *Window, area: geometry.Rect) -> err {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret state_error }
    if area.width <= 0.0 || area.height <= 0.0 { ret Invalid }
    if s.damaged { s.damage = geometry.union_rect(s.damage, area) } else { s.damage = area }
    s.damaged = true
    ret ok
}

// What is invalid now, or nothing.
fn damaged(window: *const Window) -> (geometry.Rect, bool) {
    let (s, state_error) = state_of(window)
    if state_error != ok { ret (zero, false) }
    if !s.damaged { ret (zero, false) }
    ret (s.damage, true)
}

// ------------------------------------------------ app-drawn caption (D2281, L088)

// The geometry of a window caption the application draws itself, with no host: where the title, the drag region and
// the caption buttons go on each platform, which part of the window a point belongs to, and what a press there means.
// The host keeps drawing the real chrome unless the window was opened frameless (`CaptionOptions.frameless`); a bar over
// host chrome carries only the title and no buttons, and claims no drag. Carrying the intents out (minimising, moving and
// resizing a native window) is the host's: `e.os` has no such calls yet, so an intent is data for the application to pass
// on once it does.
type Platform = enum u8 { Windows, Mac, Linux }
type CaptionButton = enum u8 { Minimize, Maximize, Close }
type CaptionOptions = struct {
    platform: Platform, mode: Mode, frameless: bool, minimizable: bool, maximizable: bool, resizable: bool,
    icon: bool, rtl: bool,
}
type CaptionSlot = struct { kind: CaptionButton, rect: geometry.Rect, enabled: bool, restore: bool }
type Caption = struct {
    bar: geometry.Rect, icon: geometry.Rect, title: geometry.Rect, drag: geometry.Rect, slots: [3]CaptionSlot,
    count: usize, leading: bool, centred: bool, draggable: bool,
}
type Region = enum u8 { Client, Caption, Minimize, Maximize, Close, Left, Right, Top, Bottom, TopLeft, TopRight, BottomLeft, BottomRight }
type Intent = enum u8 {
    None, Minimize, Maximize, Restore, Close, Move, ResizeLeft, ResizeRight, ResizeTop, ResizeBottom,
    ResizeTopLeft, ResizeTopRight, ResizeBottomLeft, ResizeBottomRight,
}

fn caption_options(platform: Platform) -> CaptionOptions {
    var out: CaptionOptions = zero
    out.platform = platform
    out.mode = .Windowed
    out.frameless = true
    out.minimizable = true
    out.maximizable = true
    out.resizable = true
    out.icon = platform != .Mac
    ret out
}

// The bar's height: 32 on Windows, 28 on macOS (traffic lights), 36 on Linux.
fn caption_height(platform: Platform) -> f32 {
    if platform == .Mac { ret 28.0 }
    if platform == .Linux { ret 36.0 }
    ret 32.0
}

// The caption buttons, in the order they stand from the window's start: the platform's own (Windows and Linux put
// minimise, maximise, close at the end with close outermost; macOS puts close, minimise, zoom at the start).
fn caption_order(platform: Platform) -> [3]CaptionButton {
    if platform == .Mac { ret [3]CaptionButton{ .Close, .Minimize, .Maximize } }
    ret [3]CaptionButton{ .Minimize, .Maximize, .Close }
}

// Whether a platform's buttons stand at the start of a left-to-right window (macOS), or at the end; `rtl` mirrors both.
fn caption_leading(options: CaptionOptions) -> bool {
    var leading = options.platform == .Mac
    if options.rtl { leading = !leading }
    ret leading
}

// A button's width and height: 46 by the bar's height on Windows (flush, no gaps), 12 round 8 apart on macOS, 28 round
// 8 apart on Linux, with 10 of margin on the platforms that space them.
fn caption_button_size(platform: Platform) -> (f32, f32) {
    if platform == .Mac { ret (12.0, 12.0) }
    if platform == .Linux { ret (28.0, 28.0) }
    ret (46.0, 32.0)
}

fn caption_gap(platform: Platform) -> f32 {
    if platform == .Windows { ret 0.0 }
    ret 8.0
}

fn caption_margin(platform: Platform) -> f32 {
    if platform == .Windows { ret 0.0 }
    ret 10.0
}

// The caption at `width`: nothing in fullscreen (the bar is 0 tall), otherwise the bar, the optional 16 icon (10 in on
// Windows and Linux, none on macOS), the buttons (only for a frameless window) and the title and drag region between.
// `title_width` is the title's own width, used to centre it on macOS.
fn caption_layout(width: f32, options: CaptionOptions, title_width: f32) -> Caption {
    var out: Caption = zero
    out.leading = caption_leading(options)
    out.centred = options.platform == .Mac
    if options.mode == .Fullscreen || width <= 0.0 { ret out }
    let height = caption_height(options.platform)
    out.bar = geometry.rect(0.0, 0.0, width, height)
    let (button_width, button_height) = caption_button_size(options.platform)
    let gap = caption_gap(options.platform)
    let margin = caption_margin(options.platform)
    var order = caption_order(options.platform)
    if options.rtl {
        let first = order[0usize]
        order[0usize] = order[2usize]
        order[2usize] = first
    }
    var count = 0usize
    if options.frameless { count = 3usize }
    out.count = count
    // the buttons, from the end that holds them
    var used: f32 = 0.0
    var i = 0usize
    while i < count {
        let kind = order[i]
        var enabled = true
        if kind == .Minimize { enabled = options.minimizable }
        if kind == .Maximize { enabled = options.maximizable && options.resizable }
        var x: f32 = 0.0
        if out.leading {
            x = margin + f32(i) * (button_width + gap)
        } else {
            // trailing: the last in order is outermost
            x = width - margin - f32(count - i) * button_width - f32(count - 1usize - i) * gap
        }
        let y = (height - button_height) * 0.5
        out.slots[i] = CaptionSlot { kind: kind, rect: geometry.rect(x, y, button_width, button_height), enabled: enabled, restore: kind == .Maximize && options.mode == .Maximized }
        i += 1usize
    }
    if count > 0usize { used = margin + f32(count) * button_width + f32(count - 1usize) * gap }
    // what is left is the title and the drag region
    var from: f32 = 0.0
    var to = width
    if out.leading {
        from = used
        if count > 0usize { from += margin }
    } else if count > 0usize {
        to = width - used
        if margin > 0.0 { to -= margin }
    }
    if options.icon && !out.centred {
        let side: f32 = 16.0
        var ix: f32 = 10.0
        if options.rtl { ix = width - 10.0 - side }
        out.icon = geometry.rect(ix, (height - side) * 0.5, side, side)
        if options.rtl {
            to = ix - 6.0
        } else {
            from = ix + side + 6.0
            if out.leading && used > from { from = used }
        }
    } else if !out.centred {
        if !out.leading || count == 0usize { from += 12.0 }
    }
    if from > to { from = to }
    out.drag = geometry.rect(from, 0.0, to - from, height)
    out.draggable = options.frameless
    if out.centred {
        var tw = title_width
        if tw > to - from { tw = to - from }
        out.title = geometry.rect(from + (to - from - tw) * 0.5, 0.0, tw, height)
    } else {
        out.title = geometry.rect(from, 0.0, to - from, height)
    }
    ret out
}

// Which part of a `width` by `height` window the point `p` is in. A frameless resizable window in the windowed state
// has a `border` wide resize ring (corners twice as long as it is wide) that takes the points before the caption.
fn hit_region(width: f32, height: f32, options: CaptionOptions, title_width: f32, border: f32, p: geometry.Point) -> Region {
    if p.x < 0.0 || p.y < 0.0 || p.x >= width || p.y >= height { ret .Client }
    if options.frameless && options.resizable && options.mode == .Windowed && border > 0.0 {
        let left = p.x < border
        let right = p.x >= width - border
        let top = p.y < border
        let bottom = p.y >= height - border
        let corner = border * 2.0
        if top && (p.x < corner || left) { ret .TopLeft }
        if top && (p.x >= width - corner || right) { ret .TopRight }
        if bottom && (p.x < corner || left) { ret .BottomLeft }
        if bottom && (p.x >= width - corner || right) { ret .BottomRight }
        if left && p.y < corner { ret .TopLeft }
        if right && p.y < corner { ret .TopRight }
        if left && p.y >= height - corner { ret .BottomLeft }
        if right && p.y >= height - corner { ret .BottomRight }
        if left { ret .Left }
        if right { ret .Right }
        if top { ret .Top }
        if bottom { ret .Bottom }
    }
    let caption = caption_layout(width, options, title_width)
    var i = 0usize
    while i < caption.count {
        if geometry.contains(caption.slots[i].rect, p) {
            if caption.slots[i].kind == .Minimize { ret .Minimize }
            if caption.slots[i].kind == .Maximize { ret .Maximize }
            ret .Close
        }
        i += 1usize
    }
    if geometry.contains(caption.bar, p) { ret .Caption }
    ret .Client
}

// What a press (or a double press) in `region` asks of the host. A disabled button, the client area and a bar over host
// chrome ask nothing; the caption moves on a press and maximises or restores on a double press.
fn caption_intent(region: Region, options: CaptionOptions, double: bool) -> Intent {
    if region == .Caption {
        if !options.frameless { ret .None }
        if double {
            if !options.maximizable || !options.resizable { ret .None }
            if options.mode == .Maximized { ret .Restore }
            ret .Maximize
        }
        if options.mode == .Fullscreen { ret .None }
        ret .Move
    }
    if region == .Minimize {
        if !options.minimizable { ret .None }
        ret .Minimize
    }
    if region == .Maximize {
        if !options.maximizable || !options.resizable { ret .None }
        if options.mode == .Maximized { ret .Restore }
        ret .Maximize
    }
    if region == .Close { ret .Close }
    if region == .Left { ret .ResizeLeft }
    if region == .Right { ret .ResizeRight }
    if region == .Top { ret .ResizeTop }
    if region == .Bottom { ret .ResizeBottom }
    if region == .TopLeft { ret .ResizeTopLeft }
    if region == .TopRight { ret .ResizeTopRight }
    if region == .BottomLeft { ret .ResizeBottomLeft }
    if region == .BottomRight { ret .ResizeBottomRight }
    ret .None
}
