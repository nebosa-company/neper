// e.algo.stat.hclust against R's hclust. tests/oracle/hclust.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hclust`; the layout is at the top of scripts/r_oracle/groups/hclust.R.

use e.algo.stat.hclust as hc
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn dmat(a: *mem.Arena, x: []const f64, n: usize, at: usize) -> []f64 {
    let (d, e) = mem.alloc[f64](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[at + 2usize * i] - x[at + 2usize * j]
            let dy = x[at + 1usize + 2usize * i] - x[at + 1usize + 2usize * j]
            d[i * n + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    ret d
}

fn pair(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[2usize])
    let k = usize(x[3usize])
    let d = dmat(a, x, n, 4usize)
    let (t1, e1) = hc.hclust(a, d, n, usize(x[0usize]))
    if e1 != ok { os.exit(6) }
    let (t2, e2) = hc.hclust(a, d, n, usize(x[1usize]))
    if e2 != ok { os.exit(7) }
    if str.eq(c.name, "corcoph") { ret hc.cor_cophenetic(a, &t1, &t2, n) }
    let (l1, e3) = mem.alloc[usize](a, n)
    if e3 != ok { os.exit(8) }
    let (l2, e4) = mem.alloc[usize](a, n)
    if e4 != ok { os.exit(9) }
    if hc.cutree(a, &t1, n, k, l1) != ok { os.exit(10) }
    if hc.cutree(a, &t2, n, k, l2) != ok { os.exit(11) }
    let (fm, ef, vf, e5) = hc.fm_index(a, l1, l2)
    if e5 != ok { os.exit(12) }
    if str.eq(c.name, "fm") { ret fm }
    if str.eq(c.name, "fmE") { ret ef }
    ret vf
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "fm") || str.eq(c.name, "fmE") || str.eq(c.name, "fmV") || str.eq(c.name, "corcoph") { ret pair(a, c) }
    let x = c.args
    let method = usize(x[0usize])
    let n = usize(x[1usize])
    let k = usize(x[2usize])
    let (d, e) = mem.alloc[f64](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[3usize + 2usize * i] - x[3usize + 2usize * j]
            let dy = x[4usize + 2usize * i] - x[4usize + 2usize * j]
            var v = math.sqrt[f64](dx * dx + dy * dy)
            if method == 6usize || method == 7usize { v = dx * dx + dy * dy }
            d[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
    let (t, e2) = hc.hclust(a, d, n, method)
    if e2 != ok { os.exit(6) }
    let kind = c.name
    var s = 0.0f64
    if str.eq(kind, "ac") { ret hc.agnes_ac(a, &t, n) }
    if str.eq(kind, "agh") {
        i = 0usize
        while i < n - 1usize {
            s += t.height[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "height") {
        i = 0usize
        while i < n - 1usize {
            s += t.height[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "merge") {
        i = 0usize
        while i < n - 1usize {
            s += f64(t.merge_a[i]) * f64(2usize * i + 1usize) + f64(t.merge_b[i]) * f64(2usize * i + 2usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "order") {
        i = 0usize
        while i < n {
            s += f64(t.order[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(kind, "cut") {
        let (lab, e3) = mem.alloc[usize](a, n)
        if e3 != ok { os.exit(7) }
        let e4 = hc.cutree(a, &t, n, k, lab)
        if e4 != ok { os.exit(8) }
        i = 0usize
        while i < n {
            s += f64(lab[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    // coph: pairs in the column-major upper triangle order of R's lower-triangle dist: (2,1), (3,1), ..., then (3,2), ...
    var pos = 1usize
    var col = 0usize
    while col < n {
        var row = col + 1usize
        while row < n {
            s += hc.cophenetic(a, &t, n, row, col) * f64(pos)
            pos += 1usize
            row += 1usize
        }
        col += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hclust.json")
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
