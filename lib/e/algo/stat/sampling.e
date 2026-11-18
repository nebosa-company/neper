// R sampling: first-order inclusion probabilities (inclusionprobabilities), the fixed-size and Poisson designs UPsystematic,
// UPrandomsystematic, UPpoisson, UPtille and srswor drawn from R's generator under set.seed, and the Horvitz-Thompson estimator.
//
// UPbrewer (Brewer's sequential design). Not here: the other UP designs (Midzuno, maxentropy, pivotal, cube), stratified and cluster sampling,
// calibration and the joint inclusion probabilities.

use e.algo.rand.r as rr
use e.math
use e.mem

error Malformed

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

// UPbrewer(pik, eps): Brewer's sequential fixed-size design. The units with pik in (eps, 1 - eps) are drawn one at a time: for step i, the
// selection probabilities p_j = (1 - s_j) pik_j ((n - a) - pik_j) / ((n - a) - pik_j (n - i + 1)), with a = sum pik_j s_j, normalised and cumulated,
// and the first unit whose cumulative probability exceeds one uniform draw is selected (the last one when none does). The other units keep their pik.
fn up_brewer(a: *mem.Arena, g: *rr.Rng, pik: []const f64, eps: f64, s: []f64) -> err {
    let nall = pik.len
    let (list, e1) = mem.alloc[usize](a, nall)
    if e1 != ok { ret e1 }
    var nb = 0usize
    var i = 0usize
    while i < nall {
        s[i] = pik[i]
        if pik[i] > eps && pik[i] < 1.0f64 - eps {
            list[nb] = i
            nb += 1usize
        }
        i += 1usize
    }
    if nb < 1usize { ret Malformed }
    let (pb, e2) = mem.alloc[f64](a, nb)
    let (sb, e3) = mem.alloc[f64](a, nb)
    let (p, e4) = mem.alloc[f64](a, nb)
    if e2 != ok || e3 != ok || e4 != ok { ret Malformed }
    // the sum is compensated (Neumaier): R accumulates it in extended precision, and a plain sum that falls just short of an integer would drop a step
    var sum_pb = 0.0f64
    var comp = 0.0f64
    i = 0usize
    while i < nb {
        pb[i] = pik[list[i]]
        sb[i] = 0.0f64
        let t = sum_pb + pb[i]
        if math.abs[f64](sum_pb) >= math.abs[f64](pb[i]) { comp += (sum_pb - t) + pb[i] } else { comp += (pb[i] - t) + sum_pb }
        sum_pb = t
        i += 1usize
    }
    sum_pb += comp
    // R's 1:n with n = sum(pikb) runs from 1 to floor(n)
    let steps = usize(math.floor[f64](sum_pb))
    var step = 1usize
    while step <= steps {
        var aa = 0.0f64
        var j = 0usize
        while j < nb {
            aa += pb[j] * sb[j]
            j += 1usize
        }
        let rem = sum_pb - aa
        let fi = f64(step)
        var tot = 0.0f64
        j = 0usize
        while j < nb {
            p[j] = (1.0f64 - sb[j]) * pb[j] * (rem - pb[j]) / (rem - pb[j] * (sum_pb - fi + 1.0f64))
            tot += p[j]
            j += 1usize
        }
        j = 0usize
        while j < nb {
            p[j] = p[j] / tot
            j += 1usize
        }
        let u = rr.runif(g, 0.0f64, 1.0f64)
        var cum = 0.0f64
        var pick = nb - 1usize
        j = 0usize
        var found = false
        while j < nb {
            cum += p[j]
            if !found && u < cum {
                pick = j
                found = true
            }
            j += 1usize
        }
        sb[pick] = 1.0f64
        step += 1usize
    }
    i = 0usize
    while i < nb {
        s[list[i]] = sb[i]
        i += 1usize
    }
    ret ok
}

// UPmidzuno(pik, eps) = 1 - UPtille(1 - pik, eps): the sample of the complements drawn by Tille's design, then complemented
fn up_midzuno(a: *mem.Arena, g: *rr.Rng, pik: []const f64, s: []f64) -> err {
    let (q, e1) = mem.alloc[f64](a, pik.len)
    let (sq, e2) = mem.alloc[f64](a, pik.len)
    if e1 != ok || e2 != ok { ret Malformed }
    var i = 0usize
    while i < pik.len {
        q[i] = 1.0f64 - pik[i]
        i += 1usize
    }
    let e3 = up_tille(a, g, q, sq)
    if e3 != ok { ret e3 }
    i = 0usize
    while i < pik.len {
        s[i] = 1.0f64 - sq[i]
        i += 1usize
    }
    ret ok
}
