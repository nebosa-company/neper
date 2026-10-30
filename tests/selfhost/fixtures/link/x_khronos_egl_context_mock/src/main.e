use e.mem
use e.io
use e.os
use x.khronos.egl
use x.khronos.eglcontext

type Counts = struct {
    initialized: usize,
    pbuffer_config_requests: usize,
    unrestricted_config_requests: usize,
    surfaceless_attempts: usize,
    pbuffer_surface_requests: usize,
    pbuffer_currents: usize,
    config_mismatches: usize,
    unbound: usize,
    destroyed_surfaces: usize,
    destroyed_contexts: usize,
    terminated: usize,
}

var counts: Counts = zero

fn fake_initialize(display: usize) -> u32 {
    counts.initialized += 1usize
    ret egl.TRUE
}

fn fake_bind_api(api_value: u32) -> u32 {
    ret egl.TRUE
}

fn fake_choose_config(display: usize, options: eglcontext.Options, surface_bits: i32) -> usize {
    if surface_bits == egl.PBUFFER_BIT {
        counts.pbuffer_config_requests += 1usize
        ret 12usize
    }
    if surface_bits == 0i32 {
        counts.unrestricted_config_requests += 1usize
        ret 11usize
    }
    ret 0usize
}

fn fake_create_context(display: usize, config: usize, share: usize, attributes: *const i32) -> usize {
    ret 100usize + config
}

fn fake_make_current(display: usize, draw: usize, read: usize, context_value: usize) -> u32 {
    if context_value == egl.NO_CONTEXT {
        counts.unbound += 1usize
        ret egl.TRUE
    }
    if draw == egl.NO_SURFACE || read == egl.NO_SURFACE {
        counts.surfaceless_attempts += 1usize
        ret 0u32
    }
    if draw < 200usize || context_value < 100usize || context_value - 100usize != draw - 200usize {
        counts.config_mismatches += 1usize
        ret 0u32
    }
    counts.pbuffer_currents += 1usize
    ret egl.TRUE
}

fn fake_create_pbuffer_surface(display: usize, config: usize, attributes: *const i32) -> usize {
    counts.pbuffer_surface_requests += 1usize
    ret 200usize + config
}

fn fake_destroy_surface(display: usize, surface: usize) -> u32 {
    counts.destroyed_surfaces += 1usize
    ret egl.TRUE
}

fn fake_destroy_context(display: usize, context_value: usize) -> u32 {
    counts.destroyed_contexts += 1usize
    ret egl.TRUE
}

fn fake_terminate(display: usize) -> u32 {
    counts.terminated += 1usize
    ret egl.TRUE
}

fn fake_api() -> eglcontext.HeadlessApi {
    let creator = eglcontext.CreateApi {
        bind_api: fake_bind_api,
        choose_config: fake_choose_config,
        create_context: fake_create_context,
    }
    let releaser = eglcontext.Releaser {
        make_current: fake_make_current,
        destroy_surface: fake_destroy_surface,
        destroy_context: fake_destroy_context,
        terminate: fake_terminate,
    }
    ret eglcontext.HeadlessApi {
        creator: creator,
        create_pbuffer_surface: fake_create_pbuffer_surface,
        releaser: releaser,
    }
}

fn check_shared_headless() -> i32 {
    if eglcontext.initialize_with(31usize, fake_initialize) != ok { ret 1i32 }
    if eglcontext.initialize_with(31usize, fake_initialize) != ok { ret 2i32 }
    if counts.initialized != 1usize { ret 3i32 }
    let api = fake_api()
    let options = eglcontext.Options { api: .Gles, major: 3u32, minor: 0u32 }
    let (first, first_error) = eglcontext.headless_with(31usize, options, true, api)
    if first_error != ok { ret 4i32 }
    let (second, second_error) = eglcontext.headless_with(31usize, options, true, api)
    if second_error != ok { ret 5i32 }
    var first_state = first
    var second_state = second
    if counts.pbuffer_config_requests != 2usize || counts.unrestricted_config_requests != 0usize { ret 6i32 }
    if first_state.config != 12usize || second_state.config != 12usize || first_state.context != 112usize || second_state.context != 112usize { ret 7i32 }
    if counts.surfaceless_attempts != 2usize || counts.pbuffer_surface_requests != 2usize || counts.pbuffer_currents != 2usize || counts.config_mismatches != 0usize { ret 8i32 }
    eglcontext.release_with(&first_state, api.releaser)
    if counts.terminated != 0usize || !second_state.initialized || !second_state.live { ret 9i32 }
    if fake_make_current(second_state.display, second_state.surface, second_state.surface, second_state.context) != egl.TRUE { ret 10i32 }
    if counts.terminated != 0usize { ret 11i32 }
    eglcontext.release_with(&second_state, api.releaser)
    if counts.terminated != 1usize || counts.destroyed_surfaces != 2usize || counts.destroyed_contexts != 2usize { ret 12i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    if check_shared_headless() != 0i32 { os.exit(1i32) }
    try io.print("x.khronos.eglcontext mock regressions passed\n")
    ret ok
}
