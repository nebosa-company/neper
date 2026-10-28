// A resize storm under a GL context (L174, L175): the window is resized from outside twelve times in a row (SetWindowPos on
// Windows, XResizeWindow through a second Xlib connection on Linux); after each, once os.window_metrics reports the new
// size, the frame is cleared to that step's colour at the new size, a 4x4 marker is scissored into its top-right corner,
// and the back buffer is read before the swap. The far corners must hold the step's colour and the marker its own: a
// back buffer still at the old size, or last step's pixels, fails. A host explicitly without a window or GL capability exits 0 having said so.

use e.io
use e.mem
use e.os
use x.khronos.context
use x.khronos.gl

type SetWindowPos = fn(usize, usize, i32, i32, i32, i32, u32) -> i32
type OpenDisplay = fn(*const u8) -> usize
type ResizeWindow = fn(usize, usize, u32, u32) -> i32
type Flush = fn(usize) -> i32
type Resizer = struct { set_window_pos: SetWindowPos, open_display: OpenDisplay, resize_window: ResizeWindow, flush: Flush, display: usize, windows: bool, library: os.Lib }

fn resizer(a: *mem.Arena) -> (Resizer, err) {
    if os.NATIVE_SEPARATOR == 92u8 {
        let (made, made_error) = windows_resizer(a)
        ret (made, made_error)
    }
    let (made, made_error) = x11_resizer(a)
    ret (made, made_error)
}

fn windows_resizer(a: *mem.Arena) -> (Resizer, err) {
    var r: Resizer = zero
    let (user32, user32_error) = os.dlopen(a, "user32.dll")
    if user32_error != ok { ret (r, user32_error) }
    let (moved, moved_error) = os.dlsym[SetWindowPos](a, user32, "SetWindowPos")
    if moved_error != ok {
        let closed = os.dlclose(user32)
        ret (r, moved_error)
    }
    r.set_window_pos = moved
    r.windows = true
    r.library = user32
    ret (r, ok)
}

fn x11_resizer(a: *mem.Arena) -> (Resizer, err) {
    var r: Resizer = zero
    let (x11, x11_error) = os.dlopen(a, "libX11.so.6")
    if x11_error != ok { ret (r, x11_error) }
    let (opened, opened_error) = os.dlsym[OpenDisplay](a, x11, "XOpenDisplay")
    let (resized, resized_error) = os.dlsym[ResizeWindow](a, x11, "XResizeWindow")
    let (flushed, flushed_error) = os.dlsym[Flush](a, x11, "XFlush")
    if opened_error != ok || resized_error != ok || flushed_error != ok {
        let closed = os.dlclose(x11)
        ret (r, os.Unsupported)
    }
    r.open_display = opened
    r.resize_window = resized
    r.flush = flushed
    r.display = r.open_display(nil)
    r.library = x11
    if r.display == 0usize { ret (r, os.Unsupported) }
    ret (r, ok)
}

// Asks for a client area of width x height; on Windows SetWindowPos sizes the frame, so the border is added.
fn resize(r: *Resizer, native: usize, width: u32, height: u32, border_w: i32, border_h: i32) {
    if r.windows {
        // SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE.
        let moved = r.set_window_pos(native, 0usize, 0i32, 0i32, i32(width) + border_w, i32(height) + border_h, 22u32)
        ret
    }
    let resized = r.resize_window(r.display, native, width, height)
    let flushed = r.flush(r.display)
}

fn pump() {
    var spins = 0usize
    while spins < 64usize {
        let (event, any, poll_error) = os.window_poll(0i64)
        if poll_error != ok { os.exit(1i32) }
        if !any { ret }
        spins += 1usize
    }
}

fn pixel(pixels: []const u8, width: u32, x: u32, y: u32) -> u32 {
    let at = (usize(y) * usize(width) + usize(x)) * 4usize
    ret (u32(pixels[at]) << 16u32) | (u32(pixels[at + 1usize]) << 8u32) | u32(pixels[at + 2usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (w, open_error) = os.window_open(a, os.WindowOptions { title: "neper x_khronos_gl_resize", width: 120u32, height: 90u32, resizable: true, visible: true, mode: .Windowed })
    if open_error == os.Unsupported {
        let printed = io.print("no window on this host; nothing checked\n")
        ret ok
    }
    if open_error != ok { os.exit(1i32) }
    pump()
    let options = context.Options { api: .Gl, major: 3u32, minor: 3u32 }
    let (c, context_error) = context.for_window(a, w, options)
    if context_error == context.Unsupported {
        let printed = io.print("no OpenGL context for a window on this host; nothing checked\n")
        if os.window_close(w) != ok { os.exit(12i32) }
        ret ok
    }
    if context_error != ok { os.exit(1i32) }
    var live = c
    if context.load(a, &live, options) != ok { os.exit(2i32) }
    let (r_value, resizer_error) = resizer(a)
    if resizer_error == os.Unsupported {
        let printed = io.print("no way to resize a window from outside on this host; nothing checked\n")
        if context.close(&live) != ok { os.exit(12i32) }
        if os.window_close(w) != ok { os.exit(13i32) }
        ret ok
    }
    if resizer_error != ok { os.exit(12i32) }
    var r = r_value
    let (native, extra, native_error) = os.window_native(w)
    if native_error != ok { os.exit(3i32) }
    // The frame's border on Windows: what SetWindowPos adds to the client area asked for.
    let (first, first_error) = os.window_metrics(w)
    if first_error != ok { os.exit(4i32) }
    var border_w = 0i32
    var border_h = 0i32
    if r.windows {
        resize(&r, native, 300u32, 200u32, 0i32, 0i32)
        pump()
        let (framed, framed_error) = os.window_metrics(w)
        if framed_error != ok { os.exit(5i32) }
        border_w = 300i32 - i32(framed.width)
        border_h = 200i32 - i32(framed.height)
    }
    var widths: [12]u32 = zero
    var heights: [12]u32 = zero
    widths[0usize] = 200u32
    heights[0usize] = 150u32
    widths[1usize] = 216u32
    heights[1usize] = 64u32
    widths[2usize] = 321u32
    heights[2usize] = 197u32
    widths[3usize] = 260u32
    heights[3usize] = 120u32
    widths[4usize] = 257u32
    heights[4usize] = 99u32
    widths[5usize] = 240u32
    heights[5usize] = 233u32
    widths[6usize] = 300u32
    heights[6usize] = 180u32
    widths[7usize] = 228u32
    heights[7usize] = 128u32
    widths[8usize] = 211u32
    heights[8usize] = 77u32
    widths[9usize] = 280u32
    heights[9usize] = 140u32
    widths[10usize] = 333u32
    heights[10usize] = 222u32
    widths[11usize] = 250u32
    heights[11usize] = 100u32
    let (pixels, pixels_error) = mem.alloc[u8](a, 400usize * 300usize * 4usize)
    if pixels_error != ok { ret pixels_error }
    var step = 0usize
    while step < 12usize {
        resize(&r, native, widths[step], heights[step], border_w, border_h)
        // Until the window says so, within two seconds.
        var waited = 0usize
        var width = 0u32
        var height = 0u32
        while waited < 200usize {
            pump()
            let (now, now_error) = os.window_metrics(w)
            if now_error == ok && now.width == widths[step] && now.height == heights[step] {
                width = now.width
                height = now.height
                break
            }
            let (event, any, poll_error) = os.window_poll(10000000i64)
            waited += 1usize
        }
        if width == 0u32 {
            let (got, got_error) = os.window_metrics(w)
            var shown: [32]u8 = zero
            var at = 0usize
            for value in [4]u32 { widths[step], heights[step], got.width, got.height } {
                var digits: [10]u8 = zero
                var n = value
                var count = 0usize
                while true {
                    digits[count] = u8(48u32 + n % 10u32)
                    n = n / 10u32
                    count += 1usize
                    if n == 0u32 { break }
                }
                while count > 0usize {
                    count -= 1usize
                    shown[at] = digits[count]
                    at += 1usize
                }
                shown[at] = 32u8
                at += 1usize
            }
            let printed = io.print("the window manager did not give the size asked for (asked, got): ")
            let numbers = io.print(shown[0usize..at])
            let ended = io.print("; failing\n")
            os.exit(12i32)
        }
        if context.make_current(&live) != ok { os.exit(6i32) }
        let shade = f32(step * 20usize + 15usize) / 255.0f32
        gl.viewport(0i32, 0i32, i32(width), i32(height))
        gl.clear_color(shade, 0.0f32, 1.0f32 - shade, 1.0f32)
        gl.clear(gl.COLOR_BUFFER_BIT)
        gl.enable(gl.SCISSOR_TEST)
        gl.scissor(i32(width) - 4i32, i32(height) - 4i32, 4i32, 4i32)
        gl.clear_color(0.0f32, 1.0f32, 0.0f32, 1.0f32)
        gl.clear(gl.COLOR_BUFFER_BIT)
        gl.disable(gl.SCISSOR_TEST)
        gl.pixel_storei(gl.PACK_ALIGNMENT, 1i32)
        gl.read_buffer(gl.BACK)
        gl.read_pixels(0i32, 0i32, i32(width), i32(height), gl.RGBA, gl.UNSIGNED_BYTE, context.as_pointer(mem.address_of(&pixels[0usize])))
        if gl.get_error() != gl.NO_ERROR { os.exit(7i32) }
        let red = u32(step * 20usize + 15usize)
        let colour = (red << 16u32) | (255u32 - red)
        if pixel(pixels, width, 0u32, 0u32) != colour { os.exit(8i32) }
        if pixel(pixels, width, width - 5u32, height - 5u32) != colour { os.exit(9i32) }
        if pixel(pixels, width, width - 1u32, height - 1u32) != 65280u32 { os.exit(10i32) }
        if context.swap(&live) != ok { os.exit(11i32) }
        step += 1usize
    }
    let printed = io.print("twelve resizes, each frame drawn and read back at its new size on ")
    let named = io.print(gl.c_text(gl.get_string(gl.RENDERER)))
    let ended = io.print("\n")
    if context.close(&live) != ok { os.exit(12i32) }
    ret os.window_close(w)
}
