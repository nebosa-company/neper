// e.algo.stat.tmstop's is_stopword_en against tm stopwords("english"). tests/oracle/tm_stop.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tm_stop`; the layout is at the top of scripts/r_oracle/groups/tm_stop.R.

use e.algo.stat.tmstop as ts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let (bld, eb) = str.builder(a, c.args.len + 1usize)
    if eb != ok { ret 0.0f64 / 0.0f64 }
    var bd = bld
    var i = 0usize
    while i < c.args.len {
        if str.push_byte(&bd, u8(c.args[i])) != ok { ret 0.0f64 / 0.0f64 }
        i += 1usize
    }
    if str.eq(c.name, "rqn") || str.eq(c.name, "rqs") {
        let (b2, eb2) = str.builder(a, c.args.len + 1usize)
        if eb2 != ok { ret 0.0f64 / 0.0f64 }
        var bd2 = b2
        var j = 1usize
        while j < c.args.len {
            if str.push_byte(&bd2, u8(c.args[j])) != ok { ret 0.0f64 / 0.0f64 }
            j += 1usize
        }
        let fl = usize(c.args[0usize])
        let (r2, er2) = ts.remove_punctuation_opts(a, str.done(&bd2), fl == 1usize || fl == 3usize, fl == 2usize || fl == 3usize)
        if er2 != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(c.name, "rqn") { ret f64(r2.len) }
        var sm2 = 0.0f64
        var k2 = 0usize
        while k2 < r2.len {
            sm2 += f64(r2[k2]) * f64(k2 + 1usize)
            k2 += 1usize
        }
        ret sm2
    }
    let w = str.done(&bd)
    if str.eq(c.name, "twn") || str.eq(c.name, "tws") {
        let (r3, er3) = ts.tokenize_words(a, w)
        if er3 != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(c.name, "twn") { ret f64(r3.len) }
        var sm3 = 0.0f64
        var k3 = 0usize
        while k3 < r3.len {
            sm3 += f64(r3[k3]) * f64(k3 + 1usize)
            k3 += 1usize
        }
        ret sm3
    }
    if str.eq(c.name, "rpn") || str.eq(c.name, "rps") {
        let (r, er) = ts.remove_punctuation(a, w)
        if er != ok { ret 0.0f64 / 0.0f64 }
        if str.eq(c.name, "rpn") { ret f64(r.len) }
        var sm = 0.0f64
        var k = 0usize
        while k < r.len {
            sm += f64(r[k]) * f64(k + 1usize)
            k += 1usize
        }
        ret sm
    }
    if ts.is_stopword_en(w) { ret 1.0f64 }
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tm_stop.json")
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
