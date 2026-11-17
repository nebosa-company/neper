// e.algo.stat.fminsearchpkg against pracma::fminsearch. tests/oracle/fminsearchpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fminsearchpkg`; the layout is at the top of scripts/r_oracle/groups/fminsearchpkg.R.

use e.algo.stat.fminsearchpkg as fm
use e.io
use e.mem
use e.os
use e.str
use e.algo.rand.r as rng
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fminsearchpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        if str.eq(c.name, "hj") {
            // (id, what 0 xmin 1 fmin 2 count 3 iterations, k, bounded, seed, x0 (n), lower (n), upper (n))
            let hid = usize(x[0usize])
            let hn = fm.dim_of(hid)
            let (hx, he1) = mem.alloc[f64](a, hn)
            if he1 != ok { os.exit(5) }
            var hrg: rng.Rng = zero
            rng.seed(&hrg, i64(x[4usize]))
            let bnd = x[3usize] == 1.0f64
            let (hf, hc, hi, hee) = fm.hooke_jeeves(a, &hrg, hid, x[5usize..5usize + hn], 1.0e-8f64, 10000usize, bnd, x[5usize + hn..5usize + hn + hn], x[5usize + hn + hn..5usize + hn + hn + hn], hx)
            if hee != ok { os.exit(7) }
            var hg = 0.0f64
            if usize(x[1usize]) == 0usize { hg = hx[usize(x[2usize])] }
            if usize(x[1usize]) == 1usize { hg = hf }
            if usize(x[1usize]) == 2usize { hg = f64(hc) }
            if usize(x[1usize]) == 3usize { hg = f64(hi) }
            if !oracle.agrees(hg, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, hg))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        let id = usize(x[0usize])
        let n = fm.dim_of(id)
        let (xmin, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        let (work, e2) = mem.alloc[f64](a, 8usize * (n + 1usize) * n)
        if e2 != ok { os.exit(6) }
        let (fmin, count, restarts) = fm.nelder_mead(id, x[3usize..3usize + n], 1.0e-8f64, 5000usize, xmin, work)
        var got = 0.0f64
        let what = usize(x[1usize])
        if what == 0usize { got = xmin[usize(x[2usize])] }
        if what == 1usize { got = fmin }
        if what == 2usize { got = f64(count) }
        if what == 3usize { got = f64(restarts) }
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
