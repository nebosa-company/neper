// e.algo.stat.fdareg smooth.morph and fdalm landmarkreg against fda. tests/oracle/fda3.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda3`; the layout is at the top of scripts/r_oracle/groups/fda3.R.

use e.algo.stat.fdalm as lm
use e.algo.stat.fdareg as fr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if c.name[0usize] == 112u8 {
        // p: (nw, lambda, m, lo, hi, ylo, yhi, nobs, which, c0[nw], x[nobs], y[nobs])
        let nw = usize(z[0usize])
        let nobs = usize(z[7usize])
        let (wb, e1) = mem.alloc[f64](a, nw - 2usize)
        let (co, e2) = mem.alloc[f64](a, nw)
        let (st, e3) = mem.alloc[f64](a, 3usize)
        if e1 != ok || e2 != ok || e3 != ok { ret nan }
        var i = 0usize
        while i < nw - 2usize {
            wb[i] = fr.seq_at(z[3usize], z[4usize], nw - 2usize, i)
            i += 1usize
        }
        if fr.smooth_morph(a, 4usize, wb, usize(z[2usize]), z[1usize], z[9usize..9usize + nw], z[9usize + nw..9usize + nw + nobs], z[9usize + nw + nobs..9usize + nw + 2usize * nobs], z[5usize], z[6usize], 1.0e-4f64, 20usize, co, st) != ok { ret nan }
        let w = usize(z[8usize])
        if w < nw { ret co[w] }
        ret st[w - nw]
    }
    // l: (nbasis, ncurve, nl, ylambda, which, index, x0marks[nl], ximarks[ncurve nl], coefs[nbasis ncurve])
    let nbasis = usize(z[0usize])
    let ncurve = usize(z[1usize])
    let nl = usize(z[2usize])
    let nw = nl + 2usize
    let (r1, e1) = mem.alloc[f64](a, nbasis * ncurve)
    let (r2, e2) = mem.alloc[f64](a, nbasis * ncurve)
    let (r3, e3) = mem.alloc[f64](a, nbasis * ncurve)
    let (r4, e4) = mem.alloc[f64](a, nw * ncurve)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    if lm.landmark_reg(a, 0.0f64, 1.0f64, nbasis, ncurve, nl, z[3usize], z[6usize..6usize + nl], z[6usize + nl..6usize + nl + ncurve * nl], z[6usize + nl + ncurve * nl..6usize + nl + ncurve * nl + nbasis * ncurve], r1, r2, r3, r4) != ok { ret nan }
    let w = usize(z[4usize])
    let q = usize(z[5usize])
    if w == 0usize { ret r1[q] }
    if w == 1usize { ret r2[q] }
    if w == 2usize { ret r3[q] }
    ret r4[q]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda3.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    let (seen, se) = mem.alloc[usize](a, 512usize)
    if se != ok { os.exit(4) }
    var s0 = 0usize
    while s0 < 512usize {
        seen[s0] = 0usize
        s0 += 1usize
    }
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            // one line per case kind (and, for landmarkreg, per output)
            var key = usize(c.name[0usize])
            if key == 108usize { key = 256usize + usize(c.args[4usize]) }
            seen[key] += 1usize
            if seen[key] <= 2usize {
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
