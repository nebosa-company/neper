// `x.khronos.present` (D5887): an `e.ui.window`'s frames shown through OpenGL instead of the
// host's software blit. `attach` makes a GL 3.3 core (or GLES 3.0) context on the window and
// installs a `window.Presenter`. Each frame is uploaded into one texture and drawn by one
// full-screen triangle with `texelFetch`, so pixel (x, y) of the frame is pixel (x, y) of the
// window -- top-left anchored, no filtering, BGRA swizzled in the shader, alpha forced opaque.
// A GL error drops the window back to `os.window_present` for the rest of the session.
//
// (D5905) After the first frame of a size only the box the renderer changed is uploaded: its
// rows go into one of two pixel-unpack buffers in turn, so filling the next never waits on the
// upload from the last, and `glTexSubImage2D` takes the box from there. A box that is empty
// uploads nothing.

use e.mem
use e.os
use e.ui.window
use x.khronos.context
use x.khronos.gl

error Unsupported
error Failed

type Present = struct { c: context.Context, program: u32, texture: u32, vertex_array: u32, height_slot: i32, origin_slot: i32, width: u32, height: u32, live: bool, unpack: [2]u32, next_unpack: usize, uploaded_bytes: usize }

const MAX_PRESENTS: usize = 16usize

var presents: [16]Present = zero

// The triangle's corners come from a vertex buffer: the Android emulator's GLES draws nothing without a vertex attribute (D5896).
fn vertex_source(es: bool) -> str {
    if es { ret "#version 300 es\nlayout(location = 0) in vec2 corner;\nvoid main() { gl_Position = vec4(corner, 0.0, 1.0); }\n" }
    ret "#version 330 core\nlayout(location = 0) in vec2 corner;\nvoid main() { gl_Position = vec4(corner, 0.0, 1.0); }\n"
}

// `origin` is the window row the frame's bottom row lands on; `height` the frame's height.
fn fragment_source(es: bool) -> str {
    if es { ret "#version 300 es\nprecision highp float;\nprecision highp int;\nuniform highp sampler2D frame;\nuniform int height;\nuniform int origin;\nout vec4 color;\nvoid main() { ivec2 p = ivec2(gl_FragCoord.xy); vec4 t = texelFetch(frame, ivec2(p.x, height - 1 - (p.y - origin)), 0); color = vec4(t.bgr, 1.0); }\n" }
    ret "#version 330 core\nuniform sampler2D frame;\nuniform int height;\nuniform int origin;\nout vec4 color;\nvoid main() { ivec2 p = ivec2(gl_FragCoord.xy); vec4 t = texelFetch(frame, ivec2(p.x, height - 1 - (p.y - origin)), 0); color = vec4(t.bgr, 1.0); }\n"
}

fn compile(kind: u32, source: str) -> (u32, err) {
    let shader = gl.create_shader(kind)
    var pointers: [1]usize = zero
    pointers[0usize] = mem.address_of(&source[0usize])
    var lengths: [1]i32 = zero
    lengths[0usize] = i32(source.len)
    gl.shader_source(shader, 1i32, mem.address_of(&pointers[0usize]), &lengths[0usize])
    gl.compile_shader(shader)
    var status = 0i32
    gl.get_shaderiv(shader, gl.COMPILE_STATUS, &status)
    if status == 0i32 { ret (0u32, Failed) }
    ret (shader, ok)
}

fn uniform_slot(program: u32, name: str) -> i32 {
    var buffer: [32]u8 = zero
    var k = 0usize
    while k < name.len && k < 31usize {
        buffer[k] = name[k]
        k += 1usize
    }
    ret gl.get_uniform_location(program, &buffer[0usize])
}

// A GL context and presenter for a host window, current on the calling thread. The index it
// answers is the presenter's `context`.
fn open(a: *mem.Arena, host: os.Window, options: context.Options) -> (usize, err) {
    var slot = 0usize
    while slot < MAX_PRESENTS && presents[slot].live { slot += 1usize }
    if slot == MAX_PRESENTS { ret (0usize, Unsupported) }
    let (c, context_error) = context.for_window(a, host, options)
    if context_error != ok { ret (0usize, Unsupported) }
    var p = Present { c: c, program: 0u32, texture: 0u32, vertex_array: 0u32, height_slot: 0i32, origin_slot: 0i32, width: 0u32, height: 0u32, live: true, unpack: zero, next_unpack: 0usize, uploaded_bytes: 0usize }
    if context.load(a, options) != ok {
        let closed = context.close(&p.c)
        ret (0usize, Unsupported)
    }
    let synced = context.swap_interval(&p.c, 1i32)
    let es = options.api == .Gles
    let (vertex, vertex_error) = compile(gl.VERTEX_SHADER, vertex_source(es))
    let (fragment, fragment_error) = compile(gl.FRAGMENT_SHADER, fragment_source(es))
    if vertex_error != ok || fragment_error != ok {
        let closed = context.close(&p.c)
        ret (0usize, Failed)
    }
    p.program = gl.create_program()
    gl.attach_shader(p.program, vertex)
    gl.attach_shader(p.program, fragment)
    gl.link_program(p.program)
    var linked = 0i32
    gl.get_programiv(p.program, gl.LINK_STATUS, &linked)
    if linked == 0i32 {
        let closed = context.close(&p.c)
        ret (0usize, Failed)
    }
    gl.use_program(p.program)
    gl.uniform_1i(uniform_slot(p.program, "frame"), 0i32)
    p.height_slot = uniform_slot(p.program, "height")
    p.origin_slot = uniform_slot(p.program, "origin")
    gl.gen_vertex_arrays(1i32, &p.vertex_array)
    gl.bind_vertex_array(p.vertex_array)
    // One triangle past every edge of the clip square: (-1, -1), (3, -1), (-1, 3).
    var corners: [6]f32 = zero
    corners[0usize] = -1.0f32
    corners[1usize] = -1.0f32
    corners[2usize] = 3.0f32
    corners[3usize] = -1.0f32
    corners[4usize] = -1.0f32
    corners[5usize] = 3.0f32
    var corner_buffer = 0u32
    gl.gen_buffers(1i32, &corner_buffer)
    gl.bind_buffer(gl.ARRAY_BUFFER, corner_buffer)
    gl.buffer_data(gl.ARRAY_BUFFER, 24isize, context.as_pointer(mem.address_of(&corners[0usize])), gl.STATIC_DRAW)
    gl.enable_vertex_attrib_array(0u32)
    gl.vertex_attrib_pointer(0u32, 2i32, gl.FLOAT, 0u8, 8i32, nil)
    gl.gen_textures(1i32, &p.texture)
    gl.active_texture(gl.TEXTURE0)
    gl.bind_texture(gl.TEXTURE_2D, p.texture)
    gl.tex_parameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
    gl.tex_parameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))
    gl.pixel_storei(gl.UNPACK_ALIGNMENT, 4i32)
    gl.gen_buffers(2i32, &p.unpack[0usize])
    if gl.get_error() != gl.NO_ERROR {
        let closed = context.close(&p.c)
        ret (0usize, Failed)
    }
    presents[slot] = p
    ret (slot, ok)
}

// Draws `pixels` (BGRA8, rows from the top) into the back buffer without swapping.
fn draw(index: usize, host: os.Window, pixels: []const u32, width: u32, height: u32) -> err {
    ret draw_changed(index, host, pixels, width, height, window.Changed { x0: 0u32, y0: 0u32, x1: width, y1: height })
}

// The same, given that only `changed` differs from the last frame drawn.
fn draw_changed(index: usize, host: os.Window, pixels: []const u32, width: u32, height: u32, changed: window.Changed) -> err {
    if index >= MAX_PRESENTS || !presents[index].live { ret Failed }
    if width == 0u32 || height == 0u32 || pixels.len < usize(width) * usize(height) { ret Unsupported }
    let p = &presents[index]
    if context.make_current(&p.c) != ok { ret Failed }
    let (metrics, metrics_error) = os.window_metrics(host)
    if metrics_error != ok { ret Failed }
    if width != p.width || height != p.height {
        gl.tex_image_2d(gl.TEXTURE_2D, 0i32, i32(gl.RGBA8), i32(width), i32(height), 0i32, gl.RGBA, gl.UNSIGNED_BYTE, context.as_pointer(mem.address_of(&pixels[0usize])))
        p.width = width
        p.height = height
        p.uploaded_bytes += usize(width) * usize(height) * 4usize
    } else {
        var x1 = changed.x1
        var y1 = changed.y1
        if x1 > width { x1 = width }
        if y1 > height { y1 = height }
        if changed.x0 < x1 && changed.y0 < y1 {
            // The box's rows, whole, into the next unpack buffer; the texture takes the box's columns from them.
            let first = usize(changed.y0) * usize(width)
            let bytes = (usize(y1) - usize(changed.y0)) * usize(width) * 4usize
            gl.bind_buffer(gl.PIXEL_UNPACK_BUFFER, p.unpack[p.next_unpack])
            gl.buffer_data(gl.PIXEL_UNPACK_BUFFER, isize(bytes), context.as_pointer(mem.address_of(&pixels[first])), gl.STREAM_DRAW)
            p.next_unpack = 1usize - p.next_unpack
            gl.pixel_storei(gl.UNPACK_ROW_LENGTH, i32(width))
            gl.pixel_storei(gl.UNPACK_SKIP_PIXELS, i32(changed.x0))
            gl.tex_sub_image_2d(gl.TEXTURE_2D, 0i32, i32(changed.x0), i32(changed.y0), i32(x1 - changed.x0), i32(y1 - changed.y0), gl.RGBA, gl.UNSIGNED_BYTE, nil)
            gl.pixel_storei(gl.UNPACK_ROW_LENGTH, 0i32)
            gl.pixel_storei(gl.UNPACK_SKIP_PIXELS, 0i32)
            gl.bind_buffer(gl.PIXEL_UNPACK_BUFFER, 0u32)
            p.uploaded_bytes += usize(x1 - changed.x0) * usize(y1 - changed.y0) * 4usize
        }
    }
    // The frame hangs from the window's top edge, as the software blit draws it.
    let origin = i32(metrics.height) - i32(height)
    gl.viewport(0i32, 0i32, i32(metrics.width), i32(metrics.height))
    gl.clear_color(0.0f32, 0.0f32, 0.0f32, 1.0f32)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.enable(gl.SCISSOR_TEST)
    gl.scissor(0i32, origin, i32(width), i32(height))
    gl.uniform_1i(p.height_slot, i32(height))
    gl.uniform_1i(p.origin_slot, origin)
    gl.draw_arrays(gl.TRIANGLES, 0i32, 3i32)
    gl.disable(gl.SCISSOR_TEST)
    if gl.get_error() != gl.NO_ERROR { ret Failed }
    ret ok
}

// The `window.Presenter` function: draw what changed, then swap.
fn present(index: usize, host: os.Window, pixels: []const u32, width: u32, height: u32, changed: window.Changed) -> err {
    let drawn = draw_changed(index, host, pixels, width, height, changed)
    if drawn != ok { ret drawn }
    ret context.swap(&presents[index].c)
}

// The texel bytes uploaded so far, for a test that checks only the changed box went up.
fn uploaded(index: usize) -> usize {
    if index >= MAX_PRESENTS || !presents[index].live { ret 0usize }
    ret presents[index].uploaded_bytes
}

// Shows `w`'s frames through GL from its next `request_frame` on.
fn attach(a: *mem.Arena, w: *window.Window, options: context.Options) -> err {
    let (host, host_error) = window.host_window(w)
    if host_error != ok { ret host_error }
    let (index, open_error) = open(a, host, options)
    if open_error != ok { ret open_error }
    ret window.set_presenter(w, window.Presenter { context: index, present: present })
}

// (D5907) Every `e.ui.window` opened from now on presents through GL 3.3 core, or GLES 3.0 with `install_es`.
fn install() {
    window.set_default_presenter(window.PresenterFactory { attach: attach_gl })
}

fn install_es() {
    window.set_default_presenter(window.PresenterFactory { attach: attach_gles })
}

fn attach_gl(a: *mem.Arena, w: *window.Window) -> err {
    ret attach(a, w, context.Options { api: .Gl, major: 3u32, minor: 3u32 })
}

fn attach_gles(a: *mem.Arena, w: *window.Window) -> err {
    ret attach(a, w, context.Options { api: .Gles, major: 3u32, minor: 0u32 })
}

fn close(index: usize) -> err {
    if index >= MAX_PRESENTS || !presents[index].live { ret ok }
    presents[index].live = false
    ret context.close(&presents[index].c)
}
