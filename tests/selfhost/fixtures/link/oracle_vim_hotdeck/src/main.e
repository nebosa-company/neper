// e.algo.stat.vimpkg.hotdeck against VIM::hotdeck. tests/oracle/vim_hotdeck.json comes from
// `Rscript scripts/r_oracle/generate.R vim_hotdeck`; the layout is at the top of
// scripts/r_oracle/groups/vim_hotdeck.R.

use e.algo.stat.vimpkg as vm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let (out, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { ret nan }
    if vm.hotdeck(a, z[3usize..3usize + n * p], n, p, i64(z[0usize]), out) != ok { ret nan }
    var s = 0.0f64
    var k = 0usize
    while k < n * p {
        s += out[k] * f64(k + 1usize)
        k += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vim_hotdeck.json")
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
