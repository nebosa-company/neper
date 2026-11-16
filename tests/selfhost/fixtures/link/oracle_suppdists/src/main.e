// e.algo.stat.suppdists against SuppDists: inverse Gaussian, Kendall, Spearman (exact) and Johnson distributions.
// tests/oracle/suppdists.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R suppdists`; the
// layout is at the top of scripts/r_oracle/groups/suppdists.R.

use e.algo.stat.suppdists as sd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nm = c.name
    let nan = 0.0f64 / 0.0f64
    if str.eq(nm, "ig_d") { ret sd.dinv_gauss(z[2usize], z[0usize], z[1usize]) }
    if str.eq(nm, "ig_p") { ret sd.pinv_gauss(z[2usize], z[0usize], z[1usize]) }
    if str.eq(nm, "ig_q") { ret sd.qinv_gauss(z[2usize], z[0usize], z[1usize]) }
    if str.eq(nm, "pc_d") { ret sd.fcorrelation(z[2usize], z[0usize], i64(z[1usize])) }
    if str.eq(nm, "pc_p") { ret sd.pcorrelation(z[2usize], z[0usize], i64(z[1usize])) }
    if str.eq(nm, "pc_q") { ret sd.qcorrelation(z[2usize], z[0usize], i64(z[1usize])) }
    if str.starts_with(nm, "kw_") {
        let nsc = z[0usize] == 1.0f64
        let kc = i64(z[1usize])
        let kn = i64(z[2usize])
        if str.eq(nm, "kw_p") { ret sd.pkruskal_wallis(z[4usize], kc, kn, z[3usize], nsc) }
        if str.eq(nm, "kw_u") { ret sd.qkruskal_wallis_upper(z[4usize], kc, kn, z[3usize], nsc) }
        if str.eq(nm, "kw_q") { ret sd.xkruskal_wallis(z[4usize], kc, kn, z[3usize], nsc) }
        ret sd.fkruskal_wallis(z[4usize], kc, kn, z[3usize], nsc)
    }
    if str.eq(nm, "gh_d") { ret sd.ghyper_d(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.eq(nm, "gh_p") { ret sd.ghyper_p(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.eq(nm, "gh_q") { ret sd.ghyper_q(z[3usize], z[0usize], z[1usize], z[2usize]) }
    if str.starts_with(nm, "ken_") || str.starts_with(nm, "sp_") {
        let n = usize(z[0usize])
        var v = 0.0f64
        var e = ok
        if str.eq(nm, "ken_d") {
            let (r, re) = sd.dkendall(a, z[1usize], n)
            v = r
            e = re
        } else if str.eq(nm, "ken_p") {
            let (r, re) = sd.pkendall(a, z[1usize], n)
            v = r
            e = re
        } else if str.eq(nm, "sp_d") {
            let (r, re) = sd.dspearman(a, z[1usize], n)
            v = r
            e = re
        } else {
            let (r, re) = sd.pspearman(a, z[1usize], n)
            v = r
            e = re
        }
        if e != ok { ret nan }
        ret v
    }
    let kind = u8(z[0usize])
    if str.eq(nm, "jo_d") { ret sd.djohnson(z[5usize], z[1usize], z[2usize], z[3usize], z[4usize], kind) }
    if str.eq(nm, "jo_p") { ret sd.pjohnson(z[5usize], z[1usize], z[2usize], z[3usize], z[4usize], kind) }
    ret sd.qjohnson(z[5usize], z[1usize], z[2usize], z[3usize], z[4usize], kind)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/suppdists.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
