// e.algo.stat.fpc's bhattacharyya_dist against fpc. tests/oracle/fpc_bhat.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_bhat`; the layout is at the top of scripts/r_oracle/groups/fpc_bhat.R.

use e.algo.stat.fpc as fp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if c.name.len == 3usize {
        let n = usize(z[0usize])
        let d = usize(z[1usize])
        let k = usize(z[2usize])
        let cut = z[3usize]
        let (pr, e0) = mem.alloc[f64](a, k)
        let (mu, e1) = mem.alloc[f64](a, k * d)
        let (sg, e2) = mem.alloc[f64](a, k * d * d)
        let (zz, e3) = mem.alloc[f64](a, n * k)
        let (mp, e4) = mem.alloc[usize](a, k)
        let (vl, e5) = mem.alloc[f64](a, k + 1usize)
        if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
        var o = 4usize
        var q = 0usize
        while q < k {
            pr[q] = z[o + q]
            q += 1usize
        }
        o += k
        q = 0usize
        while q < k * d {
            mu[q] = z[o + q]
            q += 1usize
        }
        o += k * d
        q = 0usize
        while q < k * d * d {
            sg[q] = z[o + q]
            q += 1usize
        }
        o += k * d * d
        q = 0usize
        while q < n * k {
            zz[q] = z[o + q]
            q += 1usize
        }
        o += n * k
        let (nv, em) = fp.merge_bhat(a, z[o..o + n * d], n, d, k, pr, mu, sg, zz, cut, mp, vl)
        if em != ok { ret 0.0f64 / 0.0f64 }
        let stat = usize(z[o + n * d])
        var t = 0.0f64
        if stat == 0usize { ret f64(nv) }
        if stat == 1usize {
            q = 0usize
            while q < nv {
                t += vl[q] * f64(q + 1usize)
                q += 1usize
            }
            ret t
        }
        if stat == 2usize {
            q = 0usize
            while q < k {
                t += f64(mp[q]) * f64(q + 1usize)
                q += 1usize
            }
            ret t
        }
        var mx = 0usize
        q = 0usize
        while q < k {
            if mp[q] > mx { mx = mp[q] }
            q += 1usize
        }
        ret f64(mx)
    }
    let d = usize(z[0usize])
    let (v, e) = fp.bhattacharyya_dist(a, z[1usize..1usize + d], z[1usize + d..1usize + 2usize * d], z[1usize + 2usize * d..1usize + 2usize * d + d * d], z[1usize + 2usize * d + d * d..1usize + 2usize * d + 2usize * d * d], d)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_bhat.json")
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
