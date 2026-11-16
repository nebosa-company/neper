// e.gfx.hclops against colorspace. tests/oracle/hclops.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hclops`; the layout is at the top of scripts/r_oracle/groups/hclops.R.

use e.gfx.hclops as ho
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, t: []const f64, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nm = c.name
    if str.eq(nm, "lighten") {
        var am = z[1usize]
        if z[5usize] == 1.0f64 { am = 0.0f64 - am }
        ret f64(ho.lighten(t, i64(z[0usize]), am, z[2usize] == 0.0f64, u8(z[3usize]), z[4usize] == 1.0f64))
    }
    if str.eq(nm, "coords") {
        let col = ho.unpack(i64(z[0usize]))
        var v = ho.srgb_to_polar_lab(col.a, col.b, col.c)
        if z[1usize] == 1.0f64 { v = ho.srgb_to_polar_luv(col.a, col.b, col.c) }
        let q = usize(z[2usize])
        if q == 0usize { ret v.a }
        if q == 1usize { ret v.b }
        ret v.c
    }
    if str.eq(nm, "labhex") { ret f64(ho.polar_lab_hex(z[0usize], z[1usize], z[2usize], z[3usize] == 1.0f64)) }
    ret ho.apca(i64(z[0usize]), i64(z[1usize]), z[2usize] == 1.0f64)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hclops.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (t, te) = ho.load_table(a)
    if te != ok { os.exit(4) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, t, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
