// e.algo.stat.zoo against R's zoo: rollapply (width, by, align, partial, fill), na.locf, na.approx,
// na.spline, na.fill, yearmon and yearqtr, merge by index. tests/oracle/zoo.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R zoo`; the layouts are at the top of
// scripts/r_oracle/groups/zoo.R. A vector answer is one case per element (the last argument is
// the position) plus a "len:" case.

use e.algo.stat.zoo as zoo
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
    if name.len > 4usize && name[0usize] == 108u8 && name[1usize] == 101u8 && name[2usize] == 110u8 && name[3usize] == 58u8 {
        name = name[4usize..name.len]
        wants_len = true
    } else if name.len > 2usize && name[1usize] == 58u8 {
        name = name[2usize..name.len]
    }
    let x = c.args
    if str.eq(name, "rollapply") {
        let len = usize(x[12usize])
        let data = x[13usize..13usize + len]
        let (vals, pos, e) = zoo.rollapply(a, data, u8(x[0usize]), i64(x[1usize]), i64(x[2usize]), u8(x[3usize]), i64(x[4usize]))
        if e != ok { os.exit(7) }
        if x[5usize] == 0.0f64 { ret pick(vals, c, wants_len) }
        let (full, fe) = zoo.fill_positions(a, len, vals, pos, x[6usize..12usize])
        if fe != ok { os.exit(8) }
        ret pick(full, c, wants_len)
    }
    if str.eq(name, "locf") {
        let len = usize(x[3usize])
        let (r, e) = zoo.na_locf(a, x[4usize..4usize + len], x[0usize] != 0.0f64, i64(x[1usize]), x[2usize] != 0.0f64)
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "approx") {
        let len = usize(x[3usize])
        let (r, e) = zoo.na_approx(a, x[4usize..4usize + len], x[4usize + len..4usize + 2usize * len], i64(x[0usize]), i64(x[1usize]), x[2usize] != 0.0f64)
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "spline") {
        let len = usize(x[3usize])
        let (r, e) = zoo.na_spline(a, x[4usize..4usize + len], x[4usize + len..4usize + 2usize * len], u8(x[0usize]), i64(x[1usize]), x[2usize] != 0.0f64)
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "fill") {
        let len = usize(x[6usize])
        let (r, e) = zoo.na_fill(a, x[7usize..7usize + len], x[0usize..6usize])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "ym_parts") {
        var year = 0i64
        var part = 0i64
        if x[0usize] == 0.0f64 {
            let (y, m) = zoo.yearmon_parts(x[1usize])
            year = y
            part = m
        } else {
            let (y, q) = zoo.yearqtr_parts(x[1usize])
            year = y
            part = q
        }
        if x[2usize] == 0.0f64 { ret f64(year) }
        ret f64(part)
    }
    if str.eq(name, "ym_add") {
        if x[0usize] == 0.0f64 { ret zoo.yearmon_add(x[1usize], x[2usize]) }
        ret zoo.yearqtr_add(x[1usize], x[2usize])
    }
    // merge: (all, n1, idx1..., x1..., n2, idx2..., x2..., fill, position)
    let n1 = usize(x[1usize])
    let n2 = usize(x[2usize + 2usize * n1])
    let i1 = x[2usize..2usize + n1]
    let x1 = x[2usize + n1..2usize + 2usize * n1]
    let i2 = x[3usize + 2usize * n1..3usize + 2usize * n1 + n2]
    let x2 = x[3usize + 2usize * n1 + n2..3usize + 2usize * n1 + 2usize * n2]
    let fill = x[3usize + 2usize * n1 + 2usize * n2]
    let (idx, ca, cb, e) = zoo.merge2(a, i1, x1, i2, x2, x[0usize] != 0.0f64, fill)
    if e != ok { os.exit(7) }
    if str.eq(name, "merge_idx") { ret pick(idx, c, wants_len) }
    if str.eq(name, "merge_a") { ret pick(ca, c, wants_len) }
    ret pick(cb, c, wants_len)
}

fn format_text(a: *mem.Arena, c: *const oracle.Case) -> str {
    var r = ""
    var e = ok
    if c.args[0usize] == 0.0f64 {
        let (s, fe) = zoo.yearmon_format(a, c.args[1usize], c.inputs[0usize])
        r = s
        e = fe
    } else {
        let (s, fe) = zoo.yearqtr_format(a, c.args[1usize], c.inputs[0usize])
        r = s
        e = fe
    }
    if e != ok { os.exit(9) }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/zoo.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var good = false
        if str.eq(c.name, "ym_format") {
            good = oracle.agrees_text(format_text(a, c), c)
        } else {
            good = oracle.agrees(answer(a, c), c)
        }
        if !good {
            failures += 1usize
            if failures <= 20usize {
                if str.eq(c.name, "ym_format") {
                    let _ = io.print(c.name)
                    let _ = io.print(" ")
                    let _ = io.print(c.inputs[0usize])
                    let _ = io.print(" want ")
                    let _ = io.print(c.text)
                    let _ = io.print(" got ")
                    let _ = io.print(format_text(a, c))
                    let _ = io.print("\n")
                } else {
                    let _ = io.print(oracle.describe(a, c, answer(a, c)))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
