// e.algo.stat.xts, first and last with period strings and merge by index, against xts. tests/oracle/xts2.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R xts2`; the layouts are at the top of
// scripts/r_oracle/groups/xts2.R. A vector answer is six cases: length, sum, position-weighted sum, first, last, NA count.

use e.algo.stat.xts as xts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn values(a: *mem.Arena, name: str, x: []const f64) -> []const f64 {
    var out: []const f64 = zero
    if str.eq(name, "stat:fl") {
        let kind = usize(x[0usize])
        let unit = u8(x[1usize])
        let k = i64(x[2usize])
        let n = usize(x[3usize])
        let (sec, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(6) }
        var i = 0usize
        while i < n {
            sec[i] = x[4usize + i] * 86400.0f64
            i += 1usize
        }
        let vals = x[4usize + n..4usize + 2usize * n]
        let (s, e, fe) = xts.first_last(a, sec, unit, k, kind == 1usize)
        if fe != ok { os.exit(7) }
        if e < s { ret vals[0usize..0usize] }
        ret vals[s - 1usize..e]
    }
    if str.eq(name, "stat:pi") {
        let mode = u8(x[0usize])
        let on = u8(x[1usize])
        let n = usize(x[2usize])
        let sec = x[3usize..3usize + n]
        let (ep, e1) = xts.endpoints(a, sec, on, 1i64)
        let (out2, e2) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok { os.exit(6) }
        let r = xts.period_index(sec, ep, mode, on, out2)
        ret out2[0usize..r]
    }
    let jn = u8(x[0usize])
    let nx = usize(x[1usize])
    let ny = usize(x[2usize])
    let ix = x[3usize..3usize + nx]
    let xv = x[3usize + nx..3usize + 2usize * nx]
    let iy = x[3usize + 2usize * nx..3usize + 2usize * nx + ny]
    let yv = x[3usize + 2usize * nx + ny..3usize + 2usize * nx + 2usize * ny]
    let (io_, e1) = mem.alloc[f64](a, nx + ny)
    let (xo, e2) = mem.alloc[f64](a, nx + ny)
    let (yo, e3) = mem.alloc[f64](a, nx + ny)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(6) }
    let r = xts.merge2(ix, xv, iy, yv, jn, io_, xo, yo)
    if str.eq(name, "stat:mx") {
        out = xo[0usize..r]
    } else if str.eq(name, "stat:my") {
        out = yo[0usize..r]
    } else {
        out = io_[0usize..r]
    }
    ret out
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let v = values(a, c.name, x[0usize..x.len - 1usize])
    let stat = u8(x[x.len - 1usize])
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/xts2.json")
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
