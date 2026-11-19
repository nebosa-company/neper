// e.algo.stat.massnb against MASS glm.nb and theta.mm. tests/oracle/mass_glmnb.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_glmnb`; the layout is at the top of scripts/r_oracle/groups/mass_glmnb.R.

use e.algo.stat.massnb as mn
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "thmm") {
        let n = usize(z[0usize])
        ret mn.theta_mm(z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], z[1usize], z[3usize + 2usize * n..3usize + 3usize * n], usize(z[2usize]), 1.220703125e-4f64)
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let link = usize(z[2usize])
    let has_w = z[3usize] != 0.0f64
    let has_off = z[4usize] != 0.0f64
    var init = z[5usize]
    if init == 0.0f64 { init = nan() }
    let maxit = usize(z[6usize])
    let epsilon = z[7usize]
    let mode = usize(z[8usize])
    let y = z[9usize..9usize + n]
    let x = z[9usize + n..9usize + n + n * p]
    var at = 9usize + n + n * p
    let (w, e1) = mem.alloc[f64](a, n)
    let (off, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        off[i] = 0.0f64
        i += 1usize
    }
    if has_w {
        i = 0usize
        while i < n {
            w[i] = z[at + i]
            i += 1usize
        }
        at += n
    }
    if has_off {
        i = 0usize
        while i < n {
            off[i] = z[at + i]
            i += 1usize
        }
    }
    let (r, e) = mn.glm_nb(a, x, n, p, y, w, off, link, init, maxit, epsilon, true, has_off)
    if e != ok { ret nan() }
    if mode == 0usize { ret wsum(r.fit.coef) }
    if mode == 1usize { ret r.theta }
    if mode == 2usize { ret r.se }
    if mode == 3usize { ret r.twologlik }
    if mode == 4usize { ret r.aic }
    if mode == 5usize { ret r.fit.dev }
    if mode == 6usize { ret r.nulldev }
    if mode == 7usize { ret f64(r.fit.iter) }
    if mode == 8usize { ret f64(r.fit.rank) }
    ret wsum(r.fit.mu)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_glmnb.json")
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
