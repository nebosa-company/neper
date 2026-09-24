// `e.ui.input` (D797): the host's window events as one ordered queue of `Event`s
// over `os.window_poll`, each naming its window by `window.Id`. Pointer positions
// are logical pixels -- the host's client pixels over the window's scale -- and the
// button set is tracked per queue so a `Pointer` carries every button held. Keys
// keep the host's virtual code as `physical` and `logical` alike (Windows function
// keys are normalised to X11's 0xffbe range): a layout-aware logical key waits on
// the host telling the two apart. Text arrives per code point;
// IME composition is not delivered, and `composition_rect` is `TooLarge` for the
// caller that must know, since the fence has no `Unsupported` here.
//
// A `Frame` event is what `window.request_frame` queues, delivered before the host's
// events so a frame the program asked for is the next thing it sees.

use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.ui.window

type DeviceId = u32
type PointerId = u32
type Key = struct { physical: u32, logical: u32 }
type Modifiers = struct { shift: bool, control: bool, alt: bool, meta: bool, caps_lock: bool, num_lock: bool }
type PointerButton = enum u8 { Primary, Secondary, Middle, Back, Forward }
type PointerKind = enum u8 { Mouse, Touch, Pen }
type Pointer = struct { window: window.Id, device: DeviceId, pointer: PointerId, kind: PointerKind, position: geometry.Point, buttons: u32, changed: PointerButton }
type KeyEvent = struct { window: window.Id, key: Key, modifiers: Modifiers, repeat: bool }
type TextEvent = struct { window: window.Id, text: str }
type Composition = struct { window: window.Id, text: str, selection_start: usize, selection_end: usize }
// Lifecycle events (D811): the window's lifecycle changing, its safe and keyboard
// insets changing, and the mobile back gesture; a desktop host derives the first
// from its focus and never sends the other two.
type LifecycleEvent = struct { window: window.Id, state: window.Lifecycle }
type InsetsEvent = struct { window: window.Id, safe: geometry.Insets, keyboard: geometry.Insets }
type Event = union enum u8 { Frame: window.Id, Close: window.Id, Resize: window.Metrics, Focus: window.Id, Blur: window.Id, PointerDown: Pointer, PointerUp: Pointer, PointerMove: Pointer, Scroll: Pointer, KeyDown: KeyEvent, KeyUp: KeyEvent, Text: TextEvent, Composition: Composition, Lifecycle: LifecycleEvent, Insets: InsetsEvent, Back: window.Id }
type Queue = struct { state: *void }
error Closed
error TooLarge

type State = struct { capacity: usize, buttons: u32, text: [4]u8, closed: bool, pending: Event, has_pending: bool }

fn queue(a: *mem.Arena, capacity: usize) -> (Queue, err) {
    if capacity == 0usize { ret (zero, TooLarge) }
    let (states, states_error) = mem.alloc[State](a, 1usize)
    if states_error != ok { ret (zero, TooLarge) }
    states[0usize] = State { capacity: capacity, buttons: 0u32, text: zero, closed: false, pending: zero, has_pending: false }
    ret (Queue { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn state_of(q: *Queue) -> (*State, err) {
    let s = mem.cast[*State](q.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, Closed) }
    ret (s, ok)
}

fn modifiers_of(bits: u8) -> Modifiers {
    ret Modifiers { shift: bits & 1u8 != 0u8, control: bits & 2u8 != 0u8, alt: bits & 4u8 != 0u8, meta: bits & 8u8 != 0u8, caps_lock: bits & 16u8 != 0u8, num_lock: bits & 32u8 != 0u8 }
}

fn button_of(code: u8) -> PointerButton {
    if code == 1u8 { ret .Secondary }
    if code == 2u8 { ret .Middle }
    if code == 3u8 { ret .Back }
    if code == 4u8 { ret .Forward }
    ret .Primary
}

fn button_bit(button: PointerButton) -> u32 {
    if button == .Secondary { ret 2u32 }
    if button == .Middle { ret 4u32 }
    if button == .Back { ret 8u32 }
    if button == .Forward { ret 16u32 }
    ret 1u32
}

// The pointer of a host event, in the window's logical pixels.
fn pointer_of(s: *State, id: window.Id, host: os.WindowEvent) -> Pointer {
    var scale: f32 = 1.0
    let (state, state_error) = window.state_by_id(id)
    if state_error == ok {
        let (metrics, metrics_error) = os.window_metrics(state.handle)
        if metrics_error == ok && metrics.scale_percent != 0u32 { scale = f32(metrics.scale_percent) / 100.0 }
    }
    ret Pointer { window: id, device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: f32(host.x) / scale, y: f32(host.y) / scale }, buttons: s.buttons, changed: button_of(host.button) }
}

// UTF-8 of one code point into the queue's text slot, borrowed until the next poll.
fn encode(s: *State, codepoint: u32) -> str {
    var c = codepoint
    if c > 1114111u32 || (c >= 55296u32 && c < 57344u32) { c = 65533u32 }
    if c < 128u32 {
        s.text[0] = u8(c)
        ret s.text[0usize..1usize]
    }
    if c < 2048u32 {
        s.text[0] = u8(192u32 | (c >> 6u32))
        s.text[1] = u8(128u32 | (c & 63u32))
        ret s.text[0usize..2usize]
    }
    if c < 65536u32 {
        s.text[0] = u8(224u32 | (c >> 12u32))
        s.text[1] = u8(128u32 | ((c >> 6u32) & 63u32))
        s.text[2] = u8(128u32 | (c & 63u32))
        ret s.text[0usize..3usize]
    }
    s.text[0] = u8(240u32 | (c >> 18u32))
    s.text[1] = u8(128u32 | ((c >> 12u32) & 63u32))
    s.text[2] = u8(128u32 | ((c >> 6u32) & 63u32))
    s.text[3] = u8(128u32 | (c & 63u32))
    ret s.text[0usize..4usize]
}

fn poll(q: *Queue, timeout: time.Duration) -> (Event, bool, err) {
    var none: Event = zero
    let (s, state_error) = state_of(q)
    if state_error != ok { ret (none, false, state_error) }
    let (requested, has_request) = window.take_frame_request()
    if has_request { ret (Event { Frame: requested }, true, ok) }
    // The lifecycle change a focus event implied follows it.
    if s.has_pending {
        s.has_pending = false
        ret (s.pending, true, ok)
    }
    var remaining = time.as_nanos(timeout)
    if remaining < 0i64 { remaining = 0i64 }
    while true {
        let (host, any, poll_error) = os.window_poll(remaining)
        if poll_error == os.Unsupported { ret (none, false, ok) }
        if poll_error != ok { ret (none, false, Closed) }
        if !any { ret (none, false, ok) }
        // A window this module never opened, or one already closed, is passed over.
        let (id, known) = window.id_of(host.window)
        if known {
            if host.kind == .Close { ret (Event { Close: id }, true, ok) }
            if host.kind == .Focus {
                s.pending = Event { Lifecycle: LifecycleEvent { window: id, state: .Active } }
                s.has_pending = true
                ret (Event { Focus: id }, true, ok)
            }
            if host.kind == .Blur {
                s.pending = Event { Lifecycle: LifecycleEvent { window: id, state: .Inactive } }
                s.has_pending = true
                ret (Event { Blur: id }, true, ok)
            }
            if host.kind == .Paint { ret (Event { Frame: id }, true, ok) }
            if host.kind == .Resize {
                let (state, window_error) = window.state_by_id(id)
                if window_error == ok {
                    var metrics: window.Metrics = zero
                    var scale: f32 = 1.0
                    let (host_metrics, metrics_error) = os.window_metrics(state.handle)
                    if metrics_error == ok && host_metrics.scale_percent != 0u32 { scale = f32(host_metrics.scale_percent) / 100.0 }
                    metrics = window.Metrics { logical_size: geometry.Size { width: f32(host.width) / scale, height: f32(host.height) / scale }, framebuffer_width: host.width, framebuffer_height: host.height, scale: scale, focused: host_metrics.focused, visible: host_metrics.visible }
                    ret (Event { Resize: metrics }, true, ok)
                }
            }
            if host.kind == .PointerMove { ret (Event { PointerMove: pointer_of(s, id, host) }, true, ok) }
            if host.kind == .PointerDown {
                s.buttons = s.buttons | button_bit(button_of(host.button))
                ret (Event { PointerDown: pointer_of(s, id, host) }, true, ok)
            }
            if host.kind == .PointerUp {
                s.buttons = s.buttons & (4294967295u32 ^ button_bit(button_of(host.button)))
                ret (Event { PointerUp: pointer_of(s, id, host) }, true, ok)
            }
            if host.kind == .Scroll {
                var scroll = pointer_of(s, id, host)
                // The notch count rides in `device`, signed as its bits: the fence's
                // Pointer has no delta field, and a widget reads the sign and count.
                scroll.device = mem.bitcast[u32](host.delta)
                ret (Event { Scroll: scroll }, true, ok)
            }
            if host.kind == .KeyDown { ret (Event { KeyDown: KeyEvent { window: id, key: Key { physical: host.key, logical: host.key }, modifiers: modifiers_of(host.modifiers), repeat: host.repeat } }, true, ok) }
            if host.kind == .KeyUp { ret (Event { KeyUp: KeyEvent { window: id, key: Key { physical: host.key, logical: host.key }, modifiers: modifiers_of(host.modifiers), repeat: false } }, true, ok) }
            if host.kind == .Text { ret (Event { Text: TextEvent { window: id, text: encode(s, host.codepoint) } }, true, ok) }
        }
        // Whatever was waited for has arrived; anything more is polled without waiting.
        remaining = 0i64
    }
    ret (none, false, ok)
}

fn capture(q: *Queue, window_value: window.Id, pointer: PointerId) -> err {
    let (s, state_error) = state_of(q)
    if state_error != ok { ret state_error }
    let (state, window_error) = window.state_by_id(window_value)
    if window_error != ok { ret Closed }
    if os.window_capture(state.handle, true) != ok { ret Closed }
    ret ok
}

fn release_capture(q: *Queue, window_value: window.Id, pointer: PointerId) -> err {
    let (s, state_error) = state_of(q)
    if state_error != ok { ret state_error }
    let (state, window_error) = window.state_by_id(window_value)
    if window_error != ok { ret Closed }
    if os.window_capture(state.handle, false) != ok { ret Closed }
    ret ok
}

fn composition_rect(q: *Queue, window_value: window.Id, rect: geometry.Rect) -> err {
    let (s, state_error) = state_of(q)
    if state_error != ok { ret state_error }
    let (state, window_error) = window.state_by_id(window_value)
    if window_error != ok { ret Closed }
    ret TooLarge
}

fn close(q: *Queue) -> err {
    let (s, state_error) = state_of(q)
    if state_error != ok { ret state_error }
    s.closed = true
    ret ok
}
