// Round 87, lane z: Material icons the generated matglyph.e lacks, as filled outlines in the 24 dp icon box x, y, w, h (the
// shapes of the Material Symbols "delete", "share", "archive" and "remove", drawn by hand from their 24 grid; the corner arcs of delete are
// cut square). Every subpath runs clockwise on screen, a hole counter-clockwise, so the non-zero fill unites the pieces.
use e.gfx.geometry

fn pt(x: f32, y: f32, w: f32, h: f32, u: f32, v: f32) -> geometry.Point {
    ret geometry.Point { x: x + w * u / 24.0, y: y + h * v / 24.0 }
}

fn rect(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32, l: f32, t: f32, r: f32, d: f32) -> err {
    try geometry.move_to(b, pt(x, y, w, h, l, t))
    try geometry.line_to(b, pt(x, y, w, h, r, t))
    try geometry.line_to(b, pt(x, y, w, h, r, d))
    try geometry.line_to(b, pt(x, y, w, h, l, d))
    try geometry.close_path(b)
    ret ok
}

fn circle(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32, cx: f32, cy: f32, r: f32) -> err {
    let k = r * 0.5523
    try geometry.move_to(b, pt(x, y, w, h, cx + r, cy))
    try geometry.cubic_to(b, pt(x, y, w, h, cx + r, cy + k), pt(x, y, w, h, cx + k, cy + r), pt(x, y, w, h, cx, cy + r))
    try geometry.cubic_to(b, pt(x, y, w, h, cx - k, cy + r), pt(x, y, w, h, cx - r, cy + k), pt(x, y, w, h, cx - r, cy))
    try geometry.cubic_to(b, pt(x, y, w, h, cx - r, cy - k), pt(x, y, w, h, cx - k, cy - r), pt(x, y, w, h, cx, cy - r))
    try geometry.cubic_to(b, pt(x, y, w, h, cx + k, cy - r), pt(x, y, w, h, cx + r, cy - k), pt(x, y, w, h, cx + r, cy))
    try geometry.close_path(b)
    ret ok
}

// A bar from (x1, y1) to (x2, y2), `half` either side, clockwise.
fn bar(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32, x1: f32, y1: f32, x2: f32, y2: f32, half: f32) -> err {
    var dx = x2 - x1
    var dy = y2 - y1
    let n = (dx * dx + dy * dy)
    var len: f32 = 1.0
    while len * len < n { len += 0.01 }
    dx = dx / len * half
    dy = dy / len * half
    // the points in the order that is clockwise on screen (y down): along the bar on its upper side, back on its lower
    try geometry.move_to(b, pt(x, y, w, h, x1 + dy, y1 - dx))
    try geometry.line_to(b, pt(x, y, w, h, x2 + dy, y2 - dx))
    try geometry.line_to(b, pt(x, y, w, h, x2 - dy, y2 + dx))
    try geometry.line_to(b, pt(x, y, w, h, x1 - dy, y1 + dx))
    try geometry.close_path(b)
    ret ok
}

fn mat_remove(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32) -> err {
    ret rect(b, x, y, w, h, 5.0, 11.0, 19.0, 13.0)
}

fn mat_delete(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32) -> err {
    // the lid with its handle, then the bin with the corners cut
    try geometry.move_to(b, pt(x, y, w, h, 5.0, 6.0))
    try geometry.line_to(b, pt(x, y, w, h, 8.5, 6.0))
    try geometry.line_to(b, pt(x, y, w, h, 9.5, 5.0))
    try geometry.line_to(b, pt(x, y, w, h, 14.5, 5.0))
    try geometry.line_to(b, pt(x, y, w, h, 15.5, 6.0))
    try geometry.line_to(b, pt(x, y, w, h, 19.0, 6.0))
    try geometry.line_to(b, pt(x, y, w, h, 19.0, 8.0))
    try geometry.line_to(b, pt(x, y, w, h, 5.0, 8.0))
    try geometry.close_path(b)
    try geometry.move_to(b, pt(x, y, w, h, 6.0, 9.0))
    try geometry.line_to(b, pt(x, y, w, h, 18.0, 9.0))
    try geometry.line_to(b, pt(x, y, w, h, 18.0, 19.0))
    try geometry.cubic_to(b, pt(x, y, w, h, 18.0, 20.1), pt(x, y, w, h, 17.1, 21.0), pt(x, y, w, h, 16.0, 21.0))
    try geometry.line_to(b, pt(x, y, w, h, 8.0, 21.0))
    try geometry.cubic_to(b, pt(x, y, w, h, 6.9, 21.0), pt(x, y, w, h, 6.0, 20.1), pt(x, y, w, h, 6.0, 19.0))
    try geometry.close_path(b)
    ret ok
}

fn mat_share(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32) -> err {
    try circle(b, x, y, w, h, 18.0, 5.0, 3.0)
    try circle(b, x, y, w, h, 6.0, 12.0, 3.0)
    try circle(b, x, y, w, h, 18.0, 19.0, 3.0)
    try bar(b, x, y, w, h, 18.0, 5.0, 6.0, 12.0, 0.8)
    try bar(b, x, y, w, h, 6.0, 12.0, 18.0, 19.0, 0.8)
    ret ok
}

fn mat_archive(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32) -> err {
    // the lid, then the box with a slot for the hand hole (a counter-clockwise subpath)
    try rect(b, x, y, w, h, 3.0, 3.0, 21.0, 8.0)
    try geometry.move_to(b, pt(x, y, w, h, 5.0, 9.0))
    try geometry.line_to(b, pt(x, y, w, h, 19.0, 9.0))
    try geometry.line_to(b, pt(x, y, w, h, 19.0, 21.0))
    try geometry.line_to(b, pt(x, y, w, h, 5.0, 21.0))
    try geometry.close_path(b)
    try geometry.move_to(b, pt(x, y, w, h, 9.0, 12.0))
    try geometry.line_to(b, pt(x, y, w, h, 9.0, 14.0))
    try geometry.line_to(b, pt(x, y, w, h, 15.0, 14.0))
    try geometry.line_to(b, pt(x, y, w, h, 15.0, 12.0))
    try geometry.close_path(b)
    ret ok
}

// The rows of the "drag_handle" icon: two bars.
fn mat_grip(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32) -> err {
    try rect(b, x, y, w, h, 4.0, 9.0, 20.0, 11.0)
    try rect(b, x, y, w, h, 4.0, 13.0, 20.0, 15.0)
    ret ok
}
