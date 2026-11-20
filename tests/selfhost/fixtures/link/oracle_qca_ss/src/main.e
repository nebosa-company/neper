// e.algo.stat.qcass against QCA::superSubset. tests/oracle/qca_ss.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qca_ss`; the layout is at the top of scripts/r_oracle/groups/qca_ss.R.

use e.algo.stat.qcass as ss
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let what = usize(x[0usize])
    let index = usize(x[1usize])
    let rel = usize(x[2usize])
    let n = usize(x[7usize])
    let k = usize(x[8usize])
    let (fz, e1) = mem.alloc[u8](a, k)
    if e1 != ok { os.exit(4) }
    var i = 0usize
    while i < k {
        fz[i] = u8(x[9usize + i])
        i += 1usize
    }
    let data = x[9usize + k..9usize + k + n * k]
    let y = x[9usize + k + n * k..9usize + k + n * k + n]
    let eps = 1.0f64 / 67108864.0f64
    var incl = x[3usize] - eps
    var cov = x[4usize]
    if cov > 0.0f64 { cov = cov - eps }
    if rel >= 2usize { cov = incl }
    let nec = rel == 0usize || rel == 3usize
    var f: ss.Found = zero
    let e2 = ss.super_subset(a, data, n, k, fz, y, nec, incl, cov, usize(x[5usize]), &f)
    if e2 != ok { os.exit(5) }
    // the kept expressions, conjunctions first and by code
    var keep: [800]usize = zero
    var nk = 0usize
    i = 0usize
    while i < f.count {
        if f.pri[i] >= x[6usize] {
            keep[nk] = i
            nk += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < nk {
        var j = i
        while j > 0usize && before(&f, keep[j], keep[j - 1usize]) {
            let s = keep[j]
            keep[j] = keep[j - 1usize]
            keep[j - 1usize] = s
            j -= 1usize
        }
        i += 1usize
    }
    if what == 0usize { ret f64(nk) }
    let at = keep[index]
    if what == 1usize { ret f64(f.kind[at]) }
    if what == 2usize { ret f64(f.code[at]) }
    if what == 3usize { ret f.incl[at] }
    if what == 4usize { ret f.pri[at] }
    ret f.cov[at]
}

fn before(f: *const ss.Found, p: usize, q: usize) -> bool {
    if f.kind[p] != f.kind[q] { ret f.kind[p] < f.kind[q] }
    ret f.code[p] < f.code[q]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qca_ss.json")
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
