// e.algo.stat.tgp_blm against R's tgp::blm under set.seed. tests/oracle/tgpblm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tgpblm`.
// A case is (data seed, seed, n, d, nn, B, T, E, linear mean, m0r1, pred.n, improv, Ds2x, field, k): the k-th value
// of one posterior summary. The data are rebuilt from the data seed with R's generator, as the group script does.

use e.algo.rand.r as rr
use e.algo.stat.tgp_blm as blm
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn field_of(o: *blm.Blm, f: usize) -> []f64 {
    if f == 0usize { ret o.zz_mean }
    if f == 1usize { ret o.zz_q1 }
    if f == 2usize { ret o.zz_med }
    if f == 3usize { ret o.zz_q2 }
    if f == 4usize { ret o.zz_q }
    if f == 5usize { ret o.zz_s2 }
    if f == 6usize { ret o.zz_km }
    if f == 7usize { ret o.zz_ks2 }
    if f == 8usize { ret o.zz_vark }
    if f == 9usize { ret o.zp_mean }
    if f == 10usize { ret o.zp_q1 }
    if f == 11usize { ret o.zp_med }
    if f == 12usize { ret o.zp_q2 }
    if f == 13usize { ret o.zp_q }
    if f == 14usize { ret o.zp_s2 }
    if f == 15usize { ret o.zp_km }
    if f == 16usize { ret o.zp_ks2 }
    if f == 17usize { ret o.zp_vark }
    if f == 18usize { ret o.ds2x }
    if f == 19usize { ret o.improv }
    ret o.irank
}

fn same_key(a: []const f64, b: []const f64) -> bool {
    var i = 0usize
    while i < 13usize {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tgpblm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    let group = mem.mark(a)
    var prev: []f64 = zero
    var have = false
    var o: blm.Blm = zero
    var oe: err = ok
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if !have || !same_key(x, prev) {
            mem.reset(a, group)
            let n = usize(x[2usize])
            let d = usize(x[3usize])
            let nn = usize(x[4usize])
            var r: rr.Rng = zero
            rr.seed(&r, i64(x[0usize]))
            let (xm, e1) = mem.alloc[f64](a, n * d)
            let (zv, e2) = mem.alloc[f64](a, n)
            let (xx, e3) = mem.alloc[f64](a, nn * d)
            if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
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
                var s = math.sin[f64](4.0f64 * xm[i * d])
                j = 1usize
                while j < d {
                    s += 0.5f64 * f64(j + 1usize) * xm[i * d + j]
                    j += 1usize
                }
                zv[i] = s
                i += 1usize
            }
            i = 0usize
            while i < n {
                zv[i] += 0.1f64 * rr.norm(&r)
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
            rr.seed(&r, i64(x[1usize]))
            let (res, re) = blm.blm(a, &r, xm, zv, xx, n, d, nn, usize(x[5usize]), usize(x[6usize]), usize(x[7usize]), x[8usize] == 1.0f64, x[9usize] == 1.0f64, x[10usize] == 1.0f64, x[11usize] == 1.0f64, x[12usize] == 1.0f64)
            o = res
            oe = re
            prev = x
            have = true
        }
        var got = 0.0f64 / 0.0f64
        if oe == ok {
            let v = field_of(&o, usize(x[13usize]))
            got = v[usize(x[14usize])]
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
