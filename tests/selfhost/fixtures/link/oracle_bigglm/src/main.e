// e.algo.stat.bigglm against biglm::bigglm. tests/oracle/bigglm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bigglm`; the layout is at the top of
// scripts/r_oracle/groups/bigglm.R.

use e.algo.stat.bigglm as bg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let fam = u8(z[0usize])
    let n = usize(z[1usize])
    let p0 = usize(z[2usize])
    let p = p0 + 1usize
    let x0 = z[3usize..3usize + n * p0]
    let y = z[3usize + n * p0..3usize + n * p0 + n]
    let w = z[3usize + n * p0 + n..3usize + n * p0 + 2usize * n]
    let hasoff = c.name.len == 3usize && c.name[2usize] == 111u8
    var qi = 3usize + n * p0 + 2usize * n
    if hasoff { qi += n }
    let q = usize(z[qi])
    let (off, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret nan }
    var oi = 0usize
    while oi < n {
        off[oi] = 0.0f64
        if hasoff { off[oi] = z[3usize + n * p0 + 2usize * n + oi] }
        oi += 1usize
    }
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (coef, e2) = mem.alloc[f64](a, p)
    let (se, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var i = 0usize
    while i < n {
        x[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * p0 {
        x[n + i] = x0[i]
        i += 1usize
    }
    let (sandv, sdE) = mem.alloc[f64](a, p)
    if sdE != ok { ret nan }
    var fit: bg.Fit = zero
    var e = ok
    if c.name.len == 3usize && c.name[2usize] == 97u8 {
        let (fa, ea) = bg.bigglm_alias(a, x, y, w, off, n, p, fam, 8usize, 1.0e-7f64, coef, se, sandv)
        fit = fa
        e = ea
        if q == 2usize * p {
            var na = 0.0f64
            var ci = 0usize
            while ci < p {
                if coef[ci] != coef[ci] { na += 1.0f64 }
                ci += 1usize
            }
            ret na
        }
    } else {
        let (fb, eb) = bg.bigglm_sand(a, x, y, w, off, n, p, fam, 8usize, 1.0e-7f64, coef, se, sandv)
        fit = fb
        e = eb
    }
    if e != ok { ret nan }
    if c.name.len == 3usize && c.name[2usize] == 115u8 { ret sandv[q] }
    if q < p { ret coef[q] }
    if q < 2usize * p { ret se[q - p] }
    if q == 2usize * p { ret f64(fit.iterations) }
    if q == 2usize * p + 1usize {
        if fit.converged { ret 1.0f64 }
        ret 0.0f64
    }
    ret fit.deviance
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bigglm.json")
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
