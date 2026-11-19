// e.algo.stat.tmstoplang's is_stopword against tm stopwords(language). tests/oracle/tm_stoplang.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tm_stoplang`; the layout is at the top of scripts/r_oracle/groups/tm_stoplang.R.

use e.algo.stat.tmstoplang as ts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let (bld, eb) = str.builder(a, c.args.len + 1usize)
    if eb != ok { ret 0.0f64 / 0.0f64 }
    var bd = bld
    var i = 1usize
    while i < c.args.len {
        if str.push_byte(&bd, u8(c.args[i])) != ok { ret 0.0f64 / 0.0f64 }
        i += 1usize
    }
    let w = str.done(&bd)
    if ts.is_stopword(usize(c.args[0usize]), w) { ret 1.0f64 }
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tm_stoplang.json")
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
