// e.algo.stat.flexmixpkg against flexmix: every family under EM / CEM / SEM / random classification, random and matrix starts, stepFlexmix, initFlexmix, concomitant
// multinomial priors, minprior removal, multi-covariate and factor designs, and the post-fit methods. tests/oracle/flexmix_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R flexmix_ext`; the case layout is at the top of scripts/r_oracle/groups/flexmix_ext.R. The data are drawn here from
// R's stream exactly as the group draws them.

use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.algo.stat.flexmixgen as fg
use e.algo.stat.flexmixpkg as fx
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

error Bad

type Ctx = struct { d: fg.Data, nw: fg.Data, f: fx.Fm, ll: []f64, n: usize, nnew: usize, p: usize, q: usize, fam: usize, k: usize, nrep: usize }

fn prepare(a: *mem.Arena, z: []const f64) -> (Ctx, err) {
    var c: Ctx = zero
    let seed = i64(z[0usize])
    let n = usize(z[1usize])
    let dtype = usize(z[2usize])
    let fam = usize(z[3usize])
    let k = usize(z[4usize])
    let q = usize(z[5usize])
    let flip = z[6usize]
    let nnew = usize(z[7usize])
    let seed2 = i64(z[8usize])
    let mode = usize(z[9usize])
    var o = fx.Opt { fam: fam, cls: usize(z[10usize]), start: usize(z[11usize]), minprior: z[12usize], tol: z[13usize], itermax: usize(z[14usize]), wt: z[0usize..0usize], off: z[0usize..0usize] }
    let k2 = usize(z[15usize])
    let nrep = usize(z[16usize])
    let method = usize(z[17usize])
    let kg = usize(z[20usize])
    let kq = usize(z[21usize])
    let pr = z[22usize..25usize]
    let beta = z[25usize..37usize]
    let sg = z[37usize..40usize]
    let gc = z[40usize..46usize]
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
    var nw: fg.Data = zero
    if nnew > 0usize {
        let (d2, g2) = fg.gen(a, &r, nnew, dtype, fam, kg, q, pr, beta, sg, gc)
        if g2 != ok { ret (c, g2) }
        nw = d2
    }
    rg.seed(&r, seed2)
    let (ll, le) = mem.alloc[f64](a, (k2 - k + 1usize) * nrep)
    let (models, me) = mem.alloc[fx.Fm](a, k2 - k + 1usize)
    if le != ok || me != ok { ret (c, Bad) }
    var f: fx.Fm = zero
    var fe2 = ok
    if mode == 0usize {
        let (f1, e1) = fx.run(a, &r, &o, d.x, n, p, d.y, d.sz, k, d.z, d.cx, q)
        f = f1
        fe2 = e1
    } else if mode == 1usize {
        fe2 = fx.step_all(a, &r, &o, d.x, n, p, d.y, d.sz, k, k2, nrep, d.cx, q, ll, models)
        f = models[kq - k]
    } else {
        fe2 = fx.init_flex(a, &r, &o, d.x, n, p, d.y, d.sz, k, k2, nrep, method, d.cx, q, ll, models)
        f = models[kq - k]
    }
    if fe2 != ok { ret (c, fe2) }
    c.d = d
    c.nw = nw
    c.f = f
    c.ll = ll
    c.n = n
    c.nnew = nnew
    c.p = p
    c.q = q
    c.fam = fam
    c.k = f.k
    c.nrep = nrep
    ret (c, ok)
}

fn wsum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret s
}

fn fsum(f: *const fx.Fm, c: *const Ctx, what: usize) -> f64 {
    let k = f.k
    var s = 0.0f64
    if what == 4usize {
        var j = 0usize
        while j < k {
            var cc = 0usize
            while cc < c.p {
                s += f64(j * c.p + cc + 1usize) * f.coef[j * c.p + cc]
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
        while i < c.n {
            s += f64(i + 1usize) * f64(f.cluster[i])
            i += 1usize
        }
    } else if what == 10usize {
        var i = 0usize
        while i < c.n {
            var j = 0usize
            while j < k {
                s += f64(i * k + j + 1usize) * f.post[i * f.k0 + j]
                j += 1usize
            }
            i += 1usize
        }
    } else {
        var j = 0usize
        while j < k {
            var cc = 0usize
            while cc < c.q {
                s += f64(j * c.q + cc + 1usize) * f.conc[j * c.q + cc]
                cc += 1usize
            }
            j += 1usize
        }
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const Ctx, z: []const f64) -> f64 {
    let what = usize(z[18usize])
    let idx = usize(z[19usize])
    let f = c.f
    let k = f.k
    let n = c.n
    if what == 0usize { ret f.llh }
    if what == 1usize { ret f64(f.iter) }
    if what == 2usize { ret f64(k) }
    if what == 3usize {
        if idx >= k { ret 0.0f64 / 0.0f64 }
        ret f.prior[idx]
    }
    if what == 4usize || what == 5usize || what == 6usize || what == 10usize || what == 11usize { ret fsum(&f, c, what) }
    if what == 7usize { ret fx.aic(&f) }
    if what == 8usize { ret fx.bic(&f, n) }
    if what == 9usize { ret fx.icl(&f, n) }
    if what == 30usize { ret fx.eic(&f, n) }
    if what == 15usize { ret c.ll[(usize(z[21usize]) - usize(z[4usize])) * c.nrep + idx] }
    if what == 20usize {
        if f.converged { ret 1.0f64 }
        ret 0.0f64
    }
    let (m, me) = mem.alloc[f64](a, (n + c.nnew + 2usize) * k + k * k)
    let (ll, le) = mem.alloc[f64](a, 1usize)
    if me != ok || le != ok { os.exit(4) }
    if what == 12usize {
        fx.comp_mean(&f, c.fam, c.nw.x, c.nnew, c.p, m)
        ret wsum(m, c.nnew * k)
    }
    if what == 13usize || what == 14usize || what == 29usize {
        let pe = fx.post_new(a, &f, c.fam, c.nw.x, c.nnew, c.p, c.nw.y, c.nw.sz, c.nw.cx, c.q, false, m, ll)
        if pe != ok { os.exit(6) }
        if what == 13usize { ret wsum(m, c.nnew * k) }
        if what == 14usize { ret ll[0usize] }
        var s = 0.0f64
        var i = 0usize
        while i < c.nnew {
            var b = 0usize
            var j = 1usize
            while j < k {
                if m[i * k + j] > m[i * k + b] { b = j }
                j += 1usize
            }
            s += f64(i + 1usize) * f64(b + 1usize)
            i += 1usize
        }
        ret s
    }
    if what == 18usize {
        fx.prior_new(&f, c.nw.cx, c.nnew, c.q, m)
        ret wsum(m, c.nnew * k)
    }
    if what == 28usize {
        let (mm, e2) = mem.alloc[f64](a, c.nnew * k)
        if e2 != ok { os.exit(4) }
        fx.prior_new(&f, c.nw.cx, c.nnew, c.q, m)
        fx.comp_mean(&f, c.fam, c.nw.x, c.nnew, c.p, mm)
        var s = 0.0f64
        var i = 0usize
        while i < c.nnew {
            var t = 0.0f64
            var j = 0usize
            while j < k {
                t += m[i * k + j] * mm[i * k + j]
                j += 1usize
            }
            s += f64(i + 1usize) * t
            i += 1usize
        }
        ret s
    }
    if what == 19usize {
        fx.comp_mean(&f, c.fam, c.d.x, n, c.p, m)
        ret wsum(m, n * k)
    }
    if what == 16usize {
        let ke = fx.kldiv_cont(a, &f, c.fam, c.d.x, n, c.p, m)
        if ke != ok { os.exit(7) }
        ret m[idx]
    }
    if what == 17usize {
        fx.kldiv_disc(&f, n, m)
        ret m[idx]
    }
    // relabel: 21 to 24 by prior, 25 by the first covariate's coefficient, 26 the reversed permutation, 27 by the concomitant slope
    var by = 0usize
    var ix = 0usize
    var key3: [3]f64 = zero
    if what == 25usize {
        by = 1usize
        ix = 1usize
    }
    if what == 26usize {
        by = 3usize
        var j = 0usize
        while j < k {
            key3[j] = f64(k - j)
            j += 1usize
        }
    }
    if what == 27usize {
        by = 2usize
        ix = 1usize
    }
    let (g, re) = fx.relabel(a, &f, by, ix, key3[0usize..3usize], c.p, c.q, n)
    if re != ok { os.exit(8) }
    if what == 21usize || what == 25usize || what == 26usize || what == 27usize { ret fsum(&g, c, 4usize) }
    if what == 22usize { ret fsum(&g, c, 6usize) }
    if what == 23usize { ret fsum(&g, c, 10usize) }
    ret fsum(&g, c, 11usize)
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push_f64(&b, c.args[0usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[2usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[3usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[4usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[5usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[9usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[10usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[11usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[18usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[19usize])
    let _ = str.push(&b, " ")
    let _ = str.push_f64(&b, c.args[21usize])
    let _ = str.push(&b, " ")
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn same_config(a: []const f64, b: []const f64) -> bool {
    var i = 0usize
    while i < a.len {
        if i != 18usize && i != 19usize && a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/flexmix_ext.json")
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
                let _ = io.print(oracle.describe(a, c, 0.0f64))
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
