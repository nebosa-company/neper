// e.algo.stat.geosphere_geod against geosphere. tests/oracle/geosphere_geod.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R geosphere_geod`; the layout is at the top of scripts/r_oracle/groups/geosphere_geod.R.

use e.algo.stat.geosphere_geod as g
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "area") || str.eq(k, "perim_geo") || str.eq(k, "perim_mat") || str.eq(k, "cent_x") || str.eq(k, "cent_y") {
        let n = usize(x[0usize])
        let lon = x[1usize..1usize + n]
        let lat = x[1usize + n..1usize + 2usize * n]
        let a = x[1usize + 2usize * n]
        let f = x[2usize + 2usize * n]
        if str.eq(k, "area") { ret g.area_polygon(lon, lat, a, f) }
        if str.eq(k, "perim_geo") { ret g.perimeter_geodesic(lon, lat, a, f) }
        if str.eq(k, "perim_mat") { ret g.perimeter_matrix(lon, lat) }
        let (cx, cy) = g.centroid(lon, lat)
        if str.eq(k, "cent_x") { ret cx }
        ret cy
    }
    if str.eq(k, "sbrg") { ret g.bearing_sphere(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "anti_x") || str.eq(k, "anti_y") {
        let (ax, ay) = g.antipode(x[0usize], x[1usize])
        if str.eq(k, "anti_x") { ret ax }
        ret ay
    }
    if str.eq(k, "merc_x") || str.eq(k, "merc_y") {
        let (mx, my) = g.mercator(x[0usize], x[1usize], x[2usize])
        if str.eq(k, "merc_x") { ret mx }
        ret my
    }
    if str.eq(k, "merci_x") || str.eq(k, "merci_y") {
        let (ix, iy) = g.mercator_inverse(x[0usize], x[1usize], x[2usize])
        if str.eq(k, "merci_x") { ret ix }
        ret iy
    }
    if str.eq(k, "atd") { ret g.along_track_distance(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize]) }
    if str.eq(k, "d2gc") { ret g.dist2gc(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], false) }
    if str.eq(k, "d2gcs") { ret g.dist2gc(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], true) }
    if str.eq(k, "ongc") {
        if g.on_great_circle(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize]) { ret 1.0f64 }
        ret 0.0f64
    }
    let p1 = x[0usize]
    let p2 = x[1usize]
    let p3 = x[2usize]
    let p4 = x[3usize]
    let a = x[4usize]
    let f = x[5usize]
    if str.eq(k, "dist") { ret g.dist_geo(p1, p2, p3, p4, a, f) }
    if str.eq(k, "brg") { ret g.bearing_geo(p1, p2, p3, p4, a, f) }
    if str.eq(k, "fbrg") { ret g.final_bearing_geo(p1, p2, p3, p4, a, f) }
    if str.eq(k, "mid_lon") || str.eq(k, "mid_lat") {
        let (lo, la) = g.mid_point_geo(p1, p2, p3, p4, a, f)
        if str.eq(k, "mid_lon") { ret lo }
        ret la
    }
    let (lo, la) = g.dest_point_geo(p1, p2, p3, p4, a, f)
    if str.eq(k, "dest_lon") { ret lo }
    ret la
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/geosphere_geod.json")
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
