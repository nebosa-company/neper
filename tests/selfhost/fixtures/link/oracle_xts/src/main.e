// e.algo.stat.xts against xts: endpoints, open/high/low/close and period.apply over them, align.time,
// periodicity, lag and diff. tests/oracle/xts.json comes from `R_ORACLE_LIB=<dir> Rscript
// scripts/r_oracle/generate.R xts`; the layouts are at the top of scripts/r_oracle/groups/xts.R.
// A vector answer is six cases: length, sum, position-weighted sum, first, last and NA count.

use e.algo.stat.xts as xts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn is(name: str, prefix: str) -> bool {
    if name.len < prefix.len { ret false }
    ret str.eq(name[0usize..prefix.len], prefix)
}

fn values(a: *mem.Arena, name: str, x: []const f64) -> []f64 {
    var out: []f64 = zero
    var e = ok
    if str.eq(name, "stat:period") || str.eq(name, "stat:period_scale") {
        let n = usize(x[0usize])
        let (f, sc) = xts.periodicity(x[1usize..1usize + n])
        let (r, re) = mem.alloc[f64](a, 1usize)
        if re != ok { os.exit(6) }
        r[0usize] = f
        if str.eq(name, "stat:period_scale") { r[0usize] = f64(sc) }
        ret r
    }
    if str.eq(name, "stat:align") {
        let n = usize(x[1usize])
        let (r, re) = mem.alloc[f64](a, n)
        if re != ok { os.exit(6) }
        var i = 0usize
        while i < n {
            r[i] = xts.align_time(x[2usize + i], x[0usize]) - 1573806600.0f64
            i += 1usize
        }
        ret r
    }
    if str.eq(name, "stat:lag_diff") {
        let n = usize(x[2usize])
        let (r, re) = xts.lag_diff(a, x[3usize..3usize + n], u8(x[0usize]), usize(x[1usize]))
        if re != ok { os.exit(6) }
        ret r
    }
    let on = u8(x[0usize])
    let k = i64(x[1usize])
    let n = usize(x[2usize])
    let idx = x[3usize..3usize + n]
    let (ep, ee) = xts.endpoints(a, idx, on, k)
    if ee != ok { os.exit(7) }
    if str.eq(name, "stat:endpoints") {
        let (r, re) = mem.alloc[f64](a, ep.len)
        if re != ok { os.exit(6) }
        var i = 0usize
        while i < ep.len {
            r[i] = f64(ep[i])
            i += 1usize
        }
        ret r
    }
    let v = x[3usize + n..3usize + 2usize * n]
    if str.eq(name, "stat:ohlc_o") { let (r, re) = xts.ohlc(a, v, ep, 0u8)
        out = r
        e = re }
    if str.eq(name, "stat:ohlc_h") { let (r, re) = xts.ohlc(a, v, ep, 1u8)
        out = r
        e = re }
    if str.eq(name, "stat:ohlc_l") { let (r, re) = xts.ohlc(a, v, ep, 2u8)
        out = r
        e = re }
    if str.eq(name, "stat:ohlc_c") { let (r, re) = xts.ohlc(a, v, ep, 3u8)
        out = r
        e = re }
    if str.eq(name, "stat:apply_sum") { let (r, re) = xts.period_apply(a, v, ep, 0u8)
        out = r
        e = re }
    if str.eq(name, "stat:apply_mean") { let (r, re) = xts.period_apply(a, v, ep, 1u8)
        out = r
        e = re }
    if str.eq(name, "stat:apply_max") { let (r, re) = xts.period_apply(a, v, ep, 2u8)
        out = r
        e = re }
    if str.eq(name, "stat:apply_min") { let (r, re) = xts.period_apply(a, v, ep, 3u8)
        out = r
        e = re }
    if e != ok { os.exit(8) }
    ret out
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "stat:period") || str.eq(c.name, "stat:period_scale") {
        let v = values(a, c.name, x)
        ret v[0usize]
    }
    let stat = u8(x[x.len - 1usize])
    let v = values(a, c.name, x[0usize..x.len - 1usize])
    if stat == 0u8 { ret f64(v.len) }
    var s = 0.0f64
    var w = 0.0f64
    var nas = 0.0f64
    var i = 0usize
    while i < v.len {
        if v[i] == v[i] {
            s += v[i]
            w += f64(i + 1usize) * v[i]
        } else {
            nas += 1.0f64
        }
        i += 1usize
    }
    if stat == 1u8 { ret s }
    if stat == 2u8 { ret w }
    if stat == 3u8 {
        if v.len == 0usize { ret 0.0f64 }
        ret v[0usize]
    }
    if stat == 4u8 {
        if v.len == 0usize { ret 0.0f64 }
        ret v[v.len - 1usize]
    }
    ret nas
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/xts.json")
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
                let _ = io.print(c.name)
                let _ = io.print(" got ")
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
