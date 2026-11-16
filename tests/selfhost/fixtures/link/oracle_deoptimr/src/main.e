// e.algo.stat.deoptim against DEoptimR::JDEoptim under set.seed. tests/oracle/deoptimr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R deoptimr`; the layout is at the top of
// scripts/r_oracle/groups/deoptimr.R.

use e.algo.rand.r as rr
use e.algo.stat.deoptim as de
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn obj(ctx: *u8, x: []const f64) -> f64 {
    let id = usize(*ctx)
    let n = x.len
    var s = 0.0f64
    var i = 0usize
    if id == 1usize {
        while i + 1usize < n {
            let t = x[i + 1usize] - x[i] * x[i]
            s += 100.0f64 * t * t + (1.0f64 - x[i]) * (1.0f64 - x[i])
            i += 1usize
        }
        ret s
    }
    if id == 2usize {
        while i < n {
            s += (x[i] * x[i] - 1.0f64) * (x[i] * x[i] - 1.0f64) + 0.3f64 * x[i]
            i += 1usize
        }
        ret s
    }
    while i < n {
        let t = x[i] - f64(i + 1usize) / 4.0f64
        s += t * t
        i += 1usize
    }
    ret s
}

fn cons(ctx: *u8, x: []const f64, out: []f64) {
    let id = usize(*ctx)
    if id == 3usize { out[0usize] = 1.0f64 - x[0usize] - x[1usize] }
    if id == 4usize { out[0usize] = x[0usize] + x[1usize] - 1.0f64 }
    if id == 5usize {
        out[0usize] = x[0usize] + x[1usize] - 1.0f64
        out[1usize] = 0.5f64 - x[0usize]
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let id = usize(x[0usize])
    let d = usize(x[2usize])
    let np = usize(x[3usize])
    let mi = usize(x[4usize])
    let lo = x[5usize..5usize + d]
    let hi = x[5usize + d..5usize + 2usize * d]
    let q = usize(x[5usize + 2usize * d])
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[1usize]))
    var ctx = u8(id)
    var m = 0usize
    var meq = 0usize
    if id == 3usize { m = 1usize }
    if id == 4usize {
        m = 1usize
        meq = 1usize
    }
    if id == 5usize {
        m = 2usize
        meq = 1usize
    }
    var prob = de.Prob[u8] { f: obj, cons: cons, ctx: &ctx, m: m, meq: meq, eps: 1.0e-5f64 }
    let (best, be) = mem.alloc[f64](a, d)
    if be != ok { ret 0.0f64 / 0.0f64 }
    let (r, e) = de.jdeoptim[u8](a, &g, &prob, lo, hi, np, 0.1f64, 1.0f64, 0.1f64, 0.1f64, 0.1f64, 0.001f64, 1.0e-15f64, mi, 1.0f64, false, best)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if q < d { ret best[q] }
    if q == d { ret r.value }
    if q == d + 1usize { ret f64(r.iter) }
    ret f64(r.convergence)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/deoptimr.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
