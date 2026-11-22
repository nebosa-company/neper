// e.algo.stat.polcapkg against poLCA. tests/oracle/polca.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R polca`; the layout is at the top of scripts/r_oracle/groups/polca.R.

use e.algo.rand.r as rg
use e.algo.stat.polcapkg as pl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn fit_case(a: *mem.Arena, c: *const oracle.Case) -> (pl.Fit, err) {
    let z = c.args
    let n = usize(z[0usize])
    let nj = usize(z[1usize])
    let nr = usize(z[2usize])
    let q = usize(z[3usize])
    let nrep = usize(z[4usize])
    var rng: rg.Rng = zero
    rg.seed(&rng, i64(z[5usize]))
    let na_rm = z[6usize] > 0.5f64
    let ls = usize(z[7usize])
    let st = z[8usize..8usize + ls]
    let yo = 8usize + ls
    let y = z[yo..yo + n * nj]
    let x = z[yo + n * nj..yo + n * nj + n * q]
    let (f, e) = pl.lca_fit(a, y, n, nj, x, q, nr, st, nrep, &rng, 1.0e-10f64, 1000usize, na_rm)
    ret (f, e)
}

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn pick(v: []const f64, k: usize) -> f64 {
    if k == 0usize || k > v.len { ret 0.0f64 / 0.0f64 }
    ret v[k - 1usize]
}

fn query(a: *mem.Arena, f: *const pl.Fit, code: usize, k: usize) -> f64 {
    if code == 1usize { ret f64(f.numiter) }
    if code == 2usize { ret f.npar }
    if code == 3usize { ret f.aic }
    if code == 4usize { ret f.bic }
    if code == 5usize { ret f.gsq }
    if code == 6usize { ret f.chisq }
    if code == 7usize { ret f.resid_df }
    if code == 8usize { ret f64(f.nobs) }
    if code == 9usize { ret f64(f.n) }
    if code == 10usize { ret pl.lca_entropy(a, f) }
    if code == 11usize {
        if f.eflag { ret 1.0f64 }
        ret 0.0f64
    }
    if code == 12usize { ret f64(f.ncell) }
    if code == 13usize || code == 14usize {
        var s = 0.0f64
        var i = 0usize
        while i < f.n {
            var w = 1.0f64
            if code == 14usize { w = f64(i + 1usize) }
            s += f64(f.predclass[i]) * w
            i += 1usize
        }
        ret s
    }
    if code == 20usize { ret pick(f.probs, k) }
    if code == 21usize { ret pick(f.prior_p, k) }
    if code == 22usize { ret pick(f.probs_se, k) }
    if code == 23usize { ret pick(f.p_se, k) }
    if code == 24usize { ret pick(f.coeff, k) }
    if code == 25usize { ret pick(f.coeff_se, k) }
    if code == 26usize { ret pick(f.coeff_v, k) }
    if code == 27usize { ret pick(f.attempts[0usize..f.nattempt], k) }
    if code == 28usize { ret pick(f.probs_start, k) }
    if code == 30usize { ret wsum(f.posterior) }
    if code == 31usize { ret wsum(f.observed) }
    if code == 32usize { ret wsum(f.expected) }
    if code == 33usize { ret wsum(f.cells) }
    ret 0.0f64 / 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/polca.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var cur: pl.Fit = zero
    var have = false
    let base = mem.mark(a)
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        var got = 0.0f64 / 0.0f64
        if str.eq(c.name, "fit") {
            mem.reset(a, base)
            let (f, e) = fit_case(a, c)
            have = e == ok
            cur = f
            if have { got = cur.llik }
        } else if have {
            let start = mem.mark(a)
            got = query(a, &cur, usize(c.args[0usize]), usize(c.args[1usize]))
            mem.reset(a, start)
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
