// gamlss.dist's make.link.gamlss for the common links: the link function (linkfun), the inverse link (linkinv, with the package's clamping) and the derivative of the
// inverse (mu.eta). Kinds: 0 logit (the standard logistic), 1 probit, 2 cauchit, 3 cloglog, 4 identity, 5 log, 6 sqrt, 7 1/mu^2, 8 mu^2, 9 logshiftto1, 10 logshiftto2, 11 logshiftto0.

use e.algo.stat.gamlssdist as gd
use e.math
use e.math.dist as dist

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

fn pmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn pmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn clamp(x: f64, th: f64) -> f64 { ret pmin(th, pmax(x, 0.0f64 - th)) }

fn linkfun(kind: usize, mu: f64) -> f64 {
    if kind == 0usize { ret gd.qlo(mu, 0.0f64, 1.0f64) }
    if kind == 1usize { ret dist.qnorm(mu, 0.0f64, 1.0f64, true, false) }
    if kind == 2usize { ret math.tan[f64](3.141592653589793238462643383279f64 * (mu - 0.5f64)) }
    if kind == 3usize { ret math.log[f64](0.0f64 - math.log[f64](1.0f64 - mu)) }
    if kind == 4usize { ret mu }
    if kind == 5usize { ret math.log[f64](mu) }
    if kind == 6usize { ret math.pow[f64](mu, 0.5f64) }
    if kind == 7usize { ret 1.0f64 / (mu * mu) }
    if kind == 8usize { ret mu * mu }
    if kind == 9usize { ret math.log[f64](mu - 1.0f64 + 0.00001f64) }
    if kind == 10usize { ret math.log[f64](mu - 2.0f64 + 0.00001f64) }
    ret math.log[f64](mu - 0.00001f64)
}

fn linkinv(kind: usize, eta: f64) -> f64 {
    if kind == 0usize { ret gd.plo(clamp(eta, 0.0f64 - gd.qlo(eps(), 0.0f64, 1.0f64)), 0.0f64, 1.0f64) }
    if kind == 1usize { ret dist.pnorm(clamp(eta, 0.0f64 - dist.qnorm(eps(), 0.0f64, 1.0f64, true, false)), 0.0f64, 1.0f64, true, false) }
    if kind == 2usize {
        let th = 0.0f64 - math.tan[f64](3.141592653589793238462643383279f64 * (eps() - 0.5f64))
        ret 0.5f64 + math.atan[f64](clamp(eta, th)) / 3.141592653589793238462643383279f64
    }
    if kind == 3usize { ret pmax(pmin(0.0f64 - (math.exp[f64](0.0f64 - math.exp[f64](eta)) - 1.0f64), 1.0f64 - eps()), eps()) }
    if kind == 4usize { ret eta }
    if kind == 5usize { ret pmax(math.exp[f64](eta), eps()) }
    if kind == 6usize { ret eta * eta }
    if kind == 7usize { ret 1.0f64 / math.pow[f64](eta, 0.5f64) }
    if kind == 8usize { ret math.pow[f64](eta, 0.5f64) }
    if kind == 9usize { ret 1.0f64 + pmax(eps(), math.exp[f64](eta)) }
    if kind == 10usize { ret 2.0f64 + pmax(eps(), math.exp[f64](eta)) }
    ret 0.00001f64 + pmax(eps(), math.exp[f64](eta))
}

fn mu_eta(kind: usize, eta: f64) -> f64 {
    if kind == 0usize { ret pmax(gd.dlo(eta, 0.0f64, 1.0f64), eps()) }
    if kind == 1usize { ret pmax(dist.dnorm(eta, 0.0f64, 1.0f64, false), eps()) }
    if kind == 2usize { ret pmax(1.0f64 / (3.141592653589793238462643383279f64 * (1.0f64 + eta * eta)), eps()) }
    if kind == 3usize {
        let e = pmin(eta, 700.0f64)
        ret pmax(math.exp[f64](e) * math.exp[f64](0.0f64 - math.exp[f64](e)), eps())
    }
    if kind == 4usize { ret 1.0f64 }
    if kind == 5usize { ret pmax(math.exp[f64](eta), eps()) }
    if kind == 6usize { ret 2.0f64 * eta }
    if kind == 7usize { ret (0.0f64 - 1.0f64) / (2.0f64 * math.pow[f64](eta, 1.5f64)) }
    if kind == 8usize { ret 0.5f64 * math.pow[f64](eta, 0.0f64 - 0.5f64) }
    ret pmax(eps(), math.exp[f64](eta))
}

// the default links of the families' mu, sigma, nu and tau (family()$mu.link and so on) for the 116 families in the alphabetical order of e.algo.stat.gamlssr (0 BB ... 115 ZISICHEL), as
// the kind above that make.link.gamlss gives them: 4 identity, 5 log, 0 logit, 10 logshiftto2; 99 where the family has no such parameter
fn family_link(fam: usize, which: usize) -> usize {
    let t = "gl--ili-lli-ililllilililllilgg--ggllggl-ggl-ll--glg-glg-g---lll-gl--lll-llg-ll--illll---ll--lli-gglllllll---g---lli-lli-ll--ll--illlil--ll--ll--ililililg---il--il--gl--il--ll--illlll--ll--lll-lllllll-ll--ll--iliiil--il--ili-l---l---ll--ll--ll--ill-ill-ll--ll--l---il--ill-ilililililililllilllilllilililillli-lli-gl--ili-ill-illsilililililllilllilllililill-ils-ll--ll--ll--ll--l---glg-gg--lllgllg-llg-gg--llg-lg--llg-lliglg--glg-gg--lllglllgllg-lg--lg--l---llg-llig"
    let c = t[fam * 4usize + which]
    if c == 105u8 { ret 4usize }
    if c == 108u8 { ret 5usize }
    if c == 103u8 { ret 0usize }
    if c == 115u8 { ret 10usize }
    ret 99usize
}
