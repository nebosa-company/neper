// e.algo.stat.flexmixmv against flexmix: the multivariate drivers under EM, CEM and SEM from R's random start, and stepFlexmix over them. tests/oracle/flexmix_mv2.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R flexmix_mv2`; the layout is at the top of scripts/r_oracle/groups/flexmix_mv2.R. The data are drawn
// here from R's stream as the group draws them.

use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.algo.stat.flexmixmv as mv
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

error Bad

type Ctx = struct { f: mv.Mv, ll: []f64, n: usize, d: usize, model: usize, nrep: usize, k1: usize }

fn gen(a: *mem.Arena, r: *rg.Rng, n: usize, d: usize, k: usize, model: usize) -> ([]f64, err) {
    let (y, e1) = mem.alloc[f64](a, n * d)
    let (mu, e2) = mem.alloc[f64](a, k * d)
    let (ev, e3) = mem.alloc[f64](a, n * d)
    let (pw, e4) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (y, Bad) }
    var j = 0usize
    while j < k {
        pw[j] = 1.0f64 / f64(k)
        j += 1usize
    }
    let (zs, ze) = rd.sample_prob(a, r, k, n, true, pw)
    if ze != ok { ret (y, ze) }
    var sc: [3]f64 = zero
    sc[0usize] = 0.8f64
    sc[1usize] = 1.2f64
    sc[2usize] = 0.6f64
    var i = 0usize
    if model == 0usize || model == 1usize || model == 4usize {
        var t = 0usize
        while t < k * d {
            mu[t] = rg.rnorm(r, 0.0f64, 3.0f64)
            t += 1usize
        }
        t = 0usize
        while t < n * d {
            ev[t] = rg.rnorm(r, 0.0f64, 1.0f64)
            t += 1usize
        }
        i = 0usize
        while i < n {
            var c = 0usize
            while c < d {
                let zi = usize(zs[i]) - 1usize
                y[i * d + c] = mu[c * k + zi] + ev[c * n + i] * sc[c]
                c += 1usize
            }
            if model == 0usize { y[i * d + 1usize] = y[i * d + 1usize] + 0.5f64 * y[i * d] }
            i += 1usize
        }
    } else if model == 2usize {
        var t = 0usize
        while t < k * d {
            mu[t] = rg.runif(r, 0.1f64, 0.9f64)
            t += 1usize
        }
        i = 0usize
        while i < n {
            var c = 0usize
            while c < d {
                y[i * d + c] = rd.rbinom(r, 1.0f64, mu[c * k + usize(zs[i]) - 1usize])
                c += 1usize
            }
            i += 1usize
        }
    } else {
        var t = 0usize
        while t < k * d {
            mu[t] = rg.runif(r, 1.0f64, 8.0f64)
            t += 1usize
        }
        i = 0usize
        while i < n {
            var c = 0usize
            while c < d {
                y[i * d + c] = rd.rpois(r, mu[c * k + usize(zs[i]) - 1usize])
                c += 1usize
            }
            i += 1usize
        }
    }
    ret (y, ok)
}

fn prepare(a: *mem.Arena, z: []const f64) -> (Ctx, err) {
    var c: Ctx = zero
    let seed = i64(z[0usize])
    let n = usize(z[1usize])
    let d = usize(z[2usize])
    let k = usize(z[3usize])
    let model = usize(z[4usize])
    let cls = usize(z[5usize])
    let mode = usize(z[6usize])
    let k2 = usize(z[7usize])
    let nrep = usize(z[8usize])
    let kq = usize(z[9usize])
    let seed2 = i64(z[10usize])
    var r: rg.Rng = zero
    rg.seed(&r, seed)
    let (y, ge) = gen(a, &r, n, d, k, model)
    if ge != ok { ret (c, ge) }
    rg.seed(&r, seed2)
    var m = model
    if model == 4usize { m = 1usize }
    let (ll, le) = mem.alloc[f64](a, (k2 - k + 1usize) * nrep)
    let (models, me) = mem.alloc[mv.Mv](a, k2 - k + 1usize)
    if le != ok || me != ok { ret (c, Bad) }
    var f: mv.Mv = zero
    var fe = ok
    if mode == 0usize {
        let (f1, e1) = mv.random_cls(a, &r, y, n, d, k, m, cls, 0.05f64, 0.000001f64, 200usize)
        f = f1
        fe = e1
    } else {
        fe = mv.step_mv(a, &r, y, n, d, k, k2, nrep, m, cls, 0.05f64, 0.000001f64, 200usize, ll, models)
        f = models[kq - k]
        if f.k == 0usize { fe = Bad }
    }
    if fe != ok { ret (c, fe) }
    c.f = f
    c.ll = ll
    c.n = n
    c.d = d
    c.model = model
    c.nrep = nrep
    c.k1 = k
    ret (c, ok)
}

fn answer(c: *const Ctx, z: []const f64) -> f64 {
    let what = usize(z[11usize])
    let idx = usize(z[12usize])
    let f = c.f
    let k = f.k
    let n = c.n
    let d = c.d
    var s = 0.0f64
    if what == 0usize { ret f.llh }
    if what == 1usize { ret f64(f.iter) }
    if what == 2usize { ret f64(k) }
    if what == 7usize { ret mv.aic(&f) }
    if what == 8usize { ret mv.bic(&f, n) }
    if what == 9usize { ret mv.icl(&f, n) }
    if what == 15usize { ret c.ll[(usize(z[9usize]) - c.k1) * c.nrep + idx] }
    if what == 3usize {
        var j = 0usize
        while j < k {
            s += f64(j + 1usize) * f.prior[j]
            j += 1usize
        }
    } else if what == 4usize {
        var q = 0usize
        while q < k * d {
            s += f64(q + 1usize) * f.center[q]
            q += 1usize
        }
    } else if what == 5usize {
        if c.model == 4usize {
            var j = 0usize
            while j < k {
                s += f64(j + 1usize) * math.sqrt[f64](f.cov[j])
                j += 1usize
            }
        } else {
            var q = 0usize
            while q < k * d * d {
                s += f64(q + 1usize) * f.cov[q]
                q += 1usize
            }
        }
    } else if what == 6usize {
        var i = 0usize
        while i < n {
            s += f64(i + 1usize) * f64(f.cluster[i] + 1usize)
            i += 1usize
        }
    } else {
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < k {
                s += f64(i * k + j + 1usize) * f.post[i * f.k0 + j]
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
    let _ = str.push(&b, " model ")
    let _ = str.push_f64(&b, c.args[4usize])
    let _ = str.push(&b, " cls ")
    let _ = str.push_f64(&b, c.args[5usize])
    let _ = str.push(&b, " what ")
    let _ = str.push_f64(&b, c.args[11usize])
    let _ = str.push(&b, " idx ")
    let _ = str.push_f64(&b, c.args[12usize])
    let _ = str.push(&b, " kq ")
    let _ = str.push_f64(&b, c.args[9usize])
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn same_config(a: []const f64, b: []const f64) -> bool {
    var i = 0usize
    while i < a.len {
        if i != 11usize && i != 12usize && a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/flexmix_mv2.json")
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
        let got = answer(&cur, c.args)
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
