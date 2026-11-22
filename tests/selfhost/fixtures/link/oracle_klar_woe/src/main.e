// e.algo.stat.klar.woe_counts against klaR::woe. tests/oracle/klar_woe.json comes from
// `Rscript scripts/r_oracle/generate.R klar_woe`; the layout is at the top of
// scripts/r_oracle/groups/klar_woe.R.

use e.algo.stat.klar as kl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let nlev = usize(z[1usize])
    let adj = z[2usize]
    let (codes, e0) = mem.alloc[usize](a, n)
    let (labels, e1) = mem.alloc[usize](a, n)
    let (counts, e2) = mem.alloc[f64](a, nlev * 2usize)
    let (out, e3) = mem.alloc[f64](a, nlev + 1usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        codes[i] = usize(z[3usize + i])
        labels[i] = usize(z[3usize + n + i])
        i += 1usize
    }
    if kl.woe_counts(codes, n, labels, nlev, adj, counts, out) != ok { os.exit(6) }
    var s = 0.0f64
    i = 0usize
    while i < nlev + 1usize {
        s += out[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/klar_woe.json")
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
