// R sampling: first-order inclusion probabilities (inclusionprobabilities), the fixed-size and Poisson designs UPsystematic,
// UPrandomsystematic, UPpoisson, UPtille and srswor drawn from R's generator under set.seed, and the Horvitz-Thompson estimator.
//
// Not here: the other UP designs (Brewer, Midzuno, maxentropy, pivotal, cube), stratified and cluster sampling, calibration and the
// joint inclusion probabilities.

use e.algo.rand.r as rr
use e.math
use e.mem

// inclusionprobabilities(a, n) into pik: n a / sum(a), with values at or above 1 set to 1 and the rest rescaled until none exceeds it
fn inclusion(a: []const f64, n: f64, pik: []f64) {
    var s = 0.0f64
    var i = 0usize
    while i < a.len {
        s += a[i]
        i += 1usize
    }
    i = 0usize
    while i < a.len {
        pik[i] = n * a[i] / s
        i += 1usize
    }
    var l = 0usize
    i = 0usize
    while i < a.len {
        if pik[i] >= 1.0f64 { l += 1usize }
        i += 1usize
    }
    if l == 0usize { ret }
    var l1 = 0usize
    while l != l1 {
        var sum = 0.0f64
        i = 0usize
        while i < a.len {
            if pik[i] < 1.0f64 { sum += pik[i] }
            i += 1usize
        }
        i = 0usize
        while i < a.len {
            if pik[i] < 1.0f64 { pik[i] = (n - f64(l)) * pik[i] / sum } else { pik[i] = 1.0f64 }
            i += 1usize
        }
        l1 = l
        l = 0usize
        i = 0usize
        while i < a.len {
            if pik[i] >= 1.0f64 { l += 1usize }
            i += 1usize
        }
    }
}

fn frac(x: f64) -> f64 { ret x - math.floor[f64](x) }

// UPsystematic: one uniform; s receives 0 or 1 (units with pik outside (eps, 1 - eps) keep their pik)
fn up_systematic(a: *mem.Arena, g: *rr.Rng, pik: []const f64, s: []f64) -> err {
    let eps = 1.0e-6f64
    var cnt = 0usize
    var i = 0usize
    while i < pik.len {
        if pik[i] > eps && pik[i] < 1.0f64 - eps { cnt += 1usize }
        s[i] = pik[i]
        i += 1usize
    }
    let u = rr.unif(g)
    let (av, e) = mem.alloc[f64](a, cnt + 1usize)
    if e != ok { ret e }
    av[0usize] = frac(0.0f64 - u)
    var c = 0.0f64
    var k = 0usize
    i = 0usize
    while i < pik.len {
        if pik[i] > eps && pik[i] < 1.0f64 - eps {
            c += pik[i]
            av[k + 1usize] = frac(c - u)
            k += 1usize
        }
        i += 1usize
    }
    k = 0usize
    i = 0usize
    while i < pik.len {
        if pik[i] > eps && pik[i] < 1.0f64 - eps {
            if av[k] > av[k + 1usize] { s[i] = 1.0f64 } else { s[i] = 0.0f64 }
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

// UPpoisson: one uniform per unit
fn up_poisson(g: *rr.Rng, pik: []const f64, s: []f64) {
    var i = 0usize
    while i < pik.len {
        if rr.unif(g) < pik[i] { s[i] = 1.0f64 } else { s[i] = 0.0f64 }
        i += 1usize
    }
}

// srswor(n, N): sample.int(N, n) marks the chosen units
fn srswor(a: *mem.Arena, g: *rr.Rng, n: usize, total: usize, s: []f64) -> err {
    var i = 0usize
    while i < total {
        s[i] = 0.0f64
        i += 1usize
    }
    let (v, e) = rr.sample_int(a, g, i64(total), i64(n), false)
    if e != ok { ret e }
    i = 0usize
    while i < n {
        s[usize(v[i]) - 1usize] = 1.0f64
        i += 1usize
    }
    ret ok
}

// UPrandomsystematic: sample.int(N, N) reorders the units, then UPsystematic on the reordered pik
fn up_random_systematic(a: *mem.Arena, g: *rr.Rng, pik: []const f64, s: []f64) -> err {
    let n = pik.len
    let (v, e) = rr.sample_int(a, g, i64(n), i64(n), false)
    if e != ok { ret e }
    let (pv, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    let (sv, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n {
        pv[i] = pik[usize(v[i]) - 1usize]
        i += 1usize
    }
    let e4 = up_systematic(a, g, pv, sv)
    if e4 != ok { ret e4 }
    i = 0usize
    while i < n {
        s[usize(v[i]) - 1usize] = sv[i]
        i += 1usize
    }
    ret ok
}

// UPtille: the elimination procedure; every unit has pik strictly inside (eps, 1 - eps) in the oracle, as the package requires a fixed size
fn up_tille(a: *mem.Arena, g: *rr.Rng, pik: []const f64, s: []f64) -> err {
    let eps = 1.0e-6f64
    var nb = 0usize
    var sum = 0.0f64
    var i = 0usize
    while i < pik.len {
        s[i] = pik[i]
        if pik[i] > eps && pik[i] < 1.0f64 - eps {
            nb += 1usize
            sum += pik[i]
        }
        i += 1usize
    }
    let (pikb, e1) = mem.alloc[f64](a, nb)
    if e1 != ok { ret e1 }
    let (sb, e2) = mem.alloc[f64](a, nb)
    if e2 != ok { ret e2 }
    let (b, e3) = mem.alloc[f64](a, nb)
    if e3 != ok { ret e3 }
    let (av, e4) = mem.alloc[f64](a, nb)
    if e4 != ok { ret e4 }
    var k = 0usize
    i = 0usize
    while i < pik.len {
        if pik[i] > eps && pik[i] < 1.0f64 - eps {
            pikb[k] = pik[i]
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nb {
        sb[i] = 1.0f64
        b[i] = 1.0f64
        i += 1usize
    }
    let n = usize(math.floor[f64](sum + 0.5f64))
    var step = 1usize
    while step <= nb - n {
        inclusion(pikb, f64(nb - step), av)
        let u = rr.unif(g)
        var c = 0.0f64
        var pick = nb - 1usize
        var found = false
        var j = 0usize
        while j < nb && !found {
            c += (1.0f64 - av[j] / b[j]) * sb[j]
            if u < c {
                pick = j
                found = true
            }
            j += 1usize
        }
        j = 0usize
        while j < nb {
            b[j] = av[j]
            j += 1usize
        }
        sb[pick] = 0.0f64
        step += 1usize
    }
    k = 0usize
    i = 0usize
    while i < pik.len {
        if pik[i] > eps && pik[i] < 1.0f64 - eps {
            s[i] = sb[k]
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn ht_estimator(y: []const f64, pik: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        s += y[i] / pik[i]
        i += 1usize
    }
    ret s
}
