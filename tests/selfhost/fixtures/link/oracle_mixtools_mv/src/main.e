// e.algo.stat.mixtools_mv (mvnormalmixEM) against mixtools. tests/oracle/mixtools_mv.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mixtools_mv`; the argument layout is at the top of scripts/r_oracle/groups/mixtools_mv.R.

use e.algo.rand.r as rg
use e.algo.stat.mixtools_mv as mv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// mvnormalmixEM: [sel, idx, seed, k, arbmean, arbvar, n, p, nl, nmu, nsg, x(n p), lambda(nl), mu(nmu), sigma(nsg)]
fn answer_mv(a: *mem.Arena, x: []const f64) -> f64 {
    let sel = usize(x[0usize])
    let idx = usize(x[1usize])
    var g: rg.Rng = zero
    rg.seed(&g, i64(x[2usize]))
    let k = usize(x[3usize])
    let n = usize(x[6usize])
    let p = usize(x[7usize])
    let nl = usize(x[8usize])
    let nmu = usize(x[9usize])
    let nsg = usize(x[10usize])
    let at = 11usize
    let data = x[at..at + n * p]
    let lam = x[at + n * p..at + n * p + nl]
    let mu = x[at + n * p + nl..at + n * p + nl + nmu]
    let sg = x[at + n * p + nl + nmu..at + n * p + nl + nmu + nsg]
    let (f, e) = mv.mvnormal_mix_em(a, &g, data, n, p, lam, mu, sg, k, x[4usize] != 0.0f64, x[5usize] != 0.0f64, 1.0e-8f64, 1000usize)
    if e != ok { os.exit(8) }
    if sel == 1usize { ret f.loglik }
    if sel == 2usize { ret f64(f.iter) }
    if sel == 3usize { ret f64(f.restarts) }
    if sel == 4usize { ret f.lambda[idx - 1usize] }
    if sel == 5usize {
        if x[4usize] != 0.0f64 { ret f.mu[idx - 1usize] }
        ret f.mu[idx - 1usize]
    }
    if sel == 6usize { ret f.sigma[idx - 1usize] }
    if sel == 7usize {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f.post[i * k + idx - 1usize] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if sel == 8usize { ret f.ll[idx - 1usize] }
    ret f64(f.ll.len)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let kind = c.name
    if str.eq(kind, "mv") { ret answer_mv(a, c.args) }
    os.exit(4)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mixtools_mv.json")
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
