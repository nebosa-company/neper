// e.algo.stat.micefull against mice 3.19 after set.seed over numeric and factor columns: polyreg, polr, cart, logreg with factor predictors, passive
// imputation, permuted and partial visit sequences and post-processing bounds.
// tests/oracle/micefull.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R micefull`; the layout is at the top of
// scripts/r_oracle/groups/micefull.R.

use e.algo.stat.micefull as mf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// the oracle's weighted sum of the imputed values; a negative answer is a sampler error
fn imputed_sum(a: *mem.Arena, z: []const f64) -> f64 {
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[2usize])
    let (imp, e1) = mem.alloc[f64](a, n * p * m + 4usize)
    if e1 != ok { ret 0.0f64 - 1000.0f64 }
    let empty: []f64 = zero
    let (tot, at, me) = mf.mice_run_flat(a, z, imp, empty)
    let _ = at
    if me != ok { ret 0.0f64 - 1001.0f64 }
    var s = 0.0f64
    var q = 0usize
    while q < tot {
        s += f64(q + 1usize) * imp[q]
        q += 1usize
    }
    ret s
}

fn report(a: *mem.Arena, c: *const oracle.Case, at: usize, got: f64) {
    let (b0, be) = str.builder(a, 200usize)
    if be != ok { os.exit(4) }
    var b = b0
    let _ = str.push(&b, "case ")
    let _ = str.push_f64(&b, f64(at))
    let _ = str.push(&b, " n=")
    let _ = str.push_f64(&b, c.args[0usize])
    let _ = str.push(&b, " p=")
    let _ = str.push_f64(&b, c.args[1usize])
    let _ = str.push(&b, " got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, " want ")
    let _ = str.push_f64(&b, c.want)
    let _ = str.push(&b, "\n")
    let _ = io.print(str.done(&b))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/micefull.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        var got = 0.0f64 / 0.0f64
        if str.eq(c.name, "mice_full") { got = imputed_sum(a, c.args) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize { report(a, c, at, got) }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
