// `e.math.special` against SciPy: log-gamma and gamma, erf and erfc in the body
// and the tail, the regularised incomplete gamma and beta functions on both
// sides of their series/fraction switch, the normal, t, chi-squared and F
// distribution functions, the normal quantile as the inverse of the CDF, and
// binomial coefficients. Each check exits with its own code.

use e.io
use e.math.special
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    var scale = want
    if scale < 0.0f64 { scale = 0.0f64 - scale }
    if scale < 1.0f64 { scale = 1.0f64 }
    ret d <= eps * scale
}

fn is_nan(x: f64) -> bool { ret x != x }

fn main(a: *mem.Arena, args: []str) -> err {
    let tight = 0.000000000001f64
    let loose = 0.00000001f64

    // 1: gamma.
    if !near(special.lgamma(0.5f64), 0.5723649429247f64, tight) || !near(special.lgamma(10.0f64), 12.801827480081469f64, tight) { os.exit(1i32) }
    if !near(special.lgamma(100.5f64), 361.43554046777757f64, tight) || !near(special.lgamma(0.1f64), 2.252712651734206f64, tight) { os.exit(1i32) }
    if !near(special.gamma(5.0f64), 24.0f64, loose) || !near(special.gamma(1.0f64), 1.0f64, loose) || !near(special.gamma(0.5f64), 1.7724538509055159f64, loose) { os.exit(1i32) }
    if !is_nan(special.lgamma(0.0f64)) || !is_nan(special.gamma(0.0f64 - 1.0f64)) { os.exit(1i32) }
    if special.choose(10.0f64, 3.0f64) != 120.0f64 || special.choose(52.0f64, 5.0f64) != 2598960.0f64 || special.choose(3.0f64, 5.0f64) != 0.0f64 { os.exit(1i32) }

    // 2: erf and erfc.
    if !near(special.erf(0.5f64), 0.5204998778130465f64, tight) || !near(special.erf(2.0f64), 0.9953222650189527f64, tight) { os.exit(2i32) }
    if !near(special.erf(3.0f64), 0.9999779095030014f64, tight) || !near(special.erf(0.0f64 - 1.2f64), 0.0f64 - 0.9103139782296353f64, tight) { os.exit(2i32) }
    if !near(special.erfc(4.0f64), 0.00000001541725790028002f64, 0.0000001f64) || special.erf(0.0f64) != 0.0f64 { os.exit(2i32) }
    if !near(special.erfc(4.0f64) / 0.00000001541725790028002f64, 1.0f64, loose) { os.exit(2i32) }
    if !near(special.erfc(0.5f64), 1.0f64 - 0.5204998778130465f64, tight) { os.exit(2i32) }

    // 3: incomplete gamma and beta.
    if !near(special.gamma_p(2.5f64, 1.0f64), 0.15085496391539038f64, loose) || !near(special.gamma_p(2.5f64, 6.0f64), 0.9652122194937581f64, loose) { os.exit(3i32) }
    if !near(special.gamma_q(0.5f64, 3.0f64), 0.014305878435429641f64, loose) || !near(special.gamma_q(2.5f64, 1.0f64), 1.0f64 - 0.15085496391539038f64, loose) { os.exit(3i32) }
    if special.gamma_p(2.0f64, 0.0f64) != 0.0f64 || !is_nan(special.gamma_p(0.0f64, 1.0f64)) { os.exit(3i32) }
    if !near(special.beta_i(2.0f64, 3.0f64, 0.4f64), 0.5248f64, loose) || !near(special.beta_i(0.5f64, 0.5f64, 0.9f64), 0.7951672353008665f64, loose) { os.exit(3i32) }
    if !near(special.beta_i(10.0f64, 2.0f64, 0.95f64), 0.8981054088575682f64, loose) { os.exit(3i32) }
    if special.beta_i(2.0f64, 3.0f64, 0.0f64) != 0.0f64 || special.beta_i(2.0f64, 3.0f64, 1.0f64) != 1.0f64 || !is_nan(special.beta_i(2.0f64, 3.0f64, 1.5f64)) { os.exit(3i32) }

    // 4: distribution functions.
    if !near(special.normal_cdf(1.96f64), 0.9750021048517795f64, loose) || !near(special.normal_cdf(0.0f64), 0.5f64, tight) { os.exit(4i32) }
    if !near(special.normal_cdf(0.0f64 - 1.96f64), 1.0f64 - 0.9750021048517795f64, loose) { os.exit(4i32) }
    if !near(special.t_cdf(2.0f64, 5.0f64), 0.9490302605850708f64, loose) || !near(special.t_cdf(0.0f64 - 1.5f64, 12.0f64), 0.07972875175660343f64, loose) { os.exit(4i32) }
    if !near(special.chi_squared_cdf(3.84f64, 1.0f64), 0.9499564787512949f64, loose) || !near(special.chi_squared_cdf(10.0f64, 4.0f64), 0.9595723180054873f64, loose) { os.exit(4i32) }
    if !near(special.f_cdf(3.0f64, 3.0f64, 10.0f64), 0.9182530481901753f64, loose) || special.f_cdf(0.0f64, 3.0f64, 10.0f64) != 0.0f64 { os.exit(4i32) }
    if !is_nan(special.t_cdf(1.0f64, 0.0f64)) || !is_nan(special.chi_squared_cdf(0.0f64 - 1.0f64, 2.0f64)) { os.exit(4i32) }

    // 5: the normal quantile inverts the CDF.
    if !near(special.normal_quantile(0.975f64), 1.959963984540054f64, loose) || !near(special.normal_quantile(0.001f64), 0.0f64 - 3.090232306167813f64, loose) { os.exit(5i32) }
    if !near(special.normal_quantile(0.6f64), 0.2533471031357997f64, loose) || !near(special.normal_quantile(0.5f64), 0.0f64, 0.000000001f64) { os.exit(5i32) }
    var p = 0.001f64
    while p < 0.999f64 {
        if !near(special.normal_cdf(special.normal_quantile(p)), p, 0.00000001f64) { os.exit(5i32) }
        p += 0.0137f64
    }
    if !is_nan(special.normal_quantile(0.0f64)) || !is_nan(special.normal_quantile(1.0f64)) { os.exit(5i32) }

    try io.print("math special ok\n")
    ret ok
}
