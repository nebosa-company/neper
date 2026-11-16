// e.fmt.arff against foreign::read.arff. tests/oracle/foreign.json and the ARFF files under tests/oracle/data come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R foreign`; the layout is at the top of scripts/r_oracle/groups/foreign.R.

use e.fmt.arff as arff
use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let idx = usize(x[0usize])
    let col = usize(x[1usize])
    var path = "tests/oracle/data/foreign_arff0.arff"
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/foreign_arff")
    let _ = str.push_byte(&bb, u8(48usize + idx))
    let _ = str.push(&bb, ".arff")
    path = str.done(&bb)
    let (text, re) = fs.read_file(a, path, 1048576usize)
    if re != ok { os.exit(6) }
    let (t, pe) = arff.parse(a, text)
    if pe != ok { os.exit(7) }
    if str.eq(c.name, "dim") {
        if col == 0usize { ret f64(t.nrows) }
        ret f64(t.ncols)
    }
    var s = 0.0f64
    var n = 0.0f64
    var r = 0usize
    while r < t.nrows {
        let v = t.values[r * t.ncols + col]
        if v == v { s += v } else { n += 1.0f64 }
        r += 1usize
    }
    if str.eq(c.name, "sum") { ret s }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/foreign.json")
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
