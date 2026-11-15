// e.algo.stat.matrix against R's matrixStats: row and column kernels over column-major matrices
// with NA, Inf, ties and zero-width cases, with row and column selections, plus weightedMean,
// weightedMedian and binCounts. tests/oracle/matrixstats.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R matrixstats`; the case layouts are
// written at the top of scripts/r_oracle/groups/matrixstats.R.

use e.algo.stat.matrix as mx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn selection(a: *mem.Arena, x: []const f64, at: usize) -> []usize {
    let n = usize(x[at])
    let (out, e) = mem.alloc[usize](a, n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        out[i] = usize(x[at + 1usize + i]) - 1usize
        i += 1usize
    }
    ret out
}

fn pick(r: []const f64, c: *const oracle.Case, wants_len: bool) -> f64 {
    if wants_len { ret f64(r.len) }
    let i = usize(c.args[c.args.len - 1usize])
    if i < r.len { ret r[i] }
    ret 0.0f64 / 0.0f64
}

fn probs_of(a: *mem.Arena, set: usize) -> []const f64 {
    let (p, e) = mem.alloc[f64](a, 5usize)
    if e != ok { os.exit(5) }
    if set == 0usize {
        p[0usize] = 0.0f64
        p[1usize] = 0.25f64
        p[2usize] = 0.5f64
        p[3usize] = 0.75f64
        p[4usize] = 1.0f64
        ret p[0usize..5usize]
    }
    if set == 1usize {
        p[0usize] = 0.1f64
        p[1usize] = 0.9f64
        ret p[0usize..2usize]
    }
    p[0usize] = 0.33f64
    ret p[0usize..1usize]
}

fn kernel(a: *mem.Arena, c: *const oracle.Case, wants_len: bool) -> f64 {
    let x = c.args
    var h = 0usize
    if wants_len { h = 1usize }
    let op = usize(x[h])
    let by_row = x[h + 1usize] != 0.0f64
    let na = x[h + 2usize] != 0.0f64
    let p1 = usize(x[h + 3usize])
    let p2 = usize(x[h + 4usize])
    let nrow = usize(x[h + 5usize])
    let ncol = usize(x[h + 6usize])
    let full = mx.Mat { data: x[h + 7usize..h + 7usize + nrow * ncol], nrow: nrow, ncol: ncol }
    var at = h + 7usize + nrow * ncol
    let rows = selection(a, x, at)
    at += 1usize + rows.len
    let cols = selection(a, x, at)
    let (m, se) = mx.submatrix(a, full, rows, cols)
    if se != ok { os.exit(5) }
    var r: []f64 = zero
    var e: err = ok
    if op == 0usize {
        let (v, ve) = mx.sums(a, m, by_row, na)
        r = v
        e = ve
    }
    if op == 1usize {
        let (v, ve) = mx.means(a, m, by_row, na, true)
        r = v
        e = ve
    }
    if op == 2usize {
        let (v, ve) = mx.variances(a, m, by_row, na, true)
        r = v
        e = ve
    }
    if op == 3usize {
        let (v, ve) = mx.sds(a, m, by_row, na, true)
        r = v
        e = ve
    }
    if op == 4usize {
        let (v, ve) = mx.medians(a, m, by_row, na)
        r = v
        e = ve
    }
    if op == 5usize {
        let (v, ve) = mx.mads(a, m, by_row, na, 1.4826f64)
        r = v
        e = ve
    }
    if op == 6usize {
        let (v, ve) = mx.quantiles(a, m, by_row, na, probs_of(a, p1))
        r = v
        e = ve
    }
    if op == 7usize {
        let (v, ve) = mx.ranks(a, m, by_row, u8(p1))
        r = v
        e = ve
    }
    if op == 8usize {
        let (v, ve) = mx.cumsums(a, m, by_row)
        r = v
        e = ve
    }
    if op == 9usize {
        let (v, ve) = mx.diffs(a, m, by_row, p1, p2)
        r = v
        e = ve
    }
    if op == 10usize {
        let (v, ve) = mx.order_stats(a, m, by_row, p1)
        r = v
        e = ve
    }
    if op == 11usize {
        let (v, ve) = mx.ranges(a, m, by_row, na)
        r = v
        e = ve
    }
    if e != ok { os.exit(7) }
    ret pick(r, c, wants_len)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "len") { ret kernel(a, c, true) }
    if str.eq(c.name, "v") { ret kernel(a, c, false) }
    if str.eq(c.name, "wmean") {
        let n = usize(x[1usize])
        ret mx.weighted_mean(x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], x[0usize] != 0.0f64)
    }
    if str.eq(c.name, "wmedian") {
        let n = usize(x[2usize])
        ret mx.weighted_median(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[0usize] != 0.0f64, x[1usize] != 0.0f64)
    }
    let right = x[0usize] != 0.0f64
    let nx = usize(x[1usize])
    let nb = usize(x[2usize])
    let (counts, e) = mx.bin_counts(a, x[3usize..3usize + nx], x[3usize + nx..3usize + nx + nb], right)
    if e != ok { os.exit(7) }
    if str.eq(c.name, "binsk") { ret counts[usize(x[x.len - 1usize])] }
    var weighted = 0.0f64
    var i = 0usize
    while i < counts.len {
        weighted = weighted + counts[i] * f64(i + 1usize)
        i += 1usize
    }
    ret weighted
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/matrixstats.json")
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
            if failures <= 20usize {
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
