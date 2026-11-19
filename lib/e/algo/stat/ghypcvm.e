// R GeneralizedHyperbolic hyperbCvMTest: the Cramer-von Mises statistic of data against a hyperbolic distribution (phyperb at the sorted data) and
// hyperbCvMTestPValue's interpolation in the package's table of critical values, including its behaviour for negative chi.

use e.algo.stat.ghyp as gh
use e.algo.stat.ghypcvm_tab as tb
use e.math
use e.mem

// Wsq = sum((phyperb(sort(x)) - (2 i - 1) / (2 n))^2) + 1 / (12 n); x must be sorted ascending
fn hyperb_wsq(a: *mem.Arena, x: []const f64, mu: f64, delta: f64, alpha: f64, beta: f64) -> f64 {
    let n = f64(x.len)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        let start = mem.mark(a)
        let z = gh.phyperb(a, x[i], mu, delta, alpha, beta)
        mem.reset(a, start)
        let d = z - (2.0f64 * f64(i + 1usize) - 1.0f64) / (2.0f64 * n)
        s += d * d
        i += 1usize
    }
    ret s + 1.0f64 / (12.0f64 * n)
}

fn all_eq(tg: f64, cur: f64) -> bool {
    let tol = 0.000000014901161193847656f64
    let xn = math.abs[f64](tg)
    let d = math.abs[f64](tg - cur)
    if xn > tol { ret d / xn <= tol }
    ret d <= tol
}

// hyperbCvMTestPValue(delta, alpha, beta, Wsq): the numeric p-value rounded to 3 digits in out[0] with code 0, or code 1 "> 0.25", 2 "0.25", 3 "< 0.01", 4 "0.01";
// out[1] the number of warnings
fn cvm_p_value(delta: f64, alpha: f64, beta: f64, wsq: f64, out: []f64) {
    let sq = math.sqrt[f64](1.0f64 + delta * math.sqrt[f64](alpha * alpha - beta * beta))
    var xi = 1.0f64 / sq
    var chi = beta / (alpha * sq)
    var xi_list: [12]f64 = zero
    xi_list[0usize] = 0.99f64
    xi_list[1usize] = 0.95f64
    var k = 0usize
    while k < 9usize {
        xi_list[2usize + k] = 0.9f64 - 0.1f64 * f64(k)
        k += 1usize
    }
    xi_list[11usize] = 0.0f64 / 0.0f64
    var alpha_list: [5]f64 = zero
    alpha_list[0usize] = 0.25f64
    alpha_list[1usize] = 0.1f64
    alpha_list[2usize] = 0.05f64
    alpha_list[3usize] = 0.025f64
    alpha_list[4usize] = 0.01f64
    var chi_list: [5]f64 = zero
    k = 0usize
    while k < 5usize {
        chi_list[k] = 0.2f64 * f64(k)
        k += 1usize
    }
    var warn1 = false
    var warn2 = false
    // wt: the 55 values of the working vector; as the table is a matrix until a column is picked, a table never reduced to a column reads as its first column
    var wt: [55]f64 = zero
    var vec = false
    k = 0usize
    while k < 55usize {
        wt[k] = tb.wsq_tab(k)
        k += 1usize
    }
    let tol = 2.220446049250313e-16f64
    if chi > 0.8f64 {
        chi = 0.79999f64
        warn2 = true
    }
    let ac = math.abs[f64](chi)
    var j = 0usize
    while j < 4usize {
        if chi_list[j] < ac && (chi_list[j + 1usize] - ac) > tol {
            var r = 0usize
            while r < 55usize {
                wt[r] = tb.wsq_tab(j * 55usize + r) + ((chi - chi_list[j]) / (chi_list[j + 1usize] - chi_list[j])) * (tb.wsq_tab((j + 1usize) * 55usize + r) - tb.wsq_tab(j * 55usize + r))
                r += 1usize
            }
            vec = true
        }
        j += 1usize
    }
    j = 0usize
    while j < 5usize {
        if all_eq(chi_list[j], chi) {
            var r = 0usize
            while r < 55usize {
                wt[r] = tb.wsq_tab(j * 55usize + r)
                r += 1usize
            }
            vec = true
        }
        j += 1usize
    }
    if xi < 0.9f64 && ac > 0.6f64 { xi_list[3usize] = xi_list[3usize] + 0.01f64 }
    if xi < 0.7f64 && ac > 0.4f64 { xi_list[5usize] = xi_list[5usize] + 0.01f64 }
    if xi < 0.5f64 && ac > 0.2f64 { xi_list[7usize] = xi_list[7usize] + 0.01f64 }
    if xi < 0.3f64 && ac > 0.0f64 { xi_list[9usize] = xi_list[9usize] + 0.01f64 }
    var t: [10]f64 = zero
    var exact_xi = false
    var xi_up = 0.0f64
    var xi_lo = 0.0f64
    var i = 0usize
    var have = false
    while i < 11usize {
        if xi > 0.99f64 {
            xi = 0.99f64
            warn1 = true
        }
        if xi < 0.1f64 {
            xi = 0.1f64
            warn1 = true
        }
        if all_eq(xi_list[i], xi) && !have {
            exact_xi = true
            k = 0usize
            while k < 5usize {
                t[k] = wt[5usize * i + k]
                k += 1usize
            }
            have = true
        }
        if xi < xi_list[i] && xi - xi_list[i + 1usize] > tol && !have {
            xi_up = xi_list[i]
            xi_lo = xi_list[i + 1usize]
            k = 0usize
            while k < 10usize {
                t[k] = wt[5usize * i + k]
                k += 1usize
            }
            have = true
        }
        i += 1usize
    }
    var tt: [5]f64 = zero
    k = 0usize
    while k < 5usize {
        tt[k] = t[k]
        if !exact_xi { tt[k] = t[k] + ((xi - xi_lo) / (xi_up - xi_lo)) * (t[k + 5usize] - t[k]) }
        k += 1usize
    }
    var code = 0.0f64
    var pv = 0.0f64
    if tt[0usize] > wsq { code = 1.0f64 }
    if tt[0usize] == wsq { code = 2.0f64 }
    if tt[4usize] < wsq { code = 3.0f64 }
    if tt[4usize] == wsq { code = 4.0f64 }
    k = 0usize
    while k < 4usize {
        if wsq >= tt[k] && wsq < tt[k + 1usize] {
            pv = alpha_list[k] + ((wsq - tt[k]) / (tt[k + 1usize] - tt[k])) * (alpha_list[k + 1usize] - alpha_list[k])
            code = 0.0f64
            pv = math.floor[f64](pv * 1000.0f64 + 0.5f64) / 1000.0f64
        }
        k += 1usize
    }
    out[0usize] = pv
    out[1usize] = code
    var wn = 0.0f64
    if warn1 { wn += 1.0f64 }
    if warn2 { wn += 1.0f64 }
    out[2usize] = wn
}
