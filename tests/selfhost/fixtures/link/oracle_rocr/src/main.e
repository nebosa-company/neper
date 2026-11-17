// e.algo.stat.rocr against ROCR. tests/oracle/rocr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rocr`; the layout is at the top of scripts/r_oracle/groups/rocr.R.

use e.algo.stat.rocr as rc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let pred = x[2usize..2usize + n]
    let lab = x[2usize + n..2usize + 2usize * n]
    if kind == 99usize { ret rc.auc(a, pred, lab) }
    if kind == 90usize { ret rc.mxe(pred, lab) }
    if kind == 91usize { ret rc.rmse(pred, lab) }
    if str.eq(c.name, "calc") || str.eq(c.name, "cale") || str.eq(c.name, "calm") {
        let w = usize(x[2usize + 2usize * n])
        let (md, ce1) = mem.alloc[f64](a, n)
        let (er, ce2) = mem.alloc[f64](a, n)
        if ce1 != ok || ce2 != ok { ret 0.0f64 / 0.0f64 }
        let k = rc.calibration(a, pred, lab, w, md, er)
        if str.eq(c.name, "calc") { ret f64(k) }
        var cs = 0.0f64
        var ci = 0usize
        while ci < k {
            if str.eq(c.name, "cale") { cs += er[ci] * f64(ci + 1usize) } else { cs += md[ci] * f64(ci + 1usize) }
            ci += 1usize
        }
        ret cs
    }
    if str.eq(c.name, "pbec") || str.eq(c.name, "pbes") || str.eq(c.name, "pbev") {
        let (pc, pe1) = mem.alloc[f64](a, n + 2usize)
        let (pv, pe2) = mem.alloc[f64](a, n + 2usize)
        if pe1 != ok || pe2 != ok { ret 0.0f64 / 0.0f64 }
        let k = rc.prbe(a, pred, lab, pc, pv)
        if str.eq(c.name, "pbec") { ret f64(k) }
        var ps = 0.0f64
        var pi = 0usize
        while pi < k {
            if str.eq(c.name, "pbes") { ps += pc[pi] * f64(pi + 1usize) } else { ps += pv[pi] * f64(pi + 1usize) }
            pi += 1usize
        }
        ret ps
    }
    let m = rc.cutoff_count(a, pred)
    let (out, e) = mem.alloc[f64](a, m)
    if e != ok { os.exit(5) }
    let got = rc.measure(a, pred, lab, kind, out)
    if got != m { os.exit(6) }
    var s = 0.0f64
    var cnt = 0.0f64
    var i = 0usize
    while i < m {
        if out[i] == out[i] && out[i] - out[i] == 0.0f64 {
            s += out[i] * f64(i + 1usize)
            cnt += 1.0f64
        }
        i += 1usize
    }
    if str.eq(c.name, "cnt") { ret cnt }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rocr.json")
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
