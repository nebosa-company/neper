// e.algo.stat.algdesign against AlgDesign: gen.factorial and eval.design. tests/oracle/algdesign.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R algdesign`; the layout is at the top of
// scripts/r_oracle/groups/algdesign.R.

use e.algo.rand.r as rr
use e.algo.stat.algdesign as ad
use e.algo.stat.algdesign_fed as fed
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.starts_with(c.name, "gen_") {
        let nf = usize(z[0usize])
        let (lv, e1) = mem.alloc[usize](a, nf)
        if e1 != ok { ret nan }
        var runs = 1usize
        var f = 0usize
        while f < nf {
            lv[f] = usize(z[1usize + f])
            runs *= lv[f]
            f += 1usize
        }
        let (out, e2) = mem.alloc[f64](a, runs * nf)
        if e2 != ok { ret nan }
        let r = ad.gen_factorial(lv, z[1usize + nf] != 0.0f64, out)
        var s = 0.0f64
        var i = 0usize
        while i < r * nf {
            if str.eq(c.name, "gen_sum") { s += out[i] } else { s += f64(i + 1usize) * out[i] }
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "fed") {
        var g: rr.Rng = zero
        rr.seed(&g, i64(z[0usize]))
        let nn = usize(z[1usize])
        let kk = usize(z[2usize])
        let nt = usize(z[3usize])
        let crit = i64(z[4usize])
        let approx = z[5usize] != 0.0f64
        let nul = i64(z[6usize])
        let nrep = i64(z[7usize])
        var mxit = 100i64
        if approx { mxit = 1000i64 }
        let (rows, e3) = mem.alloc[i64](a, nn + 1usize)
        let (prop, e4) = mem.alloc[f64](a, nn + 1usize)
        if e3 != ok || e4 != ok { ret nan }
        var q = 0usize
        while q < nn + 1usize {
            rows[q] = 0i64
            prop[q] = 0.0f64
            q += 1usize
        }
        var dummy: [1]f64 = zero
        let (res, fe) = fed.fedorov(a, &g, z[8usize..8usize + nn * kk], nn, kk, nul == 0i64, nul, crit, false, dummy[0usize..0usize], false, 0usize, approx, nt, mxit, nrep, 1.0f64, 1.0f64, rows, prop)
        if fe != ok || res.errcode != 0i64 { ret nan }
        let what = usize(z[8usize + nn * kk])
        if what == 0usize { ret res.dd }
        if what == 1usize { ret res.aa }
        if what == 2usize { ret res.ii }
        if what == 3usize {
            let g3 = res.gg
            ret math.floor[f64](g3 * 1000.0f64 + 0.5f64) / 1000.0f64
        }
        // the sorted 1-based row numbers of the design
        let (srt, e5) = mem.alloc[i64](a, nt)
        if e5 != ok { ret nan }
        q = 0usize
        while q < nt {
            srt[q] = 1i64 + rows[q] % i64(nn)
            q += 1usize
        }
        var i = 1usize
        while i < nt {
            let v = srt[i]
            var j = i
            while j > 0usize && srt[j - 1usize] > v {
                srt[j] = srt[j - 1usize]
                j -= 1usize
            }
            srt[j] = v
            i += 1usize
        }
        ret f64(srt[what - 4usize])
    }
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let nc = usize(z[2usize])
    let x = z[3usize..3usize + n * k]
    let cand = z[3usize + n * k..3usize + n * k + nc * k]
    let q = usize(z[3usize + n * k + nc * k])
    let (r, e) = ad.eval_design(a, x, n, k, cand, nc)
    if e != ok { ret nan }
    if q == 0usize { ret r.determinant }
    if q == 1usize { ret r.a }
    if q == 2usize { ret r.i }
    if q == 3usize { ret r.geff }
    if q == 4usize { ret r.deff }
    if q == 5usize { ret r.diagonality }
    ret r.gmean_var
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/algdesign.json")
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
