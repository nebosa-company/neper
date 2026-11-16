// e.algo.stat.ica against ica: icafast (symmetric update) compared by its sign- and order-free outputs.
// tests/oracle/ica.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ica`; the
// layout is at the top of scripts/r_oracle/groups/ica.R.

use e.algo.stat.ica as ic
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let nc = usize(x[2usize])
    let (r, e) = ic.icafast(a, x[7usize..7usize + n * p], n, p, nc, i64(x[5usize]), x[6usize], u8(x[3usize]), x[4usize])
    if e != ok { os.exit(6) }
    if str.eq(c.name, "vafs") { ret r.vafs[usize(x[x.len - 1usize])] }
    if str.eq(c.name, "iter") { ret f64(r.iter) }
    if str.eq(c.name, "conv") {
        if r.converged { ret 1.0f64 }
        ret 0.0f64
    }
    let which = u8(x[x.len - 1usize])
    // S M' (n x p, row-major): S is n x nc, M is p x nc
    var s = 0.0f64
    var w = 0.0f64
    var q = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            var v = 0.0f64
            var k = 0usize
            while k < nc {
                v += r.s[i * nc + k] * r.m[j * nc + k]
                k += 1usize
            }
            s += v
            w += f64(i * p + j + 1usize) * v
            q += v * v
            j += 1usize
        }
        i += 1usize
    }
    if which == 0u8 { ret s }
    if which == 1u8 { ret w }
    ret q
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ica.json")
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
