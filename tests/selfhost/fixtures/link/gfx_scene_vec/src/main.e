use e.gfx.scene_vec
use e.mem
use e.os

// The three packed loops of the renderer's opaque-image path against plain loops: the row blend, the bytes made from canvas floats
// (to within a level, at the values where a half rounds the other way) and the copy of pixels to the frame in either channel order.
// The same program runs on every target, so the vector forms and the loops they stand in for are held to one answer.

fn near(x: u32, y: u32) -> bool {
    if x > y { ret x - y <= 1u32 }
    ret y - x <= 1u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let n = 11usize
    let (rows, rows_error) = mem.alloc[f32](a, 2usize * 4usize * 16usize)
    if rows_error != ok { ret rows_error }
    var i = 0usize
    while i < rows.len {
        rows[i] = f32((i * 37usize + 11usize) % 256usize) / 255.0
        i += 1usize
    }
    var colv: [16]bool = zero
    i = 0usize
    while i < n {
        colv[i] = (i % 4usize) != 2usize
        i += 1usize
    }
    let (canvas, canvas_error) = mem.alloc[f32](a, 4usize * 16usize + 8usize)
    if canvas_error != ok { ret canvas_error }
    i = 0usize
    while i < canvas.len {
        canvas[i] = 7.0
        i += 1usize
    }
    let h0 = 0usize
    let h1 = 4usize * 16usize
    scene_vec.blend_row(canvas, 4usize, rows, h0, h1, colv[0usize..n], n, 0.75, 0.25)
    i = 0usize
    while i < n {
        var c = 0usize
        while c < 4usize {
            let at = 4usize + i * 4usize + c
            if colv[i] {
                let want = rows[h0 + i * 4usize + c] * 0.75 + rows[h1 + i * 4usize + c] * 0.25
                if canvas[at] != want { os.exit(1i32) }
            } else {
                if canvas[at] != 7.0 { os.exit(2i32) }
            }
            c += 1usize
        }
        i += 1usize
    }
    if canvas[0usize] != 7.0 || canvas[3usize] != 7.0 || canvas[4usize + n * 4usize] != 7.0 { os.exit(3i32) }
    // bytes: blended values are in 0..1, and the byte is the value times 255 rounded
    let (vid, vid_error) = mem.alloc[u32](a, 16usize)
    if vid_error != ok { ret vid_error }
    i = 0usize
    while i < vid.len {
        vid[i] = 0u32
        i += 1usize
    }
    scene_vec.row_bytes(canvas, 4usize, vid, 2usize, n)
    i = 0usize
    while i < n {
        var c = 0usize
        while c < 4usize {
            let value = canvas[4usize + i * 4usize + c]
            if colv[i] {
                let got = (vid[2usize + i] >> u32(8usize * c)) & 255u32
                let want = u32(value * 255.0 + 0.5)
                if !near(got, want) { os.exit(4i32) }
            }
            c += 1usize
        }
        i += 1usize
    }
    if vid[0usize] != 0u32 || vid[1usize] != 0u32 || vid[2usize + n] != 0u32 { os.exit(5i32) }
    // copy of pixels, red first or blue first
    let (src, src_error) = mem.alloc[u32](a, 16usize)
    if src_error != ok { ret src_error }
    let (dst, dst_error) = mem.alloc[u32](a, 16usize)
    if dst_error != ok { ret dst_error }
    i = 0usize
    while i < 16usize {
        src[i] = 0x04030201u32 + u32(i) * 0x10101010u32
        dst[i] = 0u32
        i += 1usize
    }
    var swapped = 0usize
    while swapped < 2usize {
        let reached = scene_vec.copy_pixels(dst, src, 1usize, 14usize, swapped == 1usize)
        if reached < 1usize || reached > 14usize { os.exit(6i32) }
        i = 1usize
        while i < reached {
            var want = src[i]
            if swapped == 1usize { want = (want & 0xFF00FF00u32) | ((want & 255u32) << 16u32) | ((want >> 16u32) & 255u32) }
            if dst[i] != want { os.exit(7i32) }
            i += 1usize
        }
        if dst[0usize] != 0u32 || dst[reached] != 0u32 { os.exit(8i32) }
        i = 0usize
        while i < 16usize {
            dst[i] = 0u32
            i += 1usize
        }
        swapped += 1usize
    }
    ret ok
}
