// x.khronos.present (L178): frames handed to the GL presenter come back from the window's back
// buffer bit for bit. A 160x120 window takes BGRA patterns at 64x48, 96x72 and 128x96 -- one
// logical 64x48 frame at scales 1.0, 1.5 and 2.0 -- through OpenGL 3.3 core and OpenGL ES 3.0;
// each is drawn hanging from the top-left corner, read back before the swap, compared pixel
// by pixel (the margin must be black), then swapped. Then (D5905) a box of each frame is
// changed and drawn as the renderer reports it: only that box's bytes may go up, through the
// presenter's tightly packed unpack buffers, and the back buffer must again equal the whole new
// frame. A one-pixel-wide vertical change keeps its PBO just as narrow, and an empty box uploads
// nothing. A host explicitly without a display or GL capability exits 0 having printed why.

use e.gpu
use e.io
use e.mem
use e.os
use e.ui.window
use x.khronos.context
use x.khronos.gl
use x.khronos.present

const WINDOW_W: u32 = 160u32
const WINDOW_H: u32 = 120u32
const PRESENTER_CYCLES: usize = 17usize

fn pattern(x: u32, y: u32, size: u32) -> u32 {
    let r = (x * 7u32 + size) & 255u32
    let g = (y * 11u32) & 255u32
    let b = (x * y + 3u32) & 255u32
    ret (255u32 << 24u32) | (r << 16u32) | (g << 8u32) | b
}

// The back buffer against `pixels`, hung from the top-left corner with a black margin.
fn compare(a: *mem.Arena, pixels: []const u32, width: u32, height: u32, base: i32) -> err {
    let (back, back_error) = mem.alloc[u8](a, usize(WINDOW_W) * usize(WINDOW_H) * 4usize)
    if back_error != ok { ret back_error }
    gl.pixel_storei(gl.PACK_ALIGNMENT, 1i32)
    gl.read_pixels(0i32, 0i32, i32(WINDOW_W), i32(WINDOW_H), gl.RGBA, gl.UNSIGNED_BYTE, context.as_pointer(mem.address_of(&back[0usize])))
    if gl.get_error() != gl.NO_ERROR { os.exit(base + 2i32) }
    // Window row `row` from the top is GL row WINDOW_H - 1 - row.
    var row = 0u32
    while row < WINDOW_H {
        var col = 0u32
        while col < WINDOW_W {
            let at = (usize(WINDOW_H - 1u32 - row) * usize(WINDOW_W) + usize(col)) * 4usize
            var want = 255u32 << 24u32
            if row < height && col < width { want = pixels[usize(row) * usize(width) + usize(col)] }
            if u32(back[at]) != (want >> 16u32) & 255u32 || u32(back[at + 1usize]) != (want >> 8u32) & 255u32 || u32(back[at + 2usize]) != want & 255u32 || back[at + 3usize] != 255u8 { os.exit(base + 3i32) }
            col += 1u32
        }
        row += 1u32
    }
    ret ok
}

fn check(a: *mem.Arena, index: usize, host: os.Window, width: u32, height: u32, base: i32) -> err {
    let (pixels, pixels_error) = mem.alloc[u32](a, usize(width) * usize(height))
    if pixels_error != ok { ret pixels_error }
    var y = 0u32
    while y < height {
        var x = 0u32
        while x < width {
            pixels[usize(y) * usize(width) + usize(x)] = pattern(x, y, width)
            x += 1u32
        }
        y += 1u32
    }
    if present.draw(index, host, pixels, width, height) != ok { os.exit(base + 1i32) }
    try compare(a, pixels, width, height, base)
    let whole = window.Changed { x0: 0u32, y0: 0u32, x1: width, y1: height }
    if present.present(index, host, pixels, width, height, whole) != ok { os.exit(base + 4i32) }
    // A box changed, and reported as the only change.
    let changed = window.Changed { x0: width / 4u32, y0: height / 3u32, x1: width / 2u32 + 1u32, y1: height / 2u32 + 3u32 }
    y = changed.y0
    while y < changed.y1 {
        var x = changed.x0
        while x < changed.x1 {
            pixels[usize(y) * usize(width) + usize(x)] = pixels[usize(y) * usize(width) + usize(x)] ^ 16777215u32
            x += 1u32
        }
        y += 1u32
    }
    let before = present.uploaded(index)
    if present.draw_changed(index, host, pixels, width, height, changed) != ok { os.exit(base + 5i32) }
    let changed_bytes = usize(changed.x1 - changed.x0) * usize(changed.y1 - changed.y0) * 4usize
    if present.uploaded(index) - before != changed_bytes { os.exit(base + 6i32) }
    if present.unpack_bytes(index) != changed_bytes { os.exit(base + 7i32) }
    try compare(a, pixels, width, height, base + 3i32)
    // A thin full-height strip distinguishes a tightly packed PBO from full-width staging.
    let thin = window.Changed { x0: width / 2u32, y0: 0u32, x1: width / 2u32 + 1u32, y1: height }
    y = thin.y0
    while y < thin.y1 {
        pixels[usize(y) * usize(width) + usize(thin.x0)] = pixels[usize(y) * usize(width) + usize(thin.x0)] ^ 16777215u32
        y += 1u32
    }
    let thin_before = present.uploaded(index)
    if present.draw_changed(index, host, pixels, width, height, thin) != ok { os.exit(base + 8i32) }
    let thin_bytes = usize(thin.x1 - thin.x0) * usize(thin.y1 - thin.y0) * 4usize
    if present.uploaded(index) - thin_before != thin_bytes { os.exit(base + 9i32) }
    if present.unpack_bytes(index) != thin_bytes { os.exit(base + 10i32) }
    try compare(a, pixels, width, height, base + 9i32)
    if present.present(index, host, pixels, width, height, window.Changed { x0: 0u32, y0: 0u32, x1: 0u32, y1: 0u32 }) != ok { os.exit(base + 11i32) }
    if present.uploaded(index) - thin_before != thin_bytes { os.exit(base + 12i32) }
    ret ok
}

fn run(a: *mem.Arena, host: os.Window, options: context.Options, base: i32) -> err {
    let (index, open_error) = present.open(a, host, options)
    if open_error != ok { ret open_error }
    if check(a, index, host, 64u32, 48u32, base) != ok { os.exit(base + 5i32) }
    if check(a, index, host, 96u32, 72u32, base + 10i32) != ok { os.exit(base + 6i32) }
    if check(a, index, host, 128u32, 96u32, base + 20i32) != ok { os.exit(base + 7i32) }
    let printed = io.print(gl.c_text(gl.get_string(gl.RENDERER)))
    let ended = io.print("\n")
    if present.close(index) != ok { os.exit(base + 8i32) }
    ret ok
}

// Close more GL-presenting UI windows than the presenter's fixed pool can hold at once. Every
// open must attach again, and the final frame must stay on GL instead of silently falling back.
// A host that cannot create even the first GL presenter reports Unsupported; a later failure is
// a lifecycle regression rather than a platform skip.
fn cycle_presenters(a: *mem.Arena) -> err {
    let (device, device_error) = gpu.open(a, .Cpu, 0u32)
    if device_error != ok { ret present.Failed }
    present.install()
    let options = window.Options { title: "neper x_khronos_gl_present lifecycle", width: WINDOW_W, height: WINDOW_H, min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: .Windowed }
    var cycle = 0usize
    var attached_once = false
    while cycle < PRESENTER_CYCLES {
        let (opened, opened_error) = window.open(a, device, options)
        if opened_error != ok {
            let released = gpu.close(device)
            if !attached_once && opened_error == window.Unsupported { ret present.Unsupported }
            ret present.Failed
        }
        var presented = opened
        if !window.presenting(&presented) {
            let closed = window.close(&presented)
            let released = gpu.close(device)
            if !attached_once { ret present.Unsupported }
            ret present.Failed
        }
        attached_once = true
        if cycle + 1usize == PRESENTER_CYCLES {
            if window.request_frame(&presented) != ok || !window.presenting(&presented) {
                let closed = window.close(&presented)
                let released = gpu.close(device)
                ret present.Failed
            }
        }
        if window.close(&presented) != ok {
            let released = gpu.close(device)
            ret present.Failed
        }
        cycle += 1usize
    }
    if gpu.close(device) != ok { ret present.Failed }
    ret ok
}

fn pump() {
    var spins = 0usize
    while spins < 64usize {
        let (event, any, poll_error) = os.window_poll(0i64)
        if poll_error != ok { os.exit(6i32) }
        if !any { ret }
        spins += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (gl_window, gl_window_error) = os.window_open(a, os.WindowOptions { title: "neper x_khronos_gl_present", width: WINDOW_W, height: WINDOW_H, resizable: false, visible: true, mode: .Windowed })
    if gl_window_error == os.Unsupported {
        let printed = io.print("no window on this host; nothing checked\n")
        ret ok
    }
    if gl_window_error != ok { os.exit(1i32) }
    pump()
    let gl_label = io.print("OpenGL 3.3 core present: ")
    let gl_error = run(a, gl_window, context.Options { api: .Gl, major: 3u32, minor: 3u32 }, 10i32)
    if gl_error == present.Unsupported {
        let skipped = io.print("unsupported\n")
    } else if gl_error != ok {
        os.exit(6i32)
    }
    if os.window_close(gl_window) != ok { os.exit(2i32) }
    // A fresh window for ES: on Windows a window's pixel format belongs to WGL once set.
    let (es_window, es_window_error) = os.window_open(a, os.WindowOptions { title: "neper x_khronos_gl_present es", width: WINDOW_W, height: WINDOW_H, resizable: false, visible: true, mode: .Windowed })
    if es_window_error == os.Unsupported {
        let skipped = io.print("no second window on this host; OpenGL ES present not checked\n")
    } else {
        if es_window_error != ok { os.exit(3i32) }
        pump()
        let es_label = io.print("OpenGL ES 3.0 present: ")
        let es_error = run(a, es_window, context.Options { api: .Gles, major: 3u32, minor: 0u32 }, 50i32)
        if es_error == present.Unsupported {
            let es_skipped = io.print("unsupported\n")
        } else if es_error != ok {
            os.exit(7i32)
        }
        if os.window_close(es_window) != ok { os.exit(4i32) }
    }
    let lifecycle_label = io.print("OpenGL presenter lifecycle: ")
    let lifecycle_error = cycle_presenters(a)
    if lifecycle_error == present.Unsupported {
        let skipped = io.print("unsupported\n")
    } else if lifecycle_error != ok {
        os.exit(5i32)
    } else {
        let passed = io.print("ok\n")
    }
    ret ok
}
