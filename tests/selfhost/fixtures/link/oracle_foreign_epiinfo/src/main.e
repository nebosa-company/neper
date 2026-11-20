// e.fmt.epiinfo against foreign::read.epiinfo. tests/oracle/foreign_epiinfo.json and the .rec files under tests/oracle/data come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R foreign_epiinfo`; the layout is at the top of scripts/r_oracle/groups/foreign_epiinfo.R.

use e.fmt.epiinfo as epi
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
    let opt = usize(x[2usize])
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/epiinfo_")
    let erred = str.eq(c.name, "eerr") || str.eq(c.name, "enrow") || str.eq(c.name, "encol")
    if erred { let _ = str.push_byte(&bb, 101u8) }
    let _ = str.push_byte(&bb, u8(48usize + idx))
    let _ = str.push(&bb, ".rec")
    let path = str.done(&bb)
    let (text, re) = fs.read_file(a, path, 1048576usize)
    if re != ok { os.exit(6) }
    var o: epi.Opts = zero
    o.deleted = u8(opt / 4usize)
    o.guess = (opt / 2usize) % 2usize == 1usize
    o.lower = opt % 2usize == 1usize
    o.year = "2020"
    let (m, pe) = epi.parse(a, text, o)
    if str.eq(c.name, "eerr") {
        if pe == epi.BadHeader || pe == epi.NoRecords { ret 1.0f64 }
        if pe != ok { os.exit(7) }
        ret 0.0f64
    }
    if pe != ok { os.exit(8) }
    if str.eq(c.name, "nrow") || str.eq(c.name, "enrow") { ret f64(m.nrows) }
    if str.eq(c.name, "ncol") || str.eq(c.name, "encol") { ret f64(m.nvars) }
    if str.eq(c.name, "ndel") { ret f64(m.ndeleted) }
    let v = m.cols[col]
    if str.eq(c.name, "kind") { ret f64(v.kind) }
    if str.eq(c.name, "nna") { ret f64(v.nna) }
    if str.eq(c.name, "sum") { ret v.sum }
    if str.eq(c.name, "wsum") { ret v.wsum }
    if str.eq(c.name, "nhash") { ret v.nhash }
    ret v.chash
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/foreign_epiinfo.json")
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
