// e.algo.stat.fpc_ridge against fpc: ridgeline, piridge.zeroes, dridgeline, ridgeline.diagnosis and mergenormals (ridge.uni, ridge.ratio).
// tests/oracle/fpc_ridge.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_ridge`; the layouts are at the top of
// scripts/r_oracle/groups/fpc_ridge.R.

use e.algo.rand.r as rg
use e.algo.stat.fpc as fp
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
    if is(c, "rl") {
        let d = usize(z[0usize])
        let (s1i, e1) = mem.alloc[f64](a, d * d)
        let (s2i, e2) = mem.alloc[f64](a, d * d)
        let (out, e3) = mem.alloc[f64](a, d)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
        if fp.lu_inverse(a, z[2usize + 2usize * d..2usize + 2usize * d + d * d], d, s1i) != ok { os.exit(6) }
        if fp.lu_inverse(a, z[2usize + 2usize * d + d * d..2usize + 2usize * d + 2usize * d * d], d, s2i) != ok { os.exit(6) }
        if fr.ridgeline(a, z[1usize], z[2usize..2usize + d], z[2usize + d..2usize + 2usize * d], s1i, s2i, d, out) != ok { os.exit(7) }
        var s = 0.0f64
        var i = 0usize
        while i < d {
            s += f64(i + 1usize) * out[i]
            i += 1usize
        }
        ret s
    }
    if is(c, "pz") {
        let d = usize(z[0usize])
        let by = z[2usize]
        let what = usize(z[3usize])
        let la = 2usize * 1100usize
        let (roots, e1) = mem.alloc[f64](a, la)
        let (dv, e2) = mem.alloc[f64](a, la)
        if e1 != ok || e2 != ok { os.exit(5) }
        let o = 4usize
        let (nz, e3) = fr.piridge_zeroes(a, z[1usize], z[o..o + d], z[o + d..o + 2usize * d], z[o + 2usize * d..o + 2usize * d + d * d], z[o + 2usize * d + d * d..o + 2usize * d + 2usize * d * d], d, by, roots, dv)
        if e3 != ok { os.exit(7) }
        if what == 0usize { ret f64(nz) }
        var s = 0.0f64
        var i = 0usize
        while i < nz {
            if what == 1usize { s += f64(i + 1usize) * roots[i] } else { s += f64(i + 1usize) * dv[i] }
            i += 1usize
        }
        ret s
    }
    if is(c, "rd") {
        let d = usize(z[0usize])
        let k = usize(z[1usize])
        let by = z[2usize]
        let ratio = z[3usize] > 0.5f64
        let cutoff = z[4usize]
        let what = usize(z[5usize])
        let o = 6usize
        let (con, e1) = mem.alloc[f64](a, k * k)
        let (rat, e2) = mem.alloc[f64](a, k * k)
        if e1 != ok || e2 != ok { os.exit(5) }
        if fr.ridge_diag(a, z[o..o + k], z[o + k..o + k + k * d], z[o + k + k * d..], d, k, ratio, by, cutoff, ratio, con, rat) != ok { os.exit(7) }
        var s = 0.0f64
        var pos = 0usize
        var cc = 0usize
        while cc < k {
            var rr = 0usize
            while rr < cc {
                pos += 1usize
                if what == 0usize { s += f64(pos) * con[rr * k + cc] } else { s += f64(pos) * rat[rr * k + cc] }
                rr += 1usize
            }
            cc += 1usize
        }
        ret s
    }
    // mnu / mnr
    let n = usize(z[0usize])
    let d = usize(z[1usize])
    let k = usize(z[2usize])
    let (pr, e1) = mem.alloc[f64](a, k)
    let (mu, e2) = mem.alloc[f64](a, k * d)
    let (sg, e3) = mem.alloc[f64](a, k * d * d)
    let (zz, e4) = mem.alloc[f64](a, n * k)
    let (mp, e5) = mem.alloc[usize](a, k)
    let (vl, e6) = mem.alloc[f64](a, k + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { os.exit(5) }
    var o = 5usize
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
    var gg: rg.Rng = zero
    let cls = mp[0usize..0usize]
    let (nv, em) = fr.merge_ridge(a, z[o..o + n * d], n, d, k, pr, mu, sg, zz, z[3usize], z[4usize], c.name[2usize] == 114u8, mp, vl, false, cls, &gg)
    if em != ok { os.exit(8) }
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
    var cnt = 0usize
    var lab = 0usize
    while lab <= mx {
        var used = false
        q = 0usize
        while q < k {
            if mp[q] == lab { used = true }
            q += 1usize
        }
        if used { cnt += 1usize }
        lab += 1usize
    }
    ret f64(cnt)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_ridge.json")
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
            if failures <= 10usize {
                var c2 = *c
                c2.args = c.args[0usize..4usize]
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
