// e.algo.rand.quasi.korobov_sequence against qrng::korobov. tests/oracle/qrng_korobov.json comes from
// `Rscript scripts/r_oracle/generate.R qrng_korobov`; the layout is at the top of
// scripts/r_oracle/groups/qrng_korobov.R.

use e.algo.rand.quasi as quasi
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = u64(z[0usize])
    let d = usize(z[1usize])
    let l = usize(z[2usize])
    let (gen, e0) = mem.alloc[u64](a, d)
    let (pts, e1) = mem.alloc[f64](a, usize(n) * d)
    if e0 != ok || e1 != ok { os.exit(5) }
    if l == 1usize {
        if quasi.korobov_generator(u64(z[3usize]), n, d, gen) != ok { os.exit(6) }
    } else {
        var j = 0usize
        while j < d {
            gen[j] = u64(z[3usize + j])
            j += 1usize
        }
    }
    if quasi.korobov_sequence(n, gen, d, pts) != ok { os.exit(7) }
    var s = 0.0f64
    var i = 0usize
    while i < usize(n) * d {
        s += pts[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qrng_korobov.json")
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
