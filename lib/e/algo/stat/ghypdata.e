// R GeneralizedHyperbolic's parameter sets (ghypLargeParam, ghypSmallParam, ghypLargeShape, ghypSmallShape, the hyperb and nig versions without the lambda column,
// gigLargeParam and gigSmallParam): the package builds them with the loops of its *CreateParameters.R, rounding alpha and beta to 3 places. Row r of set s is
// computed here from the same tables, so nothing is stored.

use e.math

// round(x, 3) of R >= 4.0: the nearer of the two neighbours on the 0.001 grid, the even last digit on a tie
fn round3(x: f64) -> f64 {
    let lo = math.floor[f64](x * 1000.0f64) / 1000.0f64
    let hi = math.ceil[f64](x * 1000.0f64) / 1000.0f64
    let dl = x - lo
    let dh = hi - x
    if dl < dh { ret lo }
    if dh < dl { ret hi }
    let k = math.floor[f64](x * 1000.0f64)
    if k - 2.0f64 * math.floor[f64](k / 2.0f64) == 0.0f64 { ret lo }
    ret hi
}

fn xi_of(small: bool, k: usize) -> f64 {
    if small {
        if k < 1usize { ret 0.1f64 }
        if k < 3usize { ret 0.3f64 }
        ret 0.7f64
    }
    if k < 1usize { ret 0.1f64 }
    if k < 3usize { ret 0.3f64 }
    if k < 6usize { ret 0.5f64 }
    if k < 10usize { ret 0.7f64 }
    ret 0.9f64
}

fn chi_of(small: bool, k: usize) -> f64 {
    if small {
        if k == 0usize { ret 0.0f64 }
        if k == 1usize { ret 0.0f64 - 0.25f64 }
        if k == 2usize { ret 0.25f64 }
        if k == 3usize { ret 0.0f64 - 0.65f64 }
        if k == 4usize { ret 0.0f64 - 0.3f64 }
        if k == 5usize { ret 0.3f64 }
        ret 0.65f64
    }
    if k == 0usize { ret 0.0f64 }
    if k == 1usize { ret 0.0f64 - 0.25f64 }
    if k == 2usize { ret 0.25f64 }
    if k == 3usize { ret 0.0f64 - 0.45f64 }
    if k == 4usize { ret 0.0f64 }
    if k == 5usize { ret 0.45f64 }
    if k == 6usize { ret 0.0f64 - 0.65f64 }
    if k == 7usize { ret 0.0f64 - 0.3f64 }
    if k == 8usize { ret 0.3f64 }
    if k == 9usize { ret 0.65f64 }
    if k == 10usize { ret 0.0f64 - 0.85f64 }
    if k == 11usize { ret 0.0f64 - 0.4f64 }
    if k == 12usize { ret 0.0f64 }
    if k == 13usize { ret 0.4f64 }
    ret 0.85f64
}

fn lambda_of(small: bool, l: usize) -> f64 {
    if small {
        if l == 0usize { ret 0.0f64 - 0.5f64 }
        if l == 1usize { ret 0.0f64 }
        ret 1.0f64
    }
    if l == 0usize { ret 0.0f64 - 1.0f64 }
    if l == 1usize { ret 0.0f64 - 0.5f64 }
    if l == 2usize { ret 0.0f64 }
    if l == 3usize { ret 0.5f64 }
    if l == 4usize { ret 1.0f64 }
    ret 2.0f64
}

// the number of rows of a set: family 0 ghyp, 1 hyperb, 2 nig; set 0 LargeParam, 1 SmallParam, 2 LargeShape, 3 SmallShape
fn param_rows(fam: usize, set: usize) -> usize {
    var nl = 1usize
    if fam == 0usize {
        if set == 0usize || set == 2usize { nl = 6usize } else { nl = 3usize }
    }
    if set == 0usize { ret 4usize * 4usize * 15usize * nl }
    if set == 1usize { ret 2usize * 2usize * 7usize * nl }
    if set == 2usize { ret 15usize * nl }
    ret 7usize * nl
}

// row r (0-based) of the set: mu, delta, alpha, beta, lambda into out[0..5] (hyperb and nig tables have the first four columns only)
fn ghyp_param_row(fam: usize, set: usize, r: usize, out: []f64) {
    let small = set == 1usize || set == 3usize
    var nl = 1usize
    if fam == 0usize {
        if small { nl = 3usize } else { nl = 6usize }
    }
    var nk = 15usize
    if small { nk = 7usize }
    var nd = 1usize
    if set == 0usize { nd = 4usize }
    if set == 1usize { nd = 2usize }
    let l = r % nl
    let k = (r / nl) % nk
    let j = (r / (nl * nk)) % nd
    let i = r / (nl * nk * nd)
    var mu = 0.0f64
    var delta = 1.0f64
    if set == 0usize {
        mu = f64(i) - 1.0f64
        if j == 0usize { delta = 1.0f64 }
        if j == 1usize { delta = 2.0f64 }
        if j == 2usize { delta = 5.0f64 }
        if j == 3usize { delta = 10.0f64 }
    }
    if set == 1usize {
        mu = f64(i)
        if j == 1usize { delta = 5.0f64 }
    }
    let xi = xi_of(small, k)
    let chi = chi_of(small, k)
    let alpha = (1.0f64 - xi * xi) / (delta * xi * math.sqrt[f64](xi * xi - chi * chi))
    let beta = alpha * chi / xi
    out[0usize] = mu
    out[1usize] = delta
    out[2usize] = round3(alpha)
    out[3usize] = round3(beta)
    var lam = 1.0f64
    if fam == 2usize { lam = 0.0f64 - 0.5f64 }
    if fam == 0usize { lam = lambda_of(small, l) }
    out[4usize] = lam
}

fn gig_chi_of(small: bool, j: usize) -> f64 {
    if small {
        if j == 0usize { ret 0.1f64 }
        if j == 1usize { ret 0.5f64 }
        if j == 2usize { ret 2.0f64 }
        if j == 3usize { ret 10.0f64 }
        ret 50.0f64
    }
    if j == 0usize { ret 0.1f64 }
    if j == 1usize { ret 0.2f64 }
    if j == 2usize { ret 0.5f64 }
    if j == 3usize { ret 1.0f64 }
    if j == 4usize { ret 2.0f64 }
    if j == 5usize { ret 5.0f64 }
    if j == 6usize { ret 10.0f64 }
    if j == 7usize { ret 20.0f64 }
    if j == 8usize { ret 50.0f64 }
    ret 100.0f64
}

fn gig_lambda_of(small: bool, i: usize) -> f64 {
    if small {
        if i == 0usize { ret 0.0f64 - 0.5f64 }
        if i == 1usize { ret 0.0f64 }
        if i == 2usize { ret 0.5f64 }
        if i == 3usize { ret 1.0f64 }
        ret 5.0f64
    }
    if i == 0usize { ret 0.0f64 - 2.0f64 }
    if i == 1usize { ret 0.0f64 - 1.0f64 }
    if i == 2usize { ret 0.0f64 - 0.5f64 }
    if i == 3usize { ret 0.0f64 }
    if i == 4usize { ret 0.1f64 }
    if i == 5usize { ret 0.2f64 }
    if i == 6usize { ret 0.5f64 }
    if i == 7usize { ret 1.0f64 }
    if i == 8usize { ret 2.0f64 }
    if i == 9usize { ret 5.0f64 }
    ret 10.0f64
}

// gigLargeParam (small = false: 1100 rows) and gigSmallParam (125 rows): chi, psi, lambda, lambda slowest and psi fastest
fn gig_param_row(small: bool, r: usize, out: []f64) {
    var n = 10usize
    if small { n = 5usize }
    let k = r % n
    let j = (r / n) % n
    let i = r / (n * n)
    out[0usize] = gig_chi_of(small, j)
    out[1usize] = gig_chi_of(small, k)
    out[2usize] = gig_lambda_of(small, i)
}
