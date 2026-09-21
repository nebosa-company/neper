// `e.ui.testing` (D800): a harness drives a widget runtime without a window -- a
// synthetic surface of the size and scale given, an offscreen target on the
// renderer's own queue, frames pumped with the time the test supplies, events sent
// straight to dispatch, elements found by key or by text, and the last frame read
// back as an image to compare against a golden within a per-channel tolerance.
// Nothing here sleeps or asks a display server for anything.

use e.mem
use e.time
use e.gpu
use e.gfx.geometry
use e.gfx.image
use e.gfx.scene
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.widget

type Harness = struct { state: *void }
type Match = struct { element: widget.ElementId, count: usize }
error NotFound
error Ambiguous
error GoldenMismatch

type State = struct { runtime: *widget.Runtime, frames: *gpu.Target, drawable: scene.Target, queue: *gpu.Queue, width: u32, height: u32, scale: f32, frame_storage: []u8, closed: bool }

const FRAME_BYTES: usize = 4194304usize

fn harness(a: *mem.Arena, runtime: *widget.Runtime, width: u32, height: u32, scale: f32) -> (Harness, err) {
    if width == 0u32 || height == 0u32 || !(scale > 0.0) { ret (zero, NotFound) }
    let queue = widget.queue_of(runtime)
    if mem.address_of(queue) == 0usize { ret (zero, NotFound) }
    let (frames, frames_error) = gpu.open_target(queue, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, width, height, .Rgba8)
    if frames_error != ok { ret (zero, NotFound) }
    let (drawable, drawable_error) = scene.target_of(a, frames)
    if drawable_error != ok { ret (zero, NotFound) }
    let (frame_storage, storage_error) = mem.alloc[u8](a, FRAME_BYTES)
    if storage_error != ok { ret (zero, NotFound) }
    let (states, states_error) = mem.alloc[State](a, 1usize)
    if states_error != ok { ret (zero, NotFound) }
    states[0usize] = State { runtime: runtime, frames: frames, drawable: drawable, queue: queue, width: width, height: height, scale: scale, frame_storage: frame_storage, closed: false }
    ret (Harness { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn state_of(h: *const Harness) -> (*State, err) {
    let s = mem.cast[*State](h.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, NotFound) }
    ret (s, ok)
}

// One frame: the tree reconciled under the surface's logical size and rendered.
fn pump(h: *Harness, root: widget.Node, now: time.Instant) -> err {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret state_error }
    var frame = mem.arena_from(s.frame_storage)
    let logical_width = f32(s.width) / s.scale
    let logical_height = f32(s.height) / s.scale
    let (compiled, reconcile_error) = widget.reconcile(s.runtime, &frame, root, ui_layout.Constraints { min_width: 0.0, max_width: logical_width, min_height: 0.0, max_height: logical_height })
    if reconcile_error != ok { ret reconcile_error }
    ret scene.render(widget.renderer_of(s.runtime), compiled, s.drawable, geometry.Size { width: logical_width, height: logical_height })
}

fn send(h: *Harness, event: input.Event) -> err {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret state_error }
    ret widget.dispatch(s.runtime, event)
}

fn by_key(h: *const Harness, key: widget.Key) -> Match {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret Match { element: zero, count: 0usize } }
    let (element, count) = widget.find_by_key(mem.cast[*widget.State](s.runtime.state), key)
    ret Match { element: element, count: count }
}

fn by_text(h: *const Harness, text: str) -> Match {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret Match { element: zero, count: 0usize } }
    let (element, count) = widget.find_by_text(mem.cast[*widget.State](s.runtime.state), text)
    ret Match { element: element, count: count }
}

// The last presented frame as premultiplied RGBA8 into `a`.
fn snapshot(h: *Harness, a: *mem.Arena) -> (image.Image, err) {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret (zero, state_error) }
    let (shown, shown_error) = gpu.presented(s.frames)
    if shown_error != ok { ret (zero, NotFound) }
    let count = usize(shown.width) * usize(shown.height)
    let (pixels, pixels_error) = mem.alloc[u32](a, count)
    if pixels_error != ok { ret (zero, pixels_error) }
    if gpu.read_image(s.queue, shown, pixels) != ok { ret (zero, NotFound) }
    let (bytes, bytes_error) = mem.alloc[u8](a, count * 4usize)
    if bytes_error != ok { ret (zero, bytes_error) }
    var i = 0usize
    while i < count {
        let p = pixels[i]
        bytes[i * 4usize] = u8(p & 255u32)
        bytes[i * 4usize + 1usize] = u8((p >> 8u32) & 255u32)
        bytes[i * 4usize + 2usize] = u8((p >> 16u32) & 255u32)
        bytes[i * 4usize + 3usize] = u8((p >> 24u32) & 255u32)
        i += 1usize
    }
    let (made, make_error) = image.make(bytes, shown.width, shown.height, usize(shown.width) * 4usize, .Rgba8, .Premultiplied)
    if make_error != ok { ret (zero, NotFound) }
    ret (made, ok)
}

// Every channel of every pixel within `tolerance` of the golden's; a different
// size or format is a mismatch too.
fn compare(actual: image.ConstImage, expected: image.ConstImage, tolerance: u8) -> err {
    if actual.width != expected.width || actual.height != expected.height || actual.format != expected.format { ret GoldenMismatch }
    let bytes = image.bytes_per_pixel(actual.format)
    var y = 0usize
    while y < usize(actual.height) {
        var x = 0usize
        while x < usize(actual.width) * bytes {
            let a = actual.pixels[y * actual.stride + x]
            let e = expected.pixels[y * expected.stride + x]
            var d = 0u8
            if a > e { d = a - e } else { d = e - a }
            if d > tolerance { ret GoldenMismatch }
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

fn close(h: *Harness) -> err {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret state_error }
    let closed = gpu.close_target(s.frames)
    s.closed = true
    ret ok
}
