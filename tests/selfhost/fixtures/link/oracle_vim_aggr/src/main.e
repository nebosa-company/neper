// e.algo.stat.vimpkg.aggr_counts against VIM::aggr. tests/oracle/vim_aggr.json comes from
// `Rscript scripts/r_oracle/generate.R vim_aggr`; the layout is at the top of
// scripts/r_oracle/groups/vim_aggr.R.

use e.algo.stat.vimpkg as vm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (missings, e0) = mem.alloc[usize](a, p)
    let (masks, e1) = mem.alloc[u32](a, n)
    let (counts, e2) = mem.alloc[usize](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret nan }
    let patterns = vm.aggr_counts(z[2usize..2usize + n * p], n, p, missings, masks, counts)
    var s = 0.0f64
    var idx = 0usize
    var i = 0usize
    while i < p {
        s += f64(missings[i]) * f64(idx + 1usize)
        idx += 1usize
        i += 1usize
    }
    var k = 0usize
    while k < patterns {
        var col = 0usize
        while col < p {
            let bit = (masks[k] >> u32(p - 1usize - col)) & 1u32
            s += f64(bit) * f64(idx + 1usize)
            idx += 1usize
            col += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < patterns {
        s += f64(counts[k]) * f64(idx + 1usize)
        idx += 1usize
        k += 1usize
    }
    k = 0usize
    while k < patterns {
        s += f64(counts[k]) * 100.0f64 / f64(n) * f64(idx + 1usize)
        idx += 1usize
        k += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vim_aggr.json")
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
