// R topicmodels on a document-term count matrix (docs by terms, row-major): LDA by variational EM (Blei's lda-c as topicmodels ships it, with Cokus's Mersenne-Twister for the initial model) and by collapsed Gibbs sampling (GibbsLDA++ over R's unif_rand), plus posterior, perplexity, logLik degrees of freedom, terms and topics.
//
// Not here: seedwords, multi-chain best selection and the burn-in/thin chain list, the CTM.

use e.algo.rand.r as rng
use e.math
use e.math.nmath as nm
use e.mem

// Cokus's MT19937 (topicmodels' cokus.c): the state, how many draws remain before a reload, and the next word
type Cokus = struct { st: [625]u64, left: i64, next: usize }

type Corpus = struct { nd: usize, nv: usize, nz: usize, off: []usize, w: []usize, c: []f64, tot: []f64 }

// what rlda returns: gamma is not yet row-normalised, beta is log p(term | topic), wa the argmax topic of each stored (doc, term) pair
type Vem = struct { k: usize, nd: usize, nv: usize, iter: usize, nlog: usize, alpha: f64, beta: []f64, gamma: []f64, llh: []f64, logliks: []f64, wa: []usize }

type Gibbs = struct { k: usize, nd: usize, nv: usize, nlog: usize, alpha: f64, loglik: f64, beta: []f64, theta: []f64, z: []usize, wa: []usize, logliks: []f64 }

const MT_N: usize = 624usize
const MT_M: usize = 397usize
const MT_MASK: u64 = 4294967295u64

fn seed_mt(r: *Cokus, seed: u64) {
    var x = (seed | 1u64) & MT_MASK
    r.left = 0i64
    r.st[0usize] = x
    var j = 1usize
    while j < MT_N {
        x = (x * 69069u64) & MT_MASK
        r.st[j] = x
        j += 1usize
    }
}

fn mt_mix(u: u64, v: u64, k: u64) -> u64 {
    var r = ((u & 2147483648u64) | (v & 2147483647u64)) >> 1u64
    if (v & 1u64) != 0u64 { r = r ^ 2567483615u64 }
    ret r
}

fn mt_temper(y0: u64) -> u64 {
    var y = y0
    y = y ^ (y >> 11u64)
    y = y ^ ((y << 7u64) & 2636928640u64)
    y = y ^ ((y << 15u64) & 4022730752u64)
    ret (y ^ (y >> 18u64)) & MT_MASK
}

fn mt_reload(r: *Cokus) -> u64 {
    if r.left < 0i64 - 1i64 { seed_mt(r, 4357u64) }
    r.left = i64(MT_N) - 1i64
    r.next = 1usize
    var p0 = 0usize
    var p2 = 2usize
    var pm = MT_M
    var s0 = r.st[0usize]
    var s1 = r.st[1usize]
    var j = MT_N - MT_M
    while j > 0usize {
        r.st[p0] = r.st[pm] ^ mt_mix(s0, s1, 0u64)
        p0 += 1usize
        pm += 1usize
        s0 = s1
        s1 = r.st[p2]
        p2 += 1usize
        j -= 1usize
    }
    pm = 0usize
    j = MT_M - 1usize
    while j > 0usize {
        r.st[p0] = r.st[pm] ^ mt_mix(s0, s1, 0u64)
        p0 += 1usize
        pm += 1usize
        s0 = s1
        s1 = r.st[p2]
        p2 += 1usize
        j -= 1usize
    }
    s1 = r.st[0usize]
    r.st[p0] = r.st[pm] ^ mt_mix(s0, s1, 0u64)
    ret mt_temper(s1)
}

fn mt_next(r: *Cokus) -> u64 {
    r.left -= 1i64
    if r.left < 0i64 { ret mt_reload(r) }
    let y = r.st[r.next]
    r.next += 1usize
    ret mt_temper(y)
}

// topicmodels' myrand(): a 32-bit draw over 2^32
fn myrand(r: *Cokus) -> f64 { ret f64(mt_next(r)) / 4294967296.0f64 }

fn zeros(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

fn zeros_u(a: *mem.Arena, n: usize) -> ([]usize, err) {
    let (v, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0usize
        i += 1usize
    }
    ret (v, ok)
}

// topicmodels' own digamma and trigamma (series after a shift by six), not the exact functions
fn digamma(x0: f64) -> f64 {
    let x = x0 + 6.0f64
    var p = 1.0f64 / (x * x)
    p = (((0.004166666666667f64 * p - 0.003968253986254f64) * p + 0.008333333333333f64) * p - 0.083333333333333f64) * p
    p = p + math.log[f64](x) - 0.5f64 / x - 1.0f64 / (x - 1.0f64) - 1.0f64 / (x - 2.0f64) - 1.0f64 / (x - 3.0f64) - 1.0f64 / (x - 4.0f64) - 1.0f64 / (x - 5.0f64) - 1.0f64 / (x - 6.0f64)
    ret p
}

fn trigamma(x0: f64) -> f64 {
    var x = x0 + 6.0f64
    var p = 1.0f64 / (x * x)
    p = (((((0.075757575757576f64 * p - 0.033333333333333f64) * p + 0.0238095238095238f64) * p - 0.033333333333333f64) * p + 0.166666666666667f64) * p + 1.0f64) / x + 0.5f64 * p
    var i = 0usize
    while i < 6usize {
        x = x - 1.0f64
        p = 1.0f64 / (x * x) + p
        i += 1usize
    }
    ret p
}

// log(exp(a) + exp(b)); the C source's test for a == -1 is kept
fn log_sum(la: f64, lb: f64) -> f64 {
    if la == 0.0f64 - 1.0f64 { ret lb }
    if la < lb { ret lb + math.log[f64](1.0f64 + math.exp[f64](la - lb)) }
    ret la + math.log[f64](1.0f64 + math.exp[f64](lb - la))
}

fn corpus_of(a: *mem.Arena, m: []const f64, nd: usize, nv: usize) -> (Corpus, err) {
    var co: Corpus = zero
    co.nd = nd
    co.nv = nv
    var nz = 0usize
    var i = 0usize
    while i < nd * nv {
        if m[i] != 0.0f64 { nz += 1usize }
        i += 1usize
    }
    co.nz = nz
    let (off, e1) = zeros_u(a, nd + 1usize)
    let (w, e2) = zeros_u(a, nz)
    let (c, e3) = zeros(a, nz)
    let (tot, e4) = zeros(a, nd)
    if e1 != ok { ret (co, e1) }
    if e2 != ok { ret (co, e2) }
    if e3 != ok { ret (co, e3) }
    if e4 != ok { ret (co, e4) }
    var at = 0usize
    var d = 0usize
    while d < nd {
        off[d] = at
        var j = 0usize
        while j < nv {
            let v = m[d * nv + j]
            if v != 0.0f64 {
                w[at] = j
                c[at] = v
                tot[d] += v
                at += 1usize
            }
            j += 1usize
        }
        d += 1usize
    }
    off[nd] = at
    co.off = off
    co.w = w
    co.c = c
    co.tot = tot
    ret (co, ok)
}

fn opt_alpha(ss: f64, nd: usize, k: usize) -> f64 {
    var init_a = 100.0f64
    var log_a = math.log[f64](init_a)
    var iter = 0usize
    var df = 0.0f64
    let dd = f64(nd)
    let kk = f64(k)
    var go = true
    while go {
        iter += 1usize
        var a = math.exp[f64](log_a)
        if a != a {
            init_a = init_a * 10.0f64
            a = init_a
            log_a = math.log[f64](a)
        }
        df = dd * (kk * digamma(kk * a) - kk * digamma(a)) + ss
        let d2f = dd * (kk * kk * trigamma(kk * a) - kk * trigamma(a))
        log_a = log_a - df / (d2f * a + df)
        go = math.abs[f64](df) > 0.00001f64 && iter < 1000usize
    }
    ret math.exp[f64](log_a)
}

fn doc_likelihood(co: *const Corpus, d: usize, k: usize, alpha: f64, logb: []const f64, phi: []const f64, gam: []const f64, go: usize, dig: []f64) -> f64 {
    var vsum = 0.0f64
    var kk = 0usize
    while kk < k {
        dig[kk] = digamma(gam[go + kk])
        vsum += gam[go + kk]
        kk += 1usize
    }
    let digsum = digamma(vsum)
    let fk = f64(k)
    var lik = nm.lgammafn(alpha * fk) - fk * nm.lgammafn(alpha) - nm.lgammafn(vsum)
    let o = co.off[d]
    let len = co.off[d + 1usize] - o
    kk = 0usize
    while kk < k {
        lik += (alpha - 1.0f64) * (dig[kk] - digsum) + nm.lgammafn(gam[go + kk]) - (gam[go + kk] - 1.0f64) * (dig[kk] - digsum)
        var n = 0usize
        while n < len {
            let ph = phi[(o + n) * k + kk]
            if ph > 0.0f64 {
                lik += co.c[o + n] * (ph * ((dig[kk] - digsum) - math.log[f64](ph) + logb[kk * co.nv + co.w[o + n]]))
            }
            n += 1usize
        }
        kk += 1usize
    }
    ret lik
}

// lda_inference: gam is this document's k variational Dirichlet parameters, phi the whole corpus's (term, topic) responsibilities
fn lda_inference(co: *const Corpus, d: usize, k: usize, alpha: f64, logb: []const f64, gam: []f64, go: usize, phi: []f64, conv: f64, maxit: i64, dg: []f64, oldphi: []f64, dig: []f64) -> f64 {
    let fk = f64(k)
    let o = co.off[d]
    let len = co.off[d + 1usize] - o
    var kk = 0usize
    while kk < k {
        gam[go + kk] = alpha + co.tot[d] / fk
        dg[kk] = digamma(gam[go + kk])
        var n = 0usize
        while n < len {
            phi[(o + n) * k + kk] = 1.0f64 / fk
            n += 1usize
        }
        kk += 1usize
    }
    var converged = 1.0f64
    var lik = 0.0f64
    var lik_old = 0.0f64
    var it = 0i64
    while converged > conv && (it < maxit || maxit == 0i64 - 1i64) {
        it += 1i64
        var n = 0usize
        while n < len {
            var phisum = 0.0f64
            let wd = co.w[o + n]
            kk = 0usize
            while kk < k {
                oldphi[kk] = phi[(o + n) * k + kk]
                phi[(o + n) * k + kk] = dg[kk] + logb[kk * co.nv + wd]
                if kk > 0usize {
                    phisum = log_sum(phisum, phi[(o + n) * k + kk])
                } else {
                    phisum = phi[(o + n) * k + kk]
                }
                kk += 1usize
            }
            kk = 0usize
            while kk < k {
                phi[(o + n) * k + kk] = math.exp[f64](phi[(o + n) * k + kk] - phisum)
                gam[go + kk] = gam[go + kk] + co.c[o + n] * (phi[(o + n) * k + kk] - oldphi[kk])
                dg[kk] = digamma(gam[go + kk])
                kk += 1usize
            }
            n += 1usize
        }
        lik = doc_likelihood(co, d, k, alpha, logb, phi, gam, go, dig)
        converged = (lik_old - lik) / lik_old
        lik_old = lik
    }
    ret lik
}

// LDA(x, k, method = "VEM"). init: 0 random, 1 seeded, 2 the given model (beta is k x terms, log scale). A control tolerance is held as a float in the C code.
fn lda_vem(a: *mem.Arena, m: []const f64, nd: usize, nv: usize, k: usize, init: usize, seed: i64, alpha0: f64, estimate_alpha: bool, var_max: i64, var_tol: f64, em_max: i64, em_tol: f64, keep: usize, init_beta: []const f64, out: *Vem) -> err {
    let (co, ec) = corpus_of(a, m, nd, nv)
    if ec != ok { ret ec }
    var rg: Cokus = zero
    seed_mt(&rg, u64(seed) & MT_MASK)
    let vtol = f64(f32(var_tol))
    let etol = f64(f32(em_tol))
    var vmax = var_max
    let (logb, e1) = zeros(a, k * nv)
    let (cw, e2) = zeros(a, k * nv)
    let (ct, e3) = zeros(a, k)
    let (gam, e4) = zeros(a, nd * k)
    let (phi, e5) = zeros(a, co.nz * k)
    let (llh, e6) = zeros(a, nd)
    let (dg, e7) = zeros(a, k)
    let (oldphi, e8) = zeros(a, k)
    let (dig, e9) = zeros(a, k)
    let (lls, e10) = zeros(a, 1usize + usize(em_max + 1i64) )
    let (wa, e11) = zeros_u(a, co.nz)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    let fk = f64(k)
    var alpha = alpha0
    var kk = 0usize
    if init == 0usize {
        while kk < k {
            var n = 0usize
            while n < nv {
                cw[kk * nv + n] += 1.0f64 / f64(nv) + myrand(&rg)
                ct[kk] += cw[kk * nv + n]
                n += 1usize
            }
            kk += 1usize
        }
    }
    if init == 1usize {
        while kk < k {
            let d = usize(math.floor[f64](myrand(&rg) * f64(nd)))
            var n = co.off[d]
            while n < co.off[d + 1usize] {
                cw[kk * nv + co.w[n]] += co.c[n]
                n += 1usize
            }
            var w = 0usize
            while w < nv {
                cw[kk * nv + w] += 1.0f64
                ct[kk] = ct[kk] + cw[kk * nv + w]
                w += 1usize
            }
            kk += 1usize
        }
    }
    if init == 2usize {
        var i = 0usize
        while i < k * nv {
            logb[i] = init_beta[i]
            i += 1usize
        }
    } else {
        mle_beta(logb, cw, ct, k, nv)
    }
    var iter = 0i64
    var nlog = 0usize
    var converged = 1.0f64
    var lik_old = 0.0f64
    var lik = 0.0f64
    while (converged < 0.0f64 || converged > etol || iter <= 2i64) && iter < em_max {
        iter += 1i64
        lik = 0.0f64
        var i = 0usize
        while i < k * nv {
            cw[i] = 0.0f64
            i += 1usize
        }
        kk = 0usize
        while kk < k {
            ct[kk] = 0.0f64
            kk += 1usize
        }
        var ass = 0.0f64
        var d = 0usize
        while d < nd {
            lik += lda_inference(&co, d, k, alpha, logb, gam, d * k, phi, vtol, vmax, dg, oldphi, dig)
            var gs = 0.0f64
            kk = 0usize
            while kk < k {
                gs += gam[d * k + kk]
                ass += digamma(gam[d * k + kk])
                kk += 1usize
            }
            ass -= fk * digamma(gs)
            var n = co.off[d]
            while n < co.off[d + 1usize] {
                kk = 0usize
                while kk < k {
                    cw[kk * nv + co.w[n]] += co.c[n] * phi[n * k + kk]
                    ct[kk] += co.c[n] * phi[n * k + kk]
                    kk += 1usize
                }
                n += 1usize
            }
            d += 1usize
        }
        mle_beta(logb, cw, ct, k, nv)
        if estimate_alpha { alpha = opt_alpha(ass, nd, k) }
        converged = (lik_old - lik) / lik_old
        if converged < 0.0f64 { vmax = vmax * 2i64 }
        lik_old = lik
        if keep > 0usize {
            lls[nlog] = lik
            nlog += 1usize
        }
    }
    var d = 0usize
    while d < nd {
        llh[d] = lda_inference(&co, d, k, alpha, logb, gam, d * k, phi, vtol, vmax, dg, oldphi, dig)
        d += 1usize
    }
    d = 0usize
    while d < nd {
        var n = co.off[d]
        while n < co.off[d + 1usize] {
            var best = 0usize
            var mx = phi[n * k]
            kk = 1usize
            while kk < k {
                if phi[n * k + kk] > mx {
                    mx = phi[n * k + kk]
                    best = kk
                }
                kk += 1usize
            }
            wa[n] = best
            n += 1usize
        }
        d += 1usize
    }
    out.k = k
    out.nd = nd
    out.nv = nv
    out.iter = usize(iter)
    out.nlog = nlog
    out.alpha = alpha
    out.beta = logb
    out.gamma = gam
    out.llh = llh
    out.logliks = lls
    out.wa = wa
    ret ok
}

// GibbsLDA++'s inference(): the collapsed log likelihood of the topic-word counts
fn gibbs_loglik(nw: []const f64, nwsum: []const f64, k: usize, nv: usize, delta: f64) -> f64 {
    let vb = f64(nv) * delta
    var ll = f64(k) * (nm.lgammafn(vb) - f64(nv) * nm.lgammafn(delta))
    var kk = 0usize
    while kk < k {
        var w = 0usize
        while w < nv {
            ll += nm.lgammafn(nw[w * k + kk] + delta)
            w += 1usize
        }
        ll -= nm.lgammafn(nwsum[kk] + vb)
        kk += 1usize
    }
    ret ll
}

// LDA(x, k, method = "Gibbs") after set.seed(seed). init: 0 random topics, 1 from the log term probabilities init_phi (k x terms), 2 from init_z (1-based, one per token).
// estimate_phi false (a new-data fit) samples with exp(init_phi) as the term probabilities.
fn lda_gibbs(a: *mem.Arena, m: []const f64, nd: usize, nv: usize, k: usize, init: usize, seed: i64, alpha: f64, delta: f64, niters: usize, keep: usize, estimate_phi: bool, init_phi: []const f64, init_z: []const usize, out: *Gibbs) -> err {
    let (co, ec) = corpus_of(a, m, nd, nv)
    if ec != ok { ret ec }
    var ntok = 0usize
    var i = 0usize
    while i < co.nz {
        ntok += usize(co.c[i])
        i += 1usize
    }
    let (dstart, e1) = zeros_u(a, nd + 1usize)
    let (wl, e2) = zeros_u(a, ntok)
    let (z, e3) = zeros_u(a, ntok)
    let (nw, e4) = zeros(a, nv * k)
    let (ndk, e5) = zeros(a, nd * k)
    let (nwsum, e6) = zeros(a, k)
    let (ndsum, e7) = zeros(a, nd)
    let (p, e8) = zeros(a, k)
    let (theta, e9) = zeros(a, nd * k)
    let (phi, e10) = zeros(a, k * nv)
    let (lls, e11) = zeros(a, niters + 1usize)
    let (wa, e12) = zeros_u(a, co.nz)
    let (wass, e13) = zeros_u(a, ntok)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    var at = 0usize
    var d = 0usize
    while d < nd {
        dstart[d] = at
        var n = co.off[d]
        while n < co.off[d + 1usize] {
            var r = 0usize
            while r < usize(co.c[n]) {
                wl[at] = co.w[n]
                at += 1usize
                r += 1usize
            }
            n += 1usize
        }
        d += 1usize
    }
    dstart[nd] = at
    let fk = f64(k)
    if !estimate_phi {
        i = 0usize
        while i < k * nv {
            phi[i] = math.exp[f64](init_phi[i])
            i += 1usize
        }
    }
    d = 0usize
    while d < nd {
        var n = dstart[d]
        while n < dstart[d + 1usize] {
            var topic = 0usize
            if init == 0usize { topic = usize(math.floor[f64](fk * rng.unif(&rg))) }
            if init == 1usize {
                let w = wl[n]
                var kk = 0usize
                while kk < k {
                    p[kk] = math.exp[f64](init_phi[kk * nv + w])
                    kk += 1usize
                }
                kk = 1usize
                while kk < k {
                    p[kk] += p[kk - 1usize]
                    kk += 1usize
                }
                let u = rng.unif(&rg) * p[k - 1usize]
                kk = 0usize
                var go = true
                while kk < k && go {
                    topic = kk
                    if p[kk] > u { go = false }
                    kk += 1usize
                }
            }
            if init == 2usize { topic = init_z[n] - 1usize }
            z[n] = topic
            nw[wl[n] * k + topic] += 1.0f64
            ndk[d * k + topic] += 1.0f64
            nwsum[topic] += 1.0f64
            n += 1usize
        }
        ndsum[d] = f64(dstart[d + 1usize] - dstart[d])
        d += 1usize
    }
    let vb = f64(nv) * delta
    let ka = fk * alpha
    var nlog = 0usize
    var liter = 1usize
    while liter <= niters {
        d = 0usize
        while d < nd {
            var n = dstart[d]
            while n < dstart[d + 1usize] {
                let topic = z[n]
                let w = wl[n]
                nw[w * k + topic] -= 1.0f64
                ndk[d * k + topic] -= 1.0f64
                nwsum[topic] -= 1.0f64
                ndsum[d] -= 1.0f64
                var kk = 0usize
                while kk < k {
                    if estimate_phi {
                        p[kk] = (nw[w * k + kk] + delta) / (nwsum[kk] + vb) * (ndk[d * k + kk] + alpha) / (ndsum[d] + ka)
                    } else {
                        p[kk] = phi[kk * nv + w] * (ndk[d * k + kk] + alpha) / (ndsum[d] + ka)
                    }
                    kk += 1usize
                }
                kk = 1usize
                while kk < k {
                    p[kk] += p[kk - 1usize]
                    kk += 1usize
                }
                let u = rng.unif(&rg) * p[k - 1usize]
                var tp = 0usize
                kk = 0usize
                var go = true
                while kk < k && go {
                    tp = kk
                    if p[kk] > u { go = false }
                    kk += 1usize
                }
                z[n] = tp
                nw[w * k + tp] += 1.0f64
                ndk[d * k + tp] += 1.0f64
                nwsum[tp] += 1.0f64
                ndsum[d] += 1.0f64
                n += 1usize
            }
            d += 1usize
        }
        if keep > 0usize && liter % keep == 0usize {
            lls[nlog] = gibbs_loglik(nw, nwsum, k, nv, delta)
            nlog += 1usize
        }
        liter += 1usize
    }
    d = 0usize
    while d < nd {
        var kk = 0usize
        while kk < k {
            theta[d * k + kk] = (ndk[d * k + kk] + alpha) / (ndsum[d] + ka)
            kk += 1usize
        }
        d += 1usize
    }
    if estimate_phi {
        var kk = 0usize
        while kk < k {
            var w = 0usize
            while w < nv {
                phi[kk * nv + w] = (nw[w * k + kk] + delta) / (nwsum[kk] + vb)
                w += 1usize
            }
            kk += 1usize
        }
    }
    d = 0usize
    while d < nd {
        var n = dstart[d]
        while n < dstart[d + 1usize] {
            let w = wl[n]
            var best = 0usize
            var pmax = 0.0f64
            var kk = 0usize
            while kk < k {
                let pk = phi[kk * nv + w] * (ndk[d * k + kk] + alpha) / (ndsum[d] + ka)
                if pk > pmax {
                    pmax = pk
                    best = kk
                }
                kk += 1usize
            }
            wass[n] = best
            n += 1usize
        }
        d += 1usize
    }
    // the (document, term) pairs in corpus order take the assignment of their first token
    d = 0usize
    while d < nd {
        var n = dstart[d]
        var s = co.off[d]
        while s < co.off[d + 1usize] {
            wa[s] = wass[n]
            n += usize(co.c[s])
            s += 1usize
        }
        d += 1usize
    }
    i = 0usize
    while i < k * nv {
        phi[i] = math.log[f64](phi[i])
        i += 1usize
    }
    out.k = k
    out.nd = nd
    out.nv = nv
    out.nlog = nlog
    out.alpha = alpha
    out.loglik = gibbs_loglik(nw, nwsum, k, nv, delta)
    out.beta = phi
    out.theta = theta
    out.z = z
    out.wa = wa
    out.logliks = lls
    ret ok
}

// perplexity of a Gibbs fit on data: exp(-sum(log(sum_k phi[k, j] theta[i, k]) * n) / sum(n)); uniform_theta uses 1/k for theta (use_theta = FALSE)
fn gibbs_perplexity(m: []const f64, nd: usize, nv: usize, k: usize, beta: []const f64, theta: []const f64, use_theta: bool) -> f64 {
    var num = 0.0f64
    var den = 0.0f64
    var i = 0usize
    while i < nd {
        var j = 0usize
        while j < nv {
            let c = m[i * nv + j]
            if c != 0.0f64 {
                var s = 0.0f64
                var kk = 0usize
                while kk < k {
                    var th = 1.0f64
                    if use_theta { th = theta[i * k + kk] } else { th = 1.0f64 / f64(k) }
                    s += math.exp[f64](beta[kk * nv + j]) * th
                    kk += 1usize
                }
                num += math.log[f64](s) * c
                den += c
            }
            j += 1usize
        }
        i += 1usize
    }
    ret math.exp[f64](0.0f64 - num / den)
}

// gamma / rowSums(gamma), as LDA_VEM.fit does after the C call
fn normalize_rows(g: []f64, nr: usize, nc: usize) {
    var i = 0usize
    while i < nr {
        var s = 0.0f64
        var j = 0usize
        while j < nc {
            s += g[i * nc + j]
            j += 1usize
        }
        j = 0usize
        while j < nc {
            g[i * nc + j] = g[i * nc + j] / s
            j += 1usize
        }
        i += 1usize
    }
}

// logLik: the sum of the per-document bounds
fn loglik(v: *const Vem) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.nd {
        s += v.llh[i]
        i += 1usize
    }
    ret s
}

// get_df of an LDA_VEM fit: the beta entries plus one when alpha was estimated
fn vem_df(v: *const Vem, estimate_alpha: bool) -> usize {
    var d = v.k * v.nv
    if estimate_alpha { d += 1usize }
    ret d
}

// perplexity of a VEM fit: exp(-logLik / n), n the number of tokens
fn vem_perplexity(v: *const Vem, n: f64) -> f64 { ret math.exp[f64](0.0f64 - loglik(v) / n) }

// most_likely: the 0-based indices of the k largest entries of row `row` of a matrix with nc columns, decreasing, ties by position
fn rank_row(p: []const f64, row: usize, nc: usize, k: usize, out: []usize) {
    var used = 0usize
    while used < k {
        var best = nc
        var j = 0usize
        while j < nc {
            var free = true
            var u = 0usize
            while u < used {
                if out[u] == j { free = false }
                u += 1usize
            }
            if free {
                if best == nc || p[row * nc + j] > p[row * nc + best] { best = j }
            }
            j += 1usize
        }
        out[used] = best
        used += 1usize
    }
}

fn mle_beta(logb: []f64, cw: []const f64, ct: []const f64, k: usize, nv: usize) {
    var kk = 0usize
    while kk < k {
        var w = 0usize
        while w < nv {
            if cw[kk * nv + w] > 0.0f64 {
                logb[kk * nv + w] = math.log[f64](cw[kk * nv + w]) - math.log[f64](ct[kk])
            } else {
                logb[kk * nv + w] = 0.0f64 - 100.0f64
            }
            w += 1usize
        }
        kk += 1usize
    }
}
