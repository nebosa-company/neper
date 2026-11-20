// e.algo.stat.gamlssstep (stepGAIC on main-effect terms) against gamlss. tests/oracle/gamlss_step.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_step`; the header and data layout are at the top of scripts/r_oracle/groups/gamlss_step.R.

use e.algo.stat.gamlssstep as gs
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_step.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var n = 0usize
    let (fncol, e1) = mem.alloc[usize](a, 3usize)
    let (link, e2) = mem.alloc[usize](a, 3usize)
    if e1 != ok || e2 != ok { os.exit(4) }
    let scen = mem.mark(a)
    var res: gs.Step = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if usize(x[0usize]) != 99usize {
            mem.reset(a, scen)
            let fam = usize(x[0usize])
            n = usize(x[2usize])
            let what = usize(x[3usize])
            let q = usize(x[4usize])
            let ninit = usize(x[5usize])
            var k = 0usize
            while k < 3usize {
                fncol[k] = usize(x[8usize + k])
                link[k] = usize(x[11usize + k])
                k += 1usize
            }
            let (init, e3) = mem.alloc[usize](a, q + 1usize)
            let (lower, e4) = mem.alloc[usize](a, q + 1usize)
            let (upper, e5) = mem.alloc[usize](a, q + 1usize)
            if e3 != ok || e4 != ok || e5 != ok { os.exit(4) }
            var i = 0usize
            while i < ninit {
                init[i] = usize(x[16usize + i])
                i += 1usize
            }
            i = 0usize
            while i < q {
                lower[i] = usize(x[16usize + ninit + i])
                upper[i] = usize(x[16usize + ninit + q + i])
                i += 1usize
            }
            let d0 = 16usize + ninit + 2usize * q
            let y = x[d0..d0 + n]
            let w = x[d0 + n..d0 + 2usize * n]
            let ft = fncol[0usize] + fncol[1usize] + fncol[2usize]
            let fixed = x[d0 + 2usize * n..d0 + 2usize * n + n * ft]
            let cand = x[d0 + 2usize * n + n * ft..x.len]
            let (r, fe) = gs.step_gaic(a, fam, usize(x[1usize]), y, w, fixed, fncol, link, what, cand, q, init, ninit, lower, upper, usize(x[6usize]), x[7usize], 1000usize)
            if fe != ok { os.exit(6) }
            res = r
        }
        let kind = usize(x[14usize])
        let idx = usize(x[15usize])
        var got = 0.0f64
        if kind == 0usize { got = f64(res.nterms) }
        if kind == 1usize { got = f64(res.terms[idx]) }
        if kind == 2usize { got = f64(res.npath) }
        if kind == 3usize { got = f64(res.change[idx]) }
        if kind == 4usize { got = res.dev[idx] }
        if kind == 5usize { got = res.gaic[idx] }
        if kind == 6usize { got = f64(n) - res.df[idx] }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
