// e.algo.stat.actuar against actuar, fourth group: quantile, VaR and CTE of aggregateDist. tests/oracle/actuar4.json comes from scripts/r_oracle/groups/actuar4.R (the layout is at its top).

use e.algo.stat.actuar as ac
use e.algo.stat.armld as ld
use e.io
use e.math
use e.mem
use e.os
use e.algo.rand.r as rr
use e.str
use e.test.oracle as oracle

fn answer(ar: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let src = usize(x[0usize])
    let stat = usize(x[1usize])
    let p = x[2usize]
    if src == 3usize {
        if stat == 0usize { ret ac.agg_normal_q(p, x[3usize], x[4usize]) }
        ret ac.agg_normal_cte(p, x[3usize], x[4usize])
    }
    if src == 4usize {
        if stat == 0usize { ret ac.agg_npower_q(p, x[3usize], x[4usize], x[5usize]) }
        ret ac.agg_npower_cte(p, x[3usize], x[4usize], x[5usize])
    }
    var fs: [512]f64 = zero
    var xs: [512]f64 = zero
    var ys: [512]f64 = zero
    var wk: [128]f64 = zero
    var n = 0usize
    if src == 0usize {
        let m = usize(x[6usize])
        ac.panjer(usize(x[3usize]), x[4usize], x[5usize], x[7usize..7usize + m], 500usize, fs[0usize..512usize])
        n = ac.panjer_len(fs[0usize..512usize], 0.5f64 - 0.000001f64 + 0.5f64, 500usize)
        var k = 0usize
        while k < n {
            xs[k] = f64(k)
            k += 1usize
        }
    } else if src == 1usize {
        let m = usize(x[3usize])
        let np = usize(x[4usize + m])
        n = (np - 1usize) * (m - 1usize) + 1usize
        ac.aggregate_convolution(x[5usize + m..5usize + m + np], x[4usize..4usize + m], n - 1usize, fs[0usize..128usize], wk[0usize..128usize])
        var k = 0usize
        while k < n {
            xs[k] = f64(k)
            k += 1usize
        }
    } else {
        var gr: rr.Rng = zero
        rr.seed(&gr, i64(x[3usize]))
        let ns = usize(x[4usize])
        let (smp, se) = mem.alloc[f64](ar, ns)
        if se != ok { os.exit(30) }
        let re = ac.rcompound_pois_gamma(ar, &gr, ns, x[5usize], x[6usize], x[7usize], smp)
        if re != ok { os.exit(31) }
        n = ac.agg_sim_table(smp, xs[0usize..512usize], fs[0usize..512usize])
    }
    // R's cumsum accumulates in a long double and rounds each partial sum to double
    var run = ld.ld_zero()
    var k = 0usize
    while k < n {
        run = ld.ld_add(run, ld.ld_from(fs[k]))
        ys[k] = ld.ld_to(run)
        if ys[k] > 1.0f64 { ys[k] = 1.0f64 }
        k += 1usize
    }
    if stat == 2usize { ret ac.agg_cte(xs[0usize..n], fs[0usize..n], ys[0usize..n], p) }
    ret ac.agg_inv(xs[0usize..n], ys[0usize..n], p, stat == 1usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/actuar4.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
