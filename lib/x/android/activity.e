// `x.android.activity` (L182, D5910): a NativeActivity's window and input as `e.os` windows, so an `e.ui` program runs as
// an Android app unchanged. The program's exported `ANativeActivity_onCreate` (D5908) calls `start` with its entry; this
// module takes the activity's callbacks, installs itself as `e.os`'s window host, and runs the entry on a thread of its
// own, since the callbacks come on Android's UI thread and must return.
//
// The UI thread only hands things over: a window or an input queue that appears is offered to the app thread, which takes
// it the next time it polls, and one that goes away is withdrawn and waited for -- the callback returns only once the app
// thread has let go of it, as Android requires. The app thread waits on its own ALooper, which the callbacks wake.
//
// Touches are the pointer (button 1), Back is Close, the screen's density is the scale. A frame without a GL presenter
// is copied into the window through ANativeWindow_lock; with one, EGL draws into the window, and its surface is made
// again on the window that comes back after a pause (x.khronos.context, D5910).

use e.mem
use e.os

@import("libandroid.so", "ANativeWindow_getWidth")
extern fn window_width(window: usize) -> i32
@import("libandroid.so", "ANativeWindow_getHeight")
extern fn window_height(window: usize) -> i32
@import("libandroid.so", "ANativeWindow_setBuffersGeometry")
extern fn window_geometry(window: usize, width: i32, height: i32, format: i32) -> i32
@import("libandroid.so", "ANativeWindow_lock")
extern fn window_lock(window: usize, buffer: *NativeBuffer, dirty: usize) -> i32
@import("libandroid.so", "ANativeWindow_unlockAndPost")
extern fn window_post(window: usize) -> i32
@import("libandroid.so", "ALooper_prepare")
extern fn looper_prepare(options: i32) -> usize
@import("libandroid.so", "ALooper_pollOnce")
extern fn looper_poll(timeout_ms: i32, fd: *i32, events: *i32, data: *usize) -> i32
@import("libandroid.so", "ALooper_wake")
extern fn looper_wake(looper: usize)
@import("libandroid.so", "AInputQueue_attachLooper")
extern fn queue_attach(queue: usize, looper: usize, ident: i32, callback: usize, data: usize)
@import("libandroid.so", "AInputQueue_detachLooper")
extern fn queue_detach(queue: usize)
@import("libandroid.so", "AInputQueue_getEvent")
extern fn queue_get(queue: usize, event: *usize) -> i32
@import("libandroid.so", "AInputQueue_preDispatchEvent")
extern fn queue_predispatch(queue: usize, event: usize) -> i32
@import("libandroid.so", "AInputQueue_finishEvent")
extern fn queue_finish(queue: usize, event: usize, handled: i32)
@import("libandroid.so", "AInputEvent_getType")
extern fn event_type(event: usize) -> i32
@import("libandroid.so", "AMotionEvent_getAction")
extern fn motion_action(event: usize) -> i32
@import("libandroid.so", "AMotionEvent_getX")
extern fn motion_x(event: usize, index: usize) -> f32
@import("libandroid.so", "AMotionEvent_getY")
extern fn motion_y(event: usize, index: usize) -> f32
@import("libandroid.so", "AKeyEvent_getKeyCode")
extern fn key_code(event: usize) -> i32
@import("libandroid.so", "AKeyEvent_getAction")
extern fn key_action(event: usize) -> i32
@import("libandroid.so", "ANativeActivity_finish")
extern fn activity_finish(activity: usize)
@import("libandroid.so", "AConfiguration_new")
extern fn configuration_new() -> usize
@import("libandroid.so", "AConfiguration_fromAssetManager")
extern fn configuration_from_assets(configuration: usize, assets: usize)
@import("libandroid.so", "AConfiguration_getDensity")
extern fn configuration_density(configuration: usize) -> i32
@import("libandroid.so", "AConfiguration_delete")
extern fn configuration_delete(configuration: usize)
@import("libc.so", "pthread_attr_init")
extern fn pthread_attr_init(attributes: *u64) -> i32
@import("libc.so", "pthread_attr_setstacksize")
extern fn pthread_attr_setstacksize(attributes: *u64, size: usize) -> i32
@import("libc.so", "pthread_create")
extern fn pthread_create(thread: *usize, attributes: *u64, routine: usize, argument: usize) -> i32
@import("libc.so", "mmap")
extern fn mmap(address: usize, length: usize, protection: i32, flags: i32, fd: i32, offset: isize) -> usize
@import("libc.so", "usleep")
extern fn usleep(microseconds: u32) -> i32

error Unsupported

// ANativeWindow_Buffer.
type NativeBuffer = struct { width: i32, height: i32, stride: i32, format: i32, bits: usize, reserved: [6]u32 }

// ANativeActivityCallbacks, in its order; only the ones set below are ever written.
type Callbacks = struct {
    on_start: fn(usize),
    on_resume: fn(usize),
    on_save_instance_state: fn(usize, usize) -> usize,
    on_pause: fn(usize),
    on_stop: fn(usize),
    on_destroy: fn(usize),
    on_window_focus_changed: fn(usize, i32),
    on_native_window_created: fn(usize, usize),
    on_native_window_resized: fn(usize, usize),
    on_native_window_redraw_needed: fn(usize, usize),
    on_native_window_destroyed: fn(usize, usize),
    on_input_queue_created: fn(usize, usize),
    on_input_queue_destroyed: fn(usize, usize),
}

type Entry = struct { run: fn(*mem.Arena) -> err }
type WordPun = union { pointer: *usize, bits: usize }
type BytesPun = union { pointer: *u8, bits: usize }
type ThreadStart = union { function: fn(usize) -> usize, bits: usize }

const EVENT_RING: usize = 64usize
const DONE: usize = 18446744073709551615usize
// The app's arena: reserved, not committed (MAP_NORESERVE), so its size costs address space alone.
const ARENA_BYTES: usize = 536870912usize
const STACK_BYTES: usize = 16777216usize

var entry: Entry = zero
var native: usize = 0usize
var app_looper: usize = 0usize
var scale_percent: u32 = 100u32
// Offered by the UI thread, taken by the app thread: the window and queue there are now (0 for none), and what the app
// thread last took, which a withdrawing callback waits to see become 0.
var offered_window: usize = 0usize
var taken_window: usize = DONE
var offered_queue: usize = 0usize
var taken_queue: usize = DONE
var destroyed: bool = false
// The app thread's own.
var current_window: usize = 0usize
var attached_queue: usize = 0usize
var geometry_width: i32 = 0i32
var geometry_height: i32 = 0i32
var pending: [64]os.WindowEvent = zero
var event_head: usize = 0usize
var event_count: usize = 0usize

fn word_at(address: usize) -> usize {
    var pun: WordPun = zero
    pun.bits = address
    ret *pun.pointer
}

fn wake() {
    if app_looper != 0usize { looper_wake(app_looper) }
}

// Until the app thread has taken `wanted` (0: let go of the old one), or two seconds.
fn wait_taken(window: bool, wanted: usize) {
    var waited = 0u32
    while waited < 1000u32 {
        if window && taken_window == wanted { ret }
        if !window && taken_queue == wanted { ret }
        wake()
        let slept = usleep(2000u32)
        waited += 1u32
    }
}

@cc(c)
fn window_created(source: usize, window: usize) {
    offered_window = window
    wake()
}

@cc(c)
fn window_destroyed(source: usize, window: usize) {
    offered_window = 0usize
    wait_taken(true, 0usize)
}

@cc(c)
fn queue_created(source: usize, queue: usize) {
    offered_queue = queue
    wake()
}

@cc(c)
fn queue_destroyed(source: usize, queue: usize) {
    offered_queue = 0usize
    wait_taken(false, 0usize)
}

@cc(c)
fn activity_destroyed(source: usize) {
    destroyed = true
    wake()
}

fn push(event: os.WindowEvent) {
    if event_count == EVENT_RING { ret }
    pending[(event_head + event_count) % EVENT_RING] = event
    event_count += 1usize
}

fn event_of(kind: os.WindowEventKind) -> os.WindowEvent {
    var event: os.WindowEvent = zero
    event.kind = kind
    event.window = os.Window { raw: 1usize }
    ret event
}

// The app thread's side of the hand-over, then whatever input is waiting.
fn take() {
    if offered_window != current_window {
        current_window = offered_window
        taken_window = current_window
        if current_window != 0usize {
            var resized = event_of(.Resize)
            resized.width = u32(window_width(current_window))
            resized.height = u32(window_height(current_window))
            push(resized)
            push(event_of(.Paint))
            geometry_width = 0i32
        }
    }
    if offered_queue != attached_queue {
        if attached_queue != 0usize { queue_detach(attached_queue) }
        attached_queue = offered_queue
        if attached_queue != 0usize { queue_attach(attached_queue, app_looper, 1i32, 0usize, 0usize) }
        taken_queue = attached_queue
    }
    if destroyed {
        destroyed = false
        push(event_of(.Close))
    }
    var event = 0usize
    while attached_queue != 0usize && queue_get(attached_queue, &event) >= 0i32 {
        if queue_predispatch(attached_queue, event) != 0i32 { continue }
        var handled = 0i32
        let kind = event_type(event)
        if kind == 2i32 {
            let action = motion_action(event) & 255i32
            var moved = event_of(.PointerMove)
            moved.x = i32(motion_x(event, 0usize))
            moved.y = i32(motion_y(event, 0usize))
            push(moved)
            if action == 0i32 {
                var down = moved
                down.kind = .PointerDown
                down.button = 1u8
                push(down)
            }
            if action == 1i32 || action == 3i32 {
                var up = moved
                up.kind = .PointerUp
                up.button = 1u8
                push(up)
            }
            handled = 1i32
        }
        // Back, released: the window is asked to close.
        if kind == 1i32 && key_code(event) == 4i32 && key_action(event) == 1i32 {
            push(event_of(.Close))
            handled = 1i32
        }
        queue_finish(attached_queue, event, handled)
    }
}

fn host_open(a: *mem.Arena, options: os.WindowOptions) -> (os.Window, err) {
    var tries = 0usize
    while tries < 200usize {
        take()
        if current_window != 0usize { ret (os.Window { raw: 1usize }, ok) }
        var fd = 0i32
        var flags = 0i32
        var data = 0usize
        let polled = looper_poll(50i32, &fd, &flags, &data)
        tries += 1usize
    }
    ret (zero, Unsupported)
}

fn host_close(w: os.Window) -> err {
    activity_finish(native)
    ret ok
}

fn host_poll(timeout_ns: i64) -> (os.WindowEvent, bool, err) {
    take()
    if event_count == 0usize {
        var wait_ms = 0i32
        if timeout_ns > 0i64 { wait_ms = i32((timeout_ns + 999999i64) / 1000000i64) }
        var fd = 0i32
        var flags = 0i32
        var data = 0usize
        let polled = looper_poll(wait_ms, &fd, &flags, &data)
        take()
    }
    if event_count == 0usize { ret (zero, false, ok) }
    let event = pending[event_head]
    event_head = (event_head + 1usize) % EVENT_RING
    event_count -= 1usize
    ret (event, true, ok)
}

fn host_metrics(w: os.Window) -> (os.WindowMetrics, err) {
    var metrics: os.WindowMetrics = zero
    if current_window != 0usize {
        metrics.width = u32(window_width(current_window))
        metrics.height = u32(window_height(current_window))
        metrics.visible = true
        metrics.focused = true
    }
    metrics.scale_percent = scale_percent
    ret (metrics, ok)
}

// A frame (BGRA words, rows from the top) copied into the window's next buffer as RGBX bytes.
fn host_present(w: os.Window, pixels: []const u32, width: u32, height: u32) -> err {
    if current_window == 0usize { ret ok }
    if pixels.len < usize(width) * usize(height) { ret Unsupported }
    if geometry_width != i32(width) || geometry_height != i32(height) {
        // WINDOW_FORMAT_RGBX_8888.
        if window_geometry(current_window, i32(width), i32(height), 2i32) != 0i32 { ret Unsupported }
        geometry_width = i32(width)
        geometry_height = i32(height)
    }
    var buffer: NativeBuffer = zero
    if window_lock(current_window, &buffer, 0usize) != 0i32 { ret Unsupported }
    var rows = u32(buffer.height)
    if height < rows { rows = height }
    var columns = u32(buffer.width)
    if width < columns { columns = width }
    var pun: BytesPun = zero
    var row = 0u32
    while row < rows {
        var column = 0u32
        while column < columns {
            let word = pixels[usize(row) * usize(width) + usize(column)]
            pun.bits = buffer.bits + (usize(row) * usize(buffer.stride) + usize(column)) * 4usize
            let swapped = (word & 4278255360u32) | ((word >> 16u32) & 255u32) | ((word & 255u32) << 16u32) | 4278190080u32
            let target_word = mem.cast[*u32](pun.pointer)
            *target_word = swapped
            column += 1u32
        }
        row += 1u32
    }
    if window_post(current_window) != 0i32 { ret Unsupported }
    ret ok
}

fn host_native(w: os.Window) -> (usize, usize, err) { ret (current_window, 0usize, ok) }

@cc(c)
fn app_thread(argument: usize) -> usize {
    app_looper = looper_prepare(0i32)
    // PROT_READ | PROT_WRITE; MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE.
    let base = mmap(0usize, ARENA_BYTES, 3i32, 16418i32, -1i32, 0isize)
    if base == DONE || base == 0usize {
        activity_finish(native)
        ret 0usize
    }
    var arena: mem.Arena = zero
    var pun: BytesPun = zero
    pun.bits = base
    arena.base = pun.pointer
    arena.cap = ARENA_BYTES
    arena.off = 0usize
    let ran = entry.run(&arena)
    activity_finish(native)
    ret 0usize
}

// From the program's `ANativeActivity_onCreate`: takes `native_activity`'s callbacks, makes this module the window host,
// and starts `run` on a thread of its own.
fn start(native_activity: usize, run: fn(*mem.Arena) -> err) {
    native = native_activity
    entry.run = run
    // ANativeActivity: callbacks at 0, the AAssetManager at 64.
    let configuration = configuration_new()
    if configuration != 0usize {
        configuration_from_assets(configuration, word_at(native_activity + 64usize))
        let density = configuration_density(configuration)
        if density > 0i32 { scale_percent = u32(density) * 100u32 / 160u32 }
        configuration_delete(configuration)
    }
    var callbacks_pun: WordPun = zero
    callbacks_pun.bits = word_at(native_activity)
    let callbacks = mem.cast[*Callbacks](callbacks_pun.pointer)
    callbacks.on_destroy = activity_destroyed
    callbacks.on_native_window_created = window_created
    callbacks.on_native_window_destroyed = window_destroyed
    callbacks.on_input_queue_created = queue_created
    callbacks.on_input_queue_destroyed = queue_destroyed
    os.set_window_host(os.WindowHost { open: host_open, close: host_close, poll: host_poll, metrics: host_metrics, present: host_present, native: host_native })
    var attributes: [8]u64 = zero
    let initialised = pthread_attr_init(&attributes[0usize])
    let sized = pthread_attr_setstacksize(&attributes[0usize], STACK_BYTES)
    var thread = 0usize
    var start_pun: ThreadStart = zero
    start_pun.function = app_thread
    let created = pthread_create(&thread, &attributes[0usize], start_pun.bits, 0usize)
}
