// e.algo.stat.fpc_dip and the dip methods of fpc_ridge.merge_ridge against fpc. tests/oracle/fpc_dip.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_dip`; the layout is at the top of scripts/r_oracle/groups/fpc_dip.R.

use e.algo.rand.r as rg
use e.algo.stat.fpc_dip as fd
use e.algo.stat.fpc_ridge as fr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn is(c: *const oracle.Case, s: str) -> bool {
    if c.name.len != s.len { ret false }
    var i = 0usize
    while i < s.len {
        if c.name[i] != s[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if is(c, "ui") {
        if fd.unimodal_ind(z) { ret 1.0f64 }
        ret 0.0f64
    }
    var g: rg.Rng = zero
    if is(c, "dt") {
        rg.seed(&g, i64(z[0usize]))
        let x = z[3usize..]
        let (xs, e0) = fd.sort_copy(a, x)
        if e0 != ok { os.exit(4) }
        let (pv, bw, e1) = fd.dipp_tantrum(a, &g, x, dipval(a, xs), usize(z[1usize]))
        if e1 != ok { os.exit(5) }
        if usize(z[2usize]) == 0usize { ret pv }
        ret bw
    }
    if is(c, "dt2") {
        rg.seed(&g, i64(z[0usize]))
        let n1 = usize(z[2usize])
        let x1 = z[4usize..4usize + n1]
        let x2 = z[4usize + n1..]
        let (xs1, e0) = fd.sort_copy(a, x1)
        let (xs2, e1) = fd.sort_copy(a, x2)
        if e0 != ok || e1 != ok { os.exit(4) }
        let (pv1, bw1, e2) = fd.dipp_tantrum(a, &g, x1, dipval(a, xs1), usize(z[1usize]))
        let (pv2, bw2, e3) = fd.dipp_tantrum(a, &g, x2, dipval(a, xs2), usize(z[1usize]))
        if e2 != ok || e3 != ok { os.exit(5) }
        // the first entry of each pair is the second call, the second is the first call plus 7
        if usize(z[3usize]) == 0usize { ret pv2 }
        ret pv1 + 7.0f64
    }
    if is(c, "dm") {
        rg.seed(&g, i64(z[0usize]))
        let n = usize(z[1usize])
        let p = usize(z[2usize])
        let (lab, e0) = mem.alloc[usize](a, n)
        if e0 != ok { os.exit(4) }
        var i = 0usize
        while i < n {
            lab[i] = usize(z[3usize + i])
            i += 1usize
        }
        let (pv, e1) = fd.diptest_multi(a, &g, z[3usize + n..], n, p, lab, 100usize)
        if e1 != ok { os.exit(5) }
        ret pv
    }
    // mnd / mnt
    rg.seed(&g, i64(z[0usize]))
    let n = usize(z[1usize])
    let d = usize(z[2usize])
    let k = usize(z[3usize])
    let (pr, e1) = mem.alloc[f64](a, k)
    let (mu, e2) = mem.alloc[f64](a, k * d)
    let (sg, e3) = mem.alloc[f64](a, k * d * d)
    let (zz, e4) = mem.alloc[f64](a, n * k)
    let (mp, e5) = mem.alloc[usize](a, k)
    let (vl, e6) = mem.alloc[f64](a, k + 2usize)
    let (cl, e7) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { os.exit(5) }
    var o = 7usize
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
    let xo = o
    o += n * d
    q = 0usize
    while q < n {
        cl[q] = usize(z[o + q])
        q += 1usize
    }
    if usize(z[6usize]) == 100usize {
        let (cn1, e8) = mem.alloc[f64](a, k * k)
        let (rt1, e9) = mem.alloc[f64](a, k * k)
        if e8 != ok || e9 != ok { os.exit(5) }
        let e10 = fr.ridge_diag(a, pr, mu, sg, d, k, true, z[5usize], 0.0f64, false, cn1, rt1)
        if e10 != ok { os.exit(8) }
        var cc = 0usize
        var r1 = 0usize
        while r1 < k {
            var c1 = r1 + 1usize
            while c1 < k {
                if rt1[r1 * k + c1] == 1.0f64 { cc += 1usize }
                c1 += 1usize
            }
            r1 += 1usize
        }
        ret f64(cc)
    }
    let (nv, em) = fr.merge_ridge(a, z[xo..xo + n * d], n, d, k, pr, mu, sg, zz, z[4usize], z[5usize], true, mp, vl, true, cl, &g)
    if em != ok { os.exit(8) }
    let stat = usize(z[6usize])
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
    if stat >= 5usize { ret vl[stat - 5usize] }
    if stat == 3usize {
        var mx = 0usize
        q = 0usize
        while q < k {
            if mp[q] > mx { mx = mp[q] }
            q += 1usize
        }
        ret f64(mx)
    }
    q = 0usize
    while q < n {
        t += f64(mp[cl[q] - 1usize]) * f64(q + 1usize)
        q += 1usize
    }
    ret t
}

fn dipval(a: *mem.Arena, xs: []const f64) -> f64 {
    let (r, e) = fd.dipof(a, xs)
    if e != ok { os.exit(9) }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_dip.json")
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
                var c2 = *c
                if c.args.len > 7usize { c2.args = c.args[0usize..7usize] }
                let _ = io.print(oracle.describe(a, &c2, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
