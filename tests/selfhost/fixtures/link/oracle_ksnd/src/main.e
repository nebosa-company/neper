// e.algo.stat.ksnd against ks in one to four dimensions. tests/oracle/ksnd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ksnd`; the layouts are at the top of scripts/r_oracle/groups/ksnd.R.

use e.algo.stat.ksnd as ks
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    let d = usize(x[0usize])
    let n = usize(x[1usize])
    if str.eq(nm, "hns") {
        var o: [16]f64 = zero
        ks.hns(x[4usize..4usize + n * d], n, d, usize(x[2usize]), o[0usize..16usize])
        ret o[usize(x[3usize])]
    }
    if str.eq(nm, "kdeat") {
        var hinv: [16]f64 = zero
        let det = ks.inv_det(x[2usize..2usize + d * d], d, hinv[0usize..16usize])
        let s = 2usize + d * d + d
        ret ks.kde_at(x[s..s + n * d], n, d, hinv[0usize..16usize], ks.norm_const(det, d), x[2usize + d * d..s])
    }
    let binned = x[2usize] != 0.0f64
    let m = usize(x[3usize])
    let h = x[4usize..4usize + d * d]
    var s = 4usize + d * d + 1usize
    if str.eq(nm, "ksupp") {
        s = s + 1usize
        var o: [5]f64 = zero
        if ks.kde_supp(a, x[s..s + n * d], n, d, h, m, binned, x[s - 2usize], o[0usize..5usize]) != ok { os.exit(7) }
        ret o[usize(x[s - 1usize])]
    }
    let xs = x[s..s + n * d]
    if str.eq(nm, "kdecont") { ret ks.kde_contour(a, xs, n, d, h, m, binned, x[s - 1usize]) }
    var total = 1usize
    var j = 0usize
    while j < d {
        total = total * m
        j += 1usize
    }
    let (gp, e1) = mem.alloc[f64](a, d * m)
    let (g, e2) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok { os.exit(5) }
    if binned {
        if ks.kde_binned(a, xs, n, d, h, m, gp, g) != ok { os.exit(6) }
    } else {
        ks.kde_grid(a, xs, n, d, h, m, gp, g)
    }
    ret g[usize(x[s - 1usize])]
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, "(")
    var at = 0usize
    while at < c.args.len && at < 6usize {
        if at > 0usize { let _ = str.push(&b, ", ") }
        let _ = str.push_f64(&b, c.args[at])
        at += 1usize
    }
    let _ = str.push(&b, "..): got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ksnd.json")
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
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
