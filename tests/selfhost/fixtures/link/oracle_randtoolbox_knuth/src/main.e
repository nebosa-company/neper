// e.algo.rand.quasi.taocp_values against randtoolbox::knuthTAOCP. tests/oracle/randtoolbox_knuth.json
// comes from `Rscript scripts/r_oracle/generate.R randtoolbox_knuth`; the layout is at the top of
// scripts/r_oracle/groups/randtoolbox_knuth.R. randf_array fills its buffer column by column, so the value
// of row i and column j is at i + j * n.

use e.algo.rand.quasi as quasi
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let seed = u64(z[0usize])
    let n = usize(z[1usize])
    let d = usize(z[2usize])
    let (out, e0) = mem.alloc[f64](a, n * d)
    if e0 != ok { os.exit(5) }
    if quasi.taocp_values(seed, out) != ok { os.exit(6) }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            s += out[i + j * n] * f64(i * d + j + 1usize)
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/randtoolbox_knuth.json")
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
