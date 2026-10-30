// The platform-specific GL constructors can fail after acquiring only part of
// their native state.  Exercise their injectable release paths without asking
// a real EGL implementation or WGL driver to fail at a particular call.

use e.io
use e.mem
use e.os
use x.khronos.context
use x.khronos.egl
use x.khronos.eglcontext

type Counts = struct { unbound: usize, surface: usize, egl_contexts: usize, terminated: usize, wgl_unbound: usize, wgl_deleted: usize, dc_released: usize, window_closed: usize }

var counts: Counts = zero

fn fake_egl_make_current(display: usize, draw: usize, read: usize, context_value: usize) -> u32 {
    counts.unbound += 1usize
    ret 1u32
}

fn fake_egl_initialize(display: usize) -> u32 {
    ret 1u32
}

fn fake_egl_destroy_surface(display: usize, surface: usize) -> u32 {
    counts.surface += 1usize
    ret 1u32
}

fn fake_egl_destroy_context(display: usize, context_value: usize) -> u32 {
    counts.egl_contexts += 1usize
    ret 1u32
}

fn fake_egl_terminate(display: usize) -> u32 {
    counts.terminated += 1usize
    ret 1u32
}

fn fake_wgl_make_current(hdc: usize, context_value: usize) -> i32 {
    counts.wgl_unbound += 1usize
    ret 1i32
}

fn fake_wgl_delete_context(context_value: usize) -> i32 {
    counts.wgl_deleted += 1usize
    ret 1i32
}

fn fake_release_dc(hwnd: usize, hdc: usize) -> i32 {
    counts.dc_released += 1usize
    ret 1i32
}

fn fake_close_window(w: os.Window) -> err {
    counts.window_closed += 1usize
    ret ok
}

fn check_egl() -> i32 {
    counts = Counts { unbound: 0usize, surface: 0usize, egl_contexts: 0usize, terminated: 0usize, wgl_unbound: 0usize, wgl_deleted: 0usize, dc_released: 0usize, window_closed: 0usize }
    var partial = eglcontext.State { display: 11usize, config: 12usize, context: 13usize, surface: 14usize, initialized: true, live: false }
    let releaser = eglcontext.Releaser {
        make_current: fake_egl_make_current,
        destroy_surface: fake_egl_destroy_surface,
        destroy_context: fake_egl_destroy_context,
        terminate: fake_egl_terminate,
    }
    if eglcontext.initialize_with(11usize, fake_egl_initialize) != ok { ret 10i32 }
    eglcontext.release_with(&partial, releaser)
    if counts.unbound != 1usize || counts.surface != 1usize || counts.egl_contexts != 1usize || counts.terminated != 1usize { ret 1i32 }
    if partial.display != egl.NO_DISPLAY || partial.config != 0usize || partial.context != egl.NO_CONTEXT || partial.surface != egl.NO_SURFACE || partial.initialized || partial.live { ret 2i32 }
    eglcontext.release_with(&partial, releaser)
    if counts.unbound != 1usize || counts.surface != 1usize || counts.egl_contexts != 1usize || counts.terminated != 1usize { ret 3i32 }
    ret 0i32
}

fn check_wgl() -> i32 {
    counts = Counts { unbound: 0usize, surface: 0usize, egl_contexts: 0usize, terminated: 0usize, wgl_unbound: 0usize, wgl_deleted: 0usize, dc_released: 0usize, window_closed: 0usize }
    let releaser = context.WglReleaser {
        make_current: fake_wgl_make_current,
        delete_context: fake_wgl_delete_context,
        release_dc: fake_release_dc,
        close_window: fake_close_window,
    }
    var live = context.Context { egl_state: zero, dispatch: zero, uses_egl: false, hwnd: 21usize, hdc: 22usize, wgl: 23usize, hidden: os.Window { raw: 24usize }, owns_window: true, live: true }
    if context.release_wgl_with(&live, releaser) != ok { ret 4i32 }
    if counts.wgl_unbound != 1usize || counts.wgl_deleted != 1usize || counts.dc_released != 1usize || counts.window_closed != 1usize { ret 5i32 }
    if live.wgl != 0usize || live.hdc != 0usize || live.owns_window || live.live { ret 6i32 }
    var partial = context.Context { egl_state: zero, dispatch: zero, uses_egl: false, hwnd: 31usize, hdc: 32usize, wgl: 0usize, hidden: os.Window { raw: 33usize }, owns_window: true, live: false }
    if context.release_wgl_with(&partial, releaser) != ok { ret 7i32 }
    if counts.wgl_unbound != 1usize || counts.wgl_deleted != 1usize || counts.dc_released != 2usize || counts.window_closed != 2usize { ret 8i32 }
    if partial.hdc != 0usize || partial.owns_window { ret 9i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    if check_egl() != 0i32 { os.exit(1i32) }
    if check_wgl() != 0i32 { os.exit(2i32) }
    try io.print("x khronos partial context cleanup ok\n")
    ret ok
}
