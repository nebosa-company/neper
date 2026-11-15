// e.algo.stat.dt against R's data.table: froll* (fixed and adaptive windows), shift, rleid,
// between, inrange, foverlaps pairs and a stable setorderv. tests/oracle/datatable.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R datatable`; the layouts are at the
// top of scripts/r_oracle/groups/datatable.R. A vector answer is one case per element (the last
// argument is the index) plus a "len:" case.

use e.algo.stat.dt as dt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pick(r: []const f64, c: *const oracle.Case, wants_len: bool) -> f64 {
    if wants_len { ret f64(r.len) }
    let i = usize(c.args[c.args.len - 1usize])
    if i < r.len { ret r[i] }
    ret 0.0f64 / 0.0f64
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    var name = c.name
    var wants_len = false
    var which = 0usize
    if name.len > 4usize && name[0usize] == 108u8 && name[1usize] == 101u8 && name[2usize] == 110u8 && name[3usize] == 58u8 {
        name = name[4usize..name.len]
        wants_len = true
    } else if name.len > 2usize && name[1usize] == 58u8 {
        if name[0usize] == 121u8 { which = 1usize }
        name = name[2usize..name.len]
    }
    let x = c.args
    if str.eq(name, "froll") {
        let kind = u8(x[0usize])
        let align = u8(x[1usize])
        let fill = x[2usize]
        let na = x[3usize] != 0.0f64
        let adaptive = x[4usize] != 0.0f64
        let n = usize(x[5usize])
        let len = usize(x[6usize])
        let data = x[7usize..7usize + len]
        if adaptive {
            let (ns, ne) = mem.alloc[usize](a, len)
            if ne != ok { os.exit(5) }
            var i = 0usize
            while i < len {
                ns[i] = usize(x[7usize + len + i])
                i += 1usize
            }
            let (r, e) = dt.froll_adaptive(a, data, ns, kind, fill, na)
            if e != ok { os.exit(7) }
            ret pick(r, c, wants_len)
        }
        let (r, e) = dt.froll(a, data, n, kind, align, fill, na)
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "shift") {
        let len = usize(x[3usize])
        let (r, e) = dt.shift(a, x[4usize..4usize + len], i64(x[0usize]), x[1usize], u8(x[2usize]))
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "rleid") {
        let len = usize(x[0usize])
        let (r, e) = dt.rleid(a, x[1usize..1usize + len])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "between") {
        let len = usize(x[3usize])
        let (r, e) = mem.alloc[f64](a, len)
        if e != ok { os.exit(5) }
        var i = 0usize
        while i < len {
            r[i] = dt.between(x[4usize + i], x[0usize], x[1usize], x[2usize] != 0.0f64)
            i += 1usize
        }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "inrange") {
        let k = usize(x[1usize])
        let len = usize(x[2usize + 2usize * k])
        let (r, e) = mem.alloc[f64](a, len)
        if e != ok { os.exit(5) }
        var i = 0usize
        while i < len {
            var v = 0.0f64
            if dt.inrange(x[3usize + 2usize * k + i], x[2usize..2usize + k], x[2usize + k..2usize + 2usize * k], x[0usize] != 0.0f64) { v = 1.0f64 }
            r[i] = v
            i += 1usize
        }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "overlaps") {
        let nx = usize(x[2usize])
        let xs = x[3usize..3usize + nx]
        let xe = x[3usize + nx..3usize + 2usize * nx]
        let ny = usize(x[3usize + 2usize * nx])
        let ys = x[4usize + 2usize * nx..4usize + 2usize * nx + ny]
        let ye = x[4usize + 2usize * nx + ny..4usize + 2usize * nx + 2usize * ny]
        let (pairs, e) = dt.foverlaps(a, xs, xe, ys, ye, u8(x[0usize]), u8(x[1usize]), true)
        if e != ok { os.exit(7) }
        if wants_len { ret f64(pairs.len / 2usize) }
        let i = usize(x[x.len - 1usize])
        ret pairs[2usize * i + which]
    }
    let len = usize(x[2usize])
    let (r, e) = dt.forder(a, x[3usize..3usize + len], x[0usize] != 0.0f64, i64(x[1usize]))
    if e != ok { os.exit(7) }
    ret pick(r, c, wants_len)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/datatable.json")
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
