// e.algo.stat.posteriorpkg second half (rhat_basic, ess_sd, mcse_sd, ess_quantile, mcse_quantile, z_scale, summarise_draws, pareto_smooth) against posterior; layouts at the top of scripts/r_oracle/groups/posterior2.R and posterior3.R.

use e.algo.stat.posteriorpkg as pp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    if str.starts_with(nm, "ps_") {
        let s = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, s)
        if e != ok { os.exit(5) }
        let (k, mn, th, rt, pe) = pp.pareto_smooth(a, x[1usize..1usize + s], usize(x[1usize + s]), x[2usize + s], o)
        if pe != ok { os.exit(6) }
        if str.eq(nm, "ps_k") { ret k }
        if str.eq(nm, "ps_min") { ret mn }
        if str.eq(nm, "ps_thr") { ret th }
        if str.eq(nm, "ps_rate") { ret rt }
        var t = 0.0f64
        var i = 0usize
        while i < s {
            t += f64(i + 1usize) * o[i]
            i += 1usize
        }
        ret t / f64(s)
    }
    let nc = usize(x[0usize])
    let n = usize(x[1usize])
    let d = x[2usize..2usize + nc * n]
    if str.eq(nm, "rb") { ret pp.rhat_basic(a, d, nc, n, true) }
    if str.eq(nm, "rbn") { ret pp.rhat_basic(a, d, nc, n, false) }
    if str.eq(nm, "sd_ess") { ret pp.ess_sd(a, d, nc, n) }
    if str.eq(nm, "sd_mcse") { ret pp.mcse_sd(a, d, nc, n) }
    if str.eq(nm, "essq") { ret pp.ess_quantile(a, d, nc, n, x[2usize + nc * n]) }
    if str.eq(nm, "mcseq") { ret pp.mcse_quantile(a, d, nc, n, x[2usize + nc * n]) }
    if str.eq(nm, "zs") {
        let (z, e) = mem.alloc[f64](a, nc * n)
        if e != ok { os.exit(7) }
        if pp.z_scale(a, d, z) != ok { os.exit(8) }
        var t = 0.0f64
        var i = 0usize
        while i < nc * n {
            t += f64(i + 1usize) * z[i]
            i += 1usize
        }
        ret t
    }
    var o: [9]f64 = zero
    pp.summarise(a, d, nc, n, o[0usize..9usize])
    if str.eq(nm, "s_mean") { ret o[0usize] }
    if str.eq(nm, "s_median") { ret o[1usize] }
    if str.eq(nm, "s_sd") { ret o[2usize] }
    if str.eq(nm, "s_mad") { ret o[3usize] }
    if str.eq(nm, "s_q5") { ret o[4usize] }
    if str.eq(nm, "s_q95") { ret o[5usize] }
    if str.eq(nm, "s_rhat") { ret o[6usize] }
    if str.eq(nm, "s_essb") { ret o[7usize] }
    ret o[8usize]
}

fn run(a: *mem.Arena, path: str) -> usize {
    let (golden, load_error) = oracle.load(a, path)
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
    ret failures
}

fn main(a: *mem.Arena, args: []str) -> err {
    let f1 = run(a, "tests/oracle/posterior2.json")
    let f2 = run(a, "tests/oracle/posterior3.json")
    if f1 + f2 > 0usize { os.exit(1) }
    ret ok
}
