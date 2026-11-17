// e.algo.stat.ksamples_steel's SteelConfInt against kSamples. tests/oracle/ksamples_ci.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ksamples_ci`; the case layout is at the top of scripts/r_oracle/groups/ksamples_ci.R.

use e.algo.rand.r as rng
use e.algo.stat.ksamples_steel as st
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn pick(v: []const f64, i: usize) -> f64 {
    if i >= 1usize && i <= v.len { ret v[i - 1usize] }
    ret 0.0f64 / 0.0f64
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var g: rng.Rng = zero
    // sci (alt, conf, method, seed, Nsim, part, idx, k, sizes..., data...)
    rng.seed(&g, i64(x[3usize]))
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
    let (r, e) = st.kx_steel_ci(a, &g, x[8usize + k..8usize + k + tot], sz, x[1usize], usize(x[0usize]), usize(x[2usize]), usize(x[4usize]))
    if e != ok { os.exit(6) }
    let part = usize(x[5usize])
    let idx = usize(x[6usize])
    if part == 0usize { ret r.levelp }
    if part == 1usize { ret r.levelc }
    if part == 2usize { ret pick(r.lp, idx) }
    if part == 3usize { ret pick(r.up, idx) }
    if part == 4usize { ret pick(r.lc, idx) }
    if part == 5usize { ret pick(r.uc, idx) }
    if part == 6usize { ret pick(r.ellLp, idx) }
    if part == 7usize { ret pick(r.ellUp, idx) }
    if part == 8usize { ret pick(r.ellLc, idx) }
    if part == 9usize { ret pick(r.ellUc, idx) }
    if part == 10usize { ret r.levelXp }
    if part == 11usize { ret r.levelXc }
    if part == 12usize { ret pick(r.lxp, idx) }
    if part == 13usize { ret pick(r.uxp, idx) }
    if part == 14usize { ret pick(r.lxc, idx) }
    if part == 15usize { ret pick(r.uxc, idx) }
    if part == 16usize { ret pick(r.ellLXp, idx) }
    if part == 17usize { ret pick(r.ellUXp, idx) }
    if part == 18usize { ret pick(r.ellLXc, idx) }
    if part == 19usize { ret pick(r.ellUXc, idx) }
    ret f64(r.nties)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ksamples_ci.json")
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
