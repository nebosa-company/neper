// `scene_vec.x64.e`'s functions a pixel at a time, for the targets whose compiler does not lower `e.simd` yet.

use e.mem

fn vid_byte(v: f32) -> u32 {
    ret u32(mem.bitcast[u64](f64(v) * 255.0f64 + 4503599627370496.0f64) & 255u64)
}

fn copy_pixels(dst: []u32, src: []const u32, from: usize, end: usize, bgra: bool) -> usize {
    ret from
}

fn blend_row(canvas: []f32, start: usize, rows: []const f32, h0: usize, h1: usize, colv: []const bool, n: usize, iv: f32, fv: f32) {
    var at = start
    var i = 0usize
    while i < n {
        if colv[i] {
            let o = i * 4usize
            canvas[at] = rows[h0 + o] * iv + rows[h1 + o] * fv
            canvas[at + 1usize] = rows[h0 + o + 1usize] * iv + rows[h1 + o + 1usize] * fv
            canvas[at + 2usize] = rows[h0 + o + 2usize] * iv + rows[h1 + o + 2usize] * fv
            canvas[at + 3usize] = rows[h0 + o + 3usize] * iv + rows[h1 + o + 3usize] * fv
        }
        at += 4usize
        i += 1usize
    }
}

fn row_bytes(canvas: []const f32, start: usize, vid: []u32, first: usize, count: usize) {
    var from = start
    var to = first
    var i = 0usize
    while i < count {
        vid[to] = vid_byte(canvas[from]) | (vid_byte(canvas[from + 1usize]) << 8u32) | (vid_byte(canvas[from + 2usize]) << 16u32) | (vid_byte(canvas[from + 3usize]) << 24u32)
        from += 4usize
        to += 1usize
        i += 1usize
    }
}
