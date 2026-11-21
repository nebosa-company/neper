// tgp.design on a treed fit, against R: the best tree of e.algo.stat.tgp_tree (btlm and btgp) cuts the candidates and
// the data, dopt.gp runs in each part. tests/oracle/tgpdesigntree.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tgpdesigntree`.
// A case is (data seed, seed, design seed, n, d, nn, ncand, howmany, B, T, E, model, k): the k-th design row's Xcand
// number ("design") or the number of design rows ("ndesign").

use e.algo.rand.r as rr
use e.algo.stat.tgp_tree as tt
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn same_key(a: []const f64, b: []const f64) -> bool {
    var i = 0usize
    while i < 12usize {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tgpdesigntree.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    let group = mem.mark(a)
    var prev: []f64 = zero
    var have = false
    var des: []i64 = zero
    var nd = 0usize
    var oe: err = ok
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if !have || !same_key(x, prev) {
            mem.reset(a, group)
            let n = usize(x[3usize])
            let d = usize(x[4usize])
            let nn = usize(x[5usize])
            let ncand = usize(x[6usize])
            let md = usize(x[11usize])
            var r: rr.Rng = zero
            rr.seed(&r, i64(x[0usize]))
            let (xm, e1) = mem.alloc[f64](a, n * d)
            let (zv, e2) = mem.alloc[f64](a, n)
            let (xx, e3) = mem.alloc[f64](a, nn * d)
            let (xc, e4) = mem.alloc[f64](a, ncand * d)
            if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(5) }
            var i = 0usize
            var j = 0usize
            while j < d {
                i = 0usize
                while i < n {
                    xm[i * d + j] = rr.runif(&r, 0.0f64, 1.0f64)
                    i += 1usize
                }
                j += 1usize
            }
            i = 0usize
            while i < n {
                var x2 = 0.0f64
                if d > 1usize { x2 = xm[i * d + 1usize] }
                var s = 0.0f64
                if md == 0usize {
                    if xm[i * d] < 0.4f64 {
                        s = 1.0f64 + 2.0f64 * x2
                    } else {
                        s = 0.0f64 - 1.0f64 + math.sin[f64](8.0f64 * xm[i * d]) + 0.5f64 * x2
                    }
                } else {
                    if xm[i * d] < 0.45f64 {
                        s = 1.0f64 + 0.5f64 * x2
                    } else {
                        s = 4.0f64 + math.sin[f64](10.0f64 * xm[i * d]) + 0.5f64 * x2
                    }
                }
                zv[i] = s
                i += 1usize
            }
            var noise = 0.1f64
            if md == 1usize { noise = 0.02f64 }
            i = 0usize
            while i < n {
                zv[i] += noise * rr.norm(&r)
                i += 1usize
            }
            j = 0usize
            while j < d {
                i = 0usize
                while i < nn {
                    xx[i * d + j] = rr.runif(&r, 0.0f64, 1.0f64)
                    i += 1usize
                }
                j += 1usize
            }
            j = 0usize
            while j < d {
                i = 0usize
                while i < ncand {
                    xc[i * d + j] = rr.runif(&r, 0.0f64, 1.0f64)
                    i += 1usize
                }
                j += 1usize
            }
            rr.seed(&r, i64(x[1usize]))
            var res: tt.Tgt = zero
            var re: err = ok
            if md == 0usize {
                let (r1, e5) = tt.btlm(a, &r, xm, zv, xx, n, d, nn, usize(x[8usize]), usize(x[9usize]), usize(x[10usize]), true, true, true, false, false, 0.5f64, 2.0f64)
                res = r1
                re = e5
            } else {
                let (r2, e6) = tt.btgp(a, &r, xm, zv, xx, n, d, nn, usize(x[8usize]), usize(x[9usize]), usize(x[10usize]), true, true, true, false, false, 0.5f64, 2.0f64, 0.0f64, 0.2f64, 0.7f64)
                res = r2
                re = e6
            }
            oe = re
            nd = 0usize
            if re == ok {
                rr.seed(&r, i64(x[2usize]))
                let (dd, cn, de) = tt.design_treed(a, &r, usize(x[7usize]), xc, ncand, xm, n, d, res.map_var, res.map_val, res.map_n, 5000usize)
                oe = de
                des = dd
                nd = cn
            }
            prev = x
            have = true
        }
        var got = 0.0f64 / 0.0f64
        if oe == ok {
            if c.name.len == 7usize {
                got = f64(nd)
            } else {
                let k = usize(x[12usize])
                if k < nd { got = f64(des[k]) }
            }
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 15usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
