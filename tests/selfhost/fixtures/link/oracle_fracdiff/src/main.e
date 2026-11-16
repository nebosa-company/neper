// e.algo.stat.fracdiff against fracdiff: diffseries, fdGPH and fdSperio. tests/oracle/fracdiff.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fracdiff`; the layout is at the top
// of scripts/r_oracle/groups/fracdiff.R.

use e.algo.stat.fracdiff as fd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = u8(x[0usize])
    let n = usize(x[3usize])
    let data = x[4usize..4usize + n]
    if kind == 0u8 {
        let (v, e) = fd.diffseries(a, data, x[1usize])
        if e != ok { os.exit(6) }
        if str.eq(c.name, "dssum") {
            var s = 0.0f64
            var i = 0usize
            while i < v.len {
                s += v[i]
                i += 1usize
            }
            ret s
        }
        ret v[usize(x[x.len - 1usize])]
    }
    let (d, sa, sr, e) = fd.periodogram_fit(a, data, x[1usize], kind == 2u8, x[2usize])
    if e != ok { os.exit(7) }
    if str.eq(c.name, "d") { ret d }
    if str.eq(c.name, "sdas") { ret sa }
    ret sr
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fracdiff.json")
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
