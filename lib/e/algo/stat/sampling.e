// R sampling: first-order inclusion probabilities (inclusionprobabilities), the fixed-size and Poisson designs UPsystematic,
// UPrandomsystematic, UPpoisson, UPtille and srswor drawn from R's generator under set.seed, and the Horvitz-Thompson estimator.
//
// UPbrewer (Brewer's sequential design). Not here: the other UP designs (Midzuno, maxentropy, pivotal, cube), stratified and cluster sampling,
// calibration and the joint inclusion probabilities.

use e.algo.rand.r as rr
use e.algo.stat.gparot as gp
use e.math
use e.math.nmath as nm
use e.mem

error Malformed

// inclusionprobabilities(a, n) into pik: n a / sum(a), with values at or above 1 set to 1 and the rest rescaled until none exceeds it; the sums are long doubles as R's sum() is
fn inclusion(a: []const f64, n: f64, pik: []f64) {
    var sh = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < a.len {
        let (h2, l2) = ld_add(sh, sl, a[i])
        sh = h2
        sl = l2
        i += 1usize
    }
    let s = sh + sl
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
        var smh = 0.0f64
        var sml = 0.0f64
        i = 0usize
        while i < a.len {
            if pik[i] < 1.0f64 {
                let (h2, l2) = ld_add(smh, sml, pik[i])
                smh = h2
                sml = l2
            }
            i += 1usize
        }
        let sum = smh + sml
        i = 0usize
        while i < a.len {
            if pik[i] < 1.0f64 { pik[i] = (n - f64(l)) * (pik[i] / sum) } else { pik[i] = 1.0f64 }
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
        if method == 3usize {
            srswr(g, usize(size[st]), m, s[0usize..m])
        } else if method == 0usize {
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
            if method == 3usize {
                var rep = 0usize
                while f64(rep) < s[i] {
                    ids[cnt] = f64(y[i] + 1usize)
                    cnt += 1usize
                    rep += 1usize
                }
            } else {
                if s[i] == 1.0f64 {
                    ids[cnt] = f64(y[i] + 1usize)
                    cnt += 1usize
                }
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
    if method == 3usize {
        srswr(g, usize(size), m, s[0usize..m])
    } else if method == 0usize {
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
        if s[c] == 1.0f64 || (method == 3usize && s[c] > 0.0f64) {
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

// calib(..., method = "logit", bounds = c(low, upp)): the g-weights F(lambda) = (low (upp - 1) + upp (1 - low) u) / (upp - 1 + (1 - low) u), u = exp(A q X lambda), A = (upp - low) /
// ((1 - low) (upp - 1)), by Newton steps on the units inside the bounds with the clamped ones held at their bound (as calib_truncated does). It starts from g = 1 (u = 1) and returns at
// once when that already calibrates the totals. The answer is the iteration count (0 on failure); g receives the weights.
fn calib_logit(a: *mem.Arena, xs: []const f64, d: []const f64, total: []const f64, q: []const f64, n: usize, p: usize, low: f64, upp: f64, g: []f64) -> usize {
    let aa = (upp - low) / ((1.0f64 - low) * (upp - 1.0f64))
    let (list, e0) = mem.alloc[usize](a, n)
    let (t2, e1) = mem.alloc[f64](a, p)
    let (am, e2) = mem.alloc[f64](a, p * p)
    let (rhs, e3) = mem.alloc[f64](a, p)
    let (lam, e4) = mem.alloc[f64](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0usize }
    var i = 0usize
    while i < n {
        g[i] = 1.0f64
        list[i] = i
        i += 1usize
    }
    var r = 0usize
    while r < p {
        lam[r] = 0.0f64
        t2[r] = total[r]
        r += 1usize
    }
    var worst = 0.0f64
    r = 0usize
    while r < p {
        var tr = 0.0f64
        i = 0usize
        while i < n {
            tr += xs[i * p + r] * d[i]
            i += 1usize
        }
        let dv = math.abs[f64](tr - total[r]) / total[r]
        if dv > worst { worst = dv }
        r += 1usize
    }
    if worst <= 1.0e-6f64 { ret 1usize }
    var m = n
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
            if cnt == 0usize { ret l }
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
        }
        if m < 2usize { ret 0usize }
        // phi = X1' (d1 g1) - t1; the Newton step lambda -= ginv(X1' diag(d1 g1) X1) (phi - t2 + t1)
        r = 0usize
        while r < p {
            var c = 0usize
            while c < p {
                var v = 0.0f64
                var k = 0usize
                while k < m {
                    let u = list[k]
                    v += xs[u * p + r] * d[u] * g[u] * xs[u * p + c]
                    k += 1usize
                }
                am[r * p + c] = v
                c += 1usize
            }
            var phi = 0.0f64
            var t1 = 0.0f64
            var k = 0usize
            while k < m {
                let u = list[k]
                phi += xs[u * p + r] * d[u] * g[u]
                t1 += xs[u * p + r] * d[u]
                k += 1usize
            }
            rhs[r] = (phi - t1) - t2[r] + t1
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
        var k = 0usize
        while k < m {
            let u = list[k]
            var e = 0.0f64
            r = 0usize
            while r < p {
                e += xs[u * p + r] * lam[r]
                r += 1usize
            }
            let ex = math.exp[f64](aa * (e * q[u]))
            let gv = (low * (upp - 1.0f64) + upp * (1.0f64 - low) * ex) / (upp - 1.0f64 + (1.0f64 - low) * ex)
            if gv != gv { ret 0usize }
            g[u] = gv
            k += 1usize
        }
        worst = 0.0f64
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
    ret 0usize
}

// Hajekestimator: type 0 total (N sum(y / pik) / sum(1 / pik)), type 1 the mean sum(y / pik) / sum(1 / pik)
fn hajek_estimator(y: []const f64, pik: []const f64, n_pop: f64, total: bool) -> f64 {
    var num = 0.0f64
    var den = 0.0f64
    var i = 0usize
    while i < y.len {
        num += y[i] / pik[i]
        den += 1.0f64 / pik[i]
        i += 1usize
    }
    if total { ret n_pop * num / den }
    ret num / den
}

// ratioest: sum(y / pik) Tx / sum(x / pik)
fn ratio_estimator(y: []const f64, x: []const f64, tx: f64, pik: []const f64) -> f64 {
    var a1 = 0.0f64
    var a2 = 0.0f64
    var i = 0usize
    while i < y.len {
        a1 += y[i] / pik[i]
        a2 += x[i] / pik[i]
        i += 1usize
    }
    ret a1 * tx / a2
}

// inclusionprobastrata: pik_i = nh[strata_i] / Nh[strata_i] with strata labelled 1, 2, ...
fn inclusion_strata(labels: []const f64, nh: []const f64, pik: []f64) {
    var i = 0usize
    while i < labels.len {
        var cnt = 0.0f64
        var j = 0usize
        while j < labels.len {
            if labels[j] == labels[i] { cnt += 1.0f64 }
            j += 1usize
        }
        pik[i] = nh[usize(labels[i]) - 1usize] / cnt
        i += 1usize
    }
}

// HTstrata: the Horvitz-Thompson estimators summed over the strata (each stratum's sum of y / pik)
fn ht_strata(y: []const f64, pik: []const f64, labels: []const f64) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < y.len {
        // a stratum label's first appearance starts its sum (the sum over strata is the sum over all units)
        total += y[i] / pik[i]
        i += 1usize
    }
    ret total
}

// varest(Ys, Xs, pik, w): the variance estimator of the total from first-order probabilities alone; with p = 0 covariates it works on y, otherwise on the residuals of the weighted regression
// beta = (X' W X)^-1 X' W y (xs is n by p row-major)
fn var_est(a: *mem.Arena, y: []const f64, xs: []const f64, p: usize, pik: []const f64, w: []const f64) -> (f64, err) {
    let n = y.len
    let (e, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret (0.0f64, e0) }
    var i = 0usize
    while i < n {
        e[i] = y[i]
        i += 1usize
    }
    if p > 0usize {
        let (am, e1) = mem.alloc[f64](a, p * p)
        let (rhs, e2) = mem.alloc[f64](a, p)
        if e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
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
                t += xs[i * p + r] * w[i] * y[i]
                i += 1usize
            }
            rhs[r] = t
            r += 1usize
        }
        let (inv, ie) = gp.invert(a, am, p)
        if ie != ok { ret (0.0f64, ie) }
        i = 0usize
        while i < n {
            var fit = 0.0f64
            r = 0usize
            while r < p {
                var b = 0.0f64
                var c = 0usize
                while c < p {
                    b += inv[r * p + c] * rhs[c]
                    c += 1usize
                }
                fit += xs[i * p + r] * b
                r += 1usize
            }
            e[i] = y[i] - fit
            i += 1usize
        }
    }
    var s1 = 0.0f64
    i = 0usize
    while i < n {
        s1 += 1.0f64 - pik[i]
        i += 1usize
    }
    var aa = 0.0f64
    var a2 = 0.0f64
    i = 0usize
    while i < n {
        let ai = (1.0f64 - pik[i]) / s1
        aa += ai * e[i] / pik[i]
        a2 += ai * ai
        i += 1usize
    }
    var v = 0.0f64
    i = 0usize
    while i < n {
        let d = e[i] / pik[i] - aa
        v += (1.0f64 - pik[i]) * d * d
        i += 1usize
    }
    ret (v / (1.0f64 - a2), ok)
}

// vartaylor_ratio(Ys, Xs, pikls): the ratio sum(y / pik) / sum(x / pik) and the Taylor linearisation variance estimate from the joint inclusion matrix (diagonal pik); out = (ratio, estvar)
fn var_taylor_ratio(y: []const f64, x: []const f64, pikl: []const f64, out: []f64) {
    let n = y.len
    var xhat = 0.0f64
    var yhat = 0.0f64
    var i = 0usize
    while i < n {
        let pi = pikl[i * n + i]
        xhat += x[i] / pi
        yhat += y[i] / pi
        i += 1usize
    }
    let r = yhat / xhat
    var s = 0.0f64
    i = 0usize
    while i < n {
        let pi = pikl[i * n + i]
        let zi = (y[i] - r * x[i]) / xhat
        var j = i + 1usize
        while j < n {
            let pj = pikl[j * n + j]
            let zj = (y[j] - r * x[j]) / xhat
            s += 2.0f64 * (1.0f64 - pi * pj / pikl[i * n + j]) * zi * zj / (pi * pj)
            j += 1usize
        }
        s += (1.0f64 - pi) * zi * zi / (pi * pi)
        i += 1usize
    }
    out[0usize] = r
    out[1usize] = s
}

// regest(y ~ x, Tx, weights = 1 / pik, pikl): the regression estimator of the total with its weighted-least-squares coefficients and sandwich standard errors. x is n by p row-major with the
// constant in column 0 and Tx the p - 1 known totals of the other columns; pikl is the n by n joint inclusion matrix (diagonal pik). out = (estimate, beta[p], std_error[p]).
fn regest(a: *mem.Arena, y: []const f64, x: []const f64, p: usize, w: []const f64, pikl: []const f64, tx: []const f64, out: []f64) -> err {
    let n = y.len
    let (am, e0) = mem.alloc[f64](a, p * p)
    let (rhs, e1) = mem.alloc[f64](a, p)
    let (beta, e2) = mem.alloc[f64](a, p)
    let (res, e3) = mem.alloc[f64](a, n)
    let (v, e4) = mem.alloc[f64](a, p * p)
    let (u, e5) = mem.alloc[f64](a, n * p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var r = 0usize
    var i = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += x[i * p + r] * w[i] * x[i * p + c]
                i += 1usize
            }
            am[r * p + c] = s
            c += 1usize
        }
        var t = 0.0f64
        i = 0usize
        while i < n {
            t += x[i * p + r] * w[i] * y[i]
            i += 1usize
        }
        rhs[r] = t
        r += 1usize
    }
    let (inv, ie) = gp.invert(a, am, p)
    if ie != ok { ret ie }
    r = 0usize
    while r < p {
        var b = 0.0f64
        var c = 0usize
        while c < p {
            b += inv[r * p + c] * rhs[c]
            c += 1usize
        }
        beta[r] = b
        r += 1usize
    }
    i = 0usize
    while i < n {
        var fit = 0.0f64
        r = 0usize
        while r < p {
            fit += x[i * p + r] * beta[r]
            r += 1usize
        }
        res[i] = y[i] - fit
        r = 0usize
        while r < p {
            u[i * p + r] = x[i * p + r] * w[i] * res[i]
            r += 1usize
        }
        i += 1usize
    }
    // V = u' delta u with delta_kl = 1 - pik_k pik_l / pikl_kl and delta_kk = 1 - pik_k
    r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                var l = 0usize
                while l < n {
                    var dl = 1.0f64 - pikl[k * n + k]
                    if k != l { dl = 1.0f64 - pikl[k * n + k] * pikl[l * n + l] / pikl[k * n + l] }
                    s += u[k * p + r] * dl * u[l * p + c]
                    l += 1usize
                }
                k += 1usize
            }
            v[r * p + c] = s
            c += 1usize
        }
        r += 1usize
    }
    // the Horvitz-Thompson estimate of y and the correction with the known totals of the other columns
    var est = 0.0f64
    i = 0usize
    while i < n {
        est += y[i] / pikl[i * n + i]
        i += 1usize
    }
    var j = 1usize
    while j < p {
        var ht = 0.0f64
        i = 0usize
        while i < n {
            ht += x[i * p + j] / pikl[i * n + i]
            i += 1usize
        }
        est += beta[j] * (tx[j - 1usize] - ht)
        j += 1usize
    }
    out[0usize] = est
    r = 0usize
    while r < p {
        out[1usize + r] = beta[r]
        var s = 0.0f64
        var c = 0usize
        while c < p {
            var vc = 0.0f64
            var d = 0usize
            while d < p {
                vc += v[c * p + d] * inv[d * p + r]
                d += 1usize
            }
            s += inv[r * p + c] * vc
            c += 1usize
        }
        out[1usize + p + r] = math.sqrt[f64](s)
        r += 1usize
    }
    ret ok
}

// postest without a Stratum column: the post-stratified estimator sum over the post-strata (in order of first appearance, NG[j] the known size of the j-th) of
// NG[j] sum(y / pik) / sum(1 / pik) within the post-stratum
fn post_estimator(y: []const f64, pik: []const f64, post: []const f64, ng: []const f64) -> f64 {
    let n = y.len
    var total = 0.0f64
    var j = 0usize
    var i = 0usize
    while i < n {
        var first = true
        var q = 0usize
        while q < i {
            if post[q] == post[i] { first = false }
            q += 1usize
        }
        if first {
            var num = 0.0f64
            var den = 0.0f64
            q = 0usize
            while q < n {
                if post[q] == post[i] {
                    num += y[q] / pik[q]
                    den += 1.0f64 / pik[q]
                }
                q += 1usize
            }
            total += ng[j] * num / den
            j += 1usize
        }
        i += 1usize
    }
    ret total
}

// srswr(n, N): rmultinom(1, n, rep(n / N, N)), i.e. sequential binomials of what is left with success probability prob / p_tot. R keeps p_tot in long double, so that probability is
// 1 / (N - k) correctly rounded (a double running sum drifts off the exact 1/2 of the last pair and flips rbinom's p > 0.5 branch); the draws use R's inversion sampler, so n times the
// smaller of p and 1 - p must stay under 30. s receives the counts.
fn srswr(g: *rr.Rng, n: usize, total: usize, s: []f64) {
    var left = f64(n)
    var k = 0usize
    while k < total {
        s[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k + 1usize < total {
        let pp = 1.0f64 / f64(total - k)
        var v = left
        if pp < 1.0f64 { v = rr.rbinom_inv(g, left, pp) }
        s[k] = v
        left -= v
        if left <= 0.0f64 { ret }
        k += 1usize
    }
    s[total - 1usize] = left
}


// x87 extended precision (64-bit mantissa) as a (hi, lo) pair of doubles: s = hi + lo with lo carrying at most the 11 bits below hi. R's sum() and rmultinom's p_tot are long doubles,
// and their rounding at 2^-64 decides some of the last bits of the conditional probabilities.
fn two_sum(x: f64, y: f64) -> (f64, f64) {
    let s = x + y
    let bb = s - x
    let er = (x - (s - bb)) + (y - bb)
    ret (s, er)
}

// round the exact pair (h, l) to a 64-bit mantissa, ties to even
fn ld_round(h: f64, l: f64) -> (f64, f64) {
    let (s, e) = two_sum(h, l)
    if s == 0.0f64 { ret (s, 0.0f64) }
    let bits = mem.bitcast[u64](s)
    let ex = i64((bits >> 52u64) & 2047u64) - 1023i64
    let qn = nm.pow2(ex - 63i64)
    let r = e / qn
    var fl = math.floor[f64](r)
    let d = r - fl
    if d > 0.5f64 { fl += 1.0f64 }
    if d == 0.5f64 {
        let half = fl / 2.0f64
        if half != math.floor[f64](half) { fl += 1.0f64 }
    }
    let (rh, rl) = two_sum(s, fl * qn)
    ret (rh, rl)
}

// (h, l) + p in extended precision
fn ld_add(h: f64, l: f64, p: f64) -> (f64, f64) {
    let (s, e) = two_sum(h, p)
    let (rh, rl) = ld_round(s, l + e)
    ret (rh, rl)
}

// UPmultinomial(pik): rmultinom(1, sum(pik), pik / sum(pik)) as R computes it. sum() runs in long double and the size is truncated to an integer; the C code normalises the
// probabilities again with a double running sum, adds them into a long double p_tot and subtracts them one by one, drawing sequential binomials with prob_k / p_tot (R's inversion
// sampler, so n times the smaller of p and 1 - p must stay under 30). s receives the counts.
fn up_multinomial(g: *rr.Rng, a: *mem.Arena, pik: []const f64, s: []f64) -> err {
    let n = pik.len
    let (prob, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret mem.Full }
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < n {
        let (h2, l2) = ld_add(hi, lo, pik[i])
        hi = h2
        lo = l2
        i += 1usize
    }
    let tot = hi + lo
    let size = math.floor[f64](tot)
    var sum2 = 0.0f64
    i = 0usize
    while i < n {
        prob[i] = pik[i] / tot
        sum2 += prob[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        prob[i] = prob[i] / sum2
        i += 1usize
    }
    var ph = 0.0f64
    var pl = 0.0f64
    i = 0usize
    while i < n {
        let (h2, l2) = ld_add(ph, pl, prob[i])
        ph = h2
        pl = l2
        s[i] = 0.0f64
        i += 1usize
    }
    var left = size
    var k = 0usize
    while k + 1usize < n {
        if prob[k] > 0.0f64 {
            // prob / p_tot in extended precision rounded to a double
            let q1 = prob[k] / ph
            let pp = q1 - q1 * (pl / ph)
            var v = left
            if pp < 1.0f64 { v = rr.rbinom_inv(g, left, pp) }
            s[k] = v
            left -= v
        }
        if left <= 0.0f64 { ret ok }
        let (h3, l3) = ld_add(ph, pl, 0.0f64 - prob[k])
        ph = h3
        pl = l3
        k += 1usize
    }
    s[n - 1usize] = left
    ret ok
}

// UPMEqfromw(w, n): the conditional inclusion probabilities q (N by n, row-major, 1-based in the comments) of the maximum entropy design with odds w
fn me_q_from_w(a: *mem.Arena, w: []const f64, n: usize, q: []f64) -> err {
    let nn = w.len
    let (ex, e0) = mem.alloc[f64](a, nn * n)
    if e0 != ok { ret mem.Full }
    var i = 0usize
    while i < nn * n {
        ex[i] = 0.0f64
        q[i] = 0.0f64
        i += 1usize
    }
    // expa[i, 1] = sum(w[i:N]) (0-based row r)
    var r = 0usize
    while r < nn {
        var sm = 0.0f64
        var j = r
        while j < nn {
            sm += w[j]
            j += 1usize
        }
        ex[r * n] = sm
        r += 1usize
    }
    // expa[i, N - i + 1] = exp(sum(log(w[i:N]))) for i = N - n + 1 .. N
    r = nn - n
    while r < nn {
        var sl = 0.0f64
        var j = r
        while j < nn {
            sl += math.log[f64](w[j])
            j += 1usize
        }
        ex[r * n + (nn - r - 1usize)] = math.exp[f64](sl)
        r += 1usize
    }
    // expa[i, z] = w[i] expa[i + 1, z - 1] + expa[i + 1, z], i = N - 2 .. 1, z = 2 .. min(N - i, n)
    if nn >= 3usize {
        var ii = nn - 2usize
        while ii >= 1usize {
            var lim = nn - ii
            if n < lim { lim = n }
            var z = 2usize
            while z <= lim {
                ex[(ii - 1usize) * n + (z - 1usize)] = w[ii - 1usize] * ex[ii * n + (z - 2usize)] + ex[ii * n + (z - 1usize)]
                z += 1usize
            }
            ii -= 1usize
        }
    }
    r = 0usize
    while r < nn {
        q[r * n] = w[r] / ex[r * n]
        r += 1usize
    }
    r = nn - n
    while r < nn {
        q[r * n + (nn - r - 1usize)] = 1.0f64
        r += 1usize
    }
    if nn >= 3usize {
        var ii = nn - 2usize
        while ii >= 1usize {
            var lim = nn - ii
            if n < lim { lim = n }
            var z = 2usize
            while z <= lim {
                q[(ii - 1usize) * n + (z - 1usize)] = w[ii - 1usize] * ex[ii * n + (z - 2usize)] / ex[(ii - 1usize) * n + (z - 1usize)]
                z += 1usize
            }
            ii -= 1usize
        }
    }
    ret ok
}

// UPMEpikfromq(q): the first-order inclusion probabilities implied by q (N by n)
fn me_pik_from_q(a: *mem.Arena, q: []const f64, nn: usize, n: usize, out: []f64) -> err {
    let (pro, e0) = mem.alloc[f64](a, nn * n)
    if e0 != ok { ret mem.Full }
    var i = 0usize
    while i < nn * n {
        pro[i] = 0.0f64
        i += 1usize
    }
    pro[n - 1usize] = 1.0f64
    var r = 2usize
    while r <= nn {
        var c = 2usize
        while c <= n {
            let pv = pro[(r - 2usize) * n + (c - 1usize)]
            pro[(r - 1usize) * n + (c - 1usize)] = pro[(r - 1usize) * n + (c - 1usize)] + pv * (1.0f64 - q[(r - 2usize) * n + (c - 1usize)])
            pro[(r - 1usize) * n + (c - 2usize)] = pro[(r - 1usize) * n + (c - 2usize)] + pv * q[(r - 2usize) * n + (c - 1usize)]
            c += 1usize
        }
        r += 1usize
    }
    r = 2usize
    while r <= nn {
        pro[(r - 1usize) * n] = pro[(r - 1usize) * n] + pro[(r - 2usize) * n] * (1.0f64 - q[(r - 2usize) * n])
        r += 1usize
    }
    r = 0usize
    while r < nn {
        var sm = 0.0f64
        var c = 0usize
        while c < n {
            sm += pro[r * n + c] * q[r * n + c]
            c += 1usize
        }
        out[r] = sm
        r += 1usize
    }
    ret ok
}

// UPMEpiktildefrompik(pik): the tilde probabilities by the fixed-point iteration (eps 1e-6); n = round(sum(pik)); out is pikt
fn me_pikt_from_pik(a: *mem.Arena, pik: []const f64, out: []f64) -> err {
    let nn = pik.len
    var tot = 0.0f64
    var i = 0usize
    while i < nn {
        tot += pik[i]
        i += 1usize
    }
    let n = usize(math.floor[f64](tot + 0.5f64))
    let (w, e0) = mem.alloc[f64](a, nn)
    let (q, e1) = mem.alloc[f64](a, nn * n)
    let (pf, e2) = mem.alloc[f64](a, nn)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    i = 0usize
    while i < nn {
        out[i] = pik[i]
        i += 1usize
    }
    var arr = 1.0f64
    var guard = 0usize
    while arr > 1.0e-6f64 && guard < 100000usize {
        i = 0usize
        while i < nn {
            w[i] = out[i] / (1.0f64 - out[i])
            i += 1usize
        }
        let m = mem.mark(a)
        let eq = me_q_from_w(a, w, n, q)
        if eq != ok { ret eq }
        let ep = me_pik_from_q(a, q, nn, n, pf)
        mem.reset(a, m)
        if ep != ok { ret ep }
        arr = 0.0f64
        i = 0usize
        while i < nn {
            let p1 = out[i] + pik[i] - pf[i]
            arr += math.abs[f64](out[i] - p1)
            out[i] = p1
            i += 1usize
        }
        guard += 1usize
    }
    ret ok
}

// UPmaxentropy(pik): the maximum entropy (conditional Poisson) sample; s receives 0 or 1
fn up_maxentropy(g: *rr.Rng, a: *mem.Arena, pik: []const f64, s: []f64) -> err {
    let nt = pik.len
    var tot = 0.0f64
    var i = 0usize
    while i < nt {
        tot += pik[i]
        i += 1usize
    }
    var n = usize(math.floor[f64](tot + 0.5f64))
    i = 0usize
    while i < nt {
        s[i] = 0.0f64
        i += 1usize
    }
    if n == 0usize { ret ok }
    if n == 1usize { ret up_multinomial(g, a, pik, s) }
    var m2 = 0usize
    i = 0usize
    while i < nt {
        if pik[i] != 1.0f64 { m2 += 1usize } else { s[i] = 1.0f64 }
        i += 1usize
    }
    let (p2, e0) = mem.alloc[f64](a, m2)
    let (pt, e1) = mem.alloc[f64](a, m2)
    let (w, e2) = mem.alloc[f64](a, m2)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var c = 0usize
    var s2sum = 0.0f64
    i = 0usize
    while i < nt {
        if pik[i] != 1.0f64 {
            p2[c] = pik[i]
            s2sum += pik[i]
            c += 1usize
        }
        i += 1usize
    }
    n = usize(math.floor[f64](s2sum + 0.5f64))
    let ep = me_pikt_from_pik(a, p2, pt)
    if ep != ok { ret ep }
    i = 0usize
    while i < m2 {
        w[i] = pt[i] / (1.0f64 - pt[i])
        i += 1usize
    }
    let (q, e3) = mem.alloc[f64](a, m2 * n)
    if e3 != ok { ret mem.Full }
    let eq = me_q_from_w(a, w, n, q)
    if eq != ok { ret eq }
    // UPMEsfromq: one uniform per unit while the count is not exhausted
    var left = n
    var k = 0usize
    var pos = 0usize
    while k < nt {
        if pik[k] != 1.0f64 {
            if left != 0usize {
                if rr.unif(g) < q[pos * n + (left - 1usize)] {
                    s[k] = 1.0f64
                    left -= 1usize
                }
            }
            pos += 1usize
        }
        k += 1usize
    }
    ret ok
}

// UPMEpik2frompikw(pik, w): the joint inclusion matrix of the maximum entropy design from the first-order probabilities and odds; m is N by N row-major
fn me_pik2_from_pikw(pik: []const f64, w: []const f64, m: []f64) {
    let nn = pik.len
    var tot = 0.0f64
    var k = 0usize
    while k < nn {
        tot += pik[k]
        k += 1usize
    }
    let n = math.floor[f64](tot + 0.5f64)
    k = 0usize
    while k < nn {
        var l = 0usize
        while l < nn {
            if pik[k] != pik[l] && k != l {
                m[k * nn + l] = (pik[k] * w[l] - pik[l] * w[k]) / (w[l] - w[k])
            } else {
                m[k * nn + l] = -1.0f64
            }
            l += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < nn {
        m[k * nn + k] = pik[k]
        k += 1usize
    }
    k = 0usize
    while k < nn {
        var tt = 0.0f64
        var comp = 0.0f64
        var l = 0usize
        while l < nn {
            if m[k * nn + l] != -1.0f64 { tt += m[k * nn + l] } else { comp += 1.0f64 }
            l += 1usize
        }
        let cc = (n * pik[k] - tt) / comp
        l = 0usize
        while l < nn {
            if m[k * nn + l] == -1.0f64 { m[k * nn + l] = cc }
            l += 1usize
        }
        k += 1usize
    }
}

// UPmaxentropypi2(pik): the joint inclusion probabilities of UPmaxentropy; pi2 is N by N row-major
fn up_maxentropy_pi2(a: *mem.Arena, pik: []const f64, pi2: []f64) -> err {
    let nt = pik.len
    var tot = 0.0f64
    var i = 0usize
    while i < nt {
        tot += pik[i]
        i += 1usize
    }
    let n = usize(math.floor[f64](tot + 0.5f64))
    i = 0usize
    while i < nt * nt {
        pi2[i] = 0.0f64
        i += 1usize
    }
    if n == 1usize {
        i = 0usize
        while i < nt {
            pi2[i * nt + i] = pik[i]
            i += 1usize
        }
    }
    if n < 2usize { ret ok }
    var m2 = 0usize
    i = 0usize
    while i < nt {
        if pik[i] > 0.0f64 && pik[i] < 1.0f64 { m2 += 1usize }
        i += 1usize
    }
    let (idx, e0) = mem.alloc[usize](a, m2)
    let (p2, e1) = mem.alloc[f64](a, m2)
    let (pt, e2) = mem.alloc[f64](a, m2)
    let (w, e3) = mem.alloc[f64](a, m2)
    let (mm, e4) = mem.alloc[f64](a, m2 * m2)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var c = 0usize
    i = 0usize
    while i < nt {
        if pik[i] > 0.0f64 && pik[i] < 1.0f64 {
            idx[c] = i
            p2[c] = pik[i]
            c += 1usize
        }
        i += 1usize
    }
    let ep = me_pikt_from_pik(a, p2, pt)
    if ep != ok { ret ep }
    i = 0usize
    while i < m2 {
        w[i] = pt[i] / (1.0f64 - pt[i])
        i += 1usize
    }
    me_pik2_from_pikw(p2, w, mm)
    i = 0usize
    while i < m2 {
        var j = 0usize
        while j < m2 {
            pi2[idx[i] * nt + idx[j]] = mm[i * m2 + j]
            j += 1usize
        }
        i += 1usize
    }
    // the columns of the certain units hold pik, and so do their rows
    var j = 0usize
    while j < nt {
        if pik[j] == 1.0f64 {
            i = 0usize
            while i < nt {
                pi2[i * nt + j] = pik[i]
                i += 1usize
            }
        }
        j += 1usize
    }
    i = 0usize
    while i < nt {
        if pik[i] == 1.0f64 {
            j = 0usize
            while j < nt {
                pi2[i * nt + j] = pik[j]
                j += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}

// postest with a Stratum column: for each post-stratum j (order of first appearance) Ng = the column sum of NG (rows are the known strata by post-strata counts, ng is row-major rows by ngc);
// for each stratum with a non-empty intersection the running sums t1 = sum(y / pik) and t2 = sum(1 / pik) over the intersections so far add Ng t1 / t2 to the total, as sampling does
fn post_estimator2(y: []const f64, pik: []const f64, stratum: []const f64, post: []const f64, ng: []const f64, nrows: usize, ngc: usize) -> f64 {
    let n = y.len
    var total = 0.0f64
    var j = 0usize
    var i = 0usize
    while i < n {
        var firstp = true
        var q = 0usize
        while q < i {
            if post[q] == post[i] { firstp = false }
            q += 1usize
        }
        if firstp {
            var ngsum = 0.0f64
            var r = 0usize
            while r < nrows {
                ngsum += ng[r * ngc + j]
                r += 1usize
            }
            var t1 = 0.0f64
            var t2 = 0.0f64
            var k = 0usize
            while k < n {
                var firsts = true
                q = 0usize
                while q < k {
                    if stratum[q] == stratum[k] { firsts = false }
                    q += 1usize
                }
                if firsts {
                    var any = false
                    q = 0usize
                    while q < n {
                        if stratum[q] == stratum[k] && post[q] == post[i] {
                            any = true
                            t1 += y[q] / pik[q]
                            t2 += 1.0f64 / pik[q]
                        }
                        q += 1usize
                    }
                    if any { total += ngsum * t1 / t2 }
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret total
}
