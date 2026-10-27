// `x.khronos.present` (D5887): an `e.ui.window`'s frames shown through OpenGL instead of the
// host's software blit. `attach` makes a GL 3.3 core (or GLES 3.0) context on the window and
// installs a `window.Presenter`. Each frame is uploaded into one texture and drawn by one
// full-screen triangle with `texelFetch`, so pixel (x, y) of the frame is pixel (x, y) of the
// window -- top-left anchored, no filtering, BGRA swizzled in the shader, alpha forced opaque.
// A GL error drops the window back to `os.window_present` for the rest of the session.
//
// ponytail: the whole frame is uploaded every time; uploading only `window.damaged`'s rectangle
// through two PBOs is the upgrade once e.ui.app reports damage to the window.

use e.mem
use e.os
use e.ui.window
use x.khronos.context
use x.khronos.gl

error Unsupported
error Failed

type Present = struct { c: context.Context, program: u32, texture: u32, vertex_array: u32, height_slot: i32, origin_slot: i32, width: u32, height: u32, live: bool }

const MAX_PRESENTS: usize = 16usize

var presents: [16]Present = zero

fn vertex_source(es: bool) -> str {
    if es { ret "#version 300 es\nvoid main() { vec2 p = vec2(float((gl_VertexID & 1) * 4 - 1), float((gl_VertexID & 2) * 2 - 1)); gl_Position = vec4(p, 0.0, 1.0); }\n" }
    ret "#version 330 core\nvoid main() { vec2 p = vec2(float((gl_VertexID & 1) * 4 - 1), float((gl_VertexID & 2) * 2 - 1)); gl_Position = vec4(p, 0.0, 1.0); }\n"
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
    var p = Present { c: c, program: 0u32, texture: 0u32, vertex_array: 0u32, height_slot: 0i32, origin_slot: 0i32, width: 0u32, height: 0u32, live: true }
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
    gl.gen_textures(1i32, &p.texture)
    gl.active_texture(gl.TEXTURE0)
    gl.bind_texture(gl.TEXTURE_2D, p.texture)
    gl.tex_parameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
    gl.tex_parameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))
    gl.pixel_storei(gl.UNPACK_ALIGNMENT, 4i32)
    if gl.get_error() != gl.NO_ERROR {
        let closed = context.close(&p.c)
        ret (0usize, Failed)
    }
    presents[slot] = p
    ret (slot, ok)
}

// Draws `pixels` (BGRA8, rows from the top) into the back buffer without swapping.
fn draw(index: usize, host: os.Window, pixels: []const u32, width: u32, height: u32) -> err {
    if index >= MAX_PRESENTS || !presents[index].live { ret Failed }
    if width == 0u32 || height == 0u32 || pixels.len < usize(width) * usize(height) { ret Unsupported }
    let p = &presents[index]
    if context.make_current(&p.c) != ok { ret Failed }
    let (metrics, metrics_error) = os.window_metrics(host)
    if metrics_error != ok { ret Failed }
    let data = context.as_pointer(mem.address_of(&pixels[0usize]))
    if width != p.width || height != p.height {
        gl.tex_image_2d(gl.TEXTURE_2D, 0i32, i32(gl.RGBA8), i32(width), i32(height), 0i32, gl.RGBA, gl.UNSIGNED_BYTE, data)
        p.width = width
        p.height = height
    } else {
        gl.tex_sub_image_2d(gl.TEXTURE_2D, 0i32, 0i32, 0i32, i32(width), i32(height), gl.RGBA, gl.UNSIGNED_BYTE, data)
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

// The `window.Presenter` function: draw, then swap.
fn present(index: usize, host: os.Window, pixels: []const u32, width: u32, height: u32) -> err {
    let drawn = draw(index, host, pixels, width, height)
    if drawn != ok { ret drawn }
    ret context.swap(&presents[index].c)
}

// Shows `w`'s frames through GL from its next `request_frame` on.
fn attach(a: *mem.Arena, w: *window.Window, options: context.Options) -> err {
    let (host, host_error) = window.host_window(w)
    if host_error != ok { ret host_error }
    let (index, open_error) = open(a, host, options)
    if open_error != ok { ret open_error }
    ret window.set_presenter(w, window.Presenter { context: index, present: present })
}

fn close(index: usize) -> err {
    if index >= MAX_PRESENTS || !presents[index].live { ret ok }
    presents[index].live = false
    ret context.close(&presents[index].c)
}
