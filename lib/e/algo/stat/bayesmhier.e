// R bayesm: the hierarchical multinomial logit sampler rhierMnlRwMixture, equal to the package under set.seed (keep = 1).
//
// llmnl_con, drawDelta and the sampler loop; the tuning pass that supplies each unit's starting beta and Hessian is the caller's.

use e.algo.rand.r as rng
use e.algo.stat.bayesmgibbs as bg
use e.algo.stat.bayesmpkg as bz
use e.math
use e.mem

// llmnl_con: the multinomial logit log likelihood, beta[i] replaced by signres[i] exp(beta[i]) where signres[i] != 0; x is n p by k, y holds 1..p
fn llmnl_con(a: *mem.Arena, beta: []const f64, signres: []const f64, y: []const f64, x: []const f64, k: usize, p: usize) -> f64 {
    let start = mem.mark(a)
    let n = y.len
    let (bt, e1) = bg.zal(a, k)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < k {
        bt[i] = beta[i]
        if signres[i] != 0.0f64 { bt[i] = signres[i] * math.exp[f64](beta[i]) }
        i += 1usize
    }
    var tot = 0.0f64
    var ob = 0usize
    while ob < n {
        var den = 0.0f64
        var xby = 0.0f64
        var q = 0usize
        while q < p {
            var xb = 0.0f64
            var c = 0usize
            while c < k {
                xb += x[c * n * p + ob * p + q] * bt[c]
                c += 1usize
            }
            den += math.exp[f64](xb)
            if q + 1usize == usize(y[ob]) { xby = xb }
            q += 1usize
        }
        tot += xby - math.log[f64](den)
        ob += 1usize
    }
    mem.reset(a, start)
    ret tot
}

// drawDelta: vec(Delta) (nvar by nz, column-major) given the labels z and the components (mu, rooti per component in comps); y is n by nvar, zm n by nz
fn draw_delta(a: *mem.Arena, r: *rng.Rng, zm: []const f64, y: []const f64, z: []const f64, comps: []const f64, dbar: []const f64, ad: []const f64, n: usize, nz: usize, nvar: usize, nc: usize, out: []f64) -> err {
    let kp = nz * nvar
    let (xtx, e1) = bg.zal(a, kp * kp)
    let (xty, e2) = bg.zal(a, kp)
    let (sg, e3) = bg.zal(a, nvar * nvar)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var c = 0usize
    while c < nc {
        let base = c * (nvar + nvar * nvar)
        let mu = comps[base..base + nvar]
        let ri = comps[base + nvar..base + nvar + nvar * nvar]
        bg.gemm(false, true, ri, nvar, ri, nvar, nvar, nvar, nvar, sg)
        var i = 0usize
        while i < n {
            if usize(z[i]) == c + 1usize {
                var a1 = 0usize
                while a1 < nz {
                    var c1 = 0usize
                    while c1 < nz {
                        let xx = zm[a1 * n + i] * zm[c1 * n + i]
                        var b1 = 0usize
                        while b1 < nvar {
                            var d1 = 0usize
                            while d1 < nvar {
                                xtx[(c1 * nvar + d1) * kp + a1 * nvar + b1] += xx * sg[d1 * nvar + b1]
                                d1 += 1usize
                            }
                            b1 += 1usize
                        }
                        c1 += 1usize
                    }
                    var b2 = 0usize
                    while b2 < nvar {
                        var sm = 0.0f64
                        var d2 = 0usize
                        while d2 < nvar {
                            sm += sg[d2 * nvar + b2] * (y[d2 * n + i] - mu[d2])
                            d2 += 1usize
                        }
                        xty[a1 * nvar + b2] += sm * zm[a1 * n + i]
                        b2 += 1usize
                    }
                    a1 += 1usize
                }
            }
            i += 1usize
        }
        c += 1usize
    }
    let (m1, e4) = bg.zal(a, kp * kp)
    let (u, e5) = bg.zal(a, kp * kp)
    let (ui, e6) = bg.zal(a, kp * kp)
    let (vinv, e7) = bg.zal(a, kp * kp)
    let (uv, e8) = bg.zal(a, kp * kp)
    let (rhs, e9) = bg.zal(a, kp)
    let (nzv, e10) = bg.zal(a, kp)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
    var i2 = 0usize
    while i2 < kp * kp {
        m1[i2] = xtx[i2] + ad[i2]
        i2 += 1usize
    }
    if !bz.chol_upper(m1, kp, u) { ret mem.Full }
    bz.inv_upper(u, kp, ui)
    bg.gemm(false, true, ui, kp, ui, kp, kp, kp, kp, vinv)
    i2 = 0usize
    while i2 < kp {
        var s1 = xty[i2]
        var j = 0usize
        while j < kp {
            s1 += ad[j * kp + i2] * dbar[j]
            j += 1usize
        }
        rhs[i2] = s1
        i2 += 1usize
    }
    if !bz.chol_upper(vinv, kp, uv) { ret mem.Full }
    i2 = 0usize
    while i2 < kp {
        nzv[i2] = rng.norm(r)
        i2 += 1usize
    }
    i2 = 0usize
    while i2 < kp {
        var s2 = 0.0f64
        var j = 0usize
        while j < kp {
            s2 += vinv[j * kp + i2] * rhs[j]
            j += 1usize
        }
        var t = 0.0f64
        j = 0usize
        while j <= i2 {
            t += uv[i2 * kp + j] * nzv[j]
            j += 1usize
        }
        out[i2] = s2 + t
        i2 += 1usize
    }
    ret ok
}

// rhierMnlRwMixture's sampler loop with keep = 1 (the tuning pass supplies bet0 and each unit's Hessian); nz = 0 means no Z; ns[l] choice occasions of unit l, y and X (ns[l] p by nvar) concatenated; draw rep is betas (nlgt nvar), prob (nc), loglike, Delta (nz nvar), then mu and rooti per component
fn rhier_mnl(a: *mem.Arena, r: *rng.Rng, ns: []const f64, ys: []const f64, xs: []const f64, hs: []const f64, zm: []const f64, dbar: []const f64, ad: []const f64, mubar: []const f64, a00: f64, nu: f64, v: []const f64, s: f64, av: []const f64, signres: []const f64, bet0: []const f64, nlgt: usize, nvar: usize, nz: usize, p: usize, nc: usize, nr: usize, out: []f64) -> err {
    let (ob, e1) = bg.zal(a, nlgt * nvar)
    let (prob, e2) = bg.zal(a, nc)
    let (ind, e3) = bg.zal(a, nlgt)
    let (dl, e4) = bg.zal(a, nz * nvar)
    let (oll, e5) = bg.zal(a, nlgt)
    let (comps, e6) = bg.zal(a, nc * (nvar + nvar * nvar))
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var i = 0usize
    while i < nlgt * nvar {
        ob[i] = bet0[i]
        i += 1usize
    }
    i = 0usize
    while i < nc {
        prob[i] = 1.0f64 / f64(nc)
        i += 1usize
    }
    let ninc = nlgt / nc
    i = 0usize
    while i < nlgt {
        var lab = i / ninc + 1usize
        if lab > nc { lab = nc }
        ind[i] = f64(lab)
        i += 1usize
    }
    let w = nlgt * nvar + nc + 1usize + nz * nvar + nc * (nvar + nvar * nvar)
    var rep = 0usize
    while rep < nr {
        let start = mem.mark(a)
        let (ym, e7) = bg.zal(a, nlgt * nvar)
        if e7 != ok { ret mem.Full }
        i = 0usize
        while i < nlgt * nvar {
            ym[i] = ob[i]
            i += 1usize
        }
        var l = 0usize
        while l < nlgt && nz > 0usize {
            var vv = 0usize
            while vv < nvar {
                var sm = 0.0f64
                var q = 0usize
                while q < nz {
                    sm += zm[q * nlgt + l] * dl[q * nvar + vv]
                    q += 1usize
                }
                ym[vv * nlgt + l] = ob[vv * nlgt + l] - sm
                vv += 1usize
            }
            l += 1usize
        }
        if bg.mix_step(a, r, ym, nlgt, nvar, mubar, a00, nu, v, av, nc, ind, prob, comps) != ok { ret mem.Full }
        if nz > 0usize {
            if draw_delta(a, r, zm, ob, ind, comps, dbar, ad, nlgt, nz, nvar, nc, dl) != ok { ret mem.Full }
        }
        var off = 0usize
        l = 0usize
        while l < nlgt {
            let start2 = mem.mark(a)
            let nl = usize(ns[l])
            let cb = (usize(ind[l]) - 1usize) * (nvar + nvar * nvar)
            let mu = comps[cb..cb + nvar]
            let rp = comps[cb + nvar..cb + nvar + nvar * nvar]
            let yl = ys[off..off + nl]
            let xl = xs[off * p * nvar..(off + nl) * p * nvar]
            let (bbar, e8) = bg.zal(a, nvar)
            let (obl, e9) = bg.zal(a, nvar)
            let (m1, e10) = bg.zal(a, nvar * nvar)
            let (u, e11) = bg.zal(a, nvar * nvar)
            let (ui, e12) = bg.zal(a, nvar * nvar)
            let (cv, e13) = bg.zal(a, nvar * nvar)
            let (ir, e14) = bg.zal(a, nvar * nvar)
            let (bc, e15) = bg.zal(a, nvar)
            let (nzv, e16) = bg.zal(a, nvar)
            if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret mem.Full }
            var vv = 0usize
            while vv < nvar {
                var sm = mu[vv]
                var q = 0usize
                while q < nz {
                    sm += dl[q * nvar + vv] * zm[q * nlgt + l]
                    q += 1usize
                }
                bbar[vv] = sm
                obl[vv] = ob[vv * nlgt + l]
                vv += 1usize
            }
            if rep == 0usize { oll[l] = llmnl_con(a, obl, signres, yl, xl, nvar, p) }
            var c1 = 0usize
            while c1 < nvar {
                var r1 = 0usize
                while r1 < nvar {
                    var sm = hs[l * nvar * nvar + c1 * nvar + r1]
                    var q = 0usize
                    while q < nvar {
                        sm += rp[q * nvar + r1] * rp[q * nvar + c1]
                        q += 1usize
                    }
                    m1[c1 * nvar + r1] = sm
                    r1 += 1usize
                }
                c1 += 1usize
            }
            if !bz.chol_upper(m1, nvar, u) { ret mem.Full }
            bz.inv_upper(u, nvar, ui)
            bg.gemm(false, true, ui, nvar, ui, nvar, nvar, nvar, nvar, cv)
            if !bz.chol_upper(cv, nvar, ir) { ret mem.Full }
            vv = 0usize
            while vv < nvar {
                nzv[vv] = rng.norm(r)
                vv += 1usize
            }
            vv = 0usize
            while vv < nvar {
                var sm = 0.0f64
                var q = 0usize
                while q <= vv {
                    sm += ir[vv * nvar + q] * nzv[q]
                    q += 1usize
                }
                bc[vv] = obl[vv] + s * sm
                vv += 1usize
            }
            let cll = llmnl_con(a, bc, signres, yl, xl, nvar, p)
            let clpost = cll + bz.lnd_mvn(a, bc, bbar, rp, nvar)
            let ldiff = clpost - oll[l] - bz.lnd_mvn(a, obl, bbar, rp, nvar)
            var alpha = 1.0f64
            let ex = math.exp[f64](ldiff)
            if ex < 1.0f64 { alpha = ex }
            var un = 0.0f64
            if alpha < 1.0f64 { un = rng.unif(r) }
            if un <= alpha {
                vv = 0usize
                while vv < nvar {
                    ob[vv * nlgt + l] = bc[vv]
                    vv += 1usize
                }
                oll[l] = cll
            }
            mem.reset(a, start2)
            off += nl
            l += 1usize
        }
        let o = out[rep * w..(rep + 1usize) * w]
        i = 0usize
        while i < nlgt * nvar {
            let col = i / nlgt
            o[i] = ob[i]
            if signres[col] != 0.0f64 { o[i] = signres[col] * math.exp[f64](ob[i]) }
            i += 1usize
        }
        var at = nlgt * nvar
        i = 0usize
        while i < nc {
            o[at + i] = prob[i]
            i += 1usize
        }
        at += nc
        var tl = 0.0f64
        i = 0usize
        while i < nlgt {
            tl += oll[i]
            i += 1usize
        }
        o[at] = tl
        at += 1usize
        i = 0usize
        while i < nz * nvar {
            o[at + i] = dl[i]
            i += 1usize
        }
        at += nz * nvar
        i = 0usize
        while i < comps.len {
            o[at + i] = comps[i]
            i += 1usize
        }
        mem.reset(a, start)
        rep += 1usize
    }
    ret ok
}
