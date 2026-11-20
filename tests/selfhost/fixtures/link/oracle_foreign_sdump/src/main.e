// e.fmt.sdump against foreign::data.restore. tests/oracle/foreign_sdump.json and the dump files under tests/oracle/data come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R foreign_sdump`; the layout is at the top of scripts/r_oracle/groups/foreign_sdump.R.
// A name with a leading x is a summary of an object in a hand-written dump (sdump_e<i>.txt).

use e.fmt.sdump as sd
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
    var nm = c.name
    var erred = str.eq(nm, "eerr") || str.eq(nm, "enobj")
    if nm.len > 1usize && nm[0usize] == 120u8 {
        erred = true
        nm = nm[1usize..nm.len]
    }
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/sdump_")
    if erred { let _ = str.push_byte(&bb, 101u8) }
    let _ = str.push_i64(&bb, i64(idx))
    let _ = str.push(&bb, ".txt")
    let (text, re) = fs.read_file(a, str.done(&bb), 1048576usize)
    if re != ok { os.exit(6) }
    let (m, pe) = sd.parse(a, text)
    if str.eq(nm, "eerr") {
        if pe == sd.Malformed { ret 1.0f64 }
        if pe != ok { os.exit(7) }
        ret 0.0f64
    }
    if pe != ok { os.exit(8) }
    if str.eq(nm, "nobj") || str.eq(nm, "enobj") { ret f64(m.n) }
    // the error files list their objects in name order already
    let v = m.items[col]
    if str.eq(nm, "len") { ret f64(v.len) }
    if str.eq(nm, "sum") { ret v.sum }
    if str.eq(nm, "wsum") { ret v.wsum }
    if str.eq(nm, "nna") { ret f64(v.nna) }
    if str.eq(nm, "ty") { ret f64(v.ty) }
    if str.eq(nm, "isum") { ret v.isum }
    if str.eq(nm, "nlev") { ret f64(v.nlev) }
    if str.eq(nm, "levs") { ret v.levs }
    if str.eq(nm, "ndim") { ret f64(v.ndim) }
    if str.eq(nm, "dimprod") { ret v.dimprod }
    if str.eq(nm, "nnames") { ret f64(v.nnames) }
    if str.eq(nm, "elh") { ret v.elh }
    ret v.nhash
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/foreign_sdump.json")
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
