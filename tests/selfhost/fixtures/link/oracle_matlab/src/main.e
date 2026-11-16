// e.fmt.mat5 against R.matlab::readMat. tests/oracle/matlab.json and the .mat files under tests/oracle/data come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R matlab`; the layout is at the top of scripts/r_oracle/groups/matlab.R.

use e.fmt.mat5 as mat
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
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/matlab_")
    let _ = str.push_byte(&bb, u8(48usize + idx))
    let _ = str.push(&bb, ".mat")
    let path = str.done(&bb)
    let (bytes, re) = fs.read_file(a, path, 1048576usize)
    if re != ok { os.exit(6) }
    let (m, pe) = mat.parse(a, bytes)
    if pe != ok { os.exit(7) }
    if str.eq(c.name, "nvars") { ret f64(m.nvars) }
    let v = m.vars[col]
    // readMat returns a character array as one string
    if str.eq(c.name, "count") {
        if v.class == 4u8 { ret 1.0f64 }
        ret f64(v.count)
    }
    ret v.sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/matlab.json")
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
