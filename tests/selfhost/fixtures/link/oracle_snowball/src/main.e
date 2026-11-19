// e.text.stem's porter and snowball against SnowballC wordStem. tests/oracle/snowball.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R snowball`; the layout is at the top of scripts/r_oracle/groups/snowball.R.

use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
use e.text.stem as stem

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let (bld, eb) = str.builder(a, c.args.len + 1usize)
    if eb != ok { ret nan }
    var bd = bld
    var i = 1usize
    while i < c.args.len {
        if str.push_byte(&bd, u8(c.args[i])) != ok { ret nan }
        i += 1usize
    }
    let w = str.done(&bd)
    let (out, eo) = mem.alloc[u8](a, w.len + 8usize)
    if eo != ok { ret nan }
    var s: str = ""
    var es = ok
    if usize(c.args[0usize]) == 0usize {
        let (r, e) = stem.porter(w, out)
        s = r
        es = e
    } else {
        let (r, e) = stem.snowball(w, out)
        s = r
        es = e
    }
    if es != ok { ret nan }
    var sm = 0.0f64
    var k = 0usize
    while k < s.len {
        sm += f64(s[k]) * f64(k + 1usize)
        k += 1usize
    }
    ret 1.0e6f64 * f64(s.len) + sm
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/snowball.json")
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
