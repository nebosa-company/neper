// R igraph, the deterministic layouts that need no graph: `layout_in_circle` (vertices on the unit circle, from
// angle 0, in vertex order or a given order), `layout_as_star` (a centre at the origin, the rest on the unit circle),
// `layout_on_grid` (row-major cells of the given width) and `layout_on_sphere` (the spiral of igraph).
// Coordinates are written row-major, n rows of 2 (3 for the sphere).
//
// Not here: layout_with_fr, kk, mds, graphopt, drl, layout_as_tree, layout_nicely and the random generators.

use e.math

fn in_circle(n: usize, order: []const usize, out: []f64) {
    let m = order.len
    var i = 0usize
    while i < m {
        let ang = 2.0f64 * 3.141592653589793f64 * f64(i) / f64(m)
        out[order[i] * 2usize] = math.cos[f64](ang)
        out[order[i] * 2usize + 1usize] = math.sin[f64](ang)
        i += 1usize
    }
}

// centre is 0-based
fn as_star(n: usize, center: usize, out: []f64) {
    var k = 0usize
    var i = 0usize
    while i < n {
        if i == center {
            out[i * 2usize] = 0.0f64
            out[i * 2usize + 1usize] = 0.0f64
        } else {
            let ang = 2.0f64 * 3.141592653589793f64 * f64(k) / f64(n - 1usize)
            out[i * 2usize] = math.cos[f64](ang)
            out[i * 2usize + 1usize] = math.sin[f64](ang)
            k += 1usize
        }
        i += 1usize
    }
}

fn on_grid(n: usize, width: usize, out: []f64) {
    var w = width
    if w == 0usize { w = usize(math.ceil[f64](math.sqrt[f64](f64(n)))) }
    var i = 0usize
    while i < n {
        out[i * 2usize] = f64(i % w)
        out[i * 2usize + 1usize] = f64(i / w)
        i += 1usize
    }
}

fn on_sphere(n: usize, out: []f64) {
    var fi = 0.0f64
    var i = 0usize
    while i < n {
        var h = 0.0f64 - 1.0f64
        if n > 1usize { h = 0.0f64 - 1.0f64 + 2.0f64 * f64(i) / f64(n - 1usize) }
        let z = h
        var r = 0.0f64
        if i > 0usize && i + 1usize < n {
            fi = fi + 3.6f64 / math.sqrt[f64](f64(n) * (1.0f64 - h * h))
            r = math.sqrt[f64](1.0f64 - h * h)
        }
        out[i * 3usize] = r * math.cos[f64](fi)
        out[i * 3usize + 1usize] = r * math.sin[f64](fi)
        out[i * 3usize + 2usize] = z
        i += 1usize
    }
}
