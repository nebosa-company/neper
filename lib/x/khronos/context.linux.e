// `x.khronos.context` on Linux: OpenGL and OpenGL ES contexts through EGL (D5880). A headless
// context sits on Mesa's surfaceless platform and renders to framebuffer objects; without that
// platform it falls back to the default display and a 1x1 pbuffer. A window's context needs an
// Xlib `Display*`, which neper's X11 client -- a protocol socket of its own -- does not have, so
// the context opens a second connection through `libX11.so.6` and draws into the same window,
// since a window id is the server's and not the connection's. The variants for other hosts keep
// the same declarations.

use e.atomic
use e.mem
use e.os
use x.khronos.egl
use x.khronos.eglcontext
use x.khronos.gl

error Unsupported
error Failed

type Api = eglcontext.Api
type Options = eglcontext.Options
type Context = struct { egl_state: eglcontext.State, dispatch: gl.Dispatch, x_display: usize, window: usize, host: os.Window, has_host: bool }

type OpenDisplay = fn(*const u8) -> usize
type CloseDisplay = fn(usize) -> i32
type Xlib = struct { open_display: OpenDisplay, close_display: CloseDisplay }
type XlibLoader = struct { state: [1]Atomic[u32], waiters: [1]Atomic[u32], library: os.Lib, api: Xlib }
type PointerPun = union { pointer: *void, bits: usize }
type BytesPun = union { pointer: *u8, bits: usize }

const XLIB_IDLE: u32 = 0u32
const XLIB_FILLING: u32 = 1u32
const XLIB_READY: u32 = 2u32
const XLIB_FAILED: u32 = 3u32
var xlib_loader: XlibLoader = zero

fn profile_of(options: Options) -> gl.Profile { ret eglcontext.profile_of(options) }

// The resolver `gl.load` takes once a context is current.
fn resolve(a: *mem.Arena, context: usize, name: str) -> usize { ret egl.proc_address(a, context, name) }

fn resolver_context(c: *const Context) -> usize { ret 0usize }

// An address as the `void *` a GL call takes, and as the base of a `mem.view` over mapped memory.
fn as_pointer(bits: usize) -> *void {
    var pun: PointerPun = zero
    pun.bits = bits
    ret pun.pointer
}

fn as_bytes(bits: usize) -> *u8 {
    var pun: BytesPun = zero
    pun.bits = bits
    ret pun.pointer
}

fn mapped(e: err) -> err {
    if e == eglcontext.Unsupported { ret Unsupported }
    if e == eglcontext.Failed { ret Failed }
    ret e
}

// A context with no window, current on the calling thread; render into framebuffer objects.
fn headless(a: *mem.Arena, options: Options) -> (Context, err) {
    var c: Context = zero
    if egl.load(a, "") != ok { ret (c, Unsupported) }
    var display = egl.NO_DISPLAY
    if egl.present(egl.GET_PLATFORM_DISPLAY_ENTRY) { display = egl.get_platform_display(u32(egl.PLATFORM_SURFACELESS_MESA), nil, nil) }
    var surfaceless = true
    if eglcontext.initialize(display) != ok {
        display = egl.get_display(egl.DEFAULT_DISPLAY)
        surfaceless = false
        if eglcontext.initialize(display) != ok { ret (c, Unsupported) }
    }
    let (s, state_error) = eglcontext.headless(display, options, surfaceless)
    c.egl_state = s
    let outcome = mapped(state_error)
    if outcome != ok { let cleaned = close(&c) }
    ret (c, outcome)
}

fn initialize_xlib(a: *mem.Arena) -> err {
    let (library, library_error) = os.dlopen(a, "libX11.so.6")
    if library_error != ok { ret library_error }
    let (open_display, open_error) = os.dlsym[OpenDisplay](a, library, "XOpenDisplay")
    let (close_display, close_error) = os.dlsym[CloseDisplay](a, library, "XCloseDisplay")
    if open_error == os.OutOfMemory || close_error == os.OutOfMemory {
        let closed = os.dlclose(library)
        ret os.OutOfMemory
    }
    if open_error != ok || close_error != ok {
        let closed = os.dlclose(library)
        ret Unsupported
    }
    xlib_loader.library = library
    xlib_loader.api = Xlib { open_display: open_display, close_display: close_display }
    ret ok
}

fn increment_xlib_waiters() {
    while true {
        let current = atomic.load(&xlib_loader.waiters[0usize], .Acquire)
        let (changed, seen) = atomic.cas(&xlib_loader.waiters[0usize], current, current + 1u32, .AcqRel, .Acquire)
        if changed {
            os.wake_all_u32(&xlib_loader.waiters[0usize])
            ret
        }
    }
}

fn decrement_xlib_waiters() {
    while true {
        let current = atomic.load(&xlib_loader.waiters[0usize], .Acquire)
        let (changed, seen) = atomic.cas(&xlib_loader.waiters[0usize], current, current - 1u32, .AcqRel, .Acquire)
        if changed {
            os.wake_all_u32(&xlib_loader.waiters[0usize])
            ret
        }
    }
}

// The acquire and publish steps are shared with the deterministic loader-race fixture.
fn begin_xlib_load() {
    while true {
        let state = atomic.load(&xlib_loader.state[0usize], .Acquire)
        if state == XLIB_READY { ret }
        if state == XLIB_FAILED { ret }
        if state == XLIB_FILLING {
            increment_xlib_waiters()
            let ignored = os.wait_u32(&xlib_loader.state[0usize], XLIB_FILLING, -1i64)
            decrement_xlib_waiters()
            continue
        }
        let (won, seen) = atomic.cas(&xlib_loader.state[0usize], XLIB_IDLE, XLIB_FILLING, .Acquire, .Acquire)
        if !won { continue }
        ret
    }
}

fn finish_xlib_load(result: err) {
    var published = XLIB_IDLE
    if result == ok { published = XLIB_READY }
    if result == Unsupported { published = XLIB_FAILED }
    atomic.store(&xlib_loader.state[0usize], published, .Release)
    os.wake_all_u32(&xlib_loader.state[0usize])
    ret
}

// These narrow hooks let the Linux fixture hold an initialization lease at the
// same publication boundary used by the real dlopen/dlsym path.
fn test_begin_xlib_load() -> bool {
    begin_xlib_load()
    ret atomic.load(&xlib_loader.state[0usize], .Acquire) == XLIB_FILLING
}

fn test_finish_xlib_load(result: err) { finish_xlib_load(result) }

fn test_wait_for_xlib_waiter(timeout_ns: i64) -> err {
    if atomic.load(&xlib_loader.waiters[0usize], .Acquire) != 0u32 { ret ok }
    let waited = os.wait_u32(&xlib_loader.waiters[0usize], 0u32, timeout_ns)
    if waited != ok { ret waited }
    if atomic.load(&xlib_loader.waiters[0usize], .Acquire) == 0u32 { ret os.Timeout }
    ret ok
}

fn open_xlib(a: *mem.Arena) -> err {
    begin_xlib_load()
    let state = atomic.load(&xlib_loader.state[0usize], .Acquire)
    if state == XLIB_READY { ret ok }
    if state == XLIB_FAILED { ret Unsupported }
    let result = initialize_xlib(a)
    finish_xlib_load(result)
    ret result
}

// A context drawing into `w`'s client area, current on the calling thread.
fn for_window(a: *mem.Arena, w: os.Window, options: Options) -> (Context, err) {
    var c: Context = zero
    let (window_id, socket, native_error) = os.window_native(w)
    if native_error != ok { ret (c, native_error) }
    if os.window_hosted() {
        // (D5910) Another host's window (Android's ANativeWindow): EGL's default display and that window, no X11.
        if window_id == 0usize || egl.load(a, "") != ok { ret (c, Unsupported) }
        let hosted_display = egl.get_display(0usize)
        if eglcontext.initialize(hosted_display) != ok { ret (c, Unsupported) }
        let (hosted_state, hosted_error) = eglcontext.on_window(hosted_display, window_id, options)
        c.egl_state = hosted_state
        c.window = window_id
        c.host = w
        c.has_host = true
        if hosted_error == ok { remember_hosted(hosted_state.surface, window_id) }
        let outcome = mapped(hosted_error)
        if outcome != ok { let cleaned = close(&c) }
        ret (c, outcome)
    }
    if egl.load(a, "") != ok || open_xlib(a) != ok { ret (c, Unsupported) }
    let x_display = xlib_loader.api.open_display(nil)
    if x_display == 0usize { ret (c, Unsupported) }
    c.x_display = x_display
    c.window = window_id
    c.host = w
    c.has_host = true
    // EGL 1.4 takes the Xlib display as its native display; 1.5 names the platform.
    var display = egl.get_display(x_display)
    if egl.present(egl.GET_PLATFORM_DISPLAY_ENTRY) { display = egl.get_platform_display(u32(egl.PLATFORM_X11_KHR), as_pointer(x_display), nil) }
    if eglcontext.initialize(display) != ok {
        let cleaned = close(&c)
        ret (c, Unsupported)
    }
    let (s, state_error) = eglcontext.on_window(display, window_id, options)
    c.egl_state = s
    if state_error == ok { remember_size(s.surface, w) }
    let outcome = mapped(state_error)
    if outcome != ok { let cleaned = close(&c) }
    ret (c, outcome)
}

// The window's size as the surface was made, for make_current to compare with.
fn remember_size(surface: usize, w: os.Window) {
    let (metrics, metrics_error) = os.window_metrics(w)
    if metrics_error != ok { ret }
    var slot = 0usize
    var empty = 16usize
    while slot < 16usize {
        if sized_surfaces[slot] == surface { break }
        if sized_surfaces[slot] == 0usize && empty == 16usize { empty = slot }
        slot += 1usize
    }
    if slot == 16usize { slot = empty }
    if slot == 16usize { ret }
    sized_surfaces[slot] = surface
    sized_widths[slot] = metrics.width
    sized_heights[slot] = metrics.height
}

// Contexts and their EGL surfaces can be created and closed many times.  Free the
// resize bookkeeping with the surface so a later context is still tracked.
fn forget_size(surface: usize) {
    var slot = 0usize
    while slot < 16usize && sized_surfaces[slot] != surface { slot += 1usize }
    if slot == 16usize { ret }
    sized_surfaces[slot] = 0usize
    sized_widths[slot] = 0u32
    sized_heights[slot] = 0u32
}

// (D5899) Mesa's X11 window surface reports a resized window's new size at once, but its buffers keep the old one until a
// swap: the first frame after a resize would be drawn into a stale buffer (its new part uninitialised). So when the window's
// size differs from the size this surface was last made current at, the surface is swapped once first -- the last frame
// shown again -- and the frame that follows has buffers of the new size.
var sized_surfaces: [16]usize = zero
var sized_widths: [16]u32 = zero
var sized_heights: [16]u32 = zero

// (D5910) A hosted context's window can go and come back (Android destroys it on pause and makes a new one on resume), and
// a surface is made on one window: each context, named by the surface it was made with, keeps the window and surface it
// has now, and gets a new surface when the host's window is another.
var hosted_keys: [16]usize = zero
var hosted_natives: [16]usize = zero
var hosted_surfaces: [16]usize = zero

fn remember_hosted(surface: usize, native: usize) {
    var slot = 0usize
    while slot < 16usize && hosted_keys[slot] != 0usize { slot += 1usize }
    if slot == 16usize { ret }
    hosted_keys[slot] = surface
    hosted_natives[slot] = native
    hosted_surfaces[slot] = surface
}

// The replacement surface belongs to the State at close, not the original
// surface which an Android window replacement may already have destroyed.
fn forget_hosted(c: *Context) {
    var slot = 0usize
    while slot < 16usize && hosted_keys[slot] != c.egl_state.surface { slot += 1usize }
    if slot == 16usize { ret }
    c.egl_state.surface = hosted_surfaces[slot]
    hosted_keys[slot] = 0usize
    hosted_natives[slot] = 0usize
    hosted_surfaces[slot] = 0usize
}

// The surface to draw a hosted context into now; NO_SURFACE while the host has no window.
fn hosted_surface(c: *const Context) -> usize {
    var slot = 0usize
    while slot < 16usize && hosted_keys[slot] != c.egl_state.surface { slot += 1usize }
    if slot == 16usize { ret c.egl_state.surface }
    let (native, extra, native_error) = os.window_native(c.host)
    if native_error != ok || native == 0usize { ret egl.NO_SURFACE }
    if native != hosted_natives[slot] {
        let released = egl.make_current(c.egl_state.display, egl.NO_SURFACE, egl.NO_SURFACE, egl.NO_CONTEXT)
        if hosted_surfaces[slot] != egl.NO_SURFACE { let destroyed = egl.destroy_surface(c.egl_state.display, hosted_surfaces[slot]) }
        hosted_surfaces[slot] = egl.create_window_surface(c.egl_state.display, c.egl_state.config, native, nil)
        hosted_natives[slot] = native
    }
    ret hosted_surfaces[slot]
}

fn make_current(c: *const Context) -> err {
    if c.has_host && os.window_hosted() {
        let surface = hosted_surface(c)
        if surface == egl.NO_SURFACE || !c.egl_state.live { ret Failed }
        if egl.make_current(c.egl_state.display, surface, surface, c.egl_state.context) != egl.TRUE { ret Failed }
        if !gl.activate(&c.dispatch) { ret Failed }
        ret ok
    }
    let made = mapped(eglcontext.make_current(&c.egl_state))
    if made != ok { ret made }
    if !gl.activate(&c.dispatch) { ret Failed }
    if !c.has_host || c.egl_state.surface == egl.NO_SURFACE { ret made }
    let (metrics, metrics_error) = os.window_metrics(c.host)
    if metrics_error != ok { ret made }
    var slot = 0usize
    while slot < 16usize && sized_surfaces[slot] != c.egl_state.surface && sized_surfaces[slot] != 0usize { slot += 1usize }
    if slot == 16usize { ret made }
    if sized_surfaces[slot] == c.egl_state.surface && (sized_widths[slot] != metrics.width || sized_heights[slot] != metrics.height) {
        let swapped = egl.swap_buffers(c.egl_state.display, c.egl_state.surface)
    }
    sized_surfaces[slot] = c.egl_state.surface
    sized_widths[slot] = metrics.width
    sized_heights[slot] = metrics.height
    ret made
}

fn swap(c: *const Context) -> err {
    if c.has_host && os.window_hosted() {
        let surface = hosted_surface(c)
        if surface == egl.NO_SURFACE || egl.swap_buffers(c.egl_state.display, surface) != egl.TRUE { ret Failed }
        ret ok
    }
    ret mapped(eglcontext.swap(&c.egl_state))
}

// 1 waits for the vertical blank, 0 does not.
fn swap_interval(c: *const Context, interval: i32) -> err { ret mapped(eglcontext.swap_interval(&c.egl_state, interval)) }

// Fills this current context's dispatch table for the profile `options` names.
fn load(a: *mem.Arena, c: *Context, options: Options) -> err {
    ret gl.load(a, profile_of(options), resolve, resolver_context(c), &c.dispatch)
}

fn close(c: *Context) -> err {
    forget_size(c.egl_state.surface)
    if c.has_host && c.x_display == 0usize { forget_hosted(c) }
    let closed = eglcontext.close(&c.egl_state)
    gl.release(&c.dispatch)
    if c.x_display != 0usize {
        let gone = xlib_loader.api.close_display(c.x_display)
        c.x_display = 0usize
    }
    ret ok
}
