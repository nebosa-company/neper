// e.algo.stat.spectrapkg against RSpectra (svds, eigs_sym) and irlba. tests/oracle/spectra.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra`; the layout is at the top of scripts/r_oracle/groups/spectra.R.

use e.algo.stat.spectrapkg as sp
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let kind = usize(z[0usize])
    let m = usize(z[1usize])
    let n = usize(z[2usize])
    let k = usize(z[3usize])
    let wh = usize(z[4usize])
    let x = z[5usize..5usize + m * n]
    let (d, e1) = mem.alloc[f64](a, k)
    let (u, e2) = mem.alloc[f64](a, m * k)
    let (v, e3) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var rows = m
    var src = u
    if kind == 1usize {
        var sigma = 0.0f64
        if wh == 4usize { sigma = z[5usize + m * n] }
        if sp.eigs_sym(a, x, n, k, wh, sigma, d, u) != ok { ret nan }
        let (zi, e4) = mem.alloc[f64](a, n * k)
        if e4 != ok { ret nan }
        var q = 0usize
        while q < n * k {
            zi[q] = 0.0f64
            q += 1usize
        }
        sp.rotate_phase(u, zi, n, k)
        rows = n
        src = u
    } else {
        if sp.svds(a, x, m, n, k, d, u, v) != ok { ret nan }
        sp.svd_sign(u, v, m, n, k)
        if str.eq(c.name, "v") {
            rows = n
            src = v
        }
    }
    if str.eq(c.name, "d") {
        var s = 0.0f64
        var i = 0usize
        while i < k {
            s += d[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    ret sp.wsum(src, rows, k)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra.json")
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
