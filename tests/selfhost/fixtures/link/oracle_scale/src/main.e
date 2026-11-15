// e.math.scale against R's labeling and scales: labelling algorithms, pretty, breaks_*,
// transformations and bounds helpers. tests/oracle/scale.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R scale`; the case layouts are written
// at the top of scripts/r_oracle/groups/scale.R. A vector answer is one case per element (the
// last argument is the index) plus a "len:" case.

use e.io
use e.mem
use e.math.scale as sc
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
    }
    let x = c.args
    if str.eq(name, "heckbert") {
        let (r, e) = sc.heckbert(a, x[0usize], x[1usize], x[2usize])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "wilkinson") {
        let q = [11]f64 { 1.0f64, 5.0f64, 2.0f64, 2.5f64, 3.0f64, 4.0f64, 1.5f64, 7.0f64, 6.0f64, 8.0f64, 9.0f64 }
        let (r, e) = sc.wilkinson(a, x[0usize], x[1usize], x[2usize], q[0usize..11usize], 0.8f64)
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "nelder") {
        let q = [11]f64 { 1.0f64, 1.2f64, 1.6f64, 2.0f64, 2.5f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64, 8.0f64, 10.0f64 }
        let (r, e) = sc.nelder(a, x[0usize], x[1usize], x[2usize], q[0usize..11usize])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "rpretty") {
        let (r, e) = sc.rpretty(a, x[0usize], x[1usize], x[2usize])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "extended") {
        let q = sc.default_q()
        let w = sc.default_w()
        let (r, e) = sc.extended(a, x[0usize], x[1usize], x[2usize], q[0usize..6usize], x[3usize] != 0.0f64, w[0usize..4usize])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "pretty") {
        let (r, e) = sc.pretty(a, x[0usize], x[1usize], i64(x[2usize]))
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "breaks_extended") {
        let k = usize(x[1usize])
        let (r, e) = sc.breaks_extended(a, x[2usize..2usize + k], x[0usize])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "breaks_pretty") {
        let k = usize(x[1usize])
        let (r, e) = sc.breaks_pretty(a, x[2usize..2usize + k], i64(x[0usize]))
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "breaks_log") {
        let k = usize(x[2usize])
        let (r, e) = sc.breaks_log(a, x[3usize..3usize + k], x[0usize], x[1usize])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "breaks_width") {
        let k = usize(x[2usize])
        let (r, e) = sc.breaks_width(a, x[3usize..3usize + k], x[0usize], x[1usize..2usize])
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "transform") {
        let t = sc.Transform { kind: u8(x[0usize]), p: x[1usize], offset: x[2usize], sigma: x[3usize], base: x[4usize] }
        ret sc.apply(a, &t, x[6usize], u8(x[5usize]))
    }
    if str.eq(name, "rescale") { ret sc.rescale(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize]) }
    if str.eq(name, "rescale_mid") { ret sc.rescale_mid(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(name, "rescale_max") { ret sc.rescale_max(x[0usize], x[1usize], x[2usize]) }
    if str.eq(name, "oob") { ret sc.oob(x[0usize], x[1usize], x[2usize], u8(x[3usize])) }
    if str.eq(name, "expand_range") {
        var out: [2]f64 = zero
        sc.expand_range(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], out[0usize..2usize])
        ret out[usize(x[5usize])]
    }
    if str.eq(name, "zero_range") {
        if sc.zero_range2(x[0usize], x[1usize]) { ret 1.0f64 }
        ret 0.0f64
    }
    os.exit(4)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/scale.json")
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
            if failures <= 25usize {
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
