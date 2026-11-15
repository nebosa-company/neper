// e.gfx.colorspace against R's farver: convert_colour between all 15 colour spaces (with white
// references) and compare_colour with the five distances. tests/oracle/colour.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R colour`; the case layouts are at the top
// of scripts/r_oracle/groups/colour.R.

use e.gfx.colorspace as cs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "convert") {
        let from = u8(x[0usize] + 0.5f64)
        let to = u8(x[1usize] + 0.5f64)
        let wf = cs.White { x: x[2usize], y: x[3usize], z: x[4usize] }
        let wt = cs.White { x: x[5usize], y: x[6usize], z: x[7usize] }
        let v = cs.Color { a: x[8usize], b: x[9usize], c: x[10usize], d: x[11usize] }
        let r = cs.convert(from, to, v, wf, wt)
        let e = usize(x[12usize] + 0.5f64)
        if e == 0usize { ret r.a }
        if e == 1usize { ret r.b }
        if e == 2usize { ret r.c }
        ret r.d
    }
    let space = u8(x[0usize] + 0.5f64)
    let method = u8(x[1usize] + 0.5f64)
    let wf = cs.White { x: x[4usize], y: x[5usize], z: x[6usize] }
    let wt = cs.White { x: x[7usize], y: x[8usize], z: x[9usize] }
    let a = cs.Color { a: x[10usize], b: x[11usize], c: x[12usize], d: x[13usize] }
    let b = cs.Color { a: x[14usize], b: x[15usize], c: x[16usize], d: x[17usize] }
    ret cs.compare(space, a, b, wf, wt, method, x[2usize], x[3usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/colour.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(c)
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
