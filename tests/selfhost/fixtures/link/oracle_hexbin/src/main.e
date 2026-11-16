// e.algo.stat.hexbin against hexbin: cell ids, counts, centres of mass and cell centres.
// tests/oracle/hexbin.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hexbin`;
// the layout is at the top of scripts/r_oracle/groups/hexbin.R.

use e.algo.stat.hexbin as hb
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn stat(v: []const f64, j: u8) -> f64 {
    if j == 0u8 { ret f64(v.len) }
    if j == 3u8 { ret v[0usize] }
    if j == 4u8 { ret v[v.len - 1usize] }
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if j == 1u8 { s += v[i] } else { s += f64(i + 1usize) * v[i] }
        i += 1usize
    }
    ret s
}

fn extra(a: *mem.Arena, c: *const oracle.Case, b: hb.Bin, ys: []const f64, xbins: f64, shape: f64, xlo: f64, xhi: f64, ylo: f64, yhi: f64) -> f64 {
    let x = c.args
    let len = x.len
    let j = u8(x[len - 1usize])
    if str.eq(c.name, "tap") {
        let (v, e) = hb.hex_tapply(a, b, ys, u8(x[len - 2usize]))
        if e != ok { os.exit(6) }
        ret stat(v, j)
    }
    if str.eq(c.name, "erode") || str.eq(c.name, "eroded") {
        let (r, e) = hb.erode(a, b.cell, b.count, b.imax, b.jmax, x[len - 2usize])
        if e != ok { os.exit(6) }
        if str.eq(c.name, "erode") {
            let (v, ve) = mem.alloc[f64](a, r.nsel)
            if ve != ok { os.exit(5) }
            var k = 0usize
            while k < r.nsel {
                v[k] = f64(r.erode[k])
                k += 1usize
            }
            ret stat(v, j)
        }
        let (v, ve) = mem.alloc[f64](a, r.good.len)
        if ve != ok { os.exit(5) }
        var k = 0usize
        while k < r.good.len {
            v[k] = 0.0f64
            if r.good[k] { v[k] = 1.0f64 }
            k += 1usize
        }
        ret stat(v, j)
    }
    let (s, e) = hb.smooth(a, b.cell, b.count, b.imax, b.jmax, i64(x[len - 4usize]), i64(x[len - 3usize]), i64(x[len - 2usize]))
    if e != ok { os.exit(6) }
    if str.eq(c.name, "sdim") {
        if j == 0u8 { ret f64(s.imax) }
        ret f64(s.jmax)
    }
    let (v, ve) = mem.alloc[f64](a, s.ncells)
    if ve != ok { os.exit(5) }
    let f = 2.0f64 / xbins
    var k = 0usize
    while k < s.ncells {
        if str.eq(c.name, "scell") { v[k] = f64(s.cell[k]) }
        if str.eq(c.name, "scount") { v[k] = f64(s.count[k]) }
        if str.eq(c.name, "scx") || str.eq(c.name, "scy") {
            let (cx, cy) = hb.hcell2xy(s.cell[k], s.jmax, xbins + 4.0f64, shape, xlo - f * (xhi - xlo), xhi + f * (xhi - xlo), ylo - f * (yhi - ylo), yhi + f * (yhi - ylo))
            if str.eq(c.name, "scx") { v[k] = cx } else { v[k] = cy }
        }
        k += 1usize
    }
    ret stat(v, j)
}

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
    if str.eq(c.name, "tap") || str.eq(c.name, "erode") || str.eq(c.name, "eroded") || str.eq(c.name, "sdim") || str.eq(c.name, "scell") || str.eq(c.name, "scount") || str.eq(c.name, "scx") || str.eq(c.name, "scy") { ret extra(a, c, b, ys, xbins, shape, xlo, xhi, ylo, yhi) }
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
