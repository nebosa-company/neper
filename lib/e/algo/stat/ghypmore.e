// R GeneralizedHyperbolic, third part: parameter checks, GIG moments in every case, the parameter conversions of the GIG and hyperbolic families, ghypScale,
// ghypStandPars and ghypMomBNS.

use e.algo.stat.ghyp as gh
use e.algo.stat.gslfns as gs
use e.math
use e.math.nmath as nm
use e.mem

// ---- parameter checks, as codes: gigCheckPars 0 normal, 1 gamma, 2 invgamma, 3 error; ghypCheckPars 0 normal, 1 error, 2 skew laplace, 3 laplace, 4 hyperbolic,
// 5 variance gamma, 6 cauchy, 7 normal inverse gaussian, 8 skew hyperbolic, 9 student's t
fn all_equal0(x: f64) -> bool { ret math.abs[f64](x) <= 0.000000014901161193847656f64 }

fn gig_check_pars(chi: f64, psi: f64, lambda: f64) -> f64 {
    if chi < 0.0f64 || psi < 0.0f64 { ret 3.0f64 }
    if all_equal0(chi) {
        if lambda <= 0.0f64 { ret 3.0f64 }
        if all_equal0(psi) { ret 3.0f64 }
        ret 1.0f64
    }
    if all_equal0(psi) {
        if lambda >= 0.0f64 { ret 3.0f64 }
        ret 2.0f64
    }
    ret 0.0f64
}

fn ghyp_check_pars(delta: f64, alpha: f64, beta: f64, lambda: f64) -> f64 {
    var cs = 0.0f64
    if alpha < 0.0f64 { ret 1.0f64 }
    let ab = math.abs[f64](beta)
    if lambda == 0.0f64 {
        if ab >= alpha || delta <= 0.0f64 { cs = 1.0f64 }
    }
    if lambda > 0.0f64 {
        if ab >= alpha || delta < 0.0f64 { cs = 1.0f64 }
        if cs != 1.0f64 {
            if lambda == 1.0f64 {
                if alpha > 0.0f64 && ab < alpha && delta == 0.0f64 { cs = 2.0f64 }
                if alpha > 0.0f64 && beta == 0.0f64 && delta == 0.0f64 { cs = 3.0f64 }
                if alpha > 0.0f64 && ab < alpha && delta > 0.0f64 { cs = 4.0f64 }
            } else {
                if alpha > 0.0f64 && ab < alpha && delta == 0.0f64 { cs = 5.0f64 }
            }
        }
    }
    if lambda < 0.0f64 {
        if ab > alpha || delta <= 0.0f64 { cs = 1.0f64 }
        if cs != 1.0f64 {
            if lambda == 0.0f64 - 0.5f64 {
                if alpha == 0.0f64 && beta == 0.0f64 && delta > 0.0f64 { cs = 6.0f64 }
                if alpha > 0.0f64 && ab < alpha && delta > 0.0f64 { cs = 7.0f64 }
            } else {
                if math.abs[f64](alpha - ab) < 0.001f64 && beta >= 0.0f64 && delta > 0.0f64 { cs = 8.0f64 }
                if alpha == 0.0f64 && beta == 0.0f64 && delta > 0.0f64 { cs = 9.0f64 }
            }
        }
    }
    ret cs
}

// ---- GIG raw moments including the gamma (chi = 0) and inverse gamma (psi = 0) cases, momChangeAbout, and the central moments gigVar, gigSkew, gigKurt
fn bes_ratio(x: f64, nu: f64, d: f64) -> f64 { ret gs.bessel_knu(nu + d, x) / gs.bessel_knu(nu, x) }

// the package passes its "scale" as the third argument, which gammaRawMom takes as the rate
fn gamma_raw_mom(order: f64, shape: f64, rate: f64) -> f64 {
    let scale = 1.0f64 / rate
    if order <= 0.0f64 - shape { ret 1.0f64 / 0.0f64 }
    ret math.pow[f64](scale, order) * nm.gammafn(shape + order) / nm.gammafn(shape)
}

fn gig_raw_mom_case(order: f64, chi: f64, psi: f64, lambda: f64) -> f64 {
    let cs = gig_check_pars(chi, psi, lambda)
    if cs == 1.0f64 { ret gamma_raw_mom(order, lambda, psi / 2.0f64) }
    if cs == 2.0f64 { ret gamma_raw_mom(0.0f64 - order, 0.0f64 - lambda, 2.0f64 / chi) }
    ret gh.gig_raw_mom(order, chi, psi, lambda)
}

// momChangeAbout(order, c(old[1..order]), oldAbout, newAbout): sum_k choose(order, k) (oldAbout - newAbout)^(order - k) old[k] with old[0] = 1
fn mom_change_about(order: usize, old: []const f64, old_about: f64, new_about: f64) -> f64 {
    var tot = 0.0f64
    var c = 1.0f64
    var j = 0usize
    while j <= order {
        var om = 1.0f64
        if j > 0usize { om = old[j - 1usize] }
        tot += c * math.pow[f64](old_about - new_about, f64(order - j)) * om
        c = c * f64(order - j) / f64(j + 1usize)
        j += 1usize
    }
    ret tot
}

// gigMom(order, about): about = 0 is the raw moment
fn gig_mom(a: *mem.Arena, order: usize, chi: f64, psi: f64, lambda: f64, about: f64) -> f64 {
    if about == 0.0f64 { ret gig_raw_mom_case(f64(order), chi, psi, lambda) }
    if order == 0usize { ret 1.0f64 }
    let (raw, e) = mem.alloc[f64](a, order)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < order {
        raw[i] = gig_raw_mom_case(f64(i + 1usize), chi, psi, lambda)
        i += 1usize
    }
    ret mom_change_about(order, raw, 0.0f64, about)
}

fn gig_var2(a: *mem.Arena, chi: f64, psi: f64, lambda: f64) -> f64 { ret gig_mom(a, 2usize, chi, psi, lambda, gh.gig_mean(chi, psi, lambda)) }

fn gig_skew(a: *mem.Arena, chi: f64, psi: f64, lambda: f64) -> f64 {
    ret gig_mom(a, 3usize, chi, psi, lambda, gh.gig_mean(chi, psi, lambda)) / math.pow[f64](gig_var2(a, chi, psi, lambda), 1.5f64)
}

fn gig_kurt(a: *mem.Arena, chi: f64, psi: f64, lambda: f64) -> f64 {
    let v = gig_var2(a, chi, psi, lambda)
    ret gig_mom(a, 4usize, chi, psi, lambda, gh.gig_mean(chi, psi, lambda)) / (v * v) - 3.0f64
}

// ---- gigChangePars (1 chi psi, 2 delta gamma, 3 alpha beta, 4 omega eta) and hyperbChangePars (1 pi zeta, 2 alpha beta, 3 phi gamma, 4 xi chi): the two changed
// parameters are written to out[0..2], by the package's direct formula for each pair
fn gig_change_pars(from: usize, to: usize, p1: f64, p2: f64, out: []f64) {
    var o1 = p1
    var o2 = p2
    if from == 1usize && to == 2usize {
        o1 = math.sqrt[f64](p1)
        o2 = math.sqrt[f64](p2)
    }
    if from == 1usize && to == 3usize {
        o1 = math.sqrt[f64](p2 / p1)
        o2 = math.sqrt[f64](p1 * p2)
    }
    if from == 1usize && to == 4usize {
        o1 = math.sqrt[f64](p1 * p2)
        o2 = math.sqrt[f64](p1 / p2)
    }
    if from == 2usize && to == 1usize {
        o1 = p1 * p1
        o2 = p2 * p2
    }
    if from == 2usize && to == 3usize {
        o1 = p2 / p1
        o2 = p2 * p1
    }
    if from == 2usize && to == 4usize {
        o1 = p1 * p2
        o2 = p1 / p2
    }
    if from == 3usize && to == 1usize {
        o1 = p2 / p1
        o2 = p1 * p2
    }
    if from == 3usize && to == 2usize {
        o1 = math.sqrt[f64](p2 / p1)
        o2 = math.sqrt[f64](p1 * p2)
    }
    if from == 3usize && to == 4usize {
        o1 = p2
        o2 = 1.0f64 / p1
    }
    if from == 4usize && to == 1usize {
        o1 = p1 * p2
        o2 = p1 / p2
    }
    if from == 4usize && to == 2usize {
        o1 = math.sqrt[f64](p1 * p2)
        o2 = math.sqrt[f64](p1 / p2)
    }
    if from == 4usize && to == 3usize {
        o1 = 1.0f64 / p2
        o2 = p1
    }
    out[0usize] = o1
    out[1usize] = o2
}

fn hyperb_change_pars(from: usize, to: usize, delta: f64, p3: f64, p4: f64, out: []f64) {
    var o1 = p3
    var o2 = p4
    let sq = math.sqrt[f64](1.0f64 + p3 * p3)
    if from == 1usize && to == 2usize {
        o1 = p4 * sq / delta
        o2 = p4 * p3 / delta
    }
    if from == 1usize && to == 3usize {
        o1 = p4 / delta * (sq + p3)
        o2 = p4 / delta * (sq - p3)
    }
    if from == 1usize && to == 4usize {
        o1 = 1.0f64 / math.sqrt[f64](1.0f64 + p4)
        o2 = p3 / math.sqrt[f64]((1.0f64 + p4) * (1.0f64 + p3 * p3))
    }
    if from == 2usize && to == 1usize {
        o1 = p4 / math.sqrt[f64](p3 * p3 - p4 * p4)
        o2 = delta * math.sqrt[f64](p3 * p3 - p4 * p4)
    }
    if from == 2usize && to == 3usize {
        o1 = p3 + p4
        o2 = p3 - p4
    }
    if from == 2usize && to == 4usize {
        let s2 = math.sqrt[f64](1.0f64 + delta * math.sqrt[f64](p3 * p3 - p4 * p4))
        o1 = 1.0f64 / s2
        o2 = p4 / (p3 * s2)
    }
    if from == 3usize && to == 1usize {
        o1 = (p3 - p4) / (2.0f64 * math.sqrt[f64](p3 * p4))
        o2 = delta * math.sqrt[f64](p3 * p4)
    }
    if from == 3usize && to == 2usize {
        o1 = (p3 + p4) / 2.0f64
        o2 = (p3 - p4) / 2.0f64
    }
    if from == 3usize && to == 4usize {
        let s3 = math.sqrt[f64](1.0f64 + delta * math.sqrt[f64](p3 * p4))
        o1 = 1.0f64 / s3
        o2 = ((p3 - p4) / (p3 + p4)) / s3
    }
    let rx = math.sqrt[f64](p3 * p3 - p4 * p4)
    if from == 4usize && to == 1usize {
        o1 = p4 / rx
        o2 = (1.0f64 - p3 * p3) / (p3 * p3)
    }
    if from == 4usize && to == 2usize {
        o1 = (1.0f64 - p3 * p3) / (delta * p3 * rx)
        o2 = p4 * (1.0f64 - p3 * p3) / (delta * p3 * p3 * rx)
    }
    if from == 4usize && to == 3usize {
        o1 = (1.0f64 - p3 * p3) * (p3 + p4) / (delta * p3 * p3 * rx)
        o2 = (1.0f64 - p3 * p3) * (p3 - p4) / (delta * p3 * p3 * rx)
    }
    out[0usize] = o1
    out[1usize] = o2
}

// ---- ghypScale and ghypStandPars (written to out as mu, delta, alpha, beta), ghypMomBNS
fn kappa_lambda(lambda: f64, zeta: f64) -> f64 { ret bes_ratio(zeta, lambda, 1.0f64) / zeta }

fn ghyp_stand_pars(rho: f64, zeta: f64, lambda: f64, out: []f64) {
    let dk = kappa_lambda(lambda + 1.0f64, zeta) - kappa_lambda(lambda, zeta)
    let kl = kappa_lambda(lambda, zeta)
    let alpha_star = math.sqrt[f64](zeta * zeta / (1.0f64 - rho * rho) * kl * (1.0f64 + rho * rho * zeta * zeta / (1.0f64 - rho * rho) * dk))
    out[0usize] = 0.0f64 - (1.0f64 / alpha_star) * rho * zeta * zeta * kl / (1.0f64 - rho * rho)
    out[1usize] = (1.0f64 / alpha_star) * zeta / math.sqrt[f64](1.0f64 - rho * rho)
    out[2usize] = alpha_star
    out[3usize] = alpha_star * rho
}

fn ghyp_scale(a: *mem.Arena, new_mean: f64, new_sd: f64, delta: f64, alpha: f64, beta: f64, lambda: f64, out: []f64) {
    let gamma = math.sqrt[f64](alpha * alpha - beta * beta)
    let rho = beta / alpha
    let zeta = delta * gamma
    let r1 = bes_ratio(zeta, lambda, 1.0f64)
    let var_factor = r1 / zeta + (rho * rho / (1.0f64 - rho * rho)) * (bes_ratio(zeta, lambda, 2.0f64) - r1 * r1)
    let nd = new_sd / math.sqrt[f64](var_factor)
    let nmu = new_mean - (nd * rho / math.sqrt[f64](1.0f64 - rho * rho)) * r1
    let (ab, e) = mem.alloc[f64](a, 2usize)
    if e != ok { ret }
    gh.ghyp_change_pars(2usize, 1usize, nd, rho, zeta, ab)
    out[0usize] = nmu
    out[1usize] = nd
    out[2usize] = ab[0usize]
    out[3usize] = ab[1usize]
}

fn ghyp_mom_bns(order: usize, delta: f64, alpha: f64, beta: f64, lambda: f64, tol: f64) -> f64 {
    let alphabar = delta * alpha
    let betabar = delta * beta
    let gamma = math.sqrt[f64](alpha * alpha - beta * beta)
    let gammabar = delta * gamma
    let m = order % 2usize
    let ord2 = (order + 1usize) / 2usize
    let o2 = f64(ord2)
    let cst = math.pow[f64](2.0f64, o2) * math.pow[f64](gammabar, lambda) * math.pow[f64](delta, 2.0f64 * o2) * math.pow[f64](beta, f64(m)) / (math.sqrt[f64](3.141592653589793238462643383279f64) * gs.bessel_knu(lambda, gammabar) * math.pow[f64](alphabar, lambda + o2))
    var ak = cst * nm.gammafn(o2 + 0.5f64) * gs.bessel_knu(lambda + o2, alphabar) / nm.gammafn(f64(m) + 1.0f64)
    var mom = ak
    var k = 0.0f64
    var cont = true
    var guard = 0usize
    while cont && guard < 100000usize {
        let mf = f64(m)
        ak = ak * 2.0f64 * betabar * betabar * (k + o2 + 0.5f64) / (alphabar * (2.0f64 * k + 2.0f64 + mf) * (2.0f64 * k + 1.0f64 + mf)) * bes_ratio(alphabar, lambda + k + o2, 1.0f64)
        if ak / mom < tol { cont = false }
        mom = mom + ak
        k = k + 1.0f64
        guard += 1usize
    }
    ret mom
}

// ---- RLambda, SLambda, MLambda, WLambda1 to 4 and gammaLambda1, gammaLambda2 (Barndorff-Nielsen and Blaesild), dgigScaled and ddgig
fn r_lambda(zeta: f64, lambda: f64) -> f64 { ret gs.bessel_knu(lambda + 1.0f64, zeta) / gs.bessel_knu(lambda, zeta) }

fn s_lambda(zeta: f64, lambda: f64) -> f64 {
    let k0 = gs.bessel_knu(lambda, zeta)
    let k1 = gs.bessel_knu(lambda + 1.0f64, zeta)
    ret (gs.bessel_knu(lambda + 2.0f64, zeta) * k0 - k1 * k1) / (k0 * k0)
}

fn m_lambda(zeta: f64, lambda: f64) -> f64 { ret gs.bessel_knu(lambda + 2.0f64, zeta) / gs.bessel_knu(lambda, zeta) }

fn w_lambda2(zeta: f64, lambda: f64) -> f64 {
    let r = r_lambda(zeta, lambda)
    ret 0.0f64 - r * r + 2.0f64 * (lambda + 1.0f64) * r / zeta + 1.0f64
}

fn w_lambda3(zeta: f64, lambda: f64) -> f64 {
    let r = r_lambda(zeta, lambda)
    ret 2.0f64 * r * r * r - 6.0f64 * (lambda + 1.0f64) * r * r / zeta + (4.0f64 * (lambda + 1.0f64) * (lambda + 2.0f64) / (zeta * zeta) - 2.0f64) * r + 2.0f64 * (lambda + 2.0f64) / zeta
}

fn w_lambda4(zeta: f64, lambda: f64) -> f64 {
    let r = r_lambda(zeta, lambda)
    ret 0.0f64 - 6.0f64 * math.pow[f64](r, 4.0f64) + 24.0f64 * (lambda + 1.0f64) * r * r * r / zeta + (0.0f64 - 4.0f64 * (lambda + 1.0f64) * (7.0f64 * lambda + 11.0f64) / (zeta * zeta) + 8.0f64) * r * r + (8.0f64 * (lambda + 1.0f64) * (lambda + 2.0f64) * (lambda + 3.0f64) / (zeta * zeta * zeta) - 4.0f64 * (4.0f64 * lambda + 5.0f64) / zeta) * r + 4.0f64 * (lambda + 2.0f64) * (lambda + 3.0f64) / (zeta * zeta) - 2.0f64
}

// the package calls WLambda1(zeta) with its default lambda = 1 inside gammaLambda1 and gammaLambda2
fn gamma_lambda1(pi_: f64, zeta: f64, lambda: f64) -> f64 {
    ret (pi_ * pi_ * pi_ * w_lambda3(zeta, lambda) + 3.0f64 * pi_ * w_lambda2(zeta, lambda) / zeta) / math.pow[f64](pi_ * pi_ * w_lambda2(zeta, lambda) + r_lambda(zeta, 1.0f64) / zeta, 1.5f64)
}

fn gamma_lambda2(pi_: f64, zeta: f64, lambda: f64) -> f64 {
    let den = pi_ * pi_ * w_lambda2(zeta, lambda) + r_lambda(zeta, 1.0f64) / zeta
    ret (math.pow[f64](pi_, 4.0f64) * w_lambda4(zeta, lambda) + 6.0f64 * pi_ * pi_ * w_lambda3(zeta, lambda) / zeta + 3.0f64 * w_lambda2(zeta, lambda) / (zeta * zeta)) / (den * den)
}

fn dgig_scaled(x: f64, chi: f64, psi: f64, lambda: f64) -> f64 {
    let omega = math.sqrt[f64](chi * psi)
    let ko = gs.bessel_knu(lambda, omega) * math.exp[f64](omega)
    ret math.pow[f64](psi / chi, lambda / 2.0f64) / (2.0f64 * ko) * math.pow[f64](x, lambda - 1.0f64) * math.exp[f64](0.0f64 - 0.5f64 * (chi * (1.0f64 / x) + psi * x) + omega)
}

fn ddgig(x: f64, chi: f64, psi: f64, lambda: f64) -> f64 {
    if !(x > 0.0f64) { ret 0.0f64 }
    ret gh.dgig(x, chi, psi, lambda) * (chi / (x * x) + 2.0f64 * (lambda - 1.0f64) / x - psi) / 2.0f64
}
