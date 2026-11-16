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
    if kind == 1usize {
        if sp.eigs_sym(a, x, n, k, wh, d, u) != ok { ret nan }
    } else {
        if sp.svds(a, x, m, n, k, d, u, v) != ok { ret nan }
    }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "d") {
        while i < k {
            s += d[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    var rows = m
    var src = u
    if str.eq(c.name, "vabs") {
        rows = n
        src = v
    }
    // R lists the matrix row by row of t(vectors): column j of the vectors, entry i, at position j * rows + i
    var j = 0usize
    while j < k {
        i = 0usize
        while i < rows {
            s += math.abs[f64](src[i * k + j]) * f64(j * rows + i + 1usize)
            i += 1usize
        }
        j += 1usize
    }
    ret s
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
