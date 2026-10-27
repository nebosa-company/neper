// A GL context on an `os` window (L174, L175): x.khronos.context.for_window on a 96x64
// window, then make_current, swap_interval(1), a clear of the default framebuffer read back
// before the swap, a scissored clear that leaves the rest alone, and five swaps with the
// window's events pumped between them. A host with no display or no GL exits 0 having printed
// why; a host that opens the context and then answers wrongly fails with the check's number.

use e.io
use e.mem
use e.os
use x.khronos.context
use x.khronos.gl

const WIDTH: usize = 96usize
const HEIGHT: usize = 64usize

fn pixel(pixels: []const u8, x: usize, y: usize) -> u32 {
    let at = (y * WIDTH + x) * 4usize
    ret (u32(pixels[at]) << 24u32) | (u32(pixels[at + 1usize]) << 16u32) | (u32(pixels[at + 2usize]) << 8u32) | u32(pixels[at + 3usize])
}

fn pump() {
    var spins = 0usize
    while spins < 64usize {
        let (event, any, poll_error) = os.window_poll(0i64)
        if poll_error != ok || !any { ret }
        spins += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (w, open_error) = os.window_open(a, os.WindowOptions { title: "neper x_khronos_gl_window", width: u32(WIDTH), height: u32(HEIGHT), resizable: false, visible: true, mode: .Windowed })
    if open_error != ok {
        let printed = io.print("no window on this host; nothing checked\n")
        ret ok
    }
    pump()
    let options = context.Options { api: .Gl, major: 3u32, minor: 3u32 }
    let (c, context_error) = context.for_window(a, w, options)
    if context_error == context.Unsupported {
        let printed = io.print("no OpenGL context for a window on this host; nothing checked\n")
        let closed = os.window_close(w)
        ret ok
    }
    if context_error != ok { os.exit(2i32) }
    var live = c
    if context.load(a, options) != ok { os.exit(3i32) }
    if context.make_current(&live) != ok { os.exit(4i32) }
    let interval = context.swap_interval(&live, 1i32)
    if interval != ok && interval != context.Unsupported { os.exit(5i32) }

    gl.viewport(0i32, 0i32, i32(WIDTH), i32(HEIGHT))
    gl.clear_color(0.2f32, 0.4f32, 0.6f32, 1.0f32)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.enable(gl.SCISSOR_TEST)
    gl.scissor(0i32, 0i32, 16i32, 16i32)
    gl.clear_color(1.0f32, 0.0f32, 0.0f32, 1.0f32)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.disable(gl.SCISSOR_TEST)
    let (pixels, pixels_error) = mem.alloc[u8](a, WIDTH * HEIGHT * 4usize)
    if pixels_error != ok { ret pixels_error }
    gl.pixel_storei(gl.PACK_ALIGNMENT, 1i32)
    gl.read_buffer(gl.BACK)
    gl.read_pixels(0i32, 0i32, i32(WIDTH), i32(HEIGHT), gl.RGBA, gl.UNSIGNED_BYTE, context.as_pointer(mem.address_of(&pixels[0usize])))
    if gl.get_error() != gl.NO_ERROR { os.exit(6i32) }
    let background = (51u32 << 24u32) | (102u32 << 16u32) | (153u32 << 8u32) | 255u32
    let red = (255u32 << 24u32) | 255u32
    if pixel(pixels, 5usize, 5usize) != red || pixel(pixels, 15usize, 15usize) != red { os.exit(7i32) }
    if pixel(pixels, 16usize, 16usize) != background || pixel(pixels, 95usize, 63usize) != background || pixel(pixels, 50usize, 3usize) != background { os.exit(8i32) }

    var frame = 0usize
    while frame < 5usize {
        gl.clear(gl.COLOR_BUFFER_BIT)
        if context.swap(&live) != ok { os.exit(9i32) }
        pump()
        frame += 1usize
    }
    let printed = io.print("OpenGL 3.3 core on a window: cleared, scissored, read back, swapped on ")
    let named = io.print(gl.c_text(gl.get_string(gl.RENDERER)))
    let ended = io.print("\n")
    if context.close(&live) != ok { os.exit(10i32) }
    if os.window_close(w) != ok { os.exit(11i32) }
    ret ok
}
