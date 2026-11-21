// e.algo.stat.tgp against R's tgp package: lhs(), the Latin hypercube sampler, through the C entry
// point lh_sample (explicit state) and through lhs() under set.seed. tests/oracle/tgp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tgp`.
// A case is (state or seed, n, d, rect (d lows then d highs), shape (d), mode (d), k): the k-th value of the
// n x d row-major sample; shape -1 is the uniform form.

use e.algo.rand.r as rr
use e.algo.stat.tgp as tgp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tgp.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[3usize])
        let d = usize(x[4usize])
        let (rect, re) = mem.alloc[f64](a, 2usize * d)
        let (shape, se) = mem.alloc[f64](a, d)
        let (mode, me) = mem.alloc[f64](a, d)
        if re != ok || se != ok || me != ok { os.exit(5) }
        var i = 0usize
        while i < 2usize * d {
            rect[i] = x[5usize + i]
            i += 1usize
        }
        i = 0usize
        while i < d {
            shape[i] = x[5usize + 2usize * d + i]
            mode[i] = x[5usize + 3usize * d + i]
            i += 1usize
        }
        let k = usize(x[x.len - 1usize])
        var got = 0.0f64 / 0.0f64
        if c.name.len == 2usize {
            let (st, ste) = mem.alloc[i64](a, 3usize)
            if ste != ok { os.exit(5) }
            st[0usize] = i64(x[0usize])
            st[1usize] = i64(x[1usize])
            st[2usize] = i64(x[2usize])
            let (s, e) = tgp.lh_sample(a, st, n, d, rect, shape, mode)
            if e == ok { got = s[k] }
        } else {
            var r: rr.Rng = zero
            rr.seed(&r, i64(x[0usize]))
            let (s, e) = tgp.lhs(a, &r, n, d, rect, shape, mode)
            if e == ok { got = s[k] }
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 15usize {
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
