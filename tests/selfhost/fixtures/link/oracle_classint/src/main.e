// e.algo.stat.classint against classInt's classIntervals and findCols: equal, pretty, sd, quantile
// (types 1 to 9), jenks, fisher, headtails, maximum and box. tests/oracle/classint.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R classint`; the layouts are at the top of
// scripts/r_oracle/groups/classint.R. A vector answer is one case per element plus a "len:" case.

use e.algo.rand.r as rr
use e.algo.stat.classint as ci
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn breaks(a: *mem.Arena, x: []const f64) -> []f64 {
    let style = u8(x[0usize])
    let n = usize(x[1usize])
    let extra = x[2usize]
    let len = usize(x[3usize])
    let data = x[4usize..4usize + len]
    var out: []f64 = zero
    var e = ok
    if style == 0u8 {
        let (r, re) = ci.equal(a, data, n)
        out = r
        e = re
    }
    if style == 1u8 {
        let (r, re) = ci.pretty_breaks(a, data, n)
        out = r
        e = re
    }
    if style == 2u8 {
        let (r, re) = ci.sd_breaks(a, data, n)
        out = r
        e = re
    }
    if style == 3u8 {
        let (r, re) = ci.quantile_breaks(a, data, n, u8(extra))
        out = r
        e = re
    }
    if style == 4u8 {
        let (r, re) = ci.jenks(a, data, n)
        out = r
        e = re
    }
    if style == 5u8 {
        let (r, re) = ci.fisher(a, data, n)
        out = r
        e = re
    }
    if style == 6u8 {
        let (r, re) = ci.headtails(a, data, extra)
        out = r
        e = re
    }
    if style == 7u8 {
        let (r, re) = ci.maximum(a, data, n)
        out = r
        e = re
    }
    if style == 8u8 {
        var t = n
        var legacy = false
        if t >= 100usize {
            t -= 100usize
            legacy = true
        }
        let (r, re) = ci.box(a, data, extra, u8(t), legacy)
        out = r
        e = re
    }
    if style == 9u8 {
        let (r, re) = ci.dpih_breaks(a, data)
        out = r
        e = re
    }
    if style == 10u8 {
        let (r, re) = ci.hclust_breaks(a, data, n)
        out = r
        e = re
    }
    if style == 11u8 {
        var g: rr.Rng = zero
        rr.seed(&g, i64(extra))
        let (r, re) = ci.kmeans_breaks(a, &g, data, n)
        out = r
        e = re
    }
    if style == 12u8 {
        var g: rr.Rng = zero
        rr.seed(&g, i64(extra))
        let (r, re) = ci.bclust_breaks(a, &g, data, n)
        out = r
        e = re
    }
    if e != ok { os.exit(7) }
    ret out
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    var name = c.name
    if str.eq(name, "cols") {
        let x = c.args
        let nb = usize(x[2usize])
        ret f64(ci.find_cols(x[3usize..3usize + nb], x[1usize], x[0usize] != 0.0f64))
    }
    var wants_len = false
    if name.len > 4usize && name[0usize] == 108u8 && name[3usize] == 58u8 {
        name = name[4usize..name.len]
        wants_len = true
    }
    let r = breaks(a, c.args)
    if wants_len { ret f64(r.len) }
    let i = usize(c.args[c.args.len - 1usize])
    if i < r.len { ret r[i] }
    ret 0.0f64 / 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/classint.json")
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
