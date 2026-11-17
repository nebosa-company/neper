// e.algo.stat.geosphere against geosphere. tests/oracle/geosphere.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R geosphere`; the layout is at the top of scripts/r_oracle/groups/geosphere.R.

use e.algo.stat.geosphere as g
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "gmean_x") || str.eq(k, "gmean_y") {
        let gn = usize(x[0usize])
        let (gx, gy) = g.geomean(x[1usize..1usize + gn], x[1usize + gn..1usize + 2usize * gn], x[1usize + 2usize * gn..1usize + 3usize * gn])
        if str.eq(k, "gmean_x") { ret gx }
        ret gy
    }
    let a = x[0usize]
    let b = x[1usize]
    let cc = x[2usize]
    let d = x[3usize]
    let p5 = x[4usize]
    if str.eq(k, "dest_lon") || str.eq(k, "dest_lat") {
        let (lo, la) = g.dest_point_rhumb(a, b, p5, x[5usize], cc)
        if str.eq(k, "dest_lon") { ret lo }
        ret la
    }
    if str.eq(k, "dsph_lon") || str.eq(k, "dsph_lat") {
        let (lo, la) = g.dest_point_sphere(a, b, p5, x[5usize], cc)
        if str.eq(k, "dsph_lon") { ret lo }
        ret la
    }
    if str.eq(k, "gci_lon") || str.eq(k, "gci_lat") {
        let (lo, la) = g.gc_intermediate(a, b, cc, d, usize(p5), usize(x[5usize]))
        if str.eq(k, "gci_lon") { ret lo }
        ret la
    }
    if str.eq(k, "haversine") { ret g.dist_haversine(a, b, cc, d, p5) }
    if str.eq(k, "vsphere") { ret g.dist_vincenty_sphere(a, b, cc, d, p5) }
    if str.eq(k, "cosine") { ret g.dist_cosine(a, b, cc, d, p5) }
    if str.eq(k, "meeus") { ret g.dist_meeus(a, b, cc, d, 6378137.0f64, 1.0f64 / 298.257223563f64) }
    if str.eq(k, "vellipsoid") { ret g.dist_vincenty_ellipsoid(a, b, cc, d, 6378137.0f64, 6356752.3142f64, 1.0f64 / 298.257223563f64) }
    if str.eq(k, "bearing_rhumb") { ret g.bearing_rhumb(a, b, cc, d) }
    ret g.dist_rhumb(a, b, cc, d, p5)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/geosphere.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
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
