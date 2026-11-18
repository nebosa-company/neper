// e.algo.stat.betareg against betareg. tests/oracle/betareg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R betareg`; the layout is at the top of scripts/r_oracle/groups/betareg.R.
// Consecutive cases of one dataset share their fit.

use e.algo.stat.betareg as br
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn same(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 3usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn value(f: *const br.Fit, which: usize) -> f64 {
    if which < 10usize { ret f.par[which] }
    if which == 20usize { ret f.phi }
    ret f.ll
}

fn fitl_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let link = usize(x[2usize])
    let which = usize(x[3usize])
    let (f, e) = br.fit_link(a, x[4usize + n..4usize + n + n * p], x[4usize..4usize + n], n, p, link)
    if e != ok { os.exit(6) }
    if which >= 70usize {
        // the model without the last mean column
        let (dr, de) = mem.alloc[f64](a, n * (p - 1usize))
        if de != ok { os.exit(9) }
        var i = 0usize
        while i < n {
            var j = 0usize
            while j + 1usize < p {
                dr[i * (p - 1usize) + j] = x[4usize + n + i * p + j]
                j += 1usize
            }
            i += 1usize
        }
        let (f0, e0) = br.fit_link(a, dr, x[4usize..4usize + n], n, p - 1usize, link)
        if e0 != ok { os.exit(10) }
        var lr: [3]f64 = zero
        br.lrtest(f.ll, p + 1usize, f0.ll, p, lr[0usize..3usize])
        ret lr[which - 70usize]
    }
    if which < 10usize { ret f.par[which] }
    if which == 20usize { ret f.phi }
    if which == 30usize { ret f.ll }
    let (se, se_e) = mem.alloc[f64](a, p + 1usize)
    if se_e != ok { os.exit(7) }
    if !br.fit_se(a, x[4usize + n..4usize + n + n * p], x[4usize..4usize + n], n, p, link, &f, se) { os.exit(8) }
    if which == 60usize { ret se[p] }
    ret se[which - 40usize]
}

// the fit of consecutive cases on the same data is reused
fn same_bres(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if i != 3usize && i != 4usize && a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

type BCache = struct { fit: br.Fit, prev: []const f64, set: bool }

fn bres_answer(a: *mem.Arena, c: *const oracle.Case, bc: *BCache) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let link = usize(x[2usize])
    if !bc.set || !same_bres(bc.prev, x) {
        let (f, e) = br.fit_link(a, x[5usize + n..5usize + n + n * p], x[5usize..5usize + n], n, p, link)
        if e != ok { os.exit(9) }
        bc.fit = f
        bc.prev = x
        bc.set = true
    }
    ret br.fit_value(x[5usize + n..5usize + n + n * p], x[5usize..5usize + n], p, link, &bc.fit, usize(x[4usize]), usize(x[3usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/betareg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var have = false
    var bcache: BCache = zero
    var cur: br.Fit = zero
    var prev: []const f64 = golden.cases[0usize].args
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if str.eq(c.name, "bres") {
            let got3 = bres_answer(a, c, &bcache)
            if !oracle.agrees(got3, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, got3))
                    let _ = io.print("\n")
                }
            }
            at += 1usize
            continue
        }
        if str.eq(c.name, "fitl") {
            let got2 = fitl_answer(a, c)
            if !oracle.agrees(got2, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, got2))
                    let _ = io.print("\n")
                }
            }
            at += 1usize
            continue
        }
        if !have || !same(prev, x) {
            let n = usize(x[0usize])
            let p = usize(x[1usize])
            let (f, e) = br.fit(a, x[3usize + n..3usize + n + n * p], x[3usize..3usize + n], n, p)
            if e != ok { os.exit(5) }
            cur = f
            prev = x
            have = true
        }
        let got = value(&cur, usize(x[2usize]))
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
