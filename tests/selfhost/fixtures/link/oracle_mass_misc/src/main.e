// e.algo.stat.massmisc against MASS corresp, mca, .rat, the truehist numerics and hubers. tests/oracle/mass_misc.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_misc`; the layout is at the top of scripts/r_oracle/groups/mass_misc.R.

use e.algo.stat.massmisc as mm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret s
}

fn missing(v: f64) -> f64 {
    if v >= 1.0e300f64 { ret nan() }
    ret v
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "corresp") {
        let nr = usize(z[0usize])
        let nc = usize(z[1usize])
        let nf = usize(z[2usize])
        let (cor, e1) = mem.alloc[f64](a, nf)
        let (rs, e2) = mem.alloc[f64](a, nr * nf)
        let (cs, e3) = mem.alloc[f64](a, nc * nf)
        if e1 != ok || e2 != ok || e3 != ok { ret nan() }
        let e = mm.corresp(a, z[4usize..4usize + nr * nc], nr, nc, nf, cor, rs, cs)
        if e != ok { ret nan() }
        let mode = usize(z[3usize])
        if mode == 0usize { ret wsum(cor) }
        if mode == 1usize { ret wsum(rs) }
        ret wsum(cs)
    }
    if str.eq(c.name, "mca") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let nf = usize(z[2usize])
        let mode = usize(z[3usize])
        let lv = z[4usize..4usize + p]
        var kk = 0usize
        var v = 0usize
        while v < p {
            kk += usize(lv[v])
            v += 1usize
        }
        let (d, e1) = mem.alloc[f64](a, nf)
        let (rs, e2) = mem.alloc[f64](a, n * nf)
        let (cs, e3) = mem.alloc[f64](a, kk * nf)
        let (fs, e4) = mem.alloc[f64](a, n * nf)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan() }
        let e = mm.mca(a, z[4usize + p..4usize + p + n * p], n, p, lv, nf, d, rs, cs, fs)
        if e != ok { ret nan() }
        if mode == 0usize { ret wsum(d) }
        if mode == 1usize { ret wsum(rs) }
        if mode == 2usize { ret wsum(cs) }
        ret wsum(fs)
    }
    if str.eq(c.name, "rat") {
        let n = usize(z[3usize])
        var s = 0.0f64
        var i = 0usize
        while i < n {
            let (nu, de) = mm.rat(z[4usize + i], usize(z[0usize]), z[1usize])
            if usize(z[2usize]) == 0usize { s += f64(i + 1usize) * nu } else { s += f64(i + 1usize) * de }
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "th") {
        let n = usize(z[5usize])
        let (br, e1) = mem.alloc[f64](a, n + 200usize)
        let (est, e2) = mem.alloc[f64](a, n + 200usize)
        if e1 != ok || e2 != ok { ret nan() }
        let (nb, e) = mm.truehist(a, z[6usize..6usize + n], usize(z[0usize]), z[1usize], z[2usize], missing(z[3usize]), br, est)
        if e != ok { ret nan() }
        let what = usize(z[4usize])
        if what == 0usize { ret wsum(br[0usize..nb]) }
        if what == 1usize { ret wsum(est[0usize..nb - 1usize]) }
        ret f64(nb)
    }
    let n = usize(z[6usize])
    let (mu, s) = mm.hubers_full(a, z[7usize..7usize + n], z[0usize], missing(z[1usize]), missing(z[2usize]), missing(z[3usize]), z[4usize])
    if usize(z[5usize]) == 0usize { ret mu }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_misc.json")
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
