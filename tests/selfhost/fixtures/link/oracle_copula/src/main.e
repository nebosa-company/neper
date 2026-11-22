// e.algo.stat.copulapkg against copula: Archimedean, normal and t copulas, tail dependence, pobs, empirical copula, itau/irho fits and rCopula.
// tests/oracle/copula.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R copula`; the layout is at the top of scripts/r_oracle/groups/copula.R.

use e.algo.rand.r as rr
use e.algo.stat.copulapkg as cp
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nm = c.name
    if str.eq(nm, "d") { ret cp.dcop(usize(z[0usize]), z[1usize], z[2usize], z[3usize]) }
    if str.eq(nm, "p") { ret cp.pcop(usize(z[0usize]), z[1usize], z[2usize], z[3usize]) }
    if str.eq(nm, "tau") { ret cp.ktau(usize(z[0usize]), z[1usize]) }
    if str.eq(nm, "rho_frank") { ret cp.rho_frank(z[1usize]) }
    if str.eq(nm, "lam") { ret cp.lambda_arch(usize(z[0usize]), z[1usize], z[2usize] > 0.5f64) }
    if str.eq(nm, "dn") { ret cp.dnorm_cop(z[0usize], z[2usize], z[3usize]) }
    if str.eq(nm, "pn") { ret cp.pnorm_cop(z[0usize], z[2usize], z[3usize]) }
    if str.eq(nm, "dt") { ret cp.dt_cop(a, z[0usize], z[1usize], z[2usize], z[3usize]) }
    if str.eq(nm, "pt") { ret cp.pt_cop(z[0usize], z[1usize], z[2usize], z[3usize]) }
    if str.eq(nm, "taun") { ret cp.tau_norm(z[0usize]) }
    if str.eq(nm, "rhon") { ret cp.rho_norm(z[0usize]) }
    if str.eq(nm, "lamt") { ret cp.lambda_t(z[0usize], z[1usize]) }
    if str.eq(nm, "itaun") { ret cp.itau_norm(z[0usize]) }
    if str.eq(nm, "irhon") { ret cp.irho_norm(z[0usize]) }
    if str.eq(nm, "itauc") { ret cp.itau_clayton(z[0usize]) }
    if str.eq(nm, "itaug") { ret cp.itau_gumbel(z[0usize]) }
    if str.eq(nm, "pobs") {
        let xs = z[1usize..z.len]
        let (o, e) = mem.alloc[f64](a, xs.len)
        if e != ok { os.exit(5) }
        cp.pobs(xs, o)
        ret o[usize(z[0usize]) - 1usize]
    }
    if str.eq(nm, "emp") {
        let n = usize(z[2usize])
        let (u, e1) = mem.alloc[f64](a, n)
        let (v, e2) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok { os.exit(5) }
        cp.pobs(z[3usize..3usize + n], u)
        cp.pobs(z[3usize + n..3usize + 2usize * n], v)
        ret cp.emp_cop(u, v, z[0usize], z[1usize])
    }
    if str.eq(nm, "fit") {
        let n = usize(z[1usize])
        let kind = usize(z[0usize])
        let x = z[2usize..2usize + n]
        let y = z[2usize + n..2usize + 2usize * n]
        let (u, e1) = mem.alloc[f64](a, n)
        let (v, e2) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok { os.exit(5) }
        cp.pobs(x, u)
        cp.pobs(y, v)
        if kind == 0usize { ret cp.itau_norm(cp.kendall(u, v)) }
        if kind == 1usize { ret cp.irho_norm(cp.spearman(a, u, v)) }
        if kind == 2usize { ret cp.itau_clayton(cp.kendall(u, v)) }
        if kind == 3usize { ret cp.itau_gumbel(cp.kendall(u, v)) }
        if kind == 4usize { ret cp.itau_arch(1usize, cp.kendall(u, v)) }
        if kind == 5usize { ret cp.itau_arch(4usize, cp.kendall(u, v)) }
        if kind == 6usize { ret cp.itau_arch(3usize, cp.kendall(u, v)) }
        if kind == 10usize { ret cp.itau_norm(cp.kendall(u, v)) }

        if kind == 8usize { ret cp.irho_clayton(a, cp.spearman(a, u, v)) }
        if kind == 9usize { ret cp.irho_gumbel(a, cp.spearman(a, u, v)) }
        ret cp.irho_frank(cp.spearman(a, u, v))
    }
    if str.eq(nm, "fitml") {
        let n = usize(z[1usize])
        let kind = usize(z[0usize])
        let (u, e1) = mem.alloc[f64](a, n)
        let (v, e2) = mem.alloc[f64](a, n)
        let (uv, e3) = mem.alloc[f64](a, 2usize * n)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
        cp.pobs(z[2usize..2usize + n], u)
        cp.pobs(z[2usize + n..2usize + 2usize * n], v)
        var i = 0usize
        while i < n {
            uv[2usize * i] = u[i]
            uv[2usize * i + 1usize] = v[i]
            i += 1usize
        }
        let tau = cp.kendall(u, v)
        var st = [2]f64{0.0f64, 4.0f64}
        if kind == 0usize { st[0usize] = cp.itau_clayton(tau) }
        if kind == 1usize { st[0usize] = cp.itau_gumbel(tau) }
        if kind == 2usize || kind == 6usize { st[0usize] = cp.itau_norm(tau) }
        if kind == 3usize { st[0usize] = cp.itau_arch(1usize, tau) }
        if kind == 4usize { st[0usize] = cp.itau_arch(4usize, tau) }
        if kind == 5usize { st[0usize] = cp.itau_arch(3usize, tau) }
        let _ = cp.fit_ml(a, kind, uv, n, st[0usize..2usize])
        ret st[usize(z[2usize + 2usize * n]) - 1usize]
    }
    if str.eq(nm, "mv_d") || str.eq(nm, "mv_p") || str.eq(nm, "mv_r") {
        let ck = usize(z[0usize])
        let mk0 = usize(z[3usize])
        let mk1 = usize(z[4usize])
        let p0 = z[5usize..7usize]
        let p1 = z[7usize..9usize]
        if str.eq(nm, "mv_d") {
            let l = cp.dmvdc_log(a, ck, z[1usize], z[2usize], mk0, p0, mk1, p1, z[9usize], z[10usize])
            if z[11usize] > 0.5f64 { ret l }
            ret math.exp[f64](l)
        }
        if str.eq(nm, "mv_p") { ret cp.pmvdc(ck, z[1usize], z[2usize], mk0, p0, mk1, p1, z[9usize], z[10usize]) }
        var gm: rr.Rng = zero
        rr.seed(&gm, i64(z[9usize]))
        let mm = cp.rmvdc(a, &gm, usize(z[10usize]), ck, z[1usize], z[2usize], mk0, p0, mk1, p1)
        ret mm[(usize(z[11usize]) - 1usize) * 2usize + usize(z[12usize]) - 1usize]
    }
    if str.eq(nm, "mv_fit") {
        let ck = usize(z[0usize])
        let mk0 = usize(z[2usize])
        let mk1 = usize(z[3usize])
        let n = usize(z[4usize])
        let q = cp.m_np(mk0) + cp.m_np(mk1) + 1usize
        var st = [8]f64{0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64}
        var j = 0usize
        while j < q {
            st[j] = z[6usize + j]
            j += 1usize
        }
        let (xs, ex) = mem.alloc[f64](a, 2usize * n)
        if ex != ok { os.exit(5) }
        j = 0usize
        while j < n {
            xs[2usize * j] = z[6usize + q + j]
            xs[2usize * j + 1usize] = z[6usize + q + n + j]
            j += 1usize
        }
        let _ = cp.fit_mvdc(a, ck, z[1usize], mk0, mk1, xs, n, st[0usize..q])
        ret st[usize(z[5usize]) - 1usize]
    }
    if str.eq(nm, "hd_d") {
        let d = usize(z[3usize])
        let u = z[4usize..4usize + d]
        let kind = usize(z[0usize])
        if kind == 0usize { ret cp.ldclayton_d(z[1usize], u) }
        if kind == 2usize { ret cp.ldnorm_d(a, z[1usize], u) }
        ret cp.ldt_d(a, z[1usize], z[2usize], u)
    }
    if str.eq(nm, "hd_p") { ret cp.pcop_d(usize(z[0usize]), z[1usize], z[3usize..3usize + usize(z[2usize])]) }
    if str.eq(nm, "hd_r") {
        let d = usize(z[3usize])
        let n = usize(z[5usize])
        let kind = usize(z[0usize])
        var gh: rr.Rng = zero
        rr.seed(&gh, i64(z[4usize]))
        var mh: []f64 = zero
        if kind == 0usize { mh = cp.rcop_clayton_d(a, &gh, n, d, z[1usize]) }
        if kind == 1usize { mh = cp.rcop_gumbel_d(a, &gh, n, d, z[1usize]) }
        if kind == 2usize { mh = cp.rcop_norm_d(a, &gh, n, d, z[1usize]) }
        if kind == 3usize { mh = cp.rcop_frank_d(a, &gh, n, d, z[1usize]) }
        if kind == 4usize { mh = cp.rcop_joe_d(a, &gh, n, d, z[1usize]) }
        if kind == 6usize { mh = cp.rcop_t_d(a, &gh, n, d, z[1usize], z[2usize]) }
        ret mh[(usize(z[6usize]) - 1usize) * d + usize(z[7usize]) - 1usize]
    }
    if str.eq(nm, "irhoc") { ret cp.irho_clayton(a, z[0usize]) }
    if str.eq(nm, "irhog") { ret cp.irho_gumbel(a, z[0usize]) }
    if str.eq(nm, "gof") {
        let n = usize(z[2usize])
        let (xs, ex) = mem.alloc[f64](a, 2usize * n)
        if ex != ok { os.exit(5) }
        var j = 0usize
        while j < n {
            xs[2usize * j] = z[5usize + j]
            xs[2usize * j + 1usize] = z[5usize + n + j]
            j += 1usize
        }
        var gr: rr.Rng = zero
        rr.seed(&gr, i64(z[1usize]))
        var res = [3]f64{0.0f64, 0.0f64, 0.0f64}
        cp.gof_sn(a, &gr, usize(z[0usize]), xs, n, usize(z[3usize]), res[0usize..3usize])
        ret res[usize(z[4usize]) - 1usize]
    }
    // rcop: (kind, seed, n, par, nu, row, col)
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[1usize]))
    let n = usize(z[2usize])
    let kind = usize(z[0usize])
    var m: []f64 = zero
    if kind == 0usize { m = cp.rcop_norm(a, &g, n, z[3usize]) }
    if kind == 1usize { m = cp.rcop_t(a, &g, n, z[3usize], z[4usize]) }
    if kind == 2usize { m = cp.rcop_clayton(a, &g, n, z[3usize]) }
    if kind == 3usize { m = cp.rcop_frank(a, &g, n, z[3usize]) }
    if kind == 4usize { m = cp.rcop_amh(a, &g, n, z[3usize]) }
    if kind == 5usize { m = cp.rcop_gumbel(a, &g, n, z[3usize]) }
    if kind == 6usize { m = cp.rcop_joe(a, &g, n, z[3usize]) }
    ret m[(usize(z[5usize]) - 1usize) * 2usize + usize(z[6usize]) - 1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/copula.json")
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
            if failures <= 40usize {
                var t: oracle.Case = zero
                t.name = c.name
                t.want = c.want
                t.rel = c.rel
                t.abs = c.abs
                var small = [3]f64{c.args[0usize], c.args[1usize], c.args[c.args.len - 1usize]}
                t.args = small[0usize..3usize]
                let _ = io.print(oracle.describe(a, &t, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
