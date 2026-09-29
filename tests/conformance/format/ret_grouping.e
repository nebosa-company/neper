// A wide `ret` of a grouping (T006): the `(` after `ret` holds no comma, so it is not
// a tuple and never breaks with a trailing comma -- `(x,)` does not parse. The call
// inside it breaks instead.
fn pixel(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64 {
    ret img[0usize]
}

fn grad_x(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64 { ret (pixel(img, w, h, x + 1i64, y) - pixel(img, w, h, x - 1i64, y)) * 0.5f64 }
