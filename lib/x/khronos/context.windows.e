// `x.khronos.context` on Windows (D5880, D5886): desktop OpenGL through WGL and the driver's
// ICD, OpenGL ES through ANGLE's `libEGL.dll`, which must be on the DLL search path (next to
// the program, or on PATH). A WGL context needs a window's device context even when it draws
// nothing, so a headless one owns a hidden `os` window. A core context is made in two steps on
// the same device context -- a legacy context first, made current only to look up
// `wglCreateContextAttribsARB` -- so no throwaway window is needed. `resolve` asks
// `wglGetProcAddress`, which answers nothing (or 1, 2, 3, -1) for the GL 1.1 entry points, and
// falls back to opengl32.dll's own exports for those. The variants for other hosts keep the
// same declarations.

use e.mem
use e.os
use x.khronos.egl
use x.khronos.eglcontext
use x.khronos.gl

error Unsupported
error Failed

type Api = eglcontext.Api
type Options = eglcontext.Options
type Context = struct { egl_state: eglcontext.State, dispatch: gl.Dispatch, uses_egl: bool, hwnd: usize, hdc: usize, wgl: usize, hidden: os.Window, owns_window: bool, live: bool }

// WGL_ARB_create_context and WGL_ARB_create_context_profile: wglext.h is not in scripts/khronos,
// and these four values are all of it this module uses.
const WGL_CONTEXT_MAJOR_VERSION_ARB: i32 = 8337i32
const WGL_CONTEXT_MINOR_VERSION_ARB: i32 = 8338i32
const WGL_CONTEXT_PROFILE_MASK_ARB: i32 = 37158i32
const WGL_CONTEXT_CORE_PROFILE_BIT_ARB: i32 = 1i32
// PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER.
const PFD_FLAGS: u32 = 37u32

@import("user32.dll", "GetDC")
extern fn raw_get_dc(hwnd: usize) -> usize
@import("user32.dll", "ReleaseDC")
extern fn raw_release_dc(hwnd: usize, hdc: usize) -> i32
@import("gdi32.dll", "ChoosePixelFormat")
extern fn raw_choose_pixel_format(hdc: usize, descriptor: *const u8) -> i32
@import("gdi32.dll", "SetPixelFormat")
extern fn raw_set_pixel_format(hdc: usize, format: i32, descriptor: *const u8) -> i32
@import("gdi32.dll", "SwapBuffers")
extern fn raw_swap_buffers(hdc: usize) -> i32
@import("opengl32.dll", "wglCreateContext")
extern fn raw_wgl_create_context(hdc: usize) -> usize
@import("opengl32.dll", "wglDeleteContext")
extern fn raw_wgl_delete_context(context: usize) -> i32
@import("opengl32.dll", "wglMakeCurrent")
extern fn raw_wgl_make_current(hdc: usize, context: usize) -> i32
@import("opengl32.dll", "wglGetProcAddress")
extern fn raw_wgl_get_proc_address(name: *const u8) -> usize
@import("kernel32.dll", "GetModuleHandleA")
extern fn raw_get_module_handle(name: *const u8) -> usize
@import("kernel32.dll", "GetProcAddress")
extern fn raw_get_proc_address(module: usize, name: *const u8) -> usize

@cc(c)
type CreateContextAttribs = extern fn(usize, usize, *const i32) -> usize
@cc(c)
type SwapIntervalExt = extern fn(i32) -> i32
type CreatePun = union { function: CreateContextAttribs, bits: usize }
type IntervalPun = union { function: SwapIntervalExt, bits: usize }
type PointerPun = union { pointer: *void, bits: usize }
type BytesPun = union { pointer: *u8, bits: usize }
type ContextPun = union { pointer: *const Context, bits: usize }

fn profile_of(options: Options) -> gl.Profile { ret eglcontext.profile_of(options) }

fn c_name(name: str, buffer: []u8) -> bool {
    if name.len + 1usize > buffer.len { ret false }
    var k = 0usize
    while k < name.len {
        buffer[k] = name[k]
        k += 1usize
    }
    buffer[name.len] = 0u8
    ret true
}

fn wgl_proc(name: str) -> usize {
    var buffer: [128]u8 = zero
    if !c_name(name, buffer[0usize..128usize]) { ret 0usize }
    let address = raw_wgl_get_proc_address(&buffer[0usize])
    // 1, 2, 3 and -1 are what some ICDs answer for "not mine" instead of 0.
    if address > 3usize && address != 18446744073709551615usize { ret address }
    var module_name: [16]u8 = zero
    let named = c_name("opengl32.dll", module_name[0usize..16usize])
    let module = raw_get_module_handle(&module_name[0usize])
    if module == 0usize { ret 0usize }
    ret raw_get_proc_address(module, &buffer[0usize])
}

// The resolver `gl.load` takes once a context is current.
fn resolver_context(c: *const Context) -> usize {
    var pun: ContextPun = zero
    pun.pointer = c
    ret pun.bits
}

fn resolve(a: *mem.Arena, context: usize, name: str) -> usize {
    var pun: ContextPun = zero
    pun.bits = context
    if pun.pointer == nil { ret 0usize }
    if pun.pointer.uses_egl { ret egl.proc_address(a, 0usize, name) }
    ret wgl_proc(name)
}

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

// PIXELFORMATDESCRIPTOR: 40 bytes, RGBA with 32 colour, 8 alpha, 24 depth and 8 stencil bits.
fn set_pixel_format(hdc: usize) -> err {
    var descriptor: [40]u8 = zero
    descriptor[0usize] = 40u8
    descriptor[2usize] = 1u8
    descriptor[4usize] = u8(PFD_FLAGS)
    descriptor[9usize] = 32u8
    descriptor[16usize] = 8u8
    descriptor[23usize] = 24u8
    descriptor[24usize] = 8u8
    let format = raw_choose_pixel_format(hdc, &descriptor[0usize])
    if format == 0i32 { ret Unsupported }
    if raw_set_pixel_format(hdc, format, &descriptor[0usize]) == 0i32 { ret Unsupported }
    ret ok
}

fn wgl_on(c: *Context, hwnd: usize, options: Options) -> err {
    let hdc = raw_get_dc(hwnd)
    if hdc == 0usize { ret Failed }
    c.hwnd = hwnd
    c.hdc = hdc
    if set_pixel_format(hdc) != ok { ret Unsupported }
    let legacy = raw_wgl_create_context(hdc)
    if legacy == 0usize { ret Unsupported }
    if raw_wgl_make_current(hdc, legacy) == 0i32 {
        let deleted = raw_wgl_delete_context(legacy)
        ret Unsupported
    }
    var pun: CreatePun = zero
    pun.bits = wgl_proc("wglCreateContextAttribsARB")
    if pun.bits == 0usize {
        let released = raw_wgl_make_current(0usize, 0usize)
        let deleted = raw_wgl_delete_context(legacy)
        ret Unsupported
    }
    var attributes: [8]i32 = zero
    attributes[0usize] = WGL_CONTEXT_MAJOR_VERSION_ARB
    attributes[1usize] = i32(options.major)
    attributes[2usize] = WGL_CONTEXT_MINOR_VERSION_ARB
    attributes[3usize] = i32(options.minor)
    attributes[4usize] = WGL_CONTEXT_PROFILE_MASK_ARB
    attributes[5usize] = WGL_CONTEXT_CORE_PROFILE_BIT_ARB
    let context = pun.function(hdc, 0usize, &attributes[0usize])
    let released = raw_wgl_make_current(0usize, 0usize)
    let deleted = raw_wgl_delete_context(legacy)
    if context == 0usize { ret Unsupported }
    c.wgl = context
    c.live = true
    if raw_wgl_make_current(hdc, context) == 0i32 { ret Failed }
    ret ok
}

fn angle_display(a: *mem.Arena) -> (usize, err) {
    if egl.load(a, "") != ok { ret (0usize, Unsupported) }
    let display = egl.get_display(egl.DEFAULT_DISPLAY)
    if eglcontext.initialize(display) != ok { ret (0usize, Unsupported) }
    ret (display, ok)
}

// A context with no window, current on the calling thread; render into framebuffer objects.
fn headless(a: *mem.Arena, options: Options) -> (Context, err) {
    var c: Context = zero
    if options.api == .Gles {
        let (display, display_error) = angle_display(a)
        if display_error != ok { ret (c, display_error) }
        let (s, state_error) = eglcontext.headless(display, options, true)
        c.egl_state = s
        c.uses_egl = true
        ret (c, mapped(state_error))
    }
    let (w, window_error) = os.window_open(a, os.WindowOptions { title: "neper GL", width: 16u32, height: 16u32, resizable: false, visible: false, mode: .Windowed })
    if window_error != ok { ret (c, Unsupported) }
    let (hwnd, instance, native_error) = os.window_native(w)
    c.hidden = w
    c.owns_window = true
    if native_error != ok { ret (c, Failed) }
    let made = wgl_on(&c, hwnd, options)
    ret (c, made)
}

// A context drawing into `w`'s client area, current on the calling thread.
fn for_window(a: *mem.Arena, w: os.Window, options: Options) -> (Context, err) {
    var c: Context = zero
    let (hwnd, instance, native_error) = os.window_native(w)
    if native_error != ok { ret (c, native_error) }
    if options.api == .Gles {
        let (display, display_error) = angle_display(a)
        if display_error != ok { ret (c, display_error) }
        let (s, state_error) = eglcontext.on_window(display, hwnd, options)
        c.egl_state = s
        c.uses_egl = true
        ret (c, mapped(state_error))
    }
    let made = wgl_on(&c, hwnd, options)
    ret (c, made)
}

fn make_current(c: *const Context) -> err {
    if c.uses_egl {
        let made = mapped(eglcontext.make_current(&c.egl_state))
        if made != ok { ret made }
        if !gl.activate(&c.dispatch) { ret Failed }
        ret ok
    }
    if !c.live || raw_wgl_make_current(c.hdc, c.wgl) == 0i32 { ret Failed }
    if !gl.activate(&c.dispatch) { ret Failed }
    ret ok
}

fn swap(c: *const Context) -> err {
    if c.uses_egl { ret mapped(eglcontext.swap(&c.egl_state)) }
    if !c.live || raw_swap_buffers(c.hdc) == 0i32 { ret Failed }
    ret ok
}

// 1 waits for the vertical blank, 0 does not. WGL_EXT_swap_control applies to the current context.
fn swap_interval(c: *const Context, interval: i32) -> err {
    if c.uses_egl { ret mapped(eglcontext.swap_interval(&c.egl_state, interval)) }
    if !c.live { ret Failed }
    var pun: IntervalPun = zero
    pun.bits = wgl_proc("wglSwapIntervalEXT")
    if pun.bits == 0usize { ret Unsupported }
    if pun.function(interval) == 0i32 { ret Unsupported }
    ret ok
}

// Fills this current context's dispatch table for the profile `options` names.
fn load(a: *mem.Arena, c: *Context, options: Options) -> err {
    ret gl.load(a, profile_of(options), resolve, resolver_context(c), &c.dispatch)
}

fn close(c: *Context) -> err {
    var closed = ok
    if c.uses_egl {
        closed = mapped(eglcontext.close(&c.egl_state))
    } else {
        if c.live {
            let released = raw_wgl_make_current(0usize, 0usize)
            let deleted = raw_wgl_delete_context(c.wgl)
            c.live = false
        }
        if c.hdc != 0usize {
            let dropped = raw_release_dc(c.hwnd, c.hdc)
            c.hdc = 0usize
        }
        if c.owns_window {
            c.owns_window = false
            closed = os.window_close(c.hidden)
        }
    }
    gl.release(&c.dispatch)
    ret closed
}
