// R stats::uniroot (the C routine R_zeroin2, Brent's method as R ports it) and rootSolve::uniroot.all (a 101-point scan for sign changes, each refined by uniroot at
// tolerance eps^0.2), on a fixed set of one-variable functions. The iterates are the same arithmetic as R's, so the root, the iteration count and the estimated precision agree.
//
// Not here: user functions, extendInt, the n and tol arguments beyond their defaults, and the other rootSolve solvers.

use e.math

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

// the test functions: 0 sin(3x) + x / 5, 1 x^3 - 2x - 5, 2 exp(x) - 3 - x / 2, 3 cos(x) - x, 4 (x - 1)(x - 2)(x + 1.5)
fn tf(id: usize, x: f64) -> f64 {
    if id == 0usize { ret math.sin[f64](3.0f64 * x) + x / 5.0f64 }
    if id == 1usize { ret x * x * x - 2.0f64 * x - 5.0f64 }
    if id == 2usize { ret math.exp[f64](x) - 3.0f64 - x / 2.0f64 }
    if id == 3usize { ret math.cos[f64](x) - x }
    ret (x - 1.0f64) * (x - 2.0f64) * (x + 1.5f64)
}

// R_zeroin2 on [ax, bx] with f(ax) = fa and f(bx) = fb: (root, iterations, estimated precision); the iteration count is -1 when maxit is reached
fn zeroin2(id: usize, ax: f64, bx: f64, fa0: f64, fb0: f64, tol: f64, maxit0: i64) -> (f64, i64, f64) {
    var a = ax
    var b = bx
    var c = a
    var fa = fa0
    var fb = fb0
    var fc = fa
    var maxit = maxit0 + 1i64
    if fa == 0.0f64 { ret (a, 0i64, 0.0f64) }
    if fb == 0.0f64 { ret (b, 0i64, 0.0f64) }
    while maxit > 0i64 {
        maxit -= 1i64
        let prev_step = b - a
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps() * math.abs[f64](b) + tol / 2.0f64
        var new_step = (c - b) / 2.0f64
        if math.abs[f64](new_step) <= tol_act || fb == 0.0f64 { ret (b, maxit0 - maxit, math.abs[f64](c - b)) }
        if math.abs[f64](prev_step) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = c - b
            var p = 0.0f64
            var q = 0.0f64
            if a == c {
                let t1 = fb / fa
                p = cb * t1
                q = 1.0f64 - t1
            } else {
                q = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                p = t2 * (cb * q * (q - t1) - (b - a) * (t1 - 1.0f64))
                q = (q - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if p > 0.0f64 { q = 0.0f64 - q } else { p = 0.0f64 - p }
            if p < (0.75f64 * cb * q - math.abs[f64](tol_act * q) / 2.0f64) && p < math.abs[f64](prev_step * q / 2.0f64) { new_step = p / q }
        }
        if math.abs[f64](new_step) < tol_act {
            if new_step > 0.0f64 { new_step = tol_act } else { new_step = 0.0f64 - tol_act }
        }
        a = b
        fa = fb
        b += new_step
        fb = tf(id, b)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret (b, -1i64, 0.0f64 - 1.0f64)
}

// uniroot(f, c(lo, hi), tol = tol)$root, $iter and $estim.prec; the interval must change sign
fn uniroot(id: usize, lo: f64, hi: f64, tol: f64) -> (f64, i64, f64) {
    let (r, it, pr) = zeroin2(id, lo, hi, tf(id, lo), tf(id, hi), tol, 1000i64)
    ret (r, it, pr)
}

// uniroot.all(f, c(lo, hi)) with n = 100 into out (at most cap roots): the grid points that are exact zeros, then each sign change refined by uniroot at tol eps^0.2; returns the count
fn uniroot_all(id: usize, lo: f64, hi: f64, out: []f64) -> usize {
    let n = 100usize
    let tol = math.pow[f64](eps(), 0.2f64)
    var cnt = 0usize
    var i = 0usize
    while i <= n {
        let x = grid_at(lo, hi, i, n)
        if tf(id, x) == 0.0f64 && cnt < out.len {
            out[cnt] = x
            cnt += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        let x0 = grid_at(lo, hi, i, n)
        let x1 = grid_at(lo, hi, i + 1usize, n)
        if tf(id, x0) * tf(id, x1) < 0.0f64 && cnt < out.len {
            let (r, it, pr) = uniroot(id, x0, x1, tol)
            let _ = it
            let _ = pr
            out[cnt] = r
            cnt += 1usize
        }
        i += 1usize
    }
    // R sorts the combined vector
    var a = 1usize
    while a < cnt {
        let t = out[a]
        var b = a
        while b > 0usize && out[b - 1usize] > t {
            out[b] = out[b - 1usize]
            b -= 1usize
        }
        out[b] = t
        a += 1usize
    }
    ret cnt
}

// seq(lo, hi, length.out = n + 1)[i + 1]: from + i * by with the last point set to hi, as R's seq.int does
fn grid_at(lo: f64, hi: f64, i: usize, n: usize) -> f64 {
    if i == n { ret hi }
    ret lo + f64(i) * ((hi - lo) / f64(n))
}
