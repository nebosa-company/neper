// e.algo.stat.hexbin against hexbin: cell ids, counts, centres of mass and cell centres.
// tests/oracle/hexbin.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hexbin`;
// the layout is at the top of scripts/r_oracle/groups/hexbin.R.

use e.algo.stat.hexbin as hb
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let xbins = x[0usize]
    let shape = x[1usize]
    let n = usize(x[2usize])
    let xs = x[3usize..3usize + n]
    let ys = x[3usize + n..3usize + 2usize * n]
    var xlo = xs[0usize]
    var xhi = xs[0usize]
    var ylo = ys[0usize]
    var yhi = ys[0usize]
    var i = 0usize
    while i < n {
        if xs[i] < xlo { xlo = xs[i] }
        if xs[i] > xhi { xhi = xs[i] }
        if ys[i] < ylo { ylo = ys[i] }
        if ys[i] > yhi { yhi = ys[i] }
        i += 1usize
    }
    let (b, e) = hb.hexbin(a, xs, ys, xbins, shape, xlo, xhi, ylo, yhi)
    if e != ok { os.exit(6) }
    let j = u8(x[x.len - 1usize])
    if str.eq(c.name, "dims") {
        if j == 0u8 { ret f64(b.imax) }
        ret f64(b.jmax)
    }
    let (v, ve) = mem.alloc[f64](a, b.ncells)
    if ve != ok { os.exit(5) }
    i = 0usize
    while i < b.ncells {
        if str.eq(c.name, "cell") { v[i] = f64(b.cell[i]) }
        if str.eq(c.name, "count") { v[i] = f64(b.count[i]) }
        if str.eq(c.name, "xcm") { v[i] = b.xcm[i] }
        if str.eq(c.name, "ycm") { v[i] = b.ycm[i] }
        if str.eq(c.name, "cx") || str.eq(c.name, "cy") {
            let (cx, cy) = hb.hcell2xy(b.cell[i], b.jmax, xbins, shape, xlo, xhi, ylo, yhi)
            if str.eq(c.name, "cx") { v[i] = cx } else { v[i] = cy }
        }
        i += 1usize
    }
    if j == 0u8 { ret f64(v.len) }
    if j == 3u8 { ret v[0usize] }
    if j == 4u8 { ret v[v.len - 1usize] }
    var s = 0.0f64
    i = 0usize
    while i < v.len {
        if j == 1u8 { s += v[i] } else { s += f64(i + 1usize) * v[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hexbin.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
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
