// e.algo.stat.proxy gower and levenshtein against proxy. tests/oracle/proxy2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R proxy2`; the layout is at the top of
// scripts/r_oracle/groups/proxy2.R.

use e.algo.stat.proxy as px
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "lev") {
        let la = usize(z[0usize])
        let lb = usize(z[1usize])
        let (s, e1) = mem.alloc[u8](a, la + 1usize)
        let (t, e2) = mem.alloc[u8](a, lb + 1usize)
        if e1 != ok || e2 != ok { ret nan }
        var i = 0usize
        while i < la {
            s[i] = u8(z[2usize + i])
            i += 1usize
        }
        i = 0usize
        while i < lb {
            t[i] = u8(z[2usize + la + i])
            i += 1usize
        }
        let (d, e) = px.levenshtein(a, s[0usize..la], t[0usize..lb])
        if e != ok { ret nan }
        ret d
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let x = z[2usize..2usize + n * p]
    let ri = usize(z[2usize + n * p])
    let rj = usize(z[3usize + n * p])
    let (rg, e) = mem.alloc[f64](a, p)
    if e != ok { ret nan }
    var k = 0usize
    while k < p {
        var lo = 1.0e308f64
        var hi = 0.0f64 - 1.0e308f64
        var i = 0usize
        while i < n {
            let v = x[i * p + k]
            if v == v {
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
            i += 1usize
        }
        rg[k] = hi - lo
        k += 1usize
    }
    ret px.gower(x[ri * p..ri * p + p], x[rj * p..rj * p + p], rg)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/proxy2.json")
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
