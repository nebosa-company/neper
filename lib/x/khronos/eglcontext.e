// `x.khronos.eglcontext`: the part of a GL context that is EGL's on every host (D5880): picking
// a config, creating the context, a headless or window surface, making it current, swapping.
// `x.khronos.context` opens the display its host needs -- Mesa's surfaceless platform or an
// Xlib connection on Linux, ANGLE's default display on Windows -- and hands it here.

use e.mem
use x.khronos.egl
use x.khronos.gl

error Unsupported
error Failed

type Api = enum u8 { Gl, Gles }
type Options = struct { api: Api, major: u32, minor: u32 }
type State = struct { display: usize, config: usize, context: usize, surface: usize, initialized: bool, live: bool }

// The EGL calls used to release a state.  Keeping this tiny seam explicit lets
// the cleanup order be checked without a particular driver's failure behaviour.
type Releaser = struct {
    make_current: fn(usize, usize, usize, usize) -> u32,
    destroy_surface: fn(usize, usize) -> u32,
    destroy_context: fn(usize, usize) -> u32,
    terminate: fn(usize) -> u32,
}

fn profile_of(options: Options) -> gl.Profile {
    if options.api == .Gles {
        if options.major > 3u32 || (options.major == 3u32 && options.minor >= 2u32) { ret .Gles32 }
        if options.major == 3u32 && options.minor == 1u32 { ret .Gles31 }
        ret .Gles30
    }
    if options.major > 4u32 || (options.major == 4u32 && options.minor >= 6u32) { ret .Gl46Core }
    if options.major == 4u32 && options.minor >= 3u32 { ret .Gl43Core }
    ret .Gl33Core
}

// The EGL resolver, for `gl.load` once a context is current.
fn resolve(a: *mem.Arena, context: usize, name: str) -> usize { ret egl.proc_address(a, context, name) }

fn initialize(display: usize) -> err {
    if display == egl.NO_DISPLAY { ret Unsupported }
    var major = 0i32
    var minor = 0i32
    if egl.initialize(display, &major, &minor) != egl.TRUE { ret Unsupported }
    ret ok
}

// The first RGBA8 config that renders `options.api` on `surface_bits` surfaces (0: any kind).
fn choose(display: usize, options: Options, surface_bits: i32) -> (usize, err) {
    var attributes: [16]i32 = zero
    attributes[0usize] = egl.RENDERABLE_TYPE
    if options.api == .Gles { attributes[1usize] = egl.OPENGL_ES3_BIT } else { attributes[1usize] = egl.OPENGL_BIT }
    // Always named: left out, it defaults to EGL_WINDOW_BIT, which no surfaceless config has.
    attributes[2usize] = egl.SURFACE_TYPE
    attributes[3usize] = surface_bits
    attributes[4usize] = egl.RED_SIZE
    attributes[5usize] = 8i32
    attributes[6usize] = egl.GREEN_SIZE
    attributes[7usize] = 8i32
    attributes[8usize] = egl.BLUE_SIZE
    attributes[9usize] = 8i32
    attributes[10usize] = egl.ALPHA_SIZE
    attributes[11usize] = 8i32
    attributes[12usize] = egl.NONE
    var config = 0usize
    var count = 0i32
    if egl.choose_config(display, &attributes[0usize], &config, 1i32, &count) != egl.TRUE || count < 1i32 { ret (0usize, Unsupported) }
    ret (config, ok)
}

fn create(s: *State, options: Options, surface_bits: i32) -> err {
    var api_value = egl.OPENGL_API
    if options.api == .Gles { api_value = egl.OPENGL_ES_API }
    if egl.bind_api(u32(api_value)) != egl.TRUE { ret Unsupported }
    let (config, config_error) = choose(s.display, options, surface_bits)
    if config_error != ok { ret config_error }
    s.config = config
    var attributes: [8]i32 = zero
    attributes[0usize] = egl.CONTEXT_MAJOR_VERSION
    attributes[1usize] = i32(options.major)
    attributes[2usize] = egl.CONTEXT_MINOR_VERSION
    attributes[3usize] = i32(options.minor)
    attributes[4usize] = egl.NONE
    if options.api == .Gl && (options.major > 3u32 || (options.major == 3u32 && options.minor >= 2u32)) {
        attributes[4usize] = egl.CONTEXT_OPENGL_PROFILE_MASK
        attributes[5usize] = egl.CONTEXT_OPENGL_CORE_PROFILE_BIT
        attributes[6usize] = egl.NONE
    }
    let context = egl.create_context(s.display, config, egl.NO_CONTEXT, &attributes[0usize])
    if context == egl.NO_CONTEXT { ret Unsupported }
    s.context = context
    s.live = true
    ret ok
}

// A context with no window on an initialized `display`, current on the calling thread. It is
// surfaceless where the driver allows that, and on a 1x1 pbuffer where it does not.
fn headless(display: usize, options: Options, surfaceless: bool) -> (State, err) {
    var s: State = zero
    s.display = display
    s.initialized = true
    var surface_bits = 0i32
    if !surfaceless { surface_bits = egl.PBUFFER_BIT }
    let create_error = create(&s, options, surface_bits)
    if create_error != ok {
        let closed = close(&s)
        ret (s, create_error)
    }
    if egl.make_current(display, egl.NO_SURFACE, egl.NO_SURFACE, s.context) == egl.TRUE { ret (s, ok) }
    var pbuffer: [8]i32 = zero
    pbuffer[0usize] = egl.WIDTH
    pbuffer[1usize] = 1i32
    pbuffer[2usize] = egl.HEIGHT
    pbuffer[3usize] = 1i32
    pbuffer[4usize] = egl.NONE
    if surfaceless {
        let (config, config_error) = choose(display, options, egl.PBUFFER_BIT)
        if config_error != ok {
            let closed = close(&s)
            ret (s, Failed)
        }
        s.config = config
    }
    s.surface = egl.create_pbuffer_surface(display, s.config, &pbuffer[0usize])
    if s.surface == egl.NO_SURFACE || egl.make_current(display, s.surface, s.surface, s.context) != egl.TRUE {
        let closed = close(&s)
        ret (s, Failed)
    }
    ret (s, ok)
}

// A context drawing into the native window `native` (an X11 window id, an HWND) on an
// initialized `display`, current on the calling thread.
fn on_window(display: usize, native: usize, options: Options) -> (State, err) {
    var s: State = zero
    s.display = display
    s.initialized = true
    let create_error = create(&s, options, egl.WINDOW_BIT)
    if create_error != ok {
        let closed = close(&s)
        ret (s, create_error)
    }
    s.surface = egl.create_window_surface(display, s.config, native, nil)
    if s.surface == egl.NO_SURFACE {
        let closed = close(&s)
        ret (s, Failed)
    }
    if egl.make_current(display, s.surface, s.surface, s.context) != egl.TRUE {
        let closed = close(&s)
        ret (s, Failed)
    }
    ret (s, ok)
}

fn make_current(s: *const State) -> err {
    if !s.live { ret Failed }
    if egl.make_current(s.display, s.surface, s.surface, s.context) != egl.TRUE { ret Failed }
    ret ok
}

fn swap(s: *const State) -> err {
    if !s.live || s.surface == egl.NO_SURFACE { ret Failed }
    if egl.swap_buffers(s.display, s.surface) != egl.TRUE { ret Failed }
    ret ok
}

fn swap_interval(s: *const State, interval: i32) -> err {
    if !s.live { ret Failed }
    if egl.swap_interval(s.display, interval) != egl.TRUE { ret Unsupported }
    ret ok
}

fn release_with(s: *State, releaser: Releaser) {
    if !s.initialized { ret }
    let released = releaser.make_current(s.display, egl.NO_SURFACE, egl.NO_SURFACE, egl.NO_CONTEXT)
    if s.surface != egl.NO_SURFACE { let destroyed = releaser.destroy_surface(s.display, s.surface) }
    if s.context != egl.NO_CONTEXT { let gone = releaser.destroy_context(s.display, s.context) }
    let finished = releaser.terminate(s.display)
    s.display = egl.NO_DISPLAY
    s.config = 0usize
    s.context = egl.NO_CONTEXT
    s.surface = egl.NO_SURFACE
    s.initialized = false
    s.live = false
}

fn native_make_current(display: usize, draw: usize, read: usize, context: usize) -> u32 {
    ret egl.make_current(display, draw, read, context)
}

fn native_destroy_surface(display: usize, surface: usize) -> u32 { ret egl.destroy_surface(display, surface) }
fn native_destroy_context(display: usize, context: usize) -> u32 { ret egl.destroy_context(display, context) }
fn native_terminate(display: usize) -> u32 { ret egl.terminate(display) }

fn close(s: *State) -> err {
    let releaser = Releaser {
        make_current: native_make_current,
        destroy_surface: native_destroy_surface,
        destroy_context: native_destroy_context,
        terminate: native_terminate,
    }
    release_with(s, releaser)
    ret ok
}
