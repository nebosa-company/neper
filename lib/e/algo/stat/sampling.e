// R sampling: first-order inclusion probabilities (inclusionprobabilities), the fixed-size and Poisson designs UPsystematic,
// UPrandomsystematic, UPpoisson, UPtille and srswor drawn from R's generator under set.seed, and the Horvitz-Thompson estimator.
//
// UPbrewer (Brewer's sequential design). Not here: the other UP designs (Midzuno, maxentropy, pivotal, cube), stratified and cluster sampling,
// calibration and the joint inclusion probabilities.

use e.algo.rand.r as rr
use e.algo.stat.gparot as gp
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

// UPtillepi2: the joint inclusion probabilities of Tille's elimination design; pi2 is n by n row-major (zero outside the units with 1e-6 < pik < 1 - 1e-6, whose diagonal is pik)
fn up_tille_pi2(a: *mem.Arena, pik: []const f64, pi2: []f64) -> err {
    let n = pik.len
    let eps = 1.0e-6f64
    var i = 0usize
    while i < n * n {
        pi2[i] = 0.0f64
        i += 1usize
    }
    var nb = 0usize
    var sumb = 0.0f64
    i = 0usize
    while i < n {
        if pik[i] > eps && pik[i] < 1.0f64 - eps {
            nb += 1usize
            sumb += pik[i]
        }
        i += 1usize
    }
    if nb < 1usize { ret mem.Full }
    let (idx, e0) = mem.alloc[usize](a, nb)
    let (pb, e1) = mem.alloc[f64](a, nb)
    let (pp, e2) = mem.alloc[f64](a, nb * nb)
    let (bb, e3) = mem.alloc[f64](a, nb)
    let (aa, e4) = mem.alloc[f64](a, nb)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var c = 0usize
    i = 0usize
    while i < n {
        if pik[i] > eps && pik[i] < 1.0f64 - eps {
            idx[c] = i
            pb[c] = pik[i]
            c += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nb * nb {
        pp[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < nb {
        bb[i] = 1.0f64
        i += 1usize
    }
    let nsum = usize(math.floor[f64](sumb + 0.5f64))
    if f64(nb) > f64(nsum) {
        var s = 1usize
        while s <= nb - nsum {
            inclusion(pb, f64(nb - s), aa)
            i = 0usize
            while i < nb {
                let vi = 1.0f64 - aa[i] / bb[i]
                var j = 0usize
                while j < nb {
                    let vj = 1.0f64 - aa[j] / bb[j]
                    pp[i * nb + j] = pp[i * nb + j] * (1.0f64 - vi - vj)
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < nb {
                bb[i] = aa[i]
                i += 1usize
            }
            s += 1usize
        }
        i = 0usize
        while i < nb {
            pp[i * nb + i] = pb[i]
            i += 1usize
        }
        i = 0usize
        while i < nb {
            var j = 0usize
            while j < nb {
                pi2[idx[i] * n + idx[j]] = pp[i * nb + j]
                j += 1usize
            }
            i += 1usize
        }
    }
    ret ok
}

// UPsystematicpi2: the joint inclusion probabilities of systematic sampling (R's `%%` on the cumulative sums), pi2 n by n row-major with pik_i pik_j outside the units with 0 < pik < 1
fn up_systematic_pi2(a: *mem.Arena, pik: []const f64, pi2: []f64) -> err {
    let n = pik.len
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            pi2[i * n + j] = pik[i] * pik[j]
            j += 1usize
        }
        i += 1usize
    }
    var nb = 0usize
    i = 0usize
    while i < n {
        if pik[i] > 0.0f64 && pik[i] < 1.0f64 { nb += 1usize }
        i += 1usize
    }
    if nb == 0usize { ret ok }
    let (idx, e0) = mem.alloc[usize](a, nb)
    let (vk, e1) = mem.alloc[f64](a, nb + 1usize)
    let (vk1, e2) = mem.alloc[f64](a, nb)
    let (r, e3) = mem.alloc[f64](a, nb + 1usize)
    let (cent, e4) = mem.alloc[f64](a, nb)
    let (p, e5) = mem.alloc[f64](a, nb)
    let (m, e6) = mem.alloc[f64](a, (nb + 1usize) * nb)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var c = 0usize
    var cum = 0.0f64
    vk[0usize] = 0.0f64
    i = 0usize
    while i < n {
        if pik[i] > 0.0f64 && pik[i] < 1.0f64 {
            idx[c] = i
            cum += pik[i]
            vk[c + 1usize] = cum
            vk1[c] = cum - math.floor[f64](cum)
            c += 1usize
        }
        i += 1usize
    }
    if vk1[nb - 1usize] != 0.0f64 { vk1[nb - 1usize] = 0.0f64 }
    // r = c(sort(vk1), 1)
    i = 0usize
    while i < nb {
        let v = vk1[i]
        var j = i
        while j > 0usize && r[j - 1usize] > v {
            r[j] = r[j - 1usize]
            j -= 1usize
        }
        r[j] = v
        i += 1usize
    }
    r[nb] = 1.0f64
    i = 0usize
    while i < nb {
        cent[i] = (r[i] + r[i + 1usize]) / 2.0f64
        p[i] = r[i + 1usize] - r[i]
        i += 1usize
    }
    // A[row, col] = (c(0, Vk)[row] - cent[col]) mod 1, rows 0..nb
    i = 0usize
    while i <= nb {
        var j = 0usize
        while j < nb {
            let d = vk[i] - cent[j]
            m[i * nb + j] = d - math.floor[f64](d)
            j += 1usize
        }
        i += 1usize
    }
    // M[row, col] = A[row, col] > A[row + 1, col]; pi21 = M diag(p) M'
    i = 0usize
    while i < nb {
        var j = 0usize
        while j < nb {
            var v = 0.0f64
            var q = 0usize
            while q < nb {
                var mi = 0.0f64
                var mj = 0.0f64
                if m[i * nb + q] > m[(i + 1usize) * nb + q] { mi = 1.0f64 }
                if m[j * nb + q] > m[(j + 1usize) * nb + q] { mj = 1.0f64 }
                v += mi * p[q] * mj
                q += 1usize
            }
            pi2[idx[i] * n + idx[j]] = v
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// varHT: the Horvitz-Thompson variance estimator from the joint inclusion matrix pikl (n by n, the diagonal the first-order probabilities); method 1 or 2 (Sen-Yates-Grundy)
fn var_ht(y: []const f64, pikl: []const f64, method: usize) -> f64 {
    let n = y.len
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let pi = pikl[i * n + i]
            let pj = pikl[j * n + j]
            let p1 = pi * pj
            if method == 1usize {
                var delta = pikl[i * n + j] - p1
                if i == j { delta = pi * (1.0f64 - pi) }
                s += y[i] * y[j] * delta / (p1 * pikl[i * n + j])
            } else {
                let d = y[i] / pi - y[j] / pj
                s += 0.5f64 * d * d * (p1 - pikl[i * n + j]) / pikl[i * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// UPmidzunopi2: 1 - b - b' + UPtillepi2(1 - pik) with b_ij = 1 - pik_i, i.e. pik_i + pik_j - 1 + the Tille matrix of the complements
fn up_midzuno_pi2(a: *mem.Arena, pik: []const f64, pi2: []f64) -> err {
    let n = pik.len
    let (comp, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < n {
        comp[i] = 1.0f64 - pik[i]
        i += 1usize
    }
    let e = up_tille_pi2(a, comp, pi2)
    if e != ok { ret e }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            pi2[i * n + j] = pik[i] + pik[j] - 1.0f64 + pi2[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// UPsampfordpi2: the joint inclusion probabilities of Sampford's design (sum(pik) an integer n >= 2); pi2 is N by N row-major
fn up_sampford_pi2(a: *mem.Arena, pik: []const f64, pi2: []f64) -> err {
    let nn = pik.len
    var tot = 0.0f64
    var i = 0usize
    while i < nn {
        tot += pik[i]
        i += 1usize
    }
    let n = usize(math.floor[f64](tot + 0.5f64))
    if n < 2usize { ret mem.Full }
    let nf = f64(n)
    let (p, e0) = mem.alloc[f64](a, nn)
    let (lam, e1) = mem.alloc[f64](a, nn)
    let (lm, e2) = mem.alloc[f64](a, n + 3usize)
    let (lm2, e3) = mem.alloc[f64](a, n + 3usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    i = 0usize
    while i < nn * nn {
        pi2[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nn {
        p[i] = pik[i] / nf
        lam[i] = p[i] / (1.0f64 - nf * p[i])
        i += 1usize
    }
    i = 0usize
    while i < n + 3usize {
        lm[i] = 0.0f64
        lm2[i] = 0.0f64
        i += 1usize
    }
    lm[1usize] = 1.0f64
    var ii = 2usize
    while ii <= n {
        var r = 1usize
        while r <= ii - 1usize {
            var sr = 0.0f64
            var q = 0usize
            while q < nn {
                sr += math.pow[f64](lam[q], f64(r))
                q += 1usize
            }
            var sg = 1.0f64
            if (r - 1usize) % 2usize == 1usize { sg = -1.0f64 }
            lm[ii] = lm[ii] + sg * sr * lm[ii - r]
            r += 1usize
        }
        lm[ii] = lm[ii] / f64(ii - 1usize)
        ii += 1usize
    }
    var k = 1usize
    while k <= n {
        if lm[k] < 0.0f64 { ret mem.Full }
        k += 1usize
    }
    var den = 0.0f64
    k = 1usize
    while k <= n {
        let t1 = f64(n + 1usize - k)
        den += t1 * lm[k] / math.pow[f64](nf, t1)
        k += 1usize
    }
    let kn = 1.0f64 / den
    i = 1usize
    while i < nn {
        var j = 0usize
        while j < i {
            lm2[1usize] = 1.0f64
            lm2[2usize] = lm[2usize] - (lam[i] + lam[j])
            var m = 3usize
            while m + 1usize <= n {
                lm2[m] = lm[m] - (lam[i] + lam[j]) * lm2[m - 1usize] - lam[i] * lam[j] * lm2[m - 2usize]
                m += 1usize
            }
            var s = 0.0f64
            m = 1usize
            while m + 1usize <= n {
                s += (f64(m + 1usize) - nf * (p[i] + p[j])) * lm2[n - m] / math.pow[f64](nf, f64(m - 1usize))
                m += 1usize
            }
            let v = kn * lam[i] * lam[j] * s
            pi2[i * nn + j] = v
            pi2[j * nn + i] = v
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nn {
        pi2[i * nn + i] = pik[i]
        i += 1usize
    }
    ret ok
}

// strata(data, stratanames, size, method) for one stratification variable: the strata are visited in order of first appearance, each draws from the shared generator, and the selected
// unit numbers (1-based, ascending within a stratum) are written to ids; method 0 srswor (size[i] of the stratum), 1 systematic and 2 poisson (pik from inclusionprobabilities(w[y], size[i])).
// size is per stratum in order of first appearance; the answer is the number of selected units.
fn strata(a: *mem.Arena, g: *rr.Rng, label: []const f64, w: []const f64, size: []const f64, method: usize, ids: []f64) -> (usize, err) {
    let n = label.len
    let (seen, e0) = mem.alloc[f64](a, n)
    let (y, e1) = mem.alloc[usize](a, n)
    let (wk, e2) = mem.alloc[f64](a, n)
    let (pk, e3) = mem.alloc[f64](a, n)
    let (s, e4) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0usize, mem.Full) }
    var ns = 0usize
    var i = 0usize
    while i < n {
        var known = false
        var q = 0usize
        while q < ns {
            if seen[q] == label[i] { known = true }
            q += 1usize
        }
        if !known {
            seen[ns] = label[i]
            ns += 1usize
        }
        i += 1usize
    }
    var cnt = 0usize
    var st = 0usize
    while st < ns {
        var m = 0usize
        i = 0usize
        while i < n {
            if label[i] == seen[st] {
                y[m] = i
                wk[m] = w[i]
                m += 1usize
            }
            i += 1usize
        }
        if method == 0usize {
            let sz = usize(size[st])
            if m < sz { ret (cnt, mem.Full) }
            let er = srswor(a, g, sz, m, s[0usize..m])
            if er != ok { ret (cnt, er) }
        } else {
            inclusion(wk[0usize..m], size[st], pk[0usize..m])
            if method == 1usize {
                let er = up_systematic(a, g, pk[0usize..m], s[0usize..m])
                if er != ok { ret (cnt, er) }
            } else {
                up_poisson(g, pk[0usize..m], s[0usize..m])
            }
        }
        i = 0usize
        while i < m {
            if s[i] == 1.0f64 {
                ids[cnt] = f64(y[i] + 1usize)
                cnt += 1usize
            }
            i += 1usize
        }
        st += 1usize
    }
    ret (cnt, ok)
}

// cluster(data, "g", size, method) with the cluster variable's levels in ascending order (labels below 10 so that the character and numeric orders agree): the clusters are drawn with
// srswor(size, K), or inclusionprobabilities(pik, size) and UPsystematic / UPpoisson over the K clusters; the selected clusters' units are written ascending by cluster and then by unit
// number (1-based) to ids. method 0 srswor, 1 systematic, 2 poisson; pik is per cluster, in level order. The answer is the number of units selected.
fn cluster(a: *mem.Arena, g: *rr.Rng, label: []const f64, pik: []const f64, size: f64, method: usize, ids: []f64) -> (usize, err) {
    let n = label.len
    let k = pik.len
    let (lv, e0) = mem.alloc[f64](a, k)
    let (pk, e1) = mem.alloc[f64](a, k)
    let (s, e2) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    // the distinct labels ascending
    var m = 0usize
    var i = 0usize
    while i < n {
        var known = false
        var q = 0usize
        while q < m {
            if lv[q] == label[i] { known = true }
            q += 1usize
        }
        if !known {
            var j = m
            while j > 0usize && lv[j - 1usize] > label[i] {
                lv[j] = lv[j - 1usize]
                j -= 1usize
            }
            lv[j] = label[i]
            m += 1usize
        }
        i += 1usize
    }
    if method == 0usize {
        let er = srswor(a, g, usize(size), m, s[0usize..m])
        if er != ok { ret (0usize, er) }
    } else {
        inclusion(pik, size, pk)
        if method == 1usize {
            let er = up_systematic(a, g, pk, s)
            if er != ok { ret (0usize, er) }
        } else {
            up_poisson(g, pk, s)
        }
    }
    var cnt = 0usize
    var c = 0usize
    while c < m {
        if s[c] == 1.0f64 {
            i = 0usize
            while i < n {
                if label[i] == lv[c] {
                    ids[cnt] = f64(i + 1usize)
                    cnt += 1usize
                }
                i += 1usize
            }
        }
        c += 1usize
    }
    ret (cnt, ok)
}

// calib(Xs, d, total, q, method) for the linear (0) and raking (1) methods: the calibration g-weights into g. xs is n by p row-major; linear solves
// (X' diag(d q) X) lambda = total - X' d and g = 1 + q X lambda; raking iterates the Newton step on w = d exp(q X lambda) until max |X' w - total| / total < 1e-6 (500 iterations at most)
// and g = w / d. The answer is the iteration count (1 for linear, 0 when raking fails to converge).
fn calib(a: *mem.Arena, xs: []const f64, d: []const f64, total: []const f64, q: []const f64, n: usize, p: usize, method: usize, g: []f64) -> usize {
    let (am, e0) = mem.alloc[f64](a, p * p)
    let (rhs, e1) = mem.alloc[f64](a, p)
    let (lam, e2) = mem.alloc[f64](a, p)
    let (w, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    var j = 0usize
    while j < p {
        lam[j] = 0.0f64
        j += 1usize
    }
    if method == 0usize {
        var r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                var v = 0.0f64
                var i = 0usize
                while i < n {
                    v += xs[i * p + r] * d[i] * q[i] * xs[i * p + c]
                    i += 1usize
                }
                am[r * p + c] = v
                c += 1usize
            }
            var t = total[r]
            var i = 0usize
            while i < n {
                t -= d[i] * xs[i * p + r]
                i += 1usize
            }
            rhs[r] = t
            r += 1usize
        }
        let (inv, ie) = gp.invert(a, am, p)
        if ie != ok { ret 0usize }
        r = 0usize
        while r < p {
            var v = 0.0f64
            var c = 0usize
            while c < p {
                v += inv[r * p + c] * rhs[c]
                c += 1usize
            }
            lam[r] = v
            r += 1usize
        }
        var i = 0usize
        while i < n {
            var e = 0.0f64
            r = 0usize
            while r < p {
                e += xs[i * p + r] * lam[r]
                r += 1usize
            }
            g[i] = 1.0f64 + q[i] * e
            i += 1usize
        }
        ret 1usize
    }
    var i = 0usize
    while i < n {
        w[i] = d[i]
        i += 1usize
    }
    var l = 1usize
    while l <= 500usize {
        var r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                var v = 0.0f64
                i = 0usize
                while i < n {
                    v += xs[i * p + r] * w[i] * xs[i * p + c]
                    i += 1usize
                }
                am[r * p + c] = v
                c += 1usize
            }
            var t = 0.0f64
            i = 0usize
            while i < n {
                t += xs[i * p + r] * w[i]
                i += 1usize
            }
            rhs[r] = t - total[r]
            r += 1usize
        }
        let (inv, ie) = gp.invert(a, am, p)
        if ie != ok { ret 0usize }
        r = 0usize
        while r < p {
            var v = 0.0f64
            var c = 0usize
            while c < p {
                v += inv[r * p + c] * rhs[c]
                c += 1usize
            }
            lam[r] = lam[r] - v
            r += 1usize
        }
        i = 0usize
        while i < n {
            var e = 0.0f64
            r = 0usize
            while r < p {
                e += xs[i * p + r] * lam[r]
                r += 1usize
            }
            w[i] = d[i] * math.exp[f64](e * q[i])
            if w[i] != w[i] || w[i] > 1.0e300f64 { ret 0usize }
            i += 1usize
        }
        var worst = 0.0f64
        r = 0usize
        while r < p {
            var tr = 0.0f64
            i = 0usize
            while i < n {
                tr += xs[i * p + r] * w[i]
                i += 1usize
            }
            let dv = math.abs[f64](tr - total[r]) / total[r]
            if dv > worst { worst = dv }
            r += 1usize
        }
        if worst < 1.0e-6f64 {
            i = 0usize
            while i < n {
                g[i] = w[i] / d[i]
                i += 1usize
            }
            ret l
        }
        l += 1usize
    }
    ret 0usize
}

// calib(..., method = "truncated", bounds = c(low, upp)): the linear g-weights, then the repeated clamp-and-resolve of sampling: the g outside the bounds are set to the bound, the weights
// strictly inside are recalibrated against the total reduced by the clamped part, until the totals agree (relative error below 1e-6) with every g inside [low, upp] (500 iterations at
// most). The answer is the iteration count (0 on failure); g receives the weights (as R returns them even when it reports no convergence).
fn calib_truncated(a: *mem.Arena, xs: []const f64, d: []const f64, total: []const f64, q: []const f64, n: usize, p: usize, low: f64, upp: f64, g: []f64) -> usize {
    let first = calib(a, xs, d, total, q, n, p, 0usize, g)
    if first == 0usize { ret 0usize }
    let (list, e0) = mem.alloc[usize](a, n)
    let (t2, e1) = mem.alloc[f64](a, p)
    let (am, e2) = mem.alloc[f64](a, p * p)
    let (rhs, e3) = mem.alloc[f64](a, p)
    let (lam, e4) = mem.alloc[f64](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0usize }
    var m = n
    var i = 0usize
    while i < n {
        list[i] = i
        i += 1usize
    }
    var r = 0usize
    while r < p {
        t2[r] = total[r]
        r += 1usize
    }
    var l = 1usize
    while l <= 500usize {
        var outside = false
        i = 0usize
        while i < n {
            if g[i] < low || g[i] > upp { outside = true }
            i += 1usize
        }
        if outside {
            i = 0usize
            while i < n {
                if g[i] < low { g[i] = low }
                if g[i] > upp { g[i] = upp }
                i += 1usize
            }
            var cnt = 0usize
            i = 0usize
            while i < n {
                if g[i] > low && g[i] < upp { cnt += 1usize }
                i += 1usize
            }
            if cnt != 0usize {
                m = 0usize
                i = 0usize
                while i < n {
                    if g[i] > low && g[i] < upp {
                        list[m] = i
                        m += 1usize
                    }
                    i += 1usize
                }
                r = 0usize
                while r < p {
                    var t = total[r]
                    i = 0usize
                    while i < n {
                        if !(g[i] > low && g[i] < upp) { t -= g[i] * d[i] * xs[i * p + r] }
                        i += 1usize
                    }
                    t2[r] = t
                    r += 1usize
                }
            } else {
                ret l
            }
        }
        // lambda over the current subset
        r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                var v = 0.0f64
                var k = 0usize
                while k < m {
                    let u = list[k]
                    v += xs[u * p + r] * d[u] * q[u] * xs[u * p + c]
                    k += 1usize
                }
                am[r * p + c] = v
                c += 1usize
            }
            var t = t2[r]
            var k = 0usize
            while k < m {
                let u = list[k]
                t -= d[u] * xs[u * p + r]
                k += 1usize
            }
            rhs[r] = t
            r += 1usize
        }
        let (inv, ie) = gp.invert(a, am, p)
        if ie != ok { ret 0usize }
        r = 0usize
        while r < p {
            var v = 0.0f64
            var c = 0usize
            while c < p {
                v += inv[r * p + c] * rhs[c]
                c += 1usize
            }
            lam[r] = v
            r += 1usize
        }
        var k = 0usize
        while k < m {
            let u = list[k]
            var e = 0.0f64
            r = 0usize
            while r < p {
                e += xs[u * p + r] * lam[r]
                r += 1usize
            }
            g[u] = 1.0f64 + q[u] * e
            k += 1usize
        }
        var worst = 0.0f64
        r = 0usize
        while r < p {
            var tr = 0.0f64
            i = 0usize
            while i < n {
                tr += xs[i * p + r] * g[i] * d[i]
                i += 1usize
            }
            let dv = math.abs[f64](tr - total[r]) / total[r]
            if dv > worst { worst = dv }
            r += 1usize
        }
        var inside = true
        i = 0usize
        while i < n {
            if g[i] < low || g[i] > upp { inside = false }
            i += 1usize
        }
        if worst < 1.0e-6f64 && inside { ret l }
        l += 1usize
    }
    ret 500usize
}
