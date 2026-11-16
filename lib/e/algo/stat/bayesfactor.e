// R BayesFactor: the JZS Bayes factor of a t statistic (ttest.tstat), the log of BF10 for a one- or two-sample t test with a Cauchy prior of
// scale rscale on the standardised effect, by integrating the inverse-chi-square mixing density as Rouder et al. (2009) do.
//
// Not here: regression and ANOVA Bayes factors (the g-prior integrals of lmBF, anovaBF), the sampling of posteriors, interval null
// hypotheses, the proportion and correlation tests.

use e.math
use e.math.quadpack as qp
use e.mem

type Ctx = struct { t: f64, n: f64, nu: f64, r2: f64 }

fn integrand(c: *Ctx, g: f64) -> f64 {
    let s = 1.0f64 + c.n * g * c.r2
    ret math.pow[f64](s, 0.0f64 - 0.5f64) * math.pow[f64](1.0f64 + c.t * c.t / (s * c.nu), 0.0f64 - (c.nu + 1.0f64) / 2.0f64) * math.pow[f64](2.0f64 * 3.141592653589793238462643383279f64, 0.0f64 - 0.5f64) * math.pow[f64](g, 0.0f64 - 1.5f64) * math.exp[f64](0.0f64 - 1.0f64 / (2.0f64 * g))
}

// the natural log of BF10; n2 = 0 selects the one-sample test (n1 observations), otherwise the two-sample test with sizes n1 and n2
fn ttest_log_bf(a: *mem.Arena, t: f64, n1: f64, n2: f64, rscale: f64) -> (f64, err) {
    var n = n1
    var nu = n1 - 1.0f64
    if n2 > 0.0f64 {
        n = n1 * n2 / (n1 + n2)
        nu = n1 + n2 - 2.0f64
    }
    var c = Ctx { t: t, n: n, nu: nu, r2: rscale * rscale }
    let (r, e) = qp.qagi[Ctx](a, &c, integrand, 0.0f64, 1i64, 1.0e-12f64, 1.0e-10f64, 200usize)
    if e != ok { ret (0.0f64, e) }
    let den = math.pow[f64](1.0f64 + t * t / nu, 0.0f64 - (nu + 1.0f64) / 2.0f64)
    ret (math.log[f64](r.result / den), ok)
}
