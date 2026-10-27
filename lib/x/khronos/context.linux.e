// `x.khronos.context` on Linux: OpenGL and OpenGL ES contexts through EGL (D5880). A headless
// context sits on Mesa's surfaceless platform and renders to framebuffer objects; without that
// platform it falls back to the default display and a 1x1 pbuffer. A window's context needs an
// Xlib `Display*`, which neper's X11 client -- a protocol socket of its own -- does not have, so
// the context opens a second connection through `libX11.so.6` and draws into the same window,
// since a window id is the server's and not the connection's. The variants for other hosts keep
// the same declarations.

use e.mem
use e.os
use x.khronos.egl
use x.khronos.eglcontext
use x.khronos.gl

error Unsupported
error Failed

type Api = eglcontext.Api
type Options = eglcontext.Options
type Context = struct { egl_state: eglcontext.State, x_display: usize, window: usize, host: os.Window, has_host: bool }

type OpenDisplay = fn(*const u8) -> usize
type CloseDisplay = fn(usize) -> i32
type Xlib = struct { open_display: OpenDisplay, close_display: CloseDisplay }
type PointerPun = union { pointer: *void, bits: usize }
type BytesPun = union { pointer: *u8, bits: usize }

var xlib_loaded: bool = false
var xlib_library: os.Lib = zero
var xlib: Xlib = zero

fn profile_of(options: Options) -> gl.Profile { ret eglcontext.profile_of(options) }

// The resolver `gl.load` takes once a context is current.
fn resolve(a: *mem.Arena, context: usize, name: str) -> usize { ret egl.proc_address(a, context, name) }

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
    ret (c, mapped(state_error))
}

fn open_xlib(a: *mem.Arena) -> err {
    if xlib_loaded { ret ok }
    let (library, library_error) = os.dlopen(a, "libX11.so.6")
    if library_error != ok { ret Unsupported }
    let (open_display, open_error) = os.dlsym[OpenDisplay](a, library, "XOpenDisplay")
    let (close_display, close_error) = os.dlsym[CloseDisplay](a, library, "XCloseDisplay")
    if open_error != ok || close_error != ok {
        let closed = os.dlclose(library)
        ret Unsupported
    }
    xlib_library = library
    xlib = Xlib { open_display: open_display, close_display: close_display }
    xlib_loaded = true
    ret ok
}

// A context drawing into `w`'s client area, current on the calling thread.
fn for_window(a: *mem.Arena, w: os.Window, options: Options) -> (Context, err) {
    var c: Context = zero
    let (window_id, socket, native_error) = os.window_native(w)
    if native_error != ok { ret (c, native_error) }
    if egl.load(a, "") != ok || open_xlib(a) != ok { ret (c, Unsupported) }
    let x_display = xlib.open_display(nil)
    if x_display == 0usize { ret (c, Unsupported) }
    c.x_display = x_display
    c.window = window_id
    c.host = w
    c.has_host = true
    // EGL 1.4 takes the Xlib display as its native display; 1.5 names the platform.
    var display = egl.get_display(x_display)
    if egl.present(egl.GET_PLATFORM_DISPLAY_ENTRY) { display = egl.get_platform_display(u32(egl.PLATFORM_X11_KHR), as_pointer(x_display), nil) }
    if eglcontext.initialize(display) != ok { ret (c, Unsupported) }
    let (s, state_error) = eglcontext.on_window(display, window_id, options)
    c.egl_state = s
    if state_error == ok { remember_size(s.surface, w) }
    ret (c, mapped(state_error))
}

// The window's size as the surface was made, for make_current to compare with.
fn remember_size(surface: usize, w: os.Window) {
    let (metrics, metrics_error) = os.window_metrics(w)
    if metrics_error != ok { ret }
    var slot = 0usize
    while slot < 16usize && sized_surfaces[slot] != surface && sized_surfaces[slot] != 0usize { slot += 1usize }
    if slot == 16usize { ret }
    sized_surfaces[slot] = surface
    sized_widths[slot] = metrics.width
    sized_heights[slot] = metrics.height
}

// (D5899) Mesa's X11 window surface reports a resized window's new size at once, but its buffers keep the old one until a
// swap: the first frame after a resize would be drawn into a stale buffer (its new part uninitialised). So when the window's
// size differs from the size this surface was last made current at, the surface is swapped once first -- the last frame
// shown again -- and the frame that follows has buffers of the new size.
var sized_surfaces: [16]usize = zero
var sized_widths: [16]u32 = zero
var sized_heights: [16]u32 = zero

fn make_current(c: *const Context) -> err {
    let made = mapped(eglcontext.make_current(&c.egl_state))
    if made != ok || !c.has_host || c.egl_state.surface == egl.NO_SURFACE { ret made }
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

fn swap(c: *const Context) -> err { ret mapped(eglcontext.swap(&c.egl_state)) }

// 1 waits for the vertical blank, 0 does not.
fn swap_interval(c: *const Context, interval: i32) -> err { ret mapped(eglcontext.swap_interval(&c.egl_state, interval)) }

// Fills `gl`'s table for the current context and the profile `options` names.
fn load(a: *mem.Arena, options: Options) -> err { ret gl.load(a, profile_of(options), resolve, 0usize) }

fn close(c: *Context) -> err {
    let closed = eglcontext.close(&c.egl_state)
    if c.x_display != 0usize {
        let gone = xlib.close_display(c.x_display)
        c.x_display = 0usize
    }
    ret ok
}
