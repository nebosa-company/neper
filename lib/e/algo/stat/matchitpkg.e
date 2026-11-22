// R MatchIt on a logistic propensity score (distance = "glm", the probability scale): method = "nearest" (ratio, replace,
// caliper in standard deviations of the score, exact strata, m.order largest / smallest / data / random / closest / farthest,
// ATT or ATC), method = "exact" and method = "subclass" (ATT, ATC, ATE; min.n = 0), and summary() balance statistics.
// Weights are MatchIt's, normalised so the nonzero weights of each group average 1.
//
// Not here: mahalanobis and matrix distances, variable ratio, antiexact and unit.id, discard, covariate calipers, min.n > 0 scooting
// in subclass, full and optimal matching (optmatch), genetic matching, cem.

use e.algo.stat.gparot as gp
use e.math.dist as md
use e.algo.stat.classint as ci
use e.algo.rand.r as rr
use e.math
use e.mem

// binomial glm score by Fisher scoring: link 0 logit, 1 probit, 2 cloglog; linear returns the linear predictor instead of the probability
fn pscore_link(a: *mem.Arena, x: []const f64, t: []const f64, n: usize, p: usize, link: usize, linear: bool, ps: []f64) -> err {
    let q = p + 1usize
    let (b, e1) = mem.alloc[f64](a, q)
    let (h, e2) = mem.alloc[f64](a, q * q)
    let (g, e3) = mem.alloc[f64](a, q)
    let (eta, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    var i = 0usize
    while i < n {
        let m = (t[i] + 0.5f64) / 2.0f64
        if link == 0usize { eta[i] = math.log[f64](m / (1.0f64 - m)) }
        if link == 1usize { eta[i] = md.qnorm(m, 0.0f64, 1.0f64, true, false) }
        if link == 2usize { eta[i] = math.log[f64](0.0f64 - math.log[f64](1.0f64 - m)) }
        i += 1usize
    }
    // R glm.fit: stop when the deviance moves by less than 1e-8 relative, so the same iterate is returned
    var devold = 0.0f64
    i = 0usize
    while i < n {
        let m0 = (t[i] + 0.5f64) / 2.0f64
        if t[i] > 0.5f64 { devold += 2.0f64 * math.log[f64](1.0f64 / m0) } else { devold += 2.0f64 * math.log[f64](1.0f64 / (1.0f64 - m0)) }
        i += 1usize
    }
    var it = 0usize
    while it < 100usize {
        var r = 0usize
        while r < q * q {
            h[r] = 0.0f64
            r += 1usize
        }
        r = 0usize
        while r < q {
            g[r] = 0.0f64
            r += 1usize
        }
        i = 0usize
        while i < n {
            var mu = 0.0f64
            var me = 0.0f64
            if link == 0usize {
                mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta[i]))
                me = mu * (1.0f64 - mu)
            } else if link == 1usize {
                mu = md.pnorm(eta[i], 0.0f64, 1.0f64, true, false)
                me = md.dnorm(eta[i], 0.0f64, 1.0f64, false)
            } else {
                let ee = math.exp[f64](eta[i])
                mu = 1.0f64 - math.exp[f64](0.0f64 - ee)
                me = ee * math.exp[f64](0.0f64 - ee)
            }
            let wi = me * me / (mu * (1.0f64 - mu))
            let z = eta[i] + (t[i] - mu) / me
            var ra = 0usize
            while ra < q {
                var xa = 1.0f64
                if ra > 0usize { xa = x[i * p + ra - 1usize] }
                g[ra] += wi * xa * z
                var rb = 0usize
                while rb < q {
                    var xb = 1.0f64
                    if rb > 0usize { xb = x[i * p + rb - 1usize] }
                    h[ra * q + rb] += wi * xa * xb
                    rb += 1usize
                }
                ra += 1usize
            }
            i += 1usize
        }
        let (inv, ie) = gp.invert(a, h, q)
        if ie != ok { ret ie }
        var step = 0.0f64
        var ra = 0usize
        while ra < q {
            var v = 0.0f64
            var rb = 0usize
            while rb < q {
                v += inv[ra * q + rb] * g[rb]
                rb += 1usize
            }
            step = math.max[f64](step, math.abs[f64](v - b[ra]))
            b[ra] = v
            ra += 1usize
        }
        i = 0usize
        while i < n {
            var e = b[0usize]
            var j = 0usize
            while j < p {
                e += b[1usize + j] * x[i * p + j]
                j += 1usize
            }
            eta[i] = e
            i += 1usize
        }
        it += 1usize
        var dev = 0.0f64
        i = 0usize
        while i < n {
            var mu = 0.0f64
            if link == 0usize { mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta[i])) }
            if link == 1usize { mu = md.pnorm(eta[i], 0.0f64, 1.0f64, true, false) }
            if link == 2usize { mu = 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](eta[i])) }
            if t[i] > 0.5f64 { dev += 2.0f64 * math.log[f64](1.0f64 / mu) } else { dev += 2.0f64 * math.log[f64](1.0f64 / (1.0f64 - mu)) }
            i += 1usize
        }
        let done = math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64
        devold = dev
        if done { break }
    }
    i = 0usize
    while i < n {
        var v = eta[i]
        if !linear {
            if link == 0usize { v = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta[i])) }
            if link == 1usize { v = md.pnorm(eta[i], 0.0f64, 1.0f64, true, false) }
            if link == 2usize { v = 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](eta[i])) }
        }
        ps[i] = v
        i += 1usize
    }
    ret ok
}

fn pscore(a: *mem.Arena, x: []const f64, t: []const f64, n: usize, p: usize, ps: []f64) -> err {
    ret pscore_link(a, x, t, n, p, 0usize, false, ps)
}

// R sd(): two-pass sample standard deviation
fn sd_of(v: []const f64, n: usize) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += v[i]
        i += 1usize
    }
    m = m / f64(n)
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += (v[i] - m) * (v[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(n - 1usize))
}

// the eligible control nearest to unit i (by score) inside the caliper and i's stratum; n when none. Ties go to the lower index.
// skip is a control to leave out (the previous match when a pair is re-made), or n.
fn nearest_control(ps: []const f64, dm: []const f64, foc: []const bool, elig: []const bool, st: []const f64, n: usize, i: usize, cal: f64, skip: usize, exclude: []const usize, nex: usize) -> usize {
    var best = n
    var bd = 1.0e300f64
    var c = 0usize
    while c < n {
        if !foc[c] && elig[c] && c != skip && (st.len == 0usize || st[c] == st[i]) {
            var banned = false
            var q = 0usize
            while q < nex {
                if exclude[q] == c { banned = true }
                q += 1usize
            }
            let d = dm[i * n + c]
            if !banned && math.abs[f64](ps[c] - ps[i]) <= cal && d < bd {
                bd = d
                best = c
            }
        }
        c += 1usize
    }
    ret best
}

// R's std::lower_bound over heap[lo..hi) with the comparison "dist[element] < dist[hi_unit]" (close) or ">=" (farthest)
fn lower_bound(heap: []const usize, dist: []const f64, lo: usize, hi: usize, unit: usize, close: bool) -> usize {
    var first = lo
    var count = hi - lo
    while count > 0usize {
        let step = count / 2usize
        let it = first + step
        var less = false
        if close { less = dist[heap[it]] < dist[unit] } else { less = dist[heap[it]] >= dist[unit] }
        if less {
            first = it + 1usize
            count = count - step - 1usize
        } else {
            count = step
        }
    }
    ret first
}

// scale each group's nonzero weights to average 1 (MatchIt normalize = TRUE); t is the original 0/1 treatment
fn normalize(w: []f64, t: []const f64, n: usize) {
    var g = 0usize
    while g < 2usize {
        var s = 0.0f64
        var k = 0.0f64
        var i = 0usize
        while i < n {
            if (t[i] > 0.5f64) == (g == 1usize) && w[i] > 0.0f64 {
                s += w[i]
                k += 1.0f64
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            if (t[i] > 0.5f64) == (g == 1usize) && w[i] > 0.0f64 { w[i] = k * w[i] / s }
            i += 1usize
        }
        g += 1usize
    }
}

// pairwise matching distances: |score difference| (mah 0) or the squared Mahalanobis distance on the first mah covariates, with the
// pooled within-group covariance (the ordering is what matching uses)
fn distances(a: *mem.Arena, x: []const f64, t: []const f64, n: usize, p: usize, ps: []const f64, mah: usize, dm: []f64) -> err {
    var i = 0usize
    var j = 0usize
    if mah == 0usize {
        while i < n {
            j = 0usize
            while j < n {
                dm[i * n + j] = math.abs[f64](ps[i] - ps[j])
                j += 1usize
            }
            i += 1usize
        }
        ret ok
    }
    let k = mah
    let (cv, e1) = mem.alloc[f64](a, k * k)
    let (mu, e2) = mem.alloc[f64](a, 2usize * k)
    if e1 != ok || e2 != ok { ret e1 }
    var c = 0usize
    while c < 2usize * k {
        mu[c] = 0.0f64
        c += 1usize
    }
    var n1 = 0.0f64
    i = 0usize
    while i < n {
        var g = 0usize
        if t[i] > 0.5f64 {
            g = 1usize
            n1 += 1.0f64
        }
        c = 0usize
        while c < k {
            mu[g * k + c] += x[i * p + c]
            c += 1usize
        }
        i += 1usize
    }
    c = 0usize
    while c < k {
        mu[c] = mu[c] / (f64(n) - n1)
        mu[k + c] = mu[k + c] / n1
        c += 1usize
    }
    c = 0usize
    while c < k * k {
        cv[c] = 0.0f64
        c += 1usize
    }
    i = 0usize
    while i < n {
        var g = 0usize
        if t[i] > 0.5f64 { g = 1usize }
        var r = 0usize
        while r < k {
            c = 0usize
            while c < k {
                cv[r * k + c] += (x[i * p + r] - mu[g * k + r]) * (x[i * p + c] - mu[g * k + c])
                c += 1usize
            }
            r += 1usize
        }
        i += 1usize
    }
    c = 0usize
    while c < k * k {
        cv[c] = cv[c] / (f64(n) - 2.0f64)
        c += 1usize
    }
    let (iv, e3) = gp.invert(a, cv, k)
    if e3 != ok { ret e3 }
    i = 0usize
    while i < n {
        j = 0usize
        while j < n {
            var s = 0.0f64
            var r = 0usize
            while r < k {
                c = 0usize
                while c < k {
                    s += (x[i * p + r] - x[j * p + r]) * iv[r * k + c] * (x[i * p + c] - x[j * p + c])
                    c += 1usize
                }
                r += 1usize
            }
            dm[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// t is 0/1, x is n by p without a constant. ratio controls per focal unit; replace allows reuse; caliper < 0 means none, else in
// standard deviations of the score (link 0 logit, 1 probit, 2 cloglog; linear scores by the linear predictor); mah > 0 matches on the
// Mahalanobis distance of the first mah covariates, the score still ordering and bounding when psdist, else distance = "mahalanobis"; order 0 largest, 1 smallest, 2 data, 3 random (set.seed(seed) before matching), 4 closest,
// 5 farthest; atc matches treated units to each control instead; strata (length 0 or n) are exact-match codes.
// w receives the normalised matching weights, ps the fitted propensity scores.
fn nearest(a: *mem.Arena, x: []const f64, t: []const f64, n: usize, p: usize, ratio: usize, replace: bool, caliper: f64, order0: usize, atc: bool, strata: []const f64, seed: i64, link: usize, linear: bool, mah: usize, psdist: bool, w: []f64, ps: []f64) -> err {
    let e0 = pscore_link(a, x, t, n, p, link, linear, ps)
    if e0 != ok { ret e0 }
    let (foc, e1) = mem.alloc[bool](a, n)
    let (elig, e2) = mem.alloc[bool](a, n)
    let (ind, e3) = mem.alloc[usize](a, n)
    let (ord, e4) = mem.alloc[usize](a, n)
    let (mm, e5) = mem.alloc[usize](a, n * ratio)
    let (fill, e6) = mem.alloc[usize](a, n)
    let (used, e7) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e1 }
    var nf = 0usize
    var i = 0usize
    while i < n {
        foc[i] = (t[i] > 0.5f64) != atc
        elig[i] = true
        w[i] = 0.0f64
        fill[i] = 0usize
        if foc[i] {
            ind[nf] = i
            nf += 1usize
        }
        i += 1usize
    }
    var cal = 1.0e300f64
    if caliper >= 0.0f64 && (psdist || mah == 0usize) { cal = caliper * sd_of(ps, n) }
    let (dm, ed) = mem.alloc[f64](a, n * n)
    if ed != ok { ret ed }
    let ee = distances(a, x, t, n, p, ps, mah, dm)
    if ee != ok { ret ee }
    var order = order0
    if !replace && nf > 1usize { order = order0 } else { order = 2usize }
    // the order the focal units are visited in
    i = 0usize
    while i < nf {
        ord[i] = ind[i]
        i += 1usize
    }
    if order == 0usize || order == 1usize {
        i = 1usize
        while i < nf {
            let v = ord[i]
            var j = i
            var go = true
            while j > 0usize && go {
                go = false
                if order == 0usize && ps[ord[j - 1usize]] < ps[v] { go = true }
                if order == 1usize && ps[ord[j - 1usize]] > ps[v] { go = true }
                if go {
                    ord[j] = ord[j - 1usize]
                    j -= 1usize
                }
            }
            ord[j] = v
            i += 1usize
        }
    }
    if order == 3usize {
        var rng: rr.Rng = zero
        rr.seed(&rng, seed)
        let (pm, pe) = rr.sample_int(a, &rng, i64(nf), i64(nf), false)
        if pe != ok { ret pe }
        i = 0usize
        while i < nf {
            ord[i] = ind[usize(pm[i] - 1i64)]
            i += 1usize
        }
    }
    if replace || nf <= 1usize {
        // every treated unit takes its ratio nearest controls at once
        i = 0usize
        while i < nf {
            let u = ord[i]
            var k = 0usize
            while k < ratio {
                let c = nearest_control(ps, dm, foc, elig, strata, n, u, cal, n, used, k)
                if c == n { break }
                used[k] = c
                k += 1usize
            }
            var q = 0usize
            while q < k {
                mm[u * ratio + q] = used[q]
                q += 1usize
            }
            fill[u] = k
            i += 1usize
        }
    } else if order != 4usize && order != 5usize {
        var pass = 0usize
        while pass < ratio {
            i = 0usize
            while i < nf {
                let u = ord[i]
                if elig[u] {
                    let c = nearest_control(ps, dm, foc, elig, strata, n, u, cal, n, used, 0usize)
                    if c == n {
                        elig[u] = false
                    } else {
                        mm[u * ratio + fill[u]] = c
                        fill[u] += 1usize
                        elig[c] = false
                        if fill[u] >= ratio { elig[u] = false }
                    }
                }
                i += 1usize
            }
            pass += 1usize
        }
    } else {
        let close = order == 4usize
        let (tt, f1) = mem.alloc[usize](a, nf)
        let (cc, f2) = mem.alloc[usize](a, nf)
        let (dd, f3) = mem.alloc[f64](a, n)
        let (heap, f4) = mem.alloc[usize](a, nf)
        if f1 != ok || f2 != ok || f3 != ok || f4 != ok { ret f1 }
        var ne0 = n - nf
        var ne1 = nf
        var pass = 0usize
        while pass < ratio {
            var np = 0usize
            i = 0usize
            while i < nf {
                let u = ind[i]
                if elig[u] {
                    let c = nearest_control(ps, dm, foc, elig, strata, n, u, cal, n, used, 0usize)
                    if c == n {
                        elig[u] = false
                        ne1 -= 1usize
                    } else {
                        tt[np] = u
                        cc[np] = c
                        dd[np] = dm[u * n + c]
                        np += 1usize
                    }
                }
                i += 1usize
            }
            // stable sort of the pairs by distance, ascending when closest, descending when farthest
            i = 0usize
            while i < np {
                heap[i] = i
                i += 1usize
            }
            i = 1usize
            while i < np {
                let v = heap[i]
                var j = i
                var go = true
                while j > 0usize && go {
                    go = false
                    if close && dd[heap[j - 1usize]] > dd[v] { go = true }
                    if !close && dd[heap[j - 1usize]] < dd[v] { go = true }
                    if go {
                        heap[j] = heap[j - 1usize]
                        j -= 1usize
                    }
                }
                heap[j] = v
                i += 1usize
            }
            var h = 0usize
            while ne0 > 0usize && ne1 > 0usize && h < np {
                let hi = heap[h]
                let u = tt[hi]
                if !elig[u] {
                    h += 1usize
                } else if !elig[cc[hi]] {
                    let c = nearest_control(ps, dm, foc, elig, strata, n, u, cal, n, used, 0usize)
                    if c == n {
                        elig[u] = false
                        ne1 -= 1usize
                    } else {
                        cc[hi] = c
                        dd[hi] = dm[u * n + c]
                        let pos = lower_bound(heap, dd, h, np, hi, close)
                        if pos != h {
                            let keep = heap[h]
                            var q = h
                            while q + 1usize < pos {
                                heap[q] = heap[q + 1usize]
                                q += 1usize
                            }
                            heap[pos - 1usize] = keep
                        }
                    }
                } else {
                    mm[u * ratio + fill[u]] = cc[hi]
                    fill[u] += 1usize
                    elig[cc[hi]] = false
                    ne0 -= 1usize
                    if fill[u] >= ratio {
                        elig[u] = false
                        ne1 -= 1usize
                    }
                    h += 1usize
                }
            }
            pass += 1usize
        }
    }
    i = 0usize
    while i < nf {
        let u = ind[i]
        if fill[u] > 0usize {
            w[u] += 1.0f64
            var q = 0usize
            while q < fill[u] {
                w[mm[u * ratio + q]] += 1.0f64 / f64(fill[u])
                q += 1usize
            }
        }
        i += 1usize
    }
    normalize(w, t, n)
    ret ok
}

// subclass codes sub (0 = unmatched, else 1..nsub) to MatchIt weights; est 0 ATT, 1 ATC, 2 ATE; then normalised
fn subclass_weights(a: *mem.Arena, sub: []const usize, nsub: usize, t: []const f64, n: usize, est: usize, w: []f64) -> err {
    let (m1, e1) = mem.alloc[f64](a, nsub + 1usize)
    let (m0, e2) = mem.alloc[f64](a, nsub + 1usize)
    if e1 != ok || e2 != ok { ret e1 }
    var s = 0usize
    while s <= nsub {
        m1[s] = 0.0f64
        m0[s] = 0.0f64
        s += 1usize
    }
    var i = 0usize
    while i < n {
        if sub[i] > 0usize {
            if t[i] > 0.5f64 { m1[sub[i]] += 1.0f64 } else { m0[sub[i]] += 1.0f64 }
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        w[i] = 0.0f64
        if sub[i] > 0usize {
            let tr = t[i] > 0.5f64
            if est == 0usize {
                if tr { w[i] = 1.0f64 } else { w[i] = m1[sub[i]] / m0[sub[i]] }
            } else if est == 1usize {
                if tr { w[i] = m0[sub[i]] / m1[sub[i]] } else { w[i] = 1.0f64 }
            } else {
                if tr { w[i] = 1.0f64 + m0[sub[i]] / m1[sub[i]] } else { w[i] = 1.0f64 + m1[sub[i]] / m0[sub[i]] }
            }
        }
        i += 1usize
    }
    normalize(w, t, n)
    ret ok
}

// method = "exact": strata codes (equal codes match); strata holding both groups are subclasses
fn exact(a: *mem.Arena, st: []const f64, t: []const f64, n: usize, est: usize, w: []f64) -> err {
    let (sub, e1) = mem.alloc[usize](a, n)
    let (key, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret e1 }
    var nk = 0usize
    var i = 0usize
    while i < n {
        var j = 0usize
        var at = nk
        while j < nk {
            if key[j] == st[i] { at = j }
            j += 1usize
        }
        if at == nk {
            key[nk] = st[i]
            nk += 1usize
        }
        sub[i] = at + 1usize
        i += 1usize
    }
    // drop strata missing a group
    var k = 1usize
    while k <= nk {
        var has1 = false
        var has0 = false
        i = 0usize
        while i < n {
            if sub[i] == k {
                if t[i] > 0.5f64 { has1 = true } else { has0 = true }
            }
            i += 1usize
        }
        if !(has1 && has0) {
            i = 0usize
            while i < n {
                if sub[i] == k { sub[i] = 0usize }
                i += 1usize
            }
        }
        k += 1usize
    }
    ret subclass_weights(a, sub, nk, t, n, est, w)
}

// method = "subclass" with nsub equal-probability classes of the score (min.n = 0: classes lacking a group are dropped);
// sub receives the 1-based class (0 = dropped), w the weights, ps the scores
fn subclass(a: *mem.Arena, x: []const f64, t: []const f64, n: usize, p: usize, nsub: usize, est: usize, min_n: usize, sub: []usize, w: []f64, ps: []f64) -> err {
    let e0 = pscore(a, x, t, n, p, ps)
    if e0 != ok { ret e0 }
    let (ref, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var m = 0usize
    var i = 0usize
    while i < n {
        if est == 2usize || (est == 0usize && t[i] > 0.5f64) || (est == 1usize && t[i] < 0.5f64) {
            ref[m] = ps[i]
            m += 1usize
        }
        i += 1usize
    }
    // insertion sort of the reference scores
    i = 1usize
    while i < m {
        let v = ref[i]
        var j = i
        while j > 0usize && ref[j - 1usize] > v {
            ref[j] = ref[j - 1usize]
            j -= 1usize
        }
        ref[j] = v
        i += 1usize
    }
    let (qu, e2) = mem.alloc[f64](a, nsub + 1usize)
    if e2 != ok { ret e2 }
    let by = 1.0f64 / f64(nsub)
    var q = 0usize
    while q <= nsub {
        var pr = f64(q) * by
        if q == nsub { pr = 1.0f64 }
        qu[q] = ci.quantile7(ref[0usize..m], pr)
        q += 1usize
    }
    i = 0usize
    while i < n {
        // findInterval(all.inside = TRUE)
        var k = 1usize
        while k < nsub && ps[i] >= qu[k] { k += 1usize }
        sub[i] = k
        i += 1usize
    }
    var k = 1usize
    while k <= nsub && min_n == 0usize {
        var has1 = false
        var has0 = false
        i = 0usize
        while i < n {
            if sub[i] == k {
                if t[i] > 0.5f64 { has1 = true } else { has0 = true }
            }
            i += 1usize
        }
        if !(has1 && has0) {
            i = 0usize
            while i < n {
                if sub[i] == k { sub[i] = 0usize }
                i += 1usize
            }
        }
        k += 1usize
    }
    if min_n > 0usize {
        let se = scoot(a, sub, t, ps, n, nsub, min_n)
        if se != ok { ret se }
    }
    ret subclass_weights(a, sub, nsub, t, n, est, w)
}

error TooFewUnits

// MatchIt subclass_scoot: when a class lacks min_n units of a group, move the nearest-in-score unit of the nearest class holding spares
fn scoot(a: *mem.Arena, sub: []usize, t: []const f64, x: []const f64, n: usize, nsub: usize, min_n: usize) -> err {
    // classes present, in order
    let (pos, e1) = mem.alloc[usize](a, nsub + 1usize)
    let (tab, e2) = mem.alloc[f64](a, nsub)
    let (ids, e3) = mem.alloc[usize](a, nsub)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    var m = 0usize
    var s = 1usize
    while s <= nsub {
        pos[s] = nsub
        var i = 0usize
        while i < n {
            if sub[i] == s && pos[s] == nsub {
                pos[s] = m
                ids[m] = s
                m += 1usize
            }
            i += 1usize
        }
        s += 1usize
    }
    var ok_all = true
    var g = 0usize
    while g < 2usize {
        var total = 0usize
        s = 0usize
        while s < m {
            tab[s] = 0.0f64
            s += 1usize
        }
        var i = 0usize
        while i < n {
            if (t[i] > 0.5f64) == (g == 1usize) {
                tab[pos[sub[i]]] += 1.0f64
                total += 1usize
            }
            i += 1usize
        }
        s = 0usize
        while s < m {
            if tab[s] < f64(min_n) { ok_all = false }
            s += 1usize
        }
        if total < m * min_n { ret TooFewUnits }
        g += 1usize
    }
    if ok_all { ret ok }
    g = 0usize
    while g < 2usize {
        s = 0usize
        while s < m {
            tab[s] = 0.0f64
            s += 1usize
        }
        var i = 0usize
        while i < n {
            if (t[i] > 0.5f64) == (g == 1usize) { tab[pos[sub[i]]] += 1.0f64 }
            i += 1usize
        }
        var rnd = 0usize
        while rnd < min_n {
            while true {
                var lowest = tab[0usize]
                s = 0usize
                while s < m {
                    if tab[s] < lowest { lowest = tab[s] }
                    s += 1usize
                }
                if lowest > 0.0f64 { break }
                s = 0usize
                while s < m && tab[s] != 0.0f64 { s += 1usize }
                if s == m { break }
                var left = false
                if s == m - 1usize {
                    left = true
                } else if s == 0usize {
                    left = false
                } else {
                    var score = 0.0f64
                    var q2 = 0usize
                    while q2 < m {
                        if tab[q2] > 1.0f64 && q2 != s { score += (tab[q2] - 1.0f64) / (f64(q2) - f64(s)) }
                        q2 += 1usize
                    }
                    left = score <= 0.0f64
                }
                var s2 = s
                if left {
                    s2 = s - 1usize
                    while s2 > 0usize && tab[s2] <= 0.0f64 { s2 -= 1usize }
                } else {
                    s2 = s + 1usize
                    while s2 < m - 1usize && tab[s2] <= 0.0f64 { s2 += 1usize }
                }
                // the unit of group g in class s2 with the closest score on the side being scooted from
                var best = n
                var i2 = 0usize
                while i2 < n {
                    if (t[i2] > 0.5f64) == (g == 1usize) && pos[sub[i2]] == s2 {
                        if best == n {
                            best = i2
                        } else {
                            var skip = false
                            if left && x[i2] < x[best] { skip = true }
                            if !left && x[i2] > x[best] { skip = true }
                            if !skip { best = i2 }
                        }
                    }
                    i2 += 1usize
                }
                if best == n { break }
                sub[best] = ids[s]
                tab[s] += 1.0f64
                tab[s2] -= 1.0f64
                pos[ids[s]] = s
            }
            s = 0usize
            while s < m {
                tab[s] -= 1.0f64
                s += 1usize
            }
            rnd += 1usize
        }
        g += 1usize
    }
    ret ok
}

// MatchIt wvar(): weights normalised to sum 1, reliability-weights variance, or m(1 - m) for a 0/1 variable
fn wvar(x: []const f64, w: []const f64, sel: []const bool, n: usize, p: usize, j: usize, bin: bool) -> f64 {
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        if sel[i] { sw += w[i] }
        i += 1usize
    }
    var mx = 0.0f64
    i = 0usize
    while i < n {
        if sel[i] { mx += w[i] / sw * x[i * p + j] }
        i += 1usize
    }
    if bin { ret mx * (1.0f64 - mx) }
    var s = 0.0f64
    var s2 = 0.0f64
    i = 0usize
    while i < n {
        if sel[i] {
            let wi = w[i] / sw
            s += wi * (x[i * p + j] - mx) * (x[i * p + j] - mx)
            s2 += wi * wi
        }
        i += 1usize
    }
    ret s / (1.0f64 - s2)
}

// summary.matchit balance of covariate column j under weights w (all ones for the unmatched sample):
// out = [Means Treated, Means Control, Std. Mean Diff., Var. Ratio]; denom 0 treated, 1 control (the full-sample sd, as MatchIt standardises)
fn balance(a: *mem.Arena, x: []const f64, t: []const f64, w: []const f64, n: usize, p: usize, j: usize, denom: usize, out: []f64) -> err {
    let (s1, e1) = mem.alloc[bool](a, n)
    let (s0, e2) = mem.alloc[bool](a, n)
    let (ones, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    var bin = true
    var i = 0usize
    while i < n {
        s1[i] = t[i] > 0.5f64
        s0[i] = !s1[i]
        ones[i] = 1.0f64
        if x[i * p + j] != 0.0f64 && x[i * p + j] != 1.0f64 { bin = false }
        i += 1usize
    }
    var m1 = 0.0f64
    var m0 = 0.0f64
    var w1 = 0.0f64
    var w0 = 0.0f64
    i = 0usize
    while i < n {
        if s1[i] {
            m1 += w[i] * x[i * p + j]
            w1 += w[i]
        } else {
            m0 += w[i] * x[i * p + j]
            w0 += w[i]
        }
        i += 1usize
    }
    m1 = m1 / w1
    m0 = m0 / w0
    out[0usize] = m1
    out[1usize] = m0
    let dmean = m1 - m0
    var sdv = math.sqrt[f64](wvar(x, ones, s1, n, p, j, bin))
    if denom == 1usize { sdv = math.sqrt[f64](wvar(x, ones, s0, n, p, j, bin)) }
    if math.abs[f64](dmean) > math.sqrt[f64](2.220446049250313e-16f64) { out[2usize] = dmean / sdv } else { out[2usize] = dmean }
    out[3usize] = wvar(x, w, s1, n, p, j, bin) / wvar(x, w, s0, n, p, j, bin)
    if bin {
        out[4usize] = math.abs[f64](dmean)
        out[5usize] = math.abs[f64](dmean)
        ret ok
    }
    // eCDF Mean and Max: weights summing to 1 within each group, cumulated in order of x (ties keep data order), read where x changes
    let (ord, e4) = mem.alloc[usize](a, n)
    if e4 != ok { ret e4 }
    i = 0usize
    while i < n {
        var k = i
        while k > 0usize && x[ord[k - 1usize] * p + j] > x[i * p + j] {
            ord[k] = ord[k - 1usize]
            k -= 1usize
        }
        ord[k] = i
        i += 1usize
    }
    // the group of the smallest x counts negative
    let first1 = t[ord[0usize]] > 0.5f64
    var cum = 0.0f64
    var sum = 0.0f64
    var mx = 0.0f64
    var cnt = 0.0f64
    i = 0usize
    while i < n {
        let u = ord[i]
        let g1 = t[u] > 0.5f64
        var wn = w[u] / w0
        if g1 { wn = w[u] / w1 }
        if g1 == first1 { cum -= wn } else { cum += wn }
        if i + 1usize == n || x[ord[i + 1usize] * p + j] != x[u * p + j] {
            let v = math.abs[f64](cum)
            sum += v
            cnt += 1.0f64
            if v > mx { mx = v }
        }
        i += 1usize
    }
    out[4usize] = sum / cnt
    out[5usize] = mx
    ret ok
}

fn sorted_col(a: *mem.Arena, x: []const f64, n: usize, p: usize, j: usize) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < n {
        let v = x[i * p + j]
        var k = i
        while k > 0usize && s[k - 1usize] > v {
            s[k] = s[k - 1usize]
            k -= 1usize
        }
        s[k] = v
        i += 1usize
    }
    ret (s, ok)
}

// R signif(x, 5)
fn signif5(x: f64) -> f64 {
    if x == 0.0f64 { ret x }
    let e10 = 4.0f64 - math.floor[f64](math.log10[f64](math.abs[f64](x)))
    let pw = math.pow[f64](10.0f64, e10)
    ret math.round[f64](x * pw) / pw
}

// method = "cem": every covariate coarsened by the same rule (kind 0 sturges, 1 fd, 2 scott, 3 number of bins = par with par 0 leaving
// the variable unbinned and 1 dropping it, 4 quantile bins "q<par>"), then exact matching on the bins; estimand 0 ATT, 1 ATC, 2 ATE
fn cem(a: *mem.Arena, x: []const f64, t: []const f64, n: usize, p: usize, kind: usize, par: f64, est: usize, w: []f64) -> err {
    let (bin, e1) = mem.alloc[f64](a, n * p)
    let (sub, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret e1 }
    var j = 0usize
    while j < p {
        let (s, se) = sorted_col(a, x, n, p, j)
        if se != ok { ret se }
        let lo = s[0usize]
        let hi = s[n - 1usize]
        var nb = 0.0f64
        var raw = false
        if kind == 0usize {
            nb = math.ceil[f64](math.log2[f64](f64(n)) + 1.0f64)
        } else if kind == 2usize {
            var m = 0.0f64
            var i = 0usize
            while i < n {
                m += s[i]
                i += 1usize
            }
            m = m / f64(n)
            var v = 0.0f64
            i = 0usize
            while i < n {
                v += (s[i] - m) * (s[i] - m)
                i += 1usize
            }
            v = v / f64(n - 1usize)
            let h = 3.5f64 * math.sqrt[f64](v) * math.pow[f64](f64(n), -1.0f64 / 3.0f64)
            nb = 1.0f64
            if h > 0.0f64 { nb = math.max[f64](1.0f64, math.ceil[f64]((hi - lo) / h)) }
        } else if kind == 1usize {
            let (s5, fe) = mem.alloc[f64](a, n)
            if fe != ok { ret fe }
            var i = 0usize
            while i < n {
                s5[i] = signif5(s[i])
                i += 1usize
            }
            // signif keeps the order of s
            var h = 2.0f64 * (ci.quantile7(s5, 0.75f64) - ci.quantile7(s5, 0.25f64))
            var al = 0.25f64
            while h == 0.0f64 && al / 2.0f64 >= 1.0f64 / 512.0f64 {
                al = al / 2.0f64
                h = (ci.quantile7(s5, 1.0f64 - al) - ci.quantile7(s5, al)) / (1.0f64 - 2.0f64 * al)
            }
            nb = 1.0f64
            if h > 0.0f64 { nb = math.max[f64](1.0f64, math.ceil[f64]((hi - lo) / (h * math.pow[f64](f64(n), -1.0f64 / 3.0f64)))) }
        } else if kind == 3usize {
            nb = par
            if par == 0.0f64 { raw = true }
        }
        var i = 0usize
        while i < n {
            let v = x[i * p + j]
            var b = 1.0f64
            if raw {
                b = v
            } else if kind == 4usize {
                // breaks at the quantiles k/q, k = 1..q-1; findInterval counts the breaks at or below v
                var k = 1usize
                var c = 1.0f64
                while f64(k) < par {
                    if v >= ci.quantile7(s, 1.0f64 / par + f64(k - 1usize) * (1.0f64 / par)) { c += 1.0f64 }
                    k += 1usize
                }
                b = c
            } else if nb > 1.0f64 {
                let by = (hi - lo) / nb
                var c = 1.0f64
                var k = 1usize
                while f64(k) < nb {
                    var br = lo + f64(k) * by
                    if v >= br { c += 1.0f64 }
                    k += 1usize
                }
                b = c
            }
            bin[i * p + j] = b
            i += 1usize
        }
        j += 1usize
    }
    // exact matching on the bins
    var nk = 0usize
    var i = 0usize
    while i < n {
        var at = nk
        var k = 0usize
        while k < nk {
            var same = true
            var jj = 0usize
            var first = n
            // compare with the first unit of class k + 1
            var u = 0usize
            while u < i && first == n {
                if sub[u] == k + 1usize { first = u }
                u += 1usize
            }
            while jj < p {
                if bin[first * p + jj] != bin[i * p + jj] { same = false }
                jj += 1usize
            }
            if same { at = k }
            k += 1usize
        }
        if at == nk { nk += 1usize }
        sub[i] = at + 1usize
        i += 1usize
    }
    var k = 1usize
    while k <= nk {
        var has1 = false
        var has0 = false
        i = 0usize
        while i < n {
            if sub[i] == k {
                if t[i] > 0.5f64 { has1 = true } else { has0 = true }
            }
            i += 1usize
        }
        if !(has1 && has0) {
            i = 0usize
            while i < n {
                if sub[i] == k { sub[i] = 0usize }
                i += 1usize
            }
        }
        k += 1usize
    }
    ret subclass_weights(a, sub, nk, t, n, est, w)
}

// match.data: the matched rows (weight above zero) in data order, with their weight and subclass; returns the row count.
fn match_data(w: []const f64, sub: []const usize, n: usize, rows: []usize, mw: []f64, ms: []usize) -> usize {
    var k = 0usize
    var i = 0usize
    while i < n {
        if w[i] > 0.0f64 {
            rows[k] = i
            mw[k] = w[i]
            ms[k] = sub[i]
            k += 1usize
        }
        i += 1usize
    }
    ret k
}

// method = "optimal" (optmatch::pairmatch, ratio 1, ATT, glm distance): MatchIt's preprocessing keeps the arcs that can lie on an optimal
// matching, optmatch rounds each distance to an integer ceiling(0.5 + d / epsilon), and the cheapest assignment of the treated units wins.
// Where integer costs tie, optmatch's LEMON cycle-cancelling order picks the pair; this Hungarian solver does not reproduce that.
fn optimal(a: *mem.Arena, x: []const f64, t: []const f64, n: usize, p: usize, w: []f64, ps: []f64) -> err {
    let e0 = pscore_link(a, x, t, n, p, 0usize, false, ps)
    if e0 != ok { ret e0 }
    let (o, e1) = mem.alloc[usize](a, n)
    let (im, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret e1 }
    var n1 = 0usize
    var i = 0usize
    while i < n {
        if t[i] > 0.5f64 { n1 += 1usize }
        o[i] = i
        i += 1usize
    }
    let n0 = n - n1
    // stable insertion sort of the order by score (R order())
    i = 1usize
    while i < n {
        let v = o[i]
        var j = i
        var go = true
        while j > 0usize && go {
            if ps[o[j - 1usize]] > ps[v] {
                o[j] = o[j - 1usize]
                j -= 1usize } else { go = false
            }
        }
        o[j] = v
        i += 1usize
    }
    var i0 = 0usize
    var i1 = 0usize
    i = 0usize
    while i < n {
        if t[i] > 0.5f64 {
            im[i] = i1
            i1 += 1usize } else { im[i] = i0
            i0 += 1usize
        }
        i += 1usize
    }
    let (qa, e3) = mem.alloc[usize](a, n1)
    let (lo, e4) = mem.alloc[usize](a, n0)
    let (hi, e5) = mem.alloc[usize](a, n0)
    let (kept, e6) = mem.alloc[bool](a, n1 * n0)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e3 }
    var k = 0usize
    var q = 0usize
    var cj = 0usize
    i = 0usize
    while i < n {
        if t[o[i]] > 0.5f64 {
            qa[q] = i
            q += 1usize
        } else {
            if q > k {
                lo[cj] = qa[k]
                k += 1usize } else { lo[cj] = i
            }
            cj += 1usize
        }
        i += 1usize
    }
    k = 0usize
    q = 0usize
    cj = n0
    i = n
    while i > 0usize {
        i -= 1usize
        if t[o[i]] > 0.5f64 {
            qa[q] = i
            q += 1usize
        } else {
            cj -= 1usize
            if q > k {
                hi[cj] = qa[k]
                k += 1usize } else { hi[cj] = i
            }
        }
    }
    i = 0usize
    while i < n1 * n0 {
        kept[i] = false
        i += 1usize
    }
    cj = 0usize
    i = 0usize
    while i < n {
        if t[o[i]] < 0.5f64 {
            var j = lo[cj]
            while j <= hi[cj] {
                if t[o[j]] > 0.5f64 { kept[im[o[j]] + n1 * im[o[i]]] = true }
                j += 1usize
            }
            cj += 1usize
        }
        i += 1usize
    }
    let (rowhas, e7) = mem.alloc[bool](a, n1)
    let (colhas, e8) = mem.alloc[bool](a, n0)
    let (dt, e9) = mem.alloc[f64](a, n1)
    let (dc, e10) = mem.alloc[f64](a, n0)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret e7 }
    i = 0usize
    while i < n1 {
        rowhas[i] = false
        i += 1usize
    }
    i = 0usize
    while i < n0 {
        colhas[i] = false
        i += 1usize
    }
    i = 0usize
    while i < n {
        if t[i] > 0.5f64 { dt[im[i]] = ps[i] } else { dc[im[i]] = ps[i] }
        i += 1usize
    }
    var maxd = 0.0f64
    var r = 0usize
    while r < n1 {
        var c = 0usize
        while c < n0 {
            if kept[r + n1 * c] {
                rowhas[r] = true
                colhas[c] = true
                let d = math.abs[f64](dt[r] - dc[c])
                if d > maxd { maxd = d }
            }
            c += 1usize
        }
        r += 1usize
    }
    var rf = 0usize
    var cf = 0usize
    i = 0usize
    while i < n1 {
        if rowhas[i] { rf += 1usize }
        i += 1usize
    }
    i = 0usize
    while i < n0 {
        if colhas[i] { cf += 1usize }
        i += 1usize
    }
    let nn = f64(n)
    var eps = 0.001f64 * nn * (f64(n1 + n0 - 2usize) / (nn - 2.0f64)) / f64(rf + cf - 2usize)
    let lower = maxd / (2147483647.0f64 / 64.0f64 - 2.0f64)
    if lower > eps { eps = lower }
    let big = 4000000000000i64
    let (cost, e11) = mem.alloc[i64](a, n1 * n0)
    if e11 != ok { ret e11 }
    r = 0usize
    while r < n1 {
        var c = 0usize
        while c < n0 {
            cost[r * n0 + c] = big
            if kept[r + n1 * c] { cost[r * n0 + c] = i64(math.ceil[f64](0.5f64 + math.abs[f64](dt[r] - dc[c]) / eps)) }
            c += 1usize
        }
        r += 1usize
    }
    // Hungarian method (potentials), rows are treated units, one control each
    let (u, e12) = mem.alloc[i64](a, n1 + 1usize)
    let (v, e13) = mem.alloc[i64](a, n0 + 1usize)
    let (pp, e14) = mem.alloc[usize](a, n0 + 1usize)
    let (way, e15) = mem.alloc[usize](a, n0 + 1usize)
    let (minv, e16) = mem.alloc[i64](a, n0 + 1usize)
    let (used, e17) = mem.alloc[bool](a, n0 + 1usize)
    if e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok { ret e12 }
    i = 0usize
    while i <= n1 {
        u[i] = 0i64
        i += 1usize
    }
    i = 0usize
    while i <= n0 {
        v[i] = 0i64
        pp[i] = 0usize
        way[i] = 0usize
        i += 1usize
    }
    let inf = 9000000000000000000i64
    var row = 1usize
    while row <= n1 {
        pp[0usize] = row
        var j0 = 0usize
        i = 0usize
        while i <= n0 {
            minv[i] = inf
            used[i] = false
            i += 1usize
        }
        var more = true
        while more {
            used[j0] = true
            let r0 = pp[j0]
            var delta = inf
            var j1 = 0usize
            var j = 1usize
            while j <= n0 {
                if !used[j] {
                    let cur = cost[(r0 - 1usize) * n0 + j - 1usize] - u[r0] - v[j]
                    if cur < minv[j] {
                        minv[j] = cur
                        way[j] = j0
                    }
                    if minv[j] < delta {
                        delta = minv[j]
                        j1 = j
                    }
                }
                j += 1usize
            }
            j = 0usize
            while j <= n0 {
                if used[j] {
                    u[pp[j]] += delta
                    v[j] -= delta } else { minv[j] -= delta
                }
                j += 1usize
            }
            j0 = j1
            more = pp[j0] != 0usize
        }
        more = true
        while more {
            let j1 = way[j0]
            pp[j0] = pp[j1]
            j0 = j1
            more = j0 != 0usize
        }
        row += 1usize
    }
    i = 0usize
    while i < n {
        w[i] = 0.0f64
        i += 1usize
    }
    // control index c (data order) of each matched pair
    let (cpos, e18) = mem.alloc[usize](a, n0)
    let (tpos, e19) = mem.alloc[usize](a, n1)
    if e18 != ok || e19 != ok { ret e18 }
    i = 0usize
    while i < n {
        if t[i] > 0.5f64 { tpos[im[i]] = i } else { cpos[im[i]] = i }
        i += 1usize
    }
    r = 0usize
    while r < n1 {
        w[tpos[r]] = 1.0f64
        r += 1usize
    }
    var c1 = 1usize
    while c1 <= n0 {
        if pp[c1] != 0usize { w[cpos[c1 - 1usize]] = 1.0f64 }
        c1 += 1usize
    }
    ret ok
}
