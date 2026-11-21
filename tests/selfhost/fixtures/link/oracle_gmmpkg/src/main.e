// e.algo.stat.gmmpkg against gmm. tests/oracle/gmmpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gmmpkg`; the layout is at the top of scripts/r_oracle/groups/gmmpkg.R.
// The data are redrawn here from the seed with R's Mersenne-Twister and inversion rnorm.

use e.algo.rand.r as rr
use e.algo.stat.gmmpkg as gm
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn same_fit(x: []const f64, y: []const f64) -> bool {
    if x.len != y.len { ret false }
    var i = 2usize
    while i < 14usize {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gmmpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (out, e1) = mem.alloc[f64](a, 64usize)
    let (wres, e2) = mem.alloc[f64](a, 4usize)
    let (opt, e3) = mem.alloc[f64](a, 8usize)
    let (rm, e4) = mem.alloc[f64](a, 4usize)
    let (rhs, e5) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(4) }
    var failures = 0usize
    var at = 0usize
    var have = false
    var prev = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let n = usize(x[3usize])
        let nz = usize(x[4usize])
        let icpt = usize(x[5usize])
        let p = 1usize + icpt
        let q = nz + icpt
        if !have || !same_fit(x, golden.cases[prev].args) {
            var rng: rr.Rng = zero
            rr.seed(&rng, i64(x[2usize]))
            let (zm, e6) = mem.alloc[f64](a, n * nz)
            let (ev, e7) = mem.alloc[f64](a, n)
            let (vv, e8) = mem.alloc[f64](a, n)
            let (uu, e9) = mem.alloc[f64](a, n)
            let (yy, e10) = mem.alloc[f64](a, n)
            let (xx, e11) = mem.alloc[f64](a, n * p)
            let (zz, e12) = mem.alloc[f64](a, n * q)
            if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { os.exit(4) }
            var i = 0usize
            while i < n * nz {
                zm[i] = rr.norm(&rng)
                i += 1usize
            }
            i = 0usize
            while i < n {
                ev[i] = rr.norm(&rng)
                i += 1usize
            }
            i = 0usize
            while i < n {
                vv[i] = rr.norm(&rng)
                i += 1usize
            }
            let rho = x[6usize]
            let ic = f64(icpt)
            i = 0usize
            while i < n {
                if i == 0usize { uu[i] = ev[i] } else { uu[i] = ev[i] + rho * uu[i - 1usize] }
                var t2 = 0.0f64
                if nz >= 2usize { t2 = 0.5f64 * zm[n + i] }
                let x1 = zm[i] + t2 + 0.5f64 * uu[i] + vv[i]
                yy[i] = ic + 2.0f64 * x1 + uu[i] * (1.0f64 + 0.5f64 * math.abs[f64](zm[i]))
                if icpt == 1usize {
                    xx[i * p] = 1.0f64
                    xx[i * p + 1usize] = x1
                    zz[i * q] = 1.0f64
                } else {
                    xx[i] = x1
                }
                var j = 0usize
                while j < nz {
                    zz[i * q + icpt + j] = zm[j * n + i]
                    j += 1usize
                }
                i += 1usize
            }
            opt[0usize] = x[7usize]
            opt[1usize] = x[8usize]
            opt[2usize] = x[9usize]
            opt[3usize] = x[10usize]
            opt[4usize] = x[11usize]
            opt[5usize] = x[12usize]
            opt[6usize] = x[13usize]
            opt[7usize] = ic
            if !gm.gmm_fit(a, yy, xx, zz, n, p, q, opt, out) { os.exit(5) }
            have = true
            prev = at
        }
        let what = usize(x[0usize])
        let idx = usize(x[1usize])
        var got = 0.0f64
        if what == 0usize { got = out[idx] }
        if what == 1usize { got = out[p + idx] }
        if what >= 2usize && what <= 4usize { got = out[p + p * p + what - 2usize] }
        if what >= 5usize {
            var m = 1usize
            rm[0usize] = 1.0f64
            rhs[0usize] = 1.95f64
            if p == 2usize {
                rm[0usize] = 0.0f64
                rm[1usize] = 1.0f64
            }
            if x[14usize] > 0.5f64 && p == 2usize {
                m = 2usize
                rm[0usize] = 1.0f64
                rm[1usize] = 0.0f64
                rm[2usize] = 0.0f64
                rm[3usize] = 1.0f64
                rhs[0usize] = 1.1f64
                rhs[1usize] = 2.0f64
            }
            if !gm.wald_test(a, out[0usize..p], out[p..p + p * p], p, rm[0usize..m * p], rhs[0usize..m], m, f64(n - p), wres) { os.exit(6) }
            got = wres[what - 5usize]
        }
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
