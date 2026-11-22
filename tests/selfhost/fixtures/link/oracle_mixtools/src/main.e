// e.algo.stat.mixtools (normalmixEM, multmixEM) against mixtools. tests/oracle/mixtools.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mixtools`; the argument layout is at the top of scripts/r_oracle/groups/mixtools.R.

use e.algo.rand.r as rg
use e.algo.stat.mixtools as mt
use e.algo.stat.mixtools_mult as mm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// normalmixEM: [sel, idx, seed, k, arbmean, arbvar, n, nl, nm, ns, x(n), lambda(nl), mu(nm), sigma(ns)]
fn answer_nm(a: *mem.Arena, x: []const f64) -> f64 {
    let sel = usize(x[0usize])
    let idx = usize(x[1usize])
    var g: rg.Rng = zero
    rg.seed(&g, i64(x[2usize]))
    let k = usize(x[3usize])
    let n = usize(x[6usize])
    let nl = usize(x[7usize])
    let nm = usize(x[8usize])
    let ns = usize(x[9usize])
    let data = x[10usize..10usize + n]
    let lam = x[10usize + n..10usize + n + nl]
    let mu = x[10usize + n + nl..10usize + n + nl + nm]
    let sg = x[10usize + n + nl + nm..10usize + n + nl + nm + ns]
    let (f, e) = mt.normal_mix_em(a, &g, data, lam, mu, sg, k, x[4usize] != 0.0f64, x[5usize] != 0.0f64, 1.0e-8f64, 1000usize, 20usize)
    if e != ok { os.exit(8) }
    if sel == 1usize { ret f.loglik }
    if sel == 2usize { ret f64(f.iter) }
    if sel == 3usize { ret f64(f.restarts) }
    if sel == 4usize { ret f.lambda[idx - 1usize] }
    if sel == 5usize { ret f.mu[idx - 1usize] }
    if sel == 6usize { ret f.sigma[idx - 1usize] }
    if sel == 7usize { ret f.scale[idx - 1usize] }
    if sel == 8usize {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f.post[i * f.k + idx - 1usize] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if sel == 9usize { ret f.ll[idx - 1usize] }
    ret f64(f.ll.len)
}

// multmixEM: [sel, idx, seed, k, n, p, nl, nt, y(n p, row-major), lambda(nl), theta(nt)]
fn answer_mm(a: *mem.Arena, x: []const f64) -> f64 {
    let sel = usize(x[0usize])
    let idx = usize(x[1usize])
    var g: rg.Rng = zero
    rg.seed(&g, i64(x[2usize]))
    let k = usize(x[3usize])
    let n = usize(x[4usize])
    let p = usize(x[5usize])
    let nl = usize(x[6usize])
    let nt = usize(x[7usize])
    let y = x[8usize..8usize + n * p]
    let lam = x[8usize + n * p..8usize + n * p + nl]
    let th = x[8usize + n * p + nl..8usize + n * p + nl + nt]
    let (f, e) = mm.mult_mix_em(a, &g, y, n, p, lam, th, k, 10000usize, 1.0e-8f64)
    if e != ok { os.exit(8) }
    if sel == 1usize { ret f.loglik }
    if sel == 2usize { ret f64(f.ll.len) }
    if sel == 3usize { ret f64(f.restarts) }
    if sel == 4usize { ret f.lambda[idx - 1usize] }
    if sel == 5usize { ret f.theta[idx - 1usize] }
    if sel == 6usize {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f.post[i * f.k + idx - 1usize] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if sel == 7usize { ret f.ll[idx - 1usize] }
    ret f64(f.ll.len)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let kind = c.name
    if str.eq(kind, "nm") { ret answer_nm(a, c.args) }
    if str.eq(kind, "mm") { ret answer_mm(a, c.args) }
    os.exit(4)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mixtools.json")
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
