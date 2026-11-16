// R copula: the bivariate Archimedean copulas Clayton, Frank, Gumbel, AMH and Joe: density (dCopula), distribution function (pCopula) and Kendall's tau.
//
// Not here: elliptical and extreme-value copulas, higher dimensions, Spearman's rho, fitting (fitCopula), sampling, goodness of fit, copula-based multivariate distributions.

use e.math

// family 0 Clayton, 1 Frank, 2 Gumbel, 3 AMH, 4 Joe
fn pcop(fam: usize, th: f64, u: f64, v: f64) -> f64 {
    if fam == 0usize { ret math.pow[f64](math.pow[f64](u, 0.0f64 - th) + math.pow[f64](v, 0.0f64 - th) - 1.0f64, 0.0f64 - 1.0f64 / th) }
    if fam == 1usize {
        let a = math.exp[f64](0.0f64 - th * u) - 1.0f64
        let b = math.exp[f64](0.0f64 - th * v) - 1.0f64
        let c = math.exp[f64](0.0f64 - th) - 1.0f64
        ret 0.0f64 - math.log[f64](1.0f64 + a * b / c) / th
    }
    if fam == 2usize {
        let s = math.pow[f64](0.0f64 - math.log[f64](u), th) + math.pow[f64](0.0f64 - math.log[f64](v), th)
        ret math.exp[f64](0.0f64 - math.pow[f64](s, 1.0f64 / th))
    }
    if fam == 3usize { ret u * v / (1.0f64 - th * (1.0f64 - u) * (1.0f64 - v)) }
    let a = math.pow[f64](1.0f64 - u, th)
    let b = math.pow[f64](1.0f64 - v, th)
    ret 1.0f64 - math.pow[f64](a + b - a * b, 1.0f64 / th)
}

fn dcop(fam: usize, th: f64, u: f64, v: f64) -> f64 {
    if fam == 0usize {
        let s = math.pow[f64](u, 0.0f64 - th) + math.pow[f64](v, 0.0f64 - th) - 1.0f64
        ret (1.0f64 + th) * math.pow[f64](u * v, 0.0f64 - 1.0f64 - th) * math.pow[f64](s, 0.0f64 - 2.0f64 - 1.0f64 / th)
    }
    if fam == 1usize {
        let eu = math.exp[f64](0.0f64 - th * u)
        let ev = math.exp[f64](0.0f64 - th * v)
        let e1 = math.exp[f64](0.0f64 - th)
        let den = (1.0f64 - e1) - (1.0f64 - eu) * (1.0f64 - ev)
        ret th * (1.0f64 - e1) * eu * ev / (den * den)
    }
    if fam == 2usize {
        let lu = 0.0f64 - math.log[f64](u)
        let lv = 0.0f64 - math.log[f64](v)
        let aa = math.pow[f64](lu, th) + math.pow[f64](lv, th)
        let c = pcop(2usize, th, u, v)
        ret c / (u * v) * math.pow[f64](lu * lv, th - 1.0f64) * math.pow[f64](aa, 2.0f64 / th - 2.0f64) * (1.0f64 + (th - 1.0f64) / math.pow[f64](aa, 1.0f64 / th))
    }
    if fam == 3usize {
        let d = 1.0f64 - th * (1.0f64 - u) * (1.0f64 - v)
        ret (1.0f64 + th * ((1.0f64 + u) * (1.0f64 + v) - 3.0f64) + th * th * (1.0f64 - u) * (1.0f64 - v)) / (d * d * d)
    }
    let a = math.pow[f64](1.0f64 - u, th)
    let b = math.pow[f64](1.0f64 - v, th)
    let s = a + b - a * b
    ret math.pow[f64](1.0f64 - u, th - 1.0f64) * math.pow[f64](1.0f64 - v, th - 1.0f64) * math.pow[f64](s, 1.0f64 / th - 2.0f64) * (th - 1.0f64 + s)
}

// Debye function D1(x) = (1/x) integral_0^x t / (e^t - 1) dt by 64-point composite Gauss-Legendre
fn debye1(x: f64) -> f64 {
    let nodes = 5usize
    var xs = 0.0f64 - 0.9061798459386640f64
    var s = 0.0f64
    let gx0 = 0.0f64 - 0.9061798459386640f64
    let gx1 = 0.0f64 - 0.5384693101056831f64
    let gw0 = 0.2369268850561891f64
    let gw1 = 0.4786286704993665f64
    let gw2 = 0.5688888888888889f64
    let panels = 24usize
    var p = 0usize
    while p < panels {
        let lo = x * f64(p) / f64(panels)
        let hi = x * f64(p + 1usize) / f64(panels)
        let mid = (lo + hi) / 2.0f64
        let half = (hi - lo) / 2.0f64
        var k = 0usize
        while k < nodes {
            var xk = 0.0f64
            var wk = gw2
            if k == 0usize {
                xk = gx0
                wk = gw0
            }
            if k == 1usize {
                xk = gx1
                wk = gw1
            }
            if k == 3usize {
                xk = 0.0f64 - gx1
                wk = gw1
            }
            if k == 4usize {
                xk = 0.0f64 - gx0
                wk = gw0
            }
            let t = mid + half * xk
            s += wk * half * t / (math.exp[f64](t) - 1.0f64)
            k += 1usize
        }
        p += 1usize
    }
    xs = 0.0f64
    ret s / x
}

fn ktau(fam: usize, th: f64) -> f64 {
    if fam == 0usize { ret th / (th + 2.0f64) }
    if fam == 1usize { ret 1.0f64 - 4.0f64 / th * (1.0f64 - debye1(th)) }
    if fam == 2usize { ret 1.0f64 - 1.0f64 / th }
    if fam == 3usize { ret 1.0f64 - 2.0f64 * (th + (1.0f64 - th) * (1.0f64 - th) * math.log[f64](1.0f64 - th)) / (3.0f64 * th * th) }
    // Joe: 1 + 4/th^2 * integral_0^1 u log(u) (1 - u)^(2 (1 - th)/th)... evaluated by the series 1 - 4 sum_{k>=1} 1/(k (th k + 2) (th (k - 1) + 2)) when th > 1
    var s = 0.0f64
    var k = 1usize
    while k <= 200000usize {
        let kf = f64(k)
        s += 1.0f64 / (kf * (th * kf + 2.0f64) * (th * (kf - 1.0f64) + 2.0f64))
        k += 1usize
    }
    ret 1.0f64 - 4.0f64 * s
}
