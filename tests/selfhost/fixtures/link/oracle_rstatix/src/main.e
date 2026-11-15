// e.algo.stat.rstatix against R's rstatix and base R: p.adjust, games_howell_test, dunn_test,
// pairwise.t.test, Welch's oneway.test, friedman.test, kruskal_effsize, cohens_d, eta_squared,
// is_outlier and mahalanobis. tests/oracle/rstatix.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rstatix`; the layout of a case's
// arguments is the header of scripts/r_oracle/groups/rstatix.R.

use e.algo.stat.rstatix as rs
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn sizes_of(a: *mem.Arena, x: []const f64, k: usize) -> []usize {
    let (s, e) = mem.alloc[usize](a, k)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < k {
        s[i] = usize(x[i])
        i += 1usize
    }
    ret s
}

fn total_of(s: []const usize) -> usize {
    var t = 0usize
    var i = 0usize
    while i < s.len {
        t += s[i]
        i += 1usize
    }
    ret t
}

fn copy_of(a: *mem.Arena, x: []const f64) -> []f64 {
    let (v, e) = mem.alloc[f64](a, x.len)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < x.len {
        v[i] = x[i]
        i += 1usize
    }
    ret v
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    if kind == 0usize {
        let n = usize(x[2usize])
        let p = copy_of(a, x[3usize..3usize + n])
        if rs.p_adjust(a, u8(x[1usize]), p) != ok { os.exit(6) }
        ret p[usize(x[3usize + n])]
    }
    if kind == 5usize {
        let blocks = usize(x[1usize])
        let k = usize(x[2usize])
        let (t, e) = rs.friedman(a, x[3usize..3usize + blocks * k], blocks, k)
        if e != ok { os.exit(6) }
        let col = usize(x[3usize + blocks * k])
        if col == 0usize { ret t.statistic }
        if col == 1usize { ret t.df1 }
        ret t.p
    }
    if kind == 8usize {
        let mode = u8(x[1usize])
        let n1 = usize(x[5usize])
        let n2 = usize(x[6usize])
        let (d, e) = rs.cohens_d(a, mode, x[7usize..7usize + n1], x[7usize + n1..7usize + n1 + n2], x[4usize], x[2usize] != 0.0f64, x[3usize] != 0.0f64)
        if e != ok { os.exit(6) }
        ret d
    }
    if kind == 10usize {
        let n = usize(x[2usize])
        let (flags, fe) = mem.alloc[u8](a, n)
        if fe != ok { os.exit(5) }
        if rs.outliers(a, x[3usize..3usize + n], x[1usize], flags) != ok { os.exit(6) }
        ret f64(flags[usize(x[3usize + n])])
    }
    if kind == 11usize {
        let n = usize(x[1usize])
        let p = usize(x[2usize])
        let (d, de) = mem.alloc[f64](a, n)
        if de != ok { os.exit(5) }
        let (thr, e) = rs.mahalanobis(a, x[3usize..3usize + n * p], n, p, d)
        if e != ok { os.exit(6) }
        let i = usize(x[3usize + n * p])
        if usize(x[4usize + n * p]) == 0usize { ret d[i] }
        if d[i] > thr { ret 1.0f64 }
        ret 0.0f64
    }
    // The rest take k, the sizes and the values after a prefix of 0 to 3 numbers.
    var at = 1usize
    var method = 0usize
    var mode = 0usize
    if kind == 2usize {
        method = usize(x[1usize])
        at = 2usize
    }
    if kind == 7usize {
        method = usize(x[1usize])
        at = 2usize
    }
    if kind == 12usize {
        mode = usize(x[1usize])
        method = usize(x[2usize])
        at = 3usize
    }
    let k = usize(x[at])
    let sizes = sizes_of(a, x[at + 1usize..at + 1usize + k], k)
    let total = total_of(sizes)
    let vstart = at + 1usize + k
    let values = x[vstart..vstart + total]
    let tail = vstart + total
    if kind == 9usize {
        let (e2, e) = rs.eta_squared(values, sizes)
        if e != ok { os.exit(6) }
        ret e2
    }
    if kind == 7usize {
        let (e2, e) = rs.kruskal_effsize(a, values, sizes, method == 1usize)
        if e != ok { os.exit(6) }
        ret e2
    }
    if kind == 4usize {
        let (t, e) = rs.welch_anova(values, sizes)
        if e != ok { os.exit(6) }
        let col = usize(x[tail])
        if col == 0usize { ret t.statistic }
        if col == 1usize { ret t.df1 }
        if col == 2usize { ret t.df2 }
        ret t.p
    }
    if kind == 1usize {
        let (rows, e) = rs.games_howell(a, values, sizes, x[tail])
        if e != ok { os.exit(6) }
        let g1 = usize(x[tail + 1usize]) - 1usize
        let g2 = usize(x[tail + 2usize]) - 1usize
        let col = usize(x[tail + 3usize])
        var r = 0usize
        while r < rows.len {
            if rows[r].first == g1 && rows[r].second == g2 {
                if col == 0usize { ret rows[r].estimate }
                if col == 1usize { ret rows[r].conf_low }
                if col == 2usize { ret rows[r].conf_high }
                if col == 3usize { ret rows[r].se }
                if col == 4usize { ret rows[r].statistic }
                if col == 5usize { ret rows[r].df }
                ret rows[r].p_adj
            }
            r += 1usize
        }
        os.exit(7)
        ret 0.0f64
    }
    if kind == 2usize {
        let (rows, e) = rs.dunn(a, values, sizes, u8(method))
        if e != ok { os.exit(6) }
        let g1 = usize(x[tail]) - 1usize
        let g2 = usize(x[tail + 1usize]) - 1usize
        let col = usize(x[tail + 2usize])
        var r = 0usize
        while r < rows.len {
            if rows[r].first == g1 && rows[r].second == g2 {
                if col == 0usize { ret rows[r].estimate }
                if col == 1usize { ret rows[r].statistic }
                if col == 2usize { ret rows[r].p }
                ret rows[r].p_adj
            }
            r += 1usize
        }
        os.exit(7)
        ret 0.0f64
    }
    let (rows, e) = rs.pairwise_t(a, values, sizes, u8(mode), u8(method))
    if e != ok { os.exit(6) }
    let g1 = usize(x[tail]) - 1usize
    let g2 = usize(x[tail + 1usize]) - 1usize
    var r = 0usize
    while r < rows.len {
        if rows[r].first == g1 && rows[r].second == g2 {
            if usize(x[tail + 2usize]) == 0usize { ret rows[r].p }
            ret rows[r].p_adj
        }
        r += 1usize
    }
    os.exit(7)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rstatix.json")
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
