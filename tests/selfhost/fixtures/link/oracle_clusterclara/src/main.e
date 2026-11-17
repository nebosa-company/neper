// e.algo.stat.clusterpam (clara) against cluster::clara. tests/oracle/clusterclara.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clusterclara`; the argument layout is at the top of
// scripts/r_oracle/groups/clusterclara.R.

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
    let samples = usize(x[3usize])
    let sampsize = usize(x[4usize])
    let metric = usize(x[5usize])
    let stand = x[6usize] != 0.0f64
    let rng_r = x[7usize] != 0.0f64
    let seed = i64(x[8usize])
    let pam_like = x[9usize] != 0.0f64
    let correct_d = x[10usize] != 0.0f64
    let (m, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n * p {
        m[i] = x[11usize + i]
        if m[i] < 0.0f64 - 999000.0f64 { m[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    if stand {
        if cd.stand_meanabsdev(a, m, n, p) != ok { os.exit(6) }
    }
    var rg: rr.Rng = zero
    rr.seed(&rg, seed)
    let (r, e2) = cp.clara_core(a, m, n, p, k, samples, sampsize, metric, rng_r, pam_like, correct_d, &rg)
    if e2 != ok { os.exit(7) }
    if r.jstop != 0usize { os.exit(8) }
    let nm = c.name
    if str.eq(nm, "sample") { ret wsum_u(r.sample, sampsize) }
    if str.eq(nm, "imed") { ret wsum_u(r.imed, k) }
    if str.eq(nm, "clu") { ret wsum_u(r.clustering, n) }
    if str.eq(nm, "obj") { ret r.obj }
    if str.eq(nm, "size") { ret wsum_u(r.size, k) }
    if str.eq(nm, "maxdis") { ret wsum_f(r.maxdis, k) }
    if str.eq(nm, "avdis") { ret wsum_f(r.avdis, k) }
    if str.eq(nm, "ratdis") { ret wsum_f(r.ratdis, k) }
    if str.eq(nm, "avsil") { ret wsum_f(r.avsil, k) }
    if str.eq(nm, "ttsil") { ret r.ttsil }
    if str.eq(nm, "sil1") { ret wsum_f(r.silinf[0usize..sampsize], sampsize) }
    if str.eq(nm, "sil2") { ret wsum_f(r.silinf[sampsize..2usize * sampsize], sampsize) }
    if str.eq(nm, "sil3") { ret wsum_f(r.silinf[2usize * sampsize..3usize * sampsize], sampsize) }
    if str.eq(nm, "sil4") { ret wsum_f(r.silinf[3usize * sampsize..4usize * sampsize], sampsize) }
    os.exit(9)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clusterclara.json")
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
