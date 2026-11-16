// e.algo.stat.factominepkg against FactoMineR PCA and CA. tests/oracle/factominer.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R factominer`; the layout is at the top of scripts/r_oracle/groups/factominer.R.

use e.algo.stat.factominepkg as fm
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn weighted(src: []const f64, lo: usize, cnt: usize, absolute: bool) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        var v = src[lo + i]
        if absolute { v = math.abs[f64](v) }
        s += v * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let r = usize(z[1usize])
    let cc = usize(z[2usize])
    let data = z[3usize..3usize + r * cc]
    let (out, e1) = mem.alloc[f64](a, 8usize * r * cc + 8usize * cc + 64usize)
    if e1 != ok { ret nan }
    if usize(z[0usize]) == 0usize {
        let n = r
        let p = cc
        if fm.pca(a, data, n, p, out) != ok { ret nan }
        if str.eq(c.name, "eig") { ret weighted(out, 0usize, p, false) }
        if str.eq(c.name, "vcoord") { ret weighted(out, p, p * p, true) }
        if str.eq(c.name, "vcontrib") { ret weighted(out, p + p * p, p * p, false) }
        if str.eq(c.name, "icoord") { ret weighted(out, p + 2usize * p * p, n * p, true) }
        if str.eq(c.name, "icos2") { ret weighted(out, p + 2usize * p * p + n * p, n * p, false) }
        if str.eq(c.name, "icontrib") { ret weighted(out, p + 2usize * p * p + 2usize * n * p, n * p, false) }
        ret weighted(out, p + 2usize * p * p + 3usize * n * p, n, false)
    }
    var nd = r
    if cc < nd { nd = cc }
    nd -= 1usize
    if fm.ca(a, data, r, cc, out) != ok { ret nan }
    if str.eq(c.name, "ceig") { ret weighted(out, 0usize, nd, false) }
    if str.eq(c.name, "rcoord") { ret weighted(out, nd, r * nd, true) }
    if str.eq(c.name, "rcontrib") { ret weighted(out, nd + r * nd, r * nd, false) }
    if str.eq(c.name, "ccoord") { ret weighted(out, nd + 2usize * r * nd, cc * nd, true) }
    ret weighted(out, nd + 2usize * r * nd + cc * nd, cc * nd, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/factominer.json")
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
