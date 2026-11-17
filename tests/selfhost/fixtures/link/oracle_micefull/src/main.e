// e.algo.stat.micefull against mice 3.19 after set.seed over numeric and factor columns: polyreg, polr, cart, logreg with factor predictors, passive
// imputation, permuted and partial visit sequences, post-processing bounds and Rubin's pooling of lm fits over the completed data.
// tests/oracle/micefull.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R micefull`; the layout is at the top of
// scripts/r_oracle/groups/micefull.R.

use e.algo.stat.micefull as mf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// the oracle's weighted sum of the imputed values
fn imputed_sum(a: *mem.Arena, z: []const f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[2usize])
    let maxit = usize(z[3usize])
    let seed = i64(z[4usize])
    var at = 5usize
    let data = z[at..at + n * p]
    at += n * p
    let (kind, e1) = mem.alloc[usize](a, p)
    let (meth, e2) = mem.alloc[usize](a, p)
    let (lo, e3) = mem.alloc[f64](a, p)
    let (hi, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var j = 0usize
    while j < p {
        kind[j] = usize(z[at + j])
        let mc = z[at + p + j]
        if mc < 0.0f64 { meth[j] = 15usize } else { meth[j] = usize(mc) }
        j += 1usize
    }
    at += 2usize * p
    let pred = z[at..at + p * p]
    at += p * p
    let nv = usize(z[at])
    at += 1usize
    let (visit, e5) = mem.alloc[usize](a, nv + 1usize)
    if e5 != ok { ret nan }
    var h = 0usize
    while h < nv {
        visit[h] = usize(z[at + h])
        h += 1usize
    }
    at += nv
    j = 0usize
    while j < p {
        lo[j] = z[at + 2usize * j]
        hi[j] = z[at + 2usize * j + 1usize]
        j += 1usize
    }
    at += 2usize * p
    let pas = z[at..at + 3usize * p]
    let (imp, e6) = mem.alloc[f64](a, n * p * m + 4usize)
    if e6 != ok { ret nan }
    let empty: []f64 = zero
    let (tot, me) = mf.mice_run(a, data, n, p, m, maxit, kind, meth, pred, lo, hi, pas, visit[0usize..nv], seed, imp, empty)
    if me == mf.Collinear { ret 0.0f64 - 1001.0f64 }
    if me == mf.NoImpute { ret 0.0f64 - 1002.0f64 }
    if me == mf.Unsupported { ret 0.0f64 - 1003.0f64 }
    if me != ok { ret 0.0f64 - 1099.0f64 }
    var s = 0.0f64
    var q = 0usize
    while q < tot {
        s += f64(q + 1usize) * imp[q]
        q += 1usize
    }
    ret s
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
            if failures <= 500usize {
                let (b0, be) = str.builder(a, 200usize)
                if be != ok { os.exit(4) }
                var b = b0
                let _ = str.push(&b, "case ")
                let _ = str.push_f64(&b, f64(at))
                let _ = str.push(&b, " n=")
                let _ = str.push_f64(&b, c.args[0usize])
                let _ = str.push(&b, " p=")
                let _ = str.push_f64(&b, c.args[1usize])
                let _ = str.push(&b, " meth ")
                var jj = 0usize
                while jj < usize(c.args[1usize]) {
                    let _ = str.push_f64(&b, c.args[5usize + usize(c.args[0usize] * c.args[1usize]) + usize(c.args[1usize]) + jj])
                    let _ = str.push(&b, ",")
                    jj += 1usize
                }
                let _ = str.push(&b, " got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, " want ")
                let _ = str.push_f64(&b, c.want)
                let _ = str.push(&b, "\n")
                let _ = io.print(str.done(&b))
            }
        }
        at += 1usize
    }
    if failures > 0usize {
        let (b0, be) = str.builder(a, 80usize)
        if be != ok { os.exit(4) }
        var b = b0
        let _ = str.push(&b, "failures ")
        let _ = str.push_f64(&b, f64(failures))
        let _ = str.push(&b, " of ")
        let _ = str.push_f64(&b, f64(golden.cases.len))
        let _ = str.push(&b, "\n")
        let _ = io.print(str.done(&b))
        os.exit(1)
    }
    ret ok
}
