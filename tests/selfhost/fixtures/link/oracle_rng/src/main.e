// R's streams against R: set.seed, runif, rnorm (inversion), rexp and sample (rejection).
// tests/oracle/rng.json comes from `Rscript scripts/r_oracle/generate.R rng`. A case is the
// i-th draw after set.seed(seed), so each case re-seeds and advances.

use e.algo.rand.r as rr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn is(name: str, want: str) -> bool {
    if name.len != want.len { ret false }
    var at = 0usize
    while at < name.len {
        if name[at] != want[at] { ret false }
        at += 1usize
    }
    ret true
}

fn draw(a: *mem.Arena, c: *const oracle.Case) -> (f64, bool) {
    var g: rr.Rng = zero
    let x = c.args
    rr.seed(&g, i64(x[0]))
    let index = i64(x[1])
    if is(c.name, "sample") {
        let start = mem.mark(a)
        let (picked, e) = rr.sample_int(a, &g, i64(x[2]), i64(x[3]), x[4] != 0.0f64)
        var out = 0.0f64
        if e == ok { out = f64(picked[usize(index - 1i64)]) }
        mem.reset(a, start)
        ret (out, e == ok)
    }
    var k = 1i64
    while k < index {
        if is(c.name, "runif") { let _ = rr.runif(&g, x[2], x[3]) }
        if is(c.name, "rnorm") { let _ = rr.rnorm(&g, x[2], x[3]) }
        if is(c.name, "rexp") { let _ = rr.rexp(&g, x[2]) }
        k += 1i64
    }
    if is(c.name, "runif") { ret (rr.runif(&g, x[2], x[3]), true) }
    if is(c.name, "rnorm") { ret (rr.rnorm(&g, x[2], x[3]), true) }
    if is(c.name, "rexp") { ret (rr.rexp(&g, x[2]), true) }
    ret (0.0f64, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rng.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let (got, known) = draw(a, c)
        if !known { os.exit(4) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 40usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
