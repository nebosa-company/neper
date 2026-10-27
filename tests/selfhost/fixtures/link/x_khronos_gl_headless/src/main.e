// A real GL context with no window (L174, L177): x.khronos.context.headless on each API the
// host offers -- OpenGL 3.3 core and OpenGL ES 3.0 -- clears a 32x32 framebuffer object, draws
// one triangle with gl_VertexID, and reads the pixels back. The clear colour is exact in eight
// bits and every pixel checked lies well inside or well outside the triangle, so the answer is
// the same on any conforming driver, not only Mesa's llvmpipe. Then, on OpenGL 4.3 or ES 3.1, a
// compute shader writes data[i] = 3i + 1 into a storage buffer that is mapped and checked.
// A host with no EGL at all exits 0 having printed why; one whose EGL fails partway fails.

use e.io
use e.mem
use e.os
use x.khronos.context
use x.khronos.gl

const SIDE: usize = 32usize
// FNV-1a of the 32x32 RGBA image llvmpipe draws (Mesa 25.2.8), edges included.
const LLVMPIPE_TRIANGLE: u64 = 10057951288596120229u64

fn fnv(bytes: []const u8) -> u64 {
    var hash = 14695981039346656037u64
    for b in bytes { hash = (hash ^ u64(b)) *% 1099511628211u64 }
    ret hash
}

fn decimal(v: u64) {
    var buffer: [24]u8 = zero
    var n = v
    var at = 24usize
    while true {
        at -= 1usize
        buffer[at] = u8(48u64 + n % 10u64)
        n = n / 10u64
        if n == 0u64 { break }
    }
    let printed = io.print(buffer[at..24usize])
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

fn link(shaders: []const u32) -> (u32, err) {
    let program = gl.create_program()
    for shader in shaders { gl.attach_shader(program, shader) }
    gl.link_program(program)
    var status = 0i32
    gl.get_programiv(program, gl.LINK_STATUS, &status)
    if status == 0i32 { ret (0u32, gl.Failed) }
    ret (program, ok)
}

fn vertex_source(es: bool) -> str {
    if es { ret "#version 300 es\nconst vec2 p[3] = vec2[3](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.0, 0.5));\nvoid main() { gl_Position = vec4(p[gl_VertexID], 0.0, 1.0); }\n" }
    ret "#version 330 core\nconst vec2 p[3] = vec2[3](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.0, 0.5));\nvoid main() { gl_Position = vec4(p[gl_VertexID], 0.0, 1.0); }\n"
}

fn fragment_source(es: bool) -> str {
    if es { ret "#version 300 es\nprecision highp float;\nout vec4 color;\nvoid main() { color = vec4(1.0, 0.0, 0.0, 1.0); }\n" }
    ret "#version 330 core\nout vec4 color;\nvoid main() { color = vec4(1.0, 0.0, 0.0, 1.0); }\n"
}

fn compute_source(es: bool) -> str {
    if es { ret "#version 310 es\nlayout(local_size_x = 64) in;\nlayout(std430, binding = 0) buffer Data { uint data[]; };\nvoid main() { uint i = gl_GlobalInvocationID.x; data[i] = 3u * i + 1u; }\n" }
    ret "#version 430 core\nlayout(local_size_x = 64) in;\nlayout(std430, binding = 0) buffer Data { uint data[]; };\nvoid main() { uint i = gl_GlobalInvocationID.x; data[i] = 3u * i + 1u; }\n"
}

// RGBA bytes at (x, y), y up from the bottom row as glReadPixels returns them.
fn pixel(pixels: []const u8, x: usize, y: usize) -> u32 {
    let at = (y * SIDE + x) * 4usize
    ret (u32(pixels[at]) << 24u32) | (u32(pixels[at + 1usize]) << 16u32) | (u32(pixels[at + 2usize]) << 8u32) | u32(pixels[at + 3usize])
}

// The triangle and clear checks; the exit code names the failing check, offset by `base`.
fn draw(a: *mem.Arena, options: context.Options, base: i32) -> err {
    let es = options.api == .Gles
    let (c, open_error) = context.headless(a, options)
    if open_error != ok { ret open_error }
    var live = c
    if context.load(a, options) != ok {
        let printed = io.print(gl.missing())
        os.exit(base + 1i32)
    }
    let (major, minor, is_es, version_error) = gl.version()
    if version_error != ok || is_es != es || major < options.major { os.exit(base + 2i32) }

    var framebuffer = 0u32
    var color = 0u32
    gl.gen_framebuffers(1i32, &framebuffer)
    gl.bind_framebuffer(gl.FRAMEBUFFER, framebuffer)
    gl.gen_renderbuffers(1i32, &color)
    gl.bind_renderbuffer(gl.RENDERBUFFER, color)
    gl.renderbuffer_storage(gl.RENDERBUFFER, gl.RGBA8, i32(SIDE), i32(SIDE))
    gl.framebuffer_renderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, color)
    if gl.check_framebuffer_status(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE { os.exit(base + 3i32) }
    gl.viewport(0i32, 0i32, i32(SIDE), i32(SIDE))
    gl.clear_color(0.2f32, 0.4f32, 0.6f32, 1.0f32)
    gl.clear(gl.COLOR_BUFFER_BIT)

    let (vertex, vertex_error) = compile(gl.VERTEX_SHADER, vertex_source(es))
    let (fragment, fragment_error) = compile(gl.FRAGMENT_SHADER, fragment_source(es))
    if vertex_error != ok || fragment_error != ok { os.exit(base + 4i32) }
    var stages: [2]u32 = zero
    stages[0usize] = vertex
    stages[1usize] = fragment
    let (program, link_error) = link(stages[0usize..2usize])
    if link_error != ok { os.exit(base + 5i32) }
    var vertex_array = 0u32
    gl.gen_vertex_arrays(1i32, &vertex_array)
    gl.bind_vertex_array(vertex_array)
    gl.use_program(program)
    gl.draw_arrays(gl.TRIANGLES, 0i32, 3i32)
    if gl.get_error() != gl.NO_ERROR { os.exit(base + 6i32) }

    let (pixels, pixels_error) = mem.alloc[u8](a, SIDE * SIDE * 4usize)
    if pixels_error != ok { ret pixels_error }
    gl.pixel_storei(gl.PACK_ALIGNMENT, 1i32)
    gl.read_pixels(0i32, 0i32, i32(SIDE), i32(SIDE), gl.RGBA, gl.UNSIGNED_BYTE, context.as_pointer(mem.address_of(&pixels[0usize])))
    // 0.2, 0.4 and 0.6 of 255 are 51, 102 and 153 exactly.
    let background = (51u32 << 24u32) | (102u32 << 16u32) | (153u32 << 8u32) | 255u32
    let red = (255u32 << 24u32) | 255u32
    if pixel(pixels, 0usize, 0usize) != background || pixel(pixels, 31usize, 31usize) != background { os.exit(base + 7i32) }
    if pixel(pixels, 0usize, 31usize) != background || pixel(pixels, 31usize, 0usize) != background { os.exit(base + 8i32) }
    // Inside: the centroid's neighbourhood. Outside: above the apex and beside the base.
    if pixel(pixels, 16usize, 12usize) != red || pixel(pixels, 12usize, 10usize) != red || pixel(pixels, 20usize, 10usize) != red { os.exit(base + 9i32) }
    if pixel(pixels, 16usize, 28usize) != background || pixel(pixels, 3usize, 9usize) != background || pixel(pixels, 28usize, 9usize) != background { os.exit(base + 10i32) }
    // On Mesa's llvmpipe every edge pixel is pinned too: the whole image's FNV-1a hash.
    let renderer = gl.c_text(gl.get_string(gl.RENDERER))
    if renderer.len >= 8usize && mem.eq[u8](renderer[0usize..8usize], "llvmpipe") && fnv(pixels) != LLVMPIPE_TRIANGLE {
        let hashed = io.print(" (image hash differs from llvmpipe's golden: ")
        decimal(fnv(pixels))
        let closed_paren = io.print(")\n")
        os.exit(base + 18i32)
    }

    // Compute: GL 4.3 or ES 3.1, when the driver goes that far.
    var compute_options = options
    if es { compute_options.minor = 1u32 } else { compute_options = context.Options { api: .Gl, major: 4u32, minor: 3u32 } }
    if major > compute_options.major || (major == compute_options.major && minor >= compute_options.minor) {
        if gl.load(a, context.profile_of(compute_options), context.resolve, 0usize) != ok { os.exit(base + 11i32) }
        let (kernel, kernel_error) = compile(gl.COMPUTE_SHADER, compute_source(es))
        if kernel_error != ok { os.exit(base + 12i32) }
        var one: [1]u32 = zero
        one[0usize] = kernel
        let (compute, compute_link_error) = link(one[0usize..1usize])
        if compute_link_error != ok { os.exit(base + 13i32) }
        var storage = 0u32
        gl.gen_buffers(1i32, &storage)
        gl.bind_buffer(gl.SHADER_STORAGE_BUFFER, storage)
        gl.buffer_data(gl.SHADER_STORAGE_BUFFER, 1024isize, nil, gl.DYNAMIC_COPY)
        gl.bind_buffer_base(gl.SHADER_STORAGE_BUFFER, 0u32, storage)
        gl.use_program(compute)
        gl.dispatch_compute(4u32, 1u32, 1u32)
        gl.memory_barrier(gl.BUFFER_UPDATE_BARRIER_BIT)
        let mapped = gl.map_buffer_range(gl.SHADER_STORAGE_BUFFER, 0isize, 1024isize, gl.MAP_READ_BIT)
        let address = mem.address_of(mapped)
        if address == 0usize { os.exit(base + 14i32) }
        var region: mem.Arena = zero
        region.base = context.as_bytes(address)
        region.cap = 1024usize
        region.off = 0usize
        let words = mem.view(&region, 0usize, 1024usize)
        var k = 0usize
        while k < 256usize {
            let at = k * 4usize
            let value = u32(words[at]) | (u32(words[at + 1usize]) << 8u32) | (u32(words[at + 2usize]) << 16u32) | (u32(words[at + 3usize]) << 24u32)
            if value != 3u32 * u32(k) + 1u32 { os.exit(base + 15i32) }
            k += 1usize
        }
        let unmapped = gl.unmap_buffer(gl.SHADER_STORAGE_BUFFER)
        if gl.get_error() != gl.NO_ERROR { os.exit(base + 16i32) }
        let said = io.print(" + compute")
    }
    let shown = io.print(" checked on ")
    let named = io.print(gl.c_text(gl.get_string(gl.RENDERER)))
    let ended = io.print("\n")
    if context.close(&live) != ok { os.exit(base + 17i32) }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let gl_label = io.print("OpenGL 3.3 core: draw")
    let gl_error = draw(a, context.Options { api: .Gl, major: 3u32, minor: 3u32 }, 10i32)
    if gl_error != ok { let gl_skipped = io.print(" unsupported\n") }
    // A driver may answer a 3.3 request with exactly 3.3, so compute gets a context of its own.
    let gl43_label = io.print("OpenGL 4.3 core: draw")
    let gl43_error = draw(a, context.Options { api: .Gl, major: 4u32, minor: 3u32 }, 20i32)
    if gl43_error != ok { let gl43_skipped = io.print(" unsupported\n") }
    let es_label = io.print("OpenGL ES 3.0: draw")
    let es_error = draw(a, context.Options { api: .Gles, major: 3u32, minor: 0u32 }, 40i32)
    if es_error != ok { let es_skipped = io.print(" unsupported\n") }
    let es31_label = io.print("OpenGL ES 3.1: draw")
    let es31_error = draw(a, context.Options { api: .Gles, major: 3u32, minor: 1u32 }, 50i32)
    if es31_error != ok { let es31_skipped = io.print(" unsupported\n") }
    if gl43_error != ok && gl43_error != context.Unsupported { os.exit(72i32) }
    if es31_error != ok && es31_error != context.Unsupported { os.exit(73i32) }
    if gl_error == context.Unsupported && es_error == context.Unsupported {
        let printed = io.print("no OpenGL or OpenGL ES through this host's context interface; nothing checked\n")
        ret ok
    }
    if gl_error != ok && gl_error != context.Unsupported { os.exit(70i32) }
    if es_error != ok && es_error != context.Unsupported { os.exit(71i32) }
    ret ok
}
