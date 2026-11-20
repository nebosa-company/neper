// e.algo.stat.flexmixpkg against flexmix(weights = w) and FLXMRglm / FLXMRglmfix(offset = o): integer case weights (weighted EM, CEM, component removal) and an offset under every
// family, for the plain model and for FLXMRglmfix, with AIC, BIC, ICL and EIC. tests/oracle/flexmix_wo.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R flexmix_wo`; the case layout is at the top of scripts/r_oracle/groups/flexmix_wo.R. The data, the weights and the offset
// are drawn here from R's stream exactly as the group draws them.

use e.algo.rand.r as rg
use e.algo.stat.flexmixgen as fg
use e.algo.stat.flexmixpkg as fx
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

error Bad

type Ctx = struct { f: fx.Fm, d: fg.Data, off: []f64, n: usize, nobs: f64, fam: usize, p: usize }

fn prepare(a: *mem.Arena, z: []const f64) -> (Ctx, err) {
    var c: Ctx = zero
    let seed = i64(z[0usize])
    let n = usize(z[1usize])
    let fam = usize(z[3usize])
    let kg = usize(z[4usize])
    let k = usize(z[5usize])
    let flip = z[6usize]
    let seed2 = i64(z[7usize])
    let wmode = usize(z[10usize])
    let omode = usize(z[11usize])
    let model = usize(z[12usize])
    var start = 0usize
    if k != kg { start = 1usize }
    var o = fx.Opt { fam: fam, cls: usize(z[8usize]), start: start, minprior: z[9usize], tol: 0.000001f64, itermax: 200usize, wt: z[0usize..0usize], off: z[0usize..0usize] }
    let pr = z[15usize..18usize]
    let beta = z[18usize..30usize]
    let sg = z[30usize..33usize]
    let p = 3usize
    var r: rg.Rng = zero
    rg.seed(&r, seed)
    let (d, ge) = fg.gen(a, &r, n, 1usize, fam, kg, 0usize, pr, beta, sg, beta)
    if ge != ok { ret (c, ge) }
    if start == 0usize {
        let nf = fg.rint(flip * f64(n))
        let (fl, fe) = rg.sample_int(a, &r, i64(n), i64(nf), false)
        if fe != ok { ret (c, fe) }
        let (nv, ne) = rg.sample_int(a, &r, i64(kg), i64(nf), true)
        if ne != ok { ret (c, ne) }
        var i = 0usize
        while i < nf {
            d.z[usize(fl[i]) - 1usize] = f64(nv[i])
            i += 1usize
        }
    }
    let (wt, we) = mem.alloc[f64](a, n)
    let (off, oe) = mem.alloc[f64](a, n)
    if we != ok || oe != ok { ret (c, Bad) }
    var nobs = f64(n)
    if wmode == 1usize {
        let (ws, wse) = rg.sample_int(a, &r, 3i64, i64(n), true)
        if wse != ok { ret (c, wse) }
        var i = 0usize
        nobs = 0.0f64
        while i < n {
            wt[i] = f64(ws[i])
            nobs += wt[i]
            i += 1usize
        }
        o.wt = wt
    }
    if omode == 1usize {
        var i = 0usize
        while i < n {
            off[i] = rg.runif(&r, 0.0f64 - 0.4f64, 0.4f64)
            i += 1usize
        }
        o.off = off
    }
    rg.seed(&r, seed2)
    var f: fx.Fm = zero
    var fe2 = ok
    var pc = p
    if model == 0usize {
        let (f1, e1) = fx.run(a, &r, &o, d.x, n, p, d.y, d.sz, k, d.z, d.cx, 0usize)
        f = f1
        fe2 = e1
    } else {
        var zs: [3]f64 = zero
        let (f1, e1) = fx.run_fix(a, &r, &o, d.x, n, p, d.y, d.sz, k, d.z, d.cx, 0usize, 3usize, 4usize, 0usize, zs[0usize..3usize], zs[0usize..3usize], 0usize, zs[0usize..3usize])
        f = f1
        fe2 = e1
        pc = f.pc
    }
    if fe2 != ok { ret (c, fe2) }
    c.f = f
    c.d = d
    c.off = off
    c.n = n
    c.nobs = nobs
    c.fam = fam
    c.p = pc
    ret (c, ok)
}

fn answer(a: *mem.Arena, c: *const Ctx, z: []const f64) -> f64 {
    let what = usize(z[13usize])
    let idx = usize(z[14usize])
    let model = usize(z[12usize])
    let f = c.f
    let k = f.k
    let n = c.n
    let pc = f.pc
    if what == 0usize { ret f.llh }
    if what == 1usize { ret f64(f.iter) }
    if what == 2usize { ret f64(k) }
    if what == 3usize {
        if idx >= k { ret 0.0f64 / 0.0f64 }
        ret f.prior[idx]
    }
    if what == 7usize { ret fx.aic(&f) }
    if what == 8usize { ret f.df * math.log[f64](c.nobs) + 0.0f64 - 2.0f64 * f.llh }
    if what == 9usize { ret f.df * math.log[f64](c.nobs) + 0.0f64 - 2.0f64 * f.clog }
    if what == 30usize { ret fx.eic(&f, n) }
    if what == 20usize {
        if f.converged { ret 1.0f64 }
        ret 0.0f64
    }
    var s = 0.0f64
    if what == 4usize {
        var j = 0usize
        while j < k {
            var cc = 0usize
            while cc < pc {
                s += f64(j * pc + cc + 1usize) * f.coef[j * pc + cc]
                cc += 1usize
            }
            j += 1usize
        }
    } else if what == 5usize {
        var j = 0usize
        while j < k {
            s += f64(j + 1usize) * f.sigma[j]
            j += 1usize
        }
    } else if what == 6usize {
        var i = 0usize
        while i < n {
            s += f64(i + 1usize) * f64(f.cluster[i])
            i += 1usize
        }
    } else if what == 10usize {
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < k {
                s += f64(i * k + j + 1usize) * f.post[i * f.k0 + j]
                j += 1usize
            }
            i += 1usize
        }
    } else if model == 0usize {
        let (m, me) = mem.alloc[f64](a, n * k)
        if me != ok { os.exit(4) }
        fx.comp_mean(&f, c.fam, c.d.x, n, pc, m)
        var i = 0usize
        while i < n * k {
            s += f64(i + 1usize) * m[i]
            i += 1usize
        }
    } else {
        // fitted(): the component means from the stacked design, plus the offset
        let nr = k * n
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < k {
                var mu = 0.0f64
                var cc = 0usize
                while cc < pc {
                    mu += f.xs[cc * nr + j * n + i] * f.coef[j * pc + cc]
                    cc += 1usize
                }
                if f.off.len > 0usize { mu += f.off[i] }
                var v = mu
                if c.fam == 1usize { v = math.exp[f64](mu) }
                if c.fam == 2usize { v = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - mu)) }
                if c.fam == 3usize { v = 1.0f64 / mu }
                s += f64(i * k + j + 1usize) * v
                j += 1usize
            }
            i += 1usize
        }
    }
    ret s
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push_f64(&b, c.args[0usize])
    let _ = str.push(&b, " fam ")
    let _ = str.push_f64(&b, c.args[3usize])
    let _ = str.push(&b, " model ")
    let _ = str.push_f64(&b, c.args[12usize])
    let _ = str.push(&b, " what ")
    let _ = str.push_f64(&b, c.args[13usize])
    let _ = str.push(&b, " idx ")
    let _ = str.push_f64(&b, c.args[14usize])
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn same_config(a: []const f64, b: []const f64) -> bool {
    var i = 0usize
    while i < a.len {
        if i != 13usize && i != 14usize && a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/flexmix_wo.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    let base = mem.mark(a)
    var have = false
    var cur: Ctx = zero
    var last: []const f64 = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        if !have || !same_config(last, c.args) {
            mem.reset(a, base)
            let (cx, pe) = prepare(a, c.args)
            if pe != ok {
                let _ = io.print(brief(a, c, 0.0f64))
                let _ = io.print("\n")
                os.exit(5)
            }
            cur = cx
            last = c.args
            have = true
        }
        let got = answer(a, &cur, c.args)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 60usize {
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
