// e.algo.stat.mixtools_reg (regmixEM) against mixtools. tests/oracle/mixtools_reg.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mixtools_reg`;
// the argument layout is at the top of scripts/r_oracle/groups/mixtools_reg.R.

use e.algo.rand.r as rg
use e.algo.stat.mixtools_reg as rgm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
// regmixEM: [sel, idx, seed, k, arbmean, arbvar, addint, n, q, nl, nb, ns, y(n), x(n q), lambda(nl), beta(nb), sigma(ns)]
fn answer_rg(a: *mem.Arena, x: []const f64) -> f64 {
    let sel = usize(x[0usize])
    let idx = usize(x[1usize])
    var g: rg.Rng = zero
    rg.seed(&g, i64(x[2usize]))
    let k = usize(x[3usize])
    let n = usize(x[7usize])
    let q = usize(x[8usize])
    let nl = usize(x[9usize])
    let nb = usize(x[10usize])
    let ns = usize(x[11usize])
    let at = 12usize
    let y = x[at..at + n]
    let xp = x[at + n..at + n + n * q]
    let lam = x[at + n + n * q..at + n + n * q + nl]
    let be = x[at + n + n * q + nl..at + n + n * q + nl + nb]
    let sg = x[at + n + n * q + nl + nb..at + n + n * q + nl + nb + ns]
    let (f, e) = rgm.reg_mix_em(a, &g, y, xp, q, x[6usize] != 0.0f64, lam, be, sg, k, x[4usize] != 0.0f64, x[5usize] != 0.0f64, 1.0e-8f64, 1000usize)
    if e != ok { os.exit(8) }
    if sel == 1usize { ret f.loglik }
    if sel == 2usize { ret f64(f.iter) }
    if sel == 3usize { ret f64(f.restarts) }
    if sel == 4usize { ret f.lambda[idx - 1usize] }
    if sel == 5usize { ret f.beta[idx - 1usize] }
    if sel == 6usize { ret f.sigma[idx - 1usize] }
    if sel == 7usize { ret f.scale[idx - 1usize] }
    if sel == 8usize {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f.post[i * k + idx - 1usize] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if sel == 9usize { ret f.ll[idx - 1usize] }
    ret f64(f.ll.len)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let kind = c.name
    if str.eq(kind, "rg") { ret answer_rg(a, c.args) }
    os.exit(4)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mixtools_reg.json")
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
