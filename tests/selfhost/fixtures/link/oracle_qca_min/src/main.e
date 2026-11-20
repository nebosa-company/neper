// e.algo.stat.qcamin against QCA::minimize. tests/oracle/qca_min.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qca_min`; the layout is at the top of scripts/r_oracle/groups/qca_min.R.

use e.algo.stat.qcamin as qm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> str {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let non = usize(x[2usize])
    let ndc = usize(x[3usize])
    let (on, e1) = mem.alloc[u32](a, non + 1usize)
    if e1 != ok { os.exit(5) }
    let (dc, e2) = mem.alloc[u32](a, ndc + 1usize)
    if e2 != ok { os.exit(6) }
    let (de, e3) = mem.alloc[u8](a, n + 1usize)
    if e3 != ok { os.exit(7) }
    var i = 0usize
    while i < non {
        on[i] = u32(x[4usize + i])
        i += 1usize
    }
    i = 0usize
    while i < ndc {
        dc[i] = u32(x[4usize + non + i])
        i += 1usize
    }
    i = 0usize
    while i < n {
        de[i] = u8(x[4usize + non + ndc + i])
        i += 1usize
    }
    let (text, e4) = qm.minimize_text(a, kind, n, on[0usize..non], dc[0usize..ndc], de[0usize..n])
    if e4 != ok { os.exit(8) }
    ret text
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qca_min.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let text = answer(a, c)
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 6usize {
                let _ = io.print("kind ")
                let _ = io.print(c.name)
                let _ = io.print("\n got ")
                let _ = io.print(text)
                let _ = io.print("\n  R  ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
