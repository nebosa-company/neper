// e.algo.stat.flexmixpkg against flexmix with FLXMRglmfix: fixed, nested and varying coefficients, varFix, component removal, concomitant priors and stepFlexmix.
// tests/oracle/flexmix_fix.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R flexmix_fix`; the case layout is at the top of
// scripts/r_oracle/groups/flexmix_fix.R. The data are drawn here from R's stream as the group draws them.

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

type Ctx = struct { f: fx.Fm, ll: []f64, n: usize, fam: usize, nrep: usize, k1: usize }

fn prepare(a: *mem.Arena, z: []const f64) -> (Ctx, err) {
    var c: Ctx = zero
    let seed = i64(z[0usize])
    let n = usize(z[1usize])
    let dtype = usize(z[2usize])
    let fam = usize(z[3usize])
    let kg = usize(z[4usize])
    let k = usize(z[5usize])
    let flip = z[6usize]
    let seed2 = i64(z[8usize])
    var o = fx.Opt { fam: fam, cls: usize(z[9usize]), start: usize(z[10usize]), minprior: z[11usize], tol: z[12usize], itermax: usize(z[13usize]), wt: z[0usize..0usize], off: z[0usize..0usize] }
    let rmask = usize(z[14usize])
    let fmask = usize(z[15usize])
    let ng = usize(z[16usize])
    let gsz = z[17usize..20usize]
    let gmask = z[20usize..23usize]
    let vmode = usize(z[23usize])
    let vsz = z[24usize..27usize]
    let q = usize(z[27usize])
    let mode = usize(z[30usize])
    let k2 = usize(z[31usize])
    let nrep = usize(z[32usize])
    let kq = usize(z[33usize])
    let pr = z[34usize..37usize]
    let beta = z[37usize..49usize]
    let sg = z[49usize..52usize]
    let gc = z[52usize..58usize]
    var p = 2usize
    if dtype == 1usize { p = 3usize }
    if dtype == 2usize { p = 4usize }
    var r: rg.Rng = zero
    rg.seed(&r, seed)
    let (d, ge) = fg.gen(a, &r, n, dtype, fam, kg, q, pr, beta, sg, gc)
    if ge != ok { ret (c, ge) }
    if o.start == 0usize {
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
    rg.seed(&r, seed2)
    let (ll, le) = mem.alloc[f64](a, (k2 - k + 1usize) * nrep)
    let (models, me) = mem.alloc[fx.Fm](a, k2 - k + 1usize)
    if le != ok || me != ok { ret (c, Bad) }
    var f: fx.Fm = zero
    var fe2 = ok
    if mode == 0usize {
        let (f1, e1) = fx.run_fix(a, &r, &o, d.x, n, p, d.y, d.sz, k, d.z, d.cx, q, rmask, fmask, ng, gsz, gmask, vmode, vsz)
        f = f1
        fe2 = e1
    } else {
        fe2 = fx.step_fix(a, &r, &o, d.x, n, p, d.y, d.sz, k, k2, nrep, d.cx, q, rmask, fmask, vmode, ll, models)
        f = models[kq - k]
        if f.k == 0usize { fe2 = Bad }
    }
    if fe2 != ok { ret (c, fe2) }
    c.f = f
    c.ll = ll
    c.n = n
    c.fam = fam
    c.nrep = nrep
    c.k1 = k
    ret (c, ok)
}

fn answer(a: *mem.Arena, c: *const Ctx, z: []const f64) -> f64 {
    let what = usize(z[28usize])
    let idx = usize(z[29usize])
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
    if what == 8usize { ret fx.bic(&f, n) }
    if what == 9usize { ret fx.icl(&f, n) }
    if what == 30usize { ret fx.eic(&f, n) }
    if what == 15usize { ret c.ll[(usize(z[33usize]) - c.k1) * c.nrep + idx] }
    if what == 20usize { ret f64(pc) }
    if what == 22usize {
        if f.converged { ret 1.0f64 }
        ret 0.0f64
    }
    var s = 0.0f64
    if what == 4usize || what == 21usize {
        var j = 0usize
        while j < k {
            var cc = 0usize
            while cc < pc {
                if what == 4usize { s += f64(j * pc + cc + 1usize) * f.coef[j * pc + cc] } else { s += f64(j * pc + cc + 1usize) * f.des[j * pc + cc] }
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
    } else {
        // fitted(): the component means from the stacked design
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
    let _ = str.push(&b, " what ")
    let _ = str.push_f64(&b, c.args[28usize])
    let _ = str.push(&b, " idx ")
    let _ = str.push_f64(&b, c.args[29usize])
    let _ = str.push(&b, " kq ")
    let _ = str.push_f64(&b, c.args[33usize])
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn same_config(a: []const f64, b: []const f64) -> bool {
    var i = 0usize
    while i < a.len {
        if i != 28usize && i != 29usize && a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/flexmix_fix.json")
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
