// e.algo.stat.partykitpkg.cforest against partykit cforest under set.seed, with factor predictors (kids drawn for levels a node never saw). tests/oracle/partykitforestf.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R partykitforestf`; the argument layout is at the top of scripts/r_oracle/groups/partykitforestf.R.

use e.algo.stat.partykitpkg as pk
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let sel = usize(z[0usize])
    let seed = i64(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let yl = usize(z[4usize])
    let ntree = usize(z[5usize])
    let mtry = usize(z[6usize])
    let minsplit = usize(z[7usize])
    let minbucket = usize(z[8usize])
    let nn = usize(z[9usize])
    let (nl, e1) = mem.alloc[usize](a, p)
    let (pred, e2) = mem.alloc[f64](a, nn)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < p {
        nl[j] = usize(z[10usize + j])
        j += 1usize
    }
    let x = z[10usize + p..10usize + p + n * p]
    let y = z[10usize + p + n * p..10usize + p + n * p + n]
    let xn = z[10usize + p + n * p + n..10usize + p + n * p + n + nn * p]
    let e3 = pk.cforest(a, x, n, p, nl, y, yl, ntree, mtry, minsplit, minbucket, 0.01f64, seed, xn, nn, pred)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    if sel == 3usize { ret pred[0usize] }
    if sel == 4usize { ret pred[nn - 1usize] }
    var s = 0.0f64
    j = 0usize
    while j < nn {
        if sel == 1usize { s += pred[j] }
        if sel == 2usize { s += f64(j + 1usize) * pred[j] }
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/partykitforestf.json")
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
