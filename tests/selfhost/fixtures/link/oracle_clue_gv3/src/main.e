// e.algo.stat.cluegv3 against clue cl_consensus(method = "GV3"). tests/oracle/clue_gv3.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clue_gv3`; the layout is at the top of scripts/r_oracle/groups/clue_gv3.R.

use e.algo.rand.r as rr
use e.algo.stat.cluecons as cc
use e.algo.stat.cluegv3 as gv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let bn = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let nruns = usize(z[3usize])
    let seed = i64(z[4usize])
    let (out, e0) = mem.alloc[f64](a, n * k)
    if e0 != ok { os.exit(5) }
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    var stage = 0usize
    if str.eq(c.name, "gv3m0") { stage = 1usize }
    if str.eq(c.name, "gv3cg") { stage = 2usize }
    if str.eq(c.name, "gv3x") { stage = 3usize }
    if gv.consensus_gv3(a, &g, z[5usize + bn..5usize + bn + bn * n * k], z[5usize..5usize + bn], bn, n, k, nruns, stage, out) != ok { ret 0.0f64 / 0.0f64 }
    if stage > 0usize {
        var t = 0.0f64
        var q = 0usize
        while q < n * k {
            t += out[q] * f64(q + 1usize)
            q += 1usize
        }
        ret t
    }
    cc.tidy(out, n, k)
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            s += out[i * k + j] * f64(10usize * (i + 1usize) + j + 1usize)
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clue_gv3.json")
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
