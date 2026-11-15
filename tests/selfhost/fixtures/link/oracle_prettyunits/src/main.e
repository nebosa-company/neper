// e.text.prettyunits against R's prettyunits, string for string. tests/oracle/prettyunits.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R prettyunits`. A case is
// (style or compact flag, values...) and answers the strings joined by "|".

use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
use e.text.prettyunits as pu

fn join(a: *mem.Arena, parts: []str) -> []u8 {
    var total = 0usize
    var i = 0usize
    while i < parts.len {
        total += parts[i].len + 1usize
        i += 1usize
    }
    let (buf, e) = mem.alloc[u8](a, total + 1usize)
    if e != ok { os.exit(5) }
    var at = 0usize
    i = 0usize
    while i < parts.len {
        if i > 0usize {
            buf[at] = 124u8
            at += 1usize
        }
        var k = 0usize
        while k < parts[i].len {
            buf[at + k] = parts[i][k]
            k += 1usize
        }
        at += parts[i].len
        i += 1usize
    }
    ret buf[0usize..at]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> []u8 {
    let flag = u8(c.args[0usize])
    let values = c.args[1usize..c.args.len]
    if str.eq(c.name, "bytes") {
        let (r, e) = pu.pretty_bytes(a, values, flag)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "num") {
        let (r, e) = pu.pretty_num(a, values, flag)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "ms") {
        let (r, e) = pu.pretty_ms(a, values, flag == 1u8)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "sec") {
        let (r, e) = pu.pretty_sec(a, values, flag == 1u8)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    let (r, e) = pu.vague_dt(a, values, flag)
    if e != ok { os.exit(7) }
    ret join(a, r)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/prettyunits.json")
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
            if failures <= 12usize {
                let _ = io.print(c.name)
                let _ = io.print("\n got [")
                let _ = io.print(text)
                let _ = io.print("]\n  R  [")
                let _ = io.print(c.text)
                let _ = io.print("]\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
