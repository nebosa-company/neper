// Per-monitor DPI under a GL context (L175, D5911): the window is sent WM_DPICHANGED with a suggested rectangle half as
// large again, as Windows sends it when the window crosses onto a monitor of another scale. A per-monitor-aware window
// takes that rectangle itself; the client area must then have grown by the same share (less the frame), os.window_metrics
// must report it, and a frame cleared at the new size must reach its far corner. Windows only: elsewhere, and on a host
// without the explicit window or GL capability, it exits 0 having said so.

use e.io
use e.mem
use e.os
use x.khronos.context
use x.khronos.gl

type Rect = struct { left: i32, top: i32, right: i32, bottom: i32 }
type SendMessage = fn(usize, u32, usize, *Rect) -> isize
type GetWindowRect = fn(usize, *Rect) -> i32

fn pump() {
    var spins = 0usize
    while spins < 64usize {
        let (event, any, poll_error) = os.window_poll(0i64)
        if poll_error != ok { os.exit(1i32) }
        if !any { ret }
        spins += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    if os.NATIVE_SEPARATOR != 92u8 {
        let printed = io.print("not Windows; nothing checked\n")
        ret ok
    }
    let (w, open_error) = os.window_open(a, os.WindowOptions { title: "neper x_khronos_gl_dpi", width: 200u32, height: 150u32, resizable: true, visible: true, mode: .Windowed })
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
        if os.window_close(w) != ok { os.exit(13i32) }
        ret ok
    }
    if context_error != ok { os.exit(1i32) }
    var live = c
    if context.load(a, &live, options) != ok { os.exit(2i32) }
    let (user32, user32_error) = os.dlopen(a, "user32.dll")
    if user32_error != ok { os.exit(3i32) }
    let (send, send_error) = os.dlsym[SendMessage](a, user32, "SendMessageW")
    let (outer_of, outer_error) = os.dlsym[GetWindowRect](a, user32, "GetWindowRect")
    if send_error != ok || outer_error != ok { os.exit(4i32) }
    let (native, extra, native_error) = os.window_native(w)
    if native_error != ok { os.exit(5i32) }
    let (before, before_error) = os.window_metrics(w)
    if before_error != ok { os.exit(6i32) }
    var outer: Rect = zero
    if outer_of(native, &outer) == 0i32 { os.exit(7i32) }
    let outer_w = outer.right - outer.left
    let outer_h = outer.bottom - outer.top
    // 144 dpi on both axes (150%), and the frame half as large again.
    var suggested = Rect { left: outer.left, top: outer.top, right: outer.left + outer_w * 3i32 / 2i32, bottom: outer.top + outer_h * 3i32 / 2i32 }
    let answered = send(native, 736u32, (144usize << 16usize) | 144usize, &suggested)
    pump()
    let (after, after_error) = os.window_metrics(w)
    if after_error != ok { os.exit(8i32) }
    let want_w = u32(i32(before.width) + outer_w / 2i32)
    let want_h = u32(i32(before.height) + outer_h / 2i32)
    if after.width != want_w || after.height != want_h {
        let printed = io.printf["client {}x{} after, {}x{} wanted\n"](after.width, after.height, want_w, want_h)
        os.exit(9i32)
    }
    // A frame at the new size reaches its far corner.
    if context.make_current(&live) != ok { os.exit(10i32) }
    gl.viewport(0i32, 0i32, i32(after.width), i32(after.height))
    gl.clear_color(0.0f32, 1.0f32, 0.0f32, 1.0f32)
    gl.clear(gl.COLOR_BUFFER_BIT)
    var corner: [4]u8 = zero
    gl.read_pixels(i32(after.width) - 1i32, i32(after.height) - 1i32, 1i32, 1i32, gl.RGBA, gl.UNSIGNED_BYTE, context.as_pointer(mem.address_of(&corner[0usize])))
    if gl.get_error() != gl.NO_ERROR || corner[0usize] != 0u8 || corner[1usize] != 255u8 { os.exit(11i32) }
    if context.swap(&live) != ok { os.exit(12i32) }
    let printed = io.printf["WM_DPICHANGED: client {}x{} -> {}x{}, scale {}%, drawn to the far corner on {}\n"](before.width, before.height, after.width, after.height, after.scale_percent, gl.c_text(gl.get_string(gl.RENDERER)))
    if os.dlclose(user32) != ok { os.exit(13i32) }
    if context.close(&live) != ok { os.exit(14i32) }
    ret os.window_close(w)
}
