// e.algo.stat.ksamples_steel against kSamples: Steel.test, jt.test, djt, pjt and qjt. tests/oracle/ksamples_steel.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ksamples_steel`; the case layouts are at the top of scripts/r_oracle/groups/ksamples_steel.R.

use e.algo.rand.r as rng
use e.algo.stat.ksamples_steel as st
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pick(v: []const f64, i: usize) -> f64 {
    if i >= 1usize && i <= v.len { ret v[i - 1usize] }
    ret nan()
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var g: rng.Rng = zero
    if c.name[0usize] == 115u8 {
        // stl (alt, method, seed, Nsim, cc, part, idx, k, sizes..., data...)
        rng.seed(&g, i64(x[2usize]))
        let k = usize(x[7usize])
        let (sz, e0) = mem.alloc[usize](a, k)
        if e0 != ok { os.exit(5) }
        var tot = 0usize
        var i = 0usize
        while i < k {
            sz[i] = usize(x[8usize + i])
            tot += sz[i]
            i += 1usize
        }
        let (r, e) = st.kx_steel_test(a, &g, x[8usize + k..8usize + k + tot], sz, i64(x[0usize]), x[4usize] != 0.0f64, usize(x[1usize]), true, usize(x[3usize]))
        if e != ok { os.exit(6) }
        let part = usize(x[5usize])
        let idx = usize(x[6usize])
        if part == 0usize { ret r.stat }
        if part == 1usize { ret r.asym }
        if part == 2usize { ret r.p }
        if part == 3usize { ret pick(r.w, idx) }
        if part == 4usize { ret pick(r.wstand, idx) }
        if part == 5usize { ret pick(r.asymadj, idx) }
        if part == 6usize { ret pick(r.padj, idx) }
        if part == 7usize { ret pick(r.dist, idx) }
        if part == 8usize { ret f64(r.dist.len) }
        if part == 9usize { ret pick(r.mu, idx) }
        if part == 10usize { ret pick(r.tau, idx) }
        if part == 11usize { ret r.sig0 }
        if part == 12usize { ret pick(r.sig, idx) }
        ret f64(r.nties)
    }
    if c.name[0usize] == 106u8 && c.name[2usize] == 116u8 {
        // jtt (method, seed, Nsim, part, idx, k, sizes..., data...)
        rng.seed(&g, i64(x[1usize]))
        let k = usize(x[5usize])
        let (sz, e0) = mem.alloc[usize](a, k)
        if e0 != ok { os.exit(5) }
        var tot = 0usize
        var i = 0usize
        while i < k {
            sz[i] = usize(x[6usize + i])
            tot += sz[i]
            i += 1usize
        }
        let (r, e) = st.kx_jt_test(a, &g, x[6usize + k..6usize + k + tot], sz, usize(x[0usize]), true, usize(x[2usize]))
        if e != ok { os.exit(6) }
        let part = usize(x[3usize])
        if part == 0usize { ret r.stat }
        if part == 1usize { ret r.mu }
        if part == 2usize { ret r.sig }
        if part == 3usize { ret r.asym }
        if part == 4usize { ret r.p }
        if part == 5usize { ret pick(r.dist, usize(x[4usize])) }
        if part == 6usize { ret f64(r.dist.len) }
        ret f64(r.nties)
    }
    // jtd (which, x or p, k, nn...)
    let k = usize(x[2usize])
    let (nn, e0) = mem.alloc[usize](a, k)
    if e0 != ok { os.exit(5) }
    var i = 0usize
    while i < k {
        nn[i] = usize(x[3usize + i])
        i += 1usize
    }
    var v = 0.0f64
    var e = ok
    if x[0usize] == 0.0f64 {
        let (r, er) = st.kx_djt(a, x[1usize], nn)
        v = r
        e = er
    } else {
        if x[0usize] == 1.0f64 {
            let (r, er) = st.kx_pjt(a, x[1usize], nn)
            v = r
            e = er
        } else {
            let (r, er) = st.kx_qjt(a, x[1usize], nn)
            v = r
            e = er
        }
    }
    if e != ok { os.exit(6) }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ksamples_steel.json")
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
