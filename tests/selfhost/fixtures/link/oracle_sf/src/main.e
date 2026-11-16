// e.algo.geom against sf (GEOS): convex hull, polygon area, point in polygon, Delaunay triangle count.
// tests/oracle/sf.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sf`; the layout is at
// the top of scripts/r_oracle/groups/sf.R.

use e.algo.geom as geom
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let (pts, e1) = mem.alloc[geom.Point](a, n)
    let (out, e2) = mem.alloc[geom.Point](a, n + 1usize)
    let (tri, e3) = mem.alloc[usize](a, 6usize * n)
    let (scr, e4) = mem.alloc[usize](a, 6usize * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        pts[i] = geom.point(x[1usize + i], x[1usize + n + i])
        i += 1usize
    }
    let nm = c.name
    if str.eq(nm, "poly_area") { ret math.abs[f64](geom.polygon_area(pts)) }
    if str.eq(nm, "pip") {
        let m = usize(x[1usize + 2usize * n])
        var inside = 0.0f64
        var q = 0usize
        while q < m {
            let p = geom.point(x[2usize + 2usize * n + q], x[2usize + 2usize * n + m + q])
            if geom.point_in_polygon(pts, p) { inside += 1.0f64 }
            q += 1usize
        }
        ret inside
    }
    if str.eq(nm, "del_n") {
        let (w, de) = geom.delaunay(pts, tri, scr)
        if de != ok { ret 0.0f64 / 0.0f64 }
        ret f64(w / 3usize)
    }
    let (h, he) = geom.hull(pts, out)
    if he != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(nm, "hull_n") { ret f64(h) }
    ret math.abs[f64](geom.polygon_area(out[0usize..h]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sf.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
