// e.algo.stat.clusterpam (pam) against cluster::pam. tests/oracle/clusterpam.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clusterpam`; the argument layout is at the top of
// scripts/r_oracle/groups/clusterpam.R.

use e.algo.rand.r as rr
use e.algo.stat.clusterdiss as cd
use e.algo.stat.clusterpam as cp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum_f(v: []const f64, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn wsum_u(v: []const usize, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += f64(v[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let k = usize(x[2usize])
    let pamonce = usize(x[3usize])
    let doswap = x[4usize] != 0.0f64
    let metric = usize(x[5usize])
    let stand = x[6usize] != 0.0f64
    let seed = i64(x[7usize])
    let nstart = usize(x[8usize])
    let diss = x[9usize] != 0.0f64
    let nmed = usize(x[10usize])
    let (med, e1) = mem.alloc[usize](a, nmed)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < nmed {
        med[i] = usize(x[11usize + i])
        i += 1usize
    }
    let base = 11usize + nmed
    var dys: []f64 = zero
    if diss {
        let (v, e2) = cd.cdv_from_dist(a, x[base..base + n * (n - 1usize) / 2usize], n)
        if e2 != ok { os.exit(6) }
        dys = v
    } else {
        let (m, e3) = mem.alloc[f64](a, n * p)
        if e3 != ok { os.exit(7) }
        i = 0usize
        while i < n * p {
            m[i] = x[base + i]
            if m[i] < 0.0f64 - 999000.0f64 { m[i] = 0.0f64 / 0.0f64 }
            i += 1usize
        }
        if stand {
            if cd.stand_meanabsdev(a, m, n, p) != ok { os.exit(8) }
        }
        let (v, e4) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
        if e4 != ok { os.exit(9) }
        if cd.dysta(m, n, p, metric, v) != 0usize { os.exit(10) }
        dys = v
    }
    var r: cp.PamOut = zero
    if seed > 0i64 {
        var rg: rr.Rng = zero
        rr.seed(&rg, seed)
        let (o, e5) = cp.pam_random(a, dys, n, k, nstart, doswap, pamonce, true, &rg)
        if e5 != ok { os.exit(11) }
        r = o
    } else {
        let (o, e6) = cp.pam_core(a, dys, n, k, med, doswap, pamonce, true)
        if e6 != ok { os.exit(12) }
        r = o
    }
    let nm = c.name
    if str.eq(nm, "obj0") { ret r.obj0 }
    if str.eq(nm, "obj1") { ret r.obj1 }
    if str.eq(nm, "med") { ret wsum_u(r.med, k) }
    if str.eq(nm, "clu") { ret wsum_u(r.clu, n) }
    if str.eq(nm, "isol") { ret wsum_u(r.isol, k) }
    if str.eq(nm, "avsil") { ret wsum_f(r.avsil, k) }
    if str.eq(nm, "ttsil") { ret r.ttsil }
    if str.eq(nm, "cs1") { ret wsum_f(r.clusinf[0usize..k], k) }
    if str.eq(nm, "cs2") { ret wsum_f(r.clusinf[k..2usize * k], k) }
    if str.eq(nm, "cs3") { ret wsum_f(r.clusinf[2usize * k..3usize * k], k) }
    if str.eq(nm, "cs4") { ret wsum_f(r.clusinf[3usize * k..4usize * k], k) }
    if str.eq(nm, "cs5") { ret wsum_f(r.clusinf[4usize * k..5usize * k], k) }
    if str.eq(nm, "sil1") { ret wsum_f(r.silinf[0usize..n], n) }
    if str.eq(nm, "sil2") { ret wsum_f(r.silinf[n..2usize * n], n) }
    if str.eq(nm, "sil3") { ret wsum_f(r.silinf[2usize * n..3usize * n], n) }
    if str.eq(nm, "sil4") { ret wsum_f(r.silinf[3usize * n..4usize * n], n) }
    os.exit(13)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clusterpam.json")
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
