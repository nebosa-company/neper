// e.algo.stat.apepkg.dist_dna against ape::dist.dna. tests/oracle/ape_dna.json comes from
// `Rscript scripts/r_oracle/generate.R ape_dna`; the layout is at the top of scripts/r_oracle/groups/ape_dna.R.

use e.algo.stat.apepkg as ape
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let l = usize(z[1usize])
    let model = u8(z[2usize])
    let (codes, e0) = mem.alloc[u8](a, n * l)
    let (d, e1) = mem.alloc[f64](a, n * n)
    if e0 != ok || e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n * l {
        codes[i] = u8(z[3usize + i])
        i += 1usize
    }
    if ape.dist_dna(a, codes, n, l, model, d) != ok { ret nan }
    var s = 0.0f64
    i = 0usize
    while i < n * n {
        s += d[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ape_dna.json")
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
