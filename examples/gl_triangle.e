// A window with one colour-blended triangle, drawn through x.khronos.gl (D5940): OpenGL 3.3
// core, or OpenGL ES 3.0 with `--es` (ANGLE's libEGL.dll on Windows, Mesa's EGL on Linux).
// It redraws at the display's rate until the window is closed, or for `--frames N` frames.
//
//   neper run examples/gl_triangle.e
//   neper run examples/gl_triangle.e -- --es --frames 120

use e.io
use e.mem
use e.os
use e.str
use x.khronos.context
use x.khronos.gl

fn vertex_source(es: bool) -> str {
    if es { ret "#version 300 es\nconst vec2 p[3] = vec2[3](vec2(-0.7, -0.6), vec2(0.7, -0.6), vec2(0.0, 0.7));\nconst vec3 c[3] = vec3[3](vec3(1.0, 0.3, 0.2), vec3(0.2, 0.8, 0.3), vec3(0.2, 0.4, 1.0));\nout vec3 shade;\nvoid main() { shade = c[gl_VertexID]; gl_Position = vec4(p[gl_VertexID], 0.0, 1.0); }\n" }
    ret "#version 330 core\nconst vec2 p[3] = vec2[3](vec2(-0.7, -0.6), vec2(0.7, -0.6), vec2(0.0, 0.7));\nconst vec3 c[3] = vec3[3](vec3(1.0, 0.3, 0.2), vec3(0.2, 0.8, 0.3), vec3(0.2, 0.4, 1.0));\nout vec3 shade;\nvoid main() { shade = c[gl_VertexID]; gl_Position = vec4(p[gl_VertexID], 0.0, 1.0); }\n"
}

fn fragment_source(es: bool) -> str {
    if es { ret "#version 300 es\nprecision highp float;\nin vec3 shade;\nout vec4 color;\nvoid main() { color = vec4(shade, 1.0); }\n" }
    ret "#version 330 core\nin vec3 shade;\nout vec4 color;\nvoid main() { color = vec4(shade, 1.0); }\n"
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
    if status == 0i32 {
        var log: [512]u8 = zero
        var written = 0i32
        gl.get_shader_info_log(shader, 511i32, &written, &log[0usize])
        let printed = io.print(log[0usize..usize(written)])
        ret (0u32, gl.Failed)
    }
    ret (shader, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var es = false
    var frames = 0u64
    var k = 0usize
    while k < args.len {
        if str.eq(args[k], "--es") { es = true }
        if str.eq(args[k], "--frames") && k + 1usize < args.len {
            let (n, n_error) = str.parse_u64(args[k + 1usize])
            if n_error == ok { frames = n }
        }
        k += 1usize
    }
    var options = context.Options { api: .Gl, major: 3u32, minor: 3u32 }
    if es { options = context.Options { api: .Gles, major: 3u32, minor: 0u32 } }

    let (w, window_error) = os.window_open(a, os.WindowOptions { title: "neper gl_triangle", width: 480u32, height: 360u32, resizable: true, visible: true, mode: .Windowed })
    if window_error != ok { ret window_error }
    let (c, context_error) = context.for_window(a, w, options)
    if context_error != ok {
        let printed = io.print("no OpenGL context for this window\n")
        ret context_error
    }
    var live = c
    if context.load(a, options) != ok {
        let printed = io.print(gl.missing())
        ret gl.Unsupported
    }
    let synced = context.swap_interval(&live, 1i32)
    let (vertex, vertex_error) = compile(gl.VERTEX_SHADER, vertex_source(es))
    if vertex_error != ok { ret vertex_error }
    let (fragment, fragment_error) = compile(gl.FRAGMENT_SHADER, fragment_source(es))
    if fragment_error != ok { ret fragment_error }
    let program = gl.create_program()
    gl.attach_shader(program, vertex)
    gl.attach_shader(program, fragment)
    gl.link_program(program)
    var vertex_array = 0u32
    gl.gen_vertex_arrays(1i32, &vertex_array)
    gl.bind_vertex_array(vertex_array)
    gl.use_program(program)

    let printed = io.print("drawing on ")
    let named = io.print(gl.c_text(gl.get_string(gl.RENDERER)))
    let ended = io.print("\n")
    var width = 480i32
    var height = 360i32
    var drawn = 0u64
    var running = true
    while running {
        var spins = 0usize
        while spins < 64usize {
            let (event, any, poll_error) = os.window_poll(0i64)
            if poll_error != ok || !any { break }
            if event.kind == .Close { running = false }
            if event.kind == .Resize {
                width = i32(event.width)
                height = i32(event.height)
            }
            spins += 1usize
        }
        gl.viewport(0i32, 0i32, width, height)
        gl.clear_color(0.08f32, 0.09f32, 0.11f32, 1.0f32)
        gl.clear(gl.COLOR_BUFFER_BIT)
        gl.draw_arrays(gl.TRIANGLES, 0i32, 3i32)
        if context.swap(&live) != ok { running = false }
        drawn += 1u64
        if frames != 0u64 && drawn >= frames { running = false }
    }
    let closed = context.close(&live)
    ret os.window_close(w)
}
