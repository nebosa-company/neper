// The data the flexmix oracle groups draw: a mixture of k regression components (gaussian, Poisson, binomial or Gamma) over the design 1 + x1 [+ x2 | + a factor of
// three levels], optionally with a concomitant variable w driving the component probabilities. The draws follow the order scripts/r_oracle/groups/flexmix_ext.R makes
// them in (runif, sample, then one rnorm / rpois / rbinom / rgamma per observation), so the fixtures regenerate from the seed what R generated.

use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.math
use e.mem

error Bad

type Data = struct { x: []f64, y: []f64, sz: []f64, cx: []f64, z: []f64 }

fn gen(a: *mem.Arena, r: *rg.Rng, n: usize, dtype: usize, fam: usize, k: usize, q: usize, pr: []const f64, beta: []const f64, sg: []const f64, gc: []const f64) -> (Data, err) {
    var d: Data = zero
    var p = 2usize
    if dtype == 1usize { p = 3usize }
    if dtype == 2usize { p = 4usize }
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (y, e2) = mem.alloc[f64](a, n)
    let (sz, e3) = mem.alloc[f64](a, n)
    let (cx, e4) = mem.alloc[f64](a, n * 2usize)
    let (zz, e5) = mem.alloc[f64](a, n)
    let (x2, e6) = mem.alloc[f64](a, n)
    let (fl, e7) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (d, Bad) }
    var i = 0usize
    while i < n {
        x[i * p] = 1.0f64
        x[i * p + 1usize] = rg.runif(r, 0.0f64 - 1.0f64, 1.0f64)
        i += 1usize
    }
    if dtype == 1usize {
        i = 0usize
        while i < n {
            x[i * p + 2usize] = rg.runif(r, 0.0f64 - 1.0f64, 1.0f64)
            i += 1usize
        }
    }
    if dtype == 2usize {
        let (fs, fe) = rg.sample_int(a, r, 3i64, i64(n), true)
        if fe != ok { ret (d, fe) }
        i = 0usize
        while i < n {
            fl[i] = usize(fs[i])
            x[i * p + 2usize] = 0.0f64
            x[i * p + 3usize] = 0.0f64
            if fl[i] == 2usize { x[i * p + 2usize] = 1.0f64 }
            if fl[i] == 3usize { x[i * p + 3usize] = 1.0f64 }
            i += 1usize
        }
    }
    if q > 0usize {
        i = 0usize
        while i < n {
            cx[i * q] = 1.0f64
            cx[i * q + 1usize] = rg.runif(r, 0.0f64 - 1.0f64, 1.0f64)
            i += 1usize
        }
    }
    if fam == 2usize {
        let (ss, se) = rg.sample_int(a, r, 13i64, i64(n), true)
        if se != ok { ret (d, se) }
        i = 0usize
        while i < n {
            sz[i] = f64(ss[i] + 7i64)
            i += 1usize
        }
    }
    if q > 0usize {
        i = 0usize
        while i < n {
            var e: [3]f64 = zero
            var s = 0.0f64
            var j = 0usize
            while j < k {
                e[j] = math.exp[f64](gc[j * 2usize] + gc[j * 2usize + 1usize] * cx[i * q + 1usize])
                s += e[j]
                j += 1usize
            }
            var pj: [3]f64 = zero
            j = 0usize
            while j < k {
                pj[j] = e[j] / s
                j += 1usize
            }
            let (dr, de) = rd.sample_prob(a, r, k, 1usize, false, pj[0usize..k])
            if de != ok { ret (d, de) }
            zz[i] = f64(dr[0usize])
            i += 1usize
        }
    } else {
        let (dr, de) = rd.sample_prob(a, r, k, n, true, pr[0usize..k])
        if de != ok { ret (d, de) }
        i = 0usize
        while i < n {
            zz[i] = f64(dr[i])
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        let zi = usize(zz[i]) - 1usize
        var mu = beta[zi * 4usize] + beta[zi * 4usize + 1usize] * x[i * p + 1usize]
        if dtype == 1usize { mu = mu + beta[zi * 4usize + 2usize] * x[i * p + 2usize] }
        if dtype == 2usize {
            mu = mu + beta[zi * 4usize + 2usize] * x[i * p + 2usize]
            mu = mu + beta[zi * 4usize + 3usize] * x[i * p + 3usize]
        }
        if fam == 0usize {
            y[i] = rg.rnorm(r, mu, sg[zi])
        } else if fam == 1usize {
            y[i] = rd.rpois(r, math.exp[f64](mu))
        } else if fam == 2usize {
            y[i] = rd.rbinom(r, sz[i], 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - mu)))
        } else {
            y[i] = rg.rgamma(r, sg[zi], (1.0f64 / mu) / sg[zi])
        }
        i += 1usize
    }
    if fam != 2usize {
        i = 0usize
        while i < n {
            sz[i] = y[i]
            i += 1usize
        }
    }
    d.x = x
    d.y = y
    d.sz = sz
    d.cx = cx
    d.z = zz
    ret (d, ok)
}

// R's round(x) for a count: half to even
fn rint(x: f64) -> usize {
    let f = math.floor[f64](x)
    let d = x - f
    if d < 0.5f64 { ret usize(f) }
    if d > 0.5f64 { ret usize(f) + 1usize }
    if usize(f) % 2usize == 0usize { ret usize(f) }
    ret usize(f) + 1usize
}
