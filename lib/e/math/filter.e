// State estimation over `f64` vectors and row-major matrices in caller
// storage: the linear Kalman filter (predict and update), the extended form
// with caller-supplied models and Jacobians (`ekf` runs one whole cycle), the
// scaled unscented form with sigma points from a Cholesky factor (`ukf` takes
// alpha, beta and kappa; `ukf_step` fixes them), a bootstrap particle filter
// with systematic resampling (`particle` takes the resampling threshold), and
// the attitude filters over a unit quaternion (complementary, Madgwick, Mahony).
//
// A state of `n` entries has an `n x n` covariance; a measurement of `m`
// entries has an `m x n` model and an `m x m` noise. Scratch sizes are stated
// per declaration; every call answers `TooSmall` for short storage and
// `Singular` when an innovation covariance cannot be inverted.

use e.algo.rand
use e.math

error TooSmall
error Singular

// C = A (r x k) times B (k x c).
fn mat_mul(a: []const f64, b: []const f64, c: []f64, r: usize, k: usize, cols: usize) {
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < cols {
            var sum = 0.0f64
            var t = 0usize
            while t < k {
                sum += a[i * k + t] * b[t * cols + j]
                t += 1usize
            }
            c[i * cols + j] = sum
            j += 1usize
        }
        i += 1usize
    }
}

fn mat_transpose(a: []const f64, out: []f64, r: usize, c: usize) {
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            out[j * r + i] = a[i * c + j]
            j += 1usize
        }
        i += 1usize
    }
}

// Gauss-Jordan inverse of an `n x n` matrix into `out`; `scratch.len >= n * n`.
fn mat_inverse(a: []const f64, out: []f64, n: usize, scratch: []f64) -> err {
    if scratch.len < n * n { ret TooSmall }
    var work = scratch[..n * n]
    var i = 0usize
    while i < n * n {
        work[i] = a[i]
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i * n + i] = 1.0f64
        i += 1usize
    }
    var col = 0usize
    while col < n {
        // Partial pivot.
        var pivot = col
        var r = col + 1usize
        while r < n {
            if math.abs[f64](work[r * n + col]) > math.abs[f64](work[pivot * n + col]) { pivot = r }
            r += 1usize
        }
        if math.abs[f64](work[pivot * n + col]) < 1.0e-300f64 { ret Singular }
        if pivot != col {
            var j = 0usize
            while j < n {
                let t = work[col * n + j]
                work[col * n + j] = work[pivot * n + j]
                work[pivot * n + j] = t
                let u = out[col * n + j]
                out[col * n + j] = out[pivot * n + j]
                out[pivot * n + j] = u
                j += 1usize
            }
        }
        let scale = 1.0f64 / work[col * n + col]
        var j = 0usize
        while j < n {
            work[col * n + j] = work[col * n + j] * scale
            out[col * n + j] = out[col * n + j] * scale
            j += 1usize
        }
        r = 0usize
        while r < n {
            if r != col {
                let factor = work[r * n + col]
                if factor != 0.0f64 {
                    j = 0usize
                    while j < n {
                        work[r * n + j] -= factor * work[col * n + j]
                        out[r * n + j] -= factor * out[col * n + j]
                        j += 1usize
                    }
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    ret ok
}

// Kalman predict: `x = F x`, `P = F P F' + Q`; `scratch.len >= 2 * n * n + n`.
fn kalman_predict(x: []f64, p: []f64, f: []const f64, q: []const f64, n: usize, scratch: []f64) -> err {
    if x.len < n || p.len < n * n || f.len < n * n || q.len < n * n || scratch.len < 2usize * n * n + n { ret TooSmall }
    var t1 = scratch[..n * n]
    var t2 = scratch[n * n..2usize * n * n]
    var nx = scratch[2usize * n * n..2usize * n * n + n]
    mat_mul(f, x, nx, n, n, 1usize)
    var i = 0usize
    while i < n {
        x[i] = nx[i]
        i += 1usize
    }
    mat_mul(f, p, t1, n, n, n)
    mat_transpose(f, t2, n, n)
    mat_mul(t1, t2, p, n, n, n)
    i = 0usize
    while i < n * n {
        p[i] += q[i]
        i += 1usize
    }
    ret ok
}

// Kalman update with measurement `z` under `H` (m x n) and noise `R` (m x m):
// `scratch.len >= 3 * n * n + 4 * m * m + 3 * n * m + m` (generous).
fn kalman_update(x: []f64, p: []f64, h: []const f64, r: []const f64, z: []const f64, n: usize, m: usize, scratch: []f64) -> err {
    let need = 3usize * n * n + 4usize * m * m + 3usize * n * m + m
    if x.len < n || p.len < n * n || h.len < m * n || r.len < m * m || z.len < m || scratch.len < need { ret TooSmall }
    var at = 0usize
    var ht = scratch[at..at + n * m]
    at += n * m
    var pht = scratch[at..at + n * m]
    at += n * m
    var s = scratch[at..at + m * m]
    at += m * m
    var s_inv = scratch[at..at + m * m]
    at += m * m
    var inv_scratch = scratch[at..at + m * m]
    at += m * m
    var k = scratch[at..at + n * m]
    at += n * m
    var y = scratch[at..at + m]
    at += m
    var kh = scratch[at..at + n * n]
    at += n * n
    var np = scratch[at..at + n * n]
    at += n * n
    mat_transpose(h, ht, m, n)
    mat_mul(p, ht, pht, n, n, m)
    mat_mul(h, pht, s, m, n, m)
    var i = 0usize
    while i < m * m {
        s[i] += r[i]
        i += 1usize
    }
    let inverse_error = mat_inverse(s, s_inv, m, inv_scratch)
    if inverse_error != ok { ret inverse_error }
    mat_mul(pht, s_inv, k, n, m, m)
    // Innovation y = z - H x, then x += K y.
    i = 0usize
    while i < m {
        var hx = 0.0f64
        var j = 0usize
        while j < n {
            hx += h[i * n + j] * x[j]
            j += 1usize
        }
        y[i] = z[i] - hx
        i += 1usize
    }
    i = 0usize
    while i < n {
        var delta = 0.0f64
        var j = 0usize
        while j < m {
            delta += k[i * m + j] * y[j]
            j += 1usize
        }
        x[i] += delta
        i += 1usize
    }
    // P = (I - K H) P.
    mat_mul(k, h, kh, n, m, n)
    i = 0usize
    while i < n * n {
        kh[i] = 0.0f64 - kh[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        kh[i * n + i] += 1.0f64
        i += 1usize
    }
    mat_mul(kh, p, np, n, n, n)
    i = 0usize
    while i < n * n {
        p[i] = np[i]
        i += 1usize
    }
    ret ok
}

// Extended Kalman predict: `transition(ctx, x, next)` moves the state and
// `jacobian(ctx, x, F)` fills the `n x n` linearisation at the old state;
// `scratch.len >= 3 * n * n + n`.
fn ekf_predict[Ctx: type](ctx: *Ctx, transition: fn(*Ctx, []const f64, []f64), jacobian: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, q: []const f64, n: usize, scratch: []f64) -> err {
    if scratch.len < 3usize * n * n + n { ret TooSmall }
    var f = scratch[..n * n]
    jacobian(ctx, x, f)
    var next = scratch[n * n..n * n + n]
    transition(ctx, x, next)
    var rest = scratch[n * n + n..3usize * n * n + n]
    // Reuse the linear covariance step with the Jacobian, then overwrite the state.
    var t1 = rest[..n * n]
    var t2 = rest[n * n..2usize * n * n]
    mat_mul(f, p, t1, n, n, n)
    mat_transpose(f, t2, n, n)
    mat_mul(t1, t2, p, n, n, n)
    var i = 0usize
    while i < n * n {
        p[i] += q[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        x[i] = next[i]
        i += 1usize
    }
    ret ok
}

// Extended Kalman update: `observe(ctx, x, predicted)` predicts the `m`
// measurements and `jacobian(ctx, x, H)` fills `m x n`; scratch as
// `kalman_update` plus `m * n + m`.
fn ekf_update[Ctx: type](ctx: *Ctx, observe: fn(*Ctx, []const f64, []f64), jacobian: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, r: []const f64, z: []const f64, n: usize, m: usize, scratch: []f64) -> err {
    let extra = m * n + m
    if scratch.len < extra { ret TooSmall }
    var h = scratch[..m * n]
    var predicted = scratch[m * n..m * n + m]
    jacobian(ctx, x, h)
    observe(ctx, x, predicted)
    // Linearised innovation: z - h(x) = z - (H x) + (H x - h(x)); fold the
    // nonlinearity into a pseudo-measurement so the linear update applies.
    var i = 0usize
    while i < m {
        var hx = 0.0f64
        var j = 0usize
        while j < n {
            hx += h[i * n + j] * x[j]
            j += 1usize
        }
        predicted[i] = z[i] - predicted[i] + hx
        i += 1usize
    }
    ret kalman_update(x, p, h, r, predicted, n, m, scratch[extra..])
}

// The extended Kalman filter cycle: `ekf_predict` under `transition` and
// `transition_jacobian`, then `ekf_update` of `z` under `observe` and
// `observe_jacobian`; the scratch is reused, so its length is the larger of
// the two requirements.
fn ekf[Ctx: type](ctx: *Ctx, transition: fn(*Ctx, []const f64, []f64), transition_jacobian: fn(*Ctx, []const f64, []f64), observe: fn(*Ctx, []const f64, []f64), observe_jacobian: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, q: []const f64, r: []const f64, z: []const f64, n: usize, m: usize, scratch: []f64) -> err {
    let e = ekf_predict[Ctx](ctx, transition, transition_jacobian, x, p, q, n, scratch)
    if e != ok { ret e }
    ret ekf_update[Ctx](ctx, observe, observe_jacobian, x, p, r, z, n, m, scratch)
}

// Unscented Kalman step (predict then update) with the symmetric sigma set
// (`2n + 1` points, `kappa = 3 - n` weighting, scaled by `alpha = 1`):
// `transition(ctx, x, next)` and `observe(ctx, x, z_predicted)` are the
// nonlinear models. `scratch.len >= (2n + 1) * (n + m) + 4 * n * n + 3 * m * m +
// 2 * n * m + 2 * n + 2 * m`.
fn ukf_step[Ctx: type](ctx: *Ctx, transition: fn(*Ctx, []const f64, []f64), observe: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, q: []const f64, r: []const f64, z: []const f64, n: usize, m: usize, scratch: []f64) -> err {
    ret ukf[Ctx](ctx, transition, observe, x, p, q, r, z, n, m, 1.0f64, 0.0f64, 3.0f64 - f64(n), scratch)
}

// The scaled unscented Kalman filter cycle (predict then update) of Wan and
// van der Merwe: `lambda = alpha^2 (n + kappa) - n`, mean weights
// `lambda / (n + lambda)` and `1 / 2(n + lambda)`, the centre covariance
// weight raised by `1 - alpha^2 + beta` (`beta = 2` is optimal for a
// Gaussian). Models and scratch as `ukf_step`, which is `alpha = 1`,
// `beta = 0`, `kappa = 3 - n`.
fn ukf[Ctx: type](ctx: *Ctx, transition: fn(*Ctx, []const f64, []f64), observe: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, q: []const f64, r: []const f64, z: []const f64, n: usize, m: usize, alpha: f64, beta: f64, kappa: f64, scratch: []f64) -> err {
    let points = 2usize * n + 1usize
    let need = points * (n + m) + 4usize * n * n + 3usize * m * m + 2usize * n * m + 2usize * n + 2usize * m
    if scratch.len < need { ret TooSmall }
    var at = 0usize
    var sigma = scratch[at..at + points * n]
    at += points * n
    var zsig = scratch[at..at + points * m]
    at += points * m
    var chol = scratch[at..at + n * n]
    at += n * n
    var pxz = scratch[at..at + n * m]
    at += n * m
    var pzz = scratch[at..at + m * m]
    at += m * m
    var pzz_inv = scratch[at..at + m * m]
    at += m * m
    var inv_scratch = scratch[at..at + m * m]
    at += m * m
    var gain = scratch[at..at + n * m]
    at += n * m
    var xm = scratch[at..at + n]
    at += n
    var zm = scratch[at..at + m]
    at += m
    var innovation = scratch[at..at + m]
    at += m
    var dx = scratch[at..at + n]
    at += n
    var pn = scratch[at..at + n * n]
    at += n * n
    let lambda = alpha * alpha * (f64(n) + kappa) - f64(n)
    let spread = math.sqrt[f64](f64(n) + lambda)
    let w0 = lambda / (f64(n) + lambda)
    let w0c = w0 + (1.0f64 - alpha * alpha + beta)
    let wi = 1.0f64 / (2.0f64 * (f64(n) + lambda))
    // Cholesky of P (lower), scaled sigma points around x.
    let chol_error = cholesky(p, n, chol)
    if chol_error != ok { ret chol_error }
    var i = 0usize
    while i < n {
        sigma[i] = x[i]
        i += 1usize
    }
    var k = 0usize
    while k < n {
        i = 0usize
        while i < n {
            sigma[(1usize + k) * n + i] = x[i] + spread * chol[i * n + k]
            sigma[(1usize + n + k) * n + i] = x[i] - spread * chol[i * n + k]
            i += 1usize
        }
        k += 1usize
    }
    // Propagate each point through the transition, then the observation.
    var s = 0usize
    while s < points {
        transition(ctx, sigma[s * n..(s + 1usize) * n], dx)
        i = 0usize
        while i < n {
            sigma[s * n + i] = dx[i]
            i += 1usize
        }
        observe(ctx, sigma[s * n..(s + 1usize) * n], zsig[s * m..(s + 1usize) * m])
        s += 1usize
    }
    // Weighted means.
    i = 0usize
    while i < n {
        xm[i] = w0 * sigma[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        zm[i] = w0 * zsig[i]
        i += 1usize
    }
    s = 1usize
    while s < points {
        i = 0usize
        while i < n {
            xm[i] += wi * sigma[s * n + i]
            i += 1usize
        }
        i = 0usize
        while i < m {
            zm[i] += wi * zsig[s * m + i]
            i += 1usize
        }
        s += 1usize
    }
    // Covariances: P = Q + sum w (s - xm)(s - xm)', Pzz = R + ..., Pxz = ...
    i = 0usize
    while i < n * n {
        pn[i] = q[i]
        i += 1usize
    }
    i = 0usize
    while i < m * m {
        pzz[i] = r[i]
        i += 1usize
    }
    i = 0usize
    while i < n * m {
        pxz[i] = 0.0f64
        i += 1usize
    }
    s = 0usize
    while s < points {
        var w = wi
        if s == 0usize { w = w0c }
        var a = 0usize
        while a < n {
            let da = sigma[s * n + a] - xm[a]
            var b = 0usize
            while b < n {
                pn[a * n + b] += w * da * (sigma[s * n + b] - xm[b])
                b += 1usize
            }
            b = 0usize
            while b < m {
                pxz[a * m + b] += w * da * (zsig[s * m + b] - zm[b])
                b += 1usize
            }
            a += 1usize
        }
        a = 0usize
        while a < m {
            var b = 0usize
            while b < m {
                pzz[a * m + b] += w * (zsig[s * m + a] - zm[a]) * (zsig[s * m + b] - zm[b])
                b += 1usize
            }
            a += 1usize
        }
        s += 1usize
    }
    let inverse_error = mat_inverse(pzz, pzz_inv, m, inv_scratch)
    if inverse_error != ok { ret inverse_error }
    mat_mul(pxz, pzz_inv, gain, n, m, m)
    i = 0usize
    while i < m {
        innovation[i] = z[i] - zm[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var delta = 0.0f64
        var j = 0usize
        while j < m {
            delta += gain[i * m + j] * innovation[j]
            j += 1usize
        }
        x[i] = xm[i] + delta
        i += 1usize
    }
    // P = Pn - K Pzz K'.
    var a = 0usize
    while a < n {
        var b = 0usize
        while b < n {
            var sum = 0.0f64
            var c = 0usize
            while c < m {
                var kp = 0.0f64
                var d = 0usize
                while d < m {
                    kp += gain[a * m + d] * pzz[d * m + c]
                    d += 1usize
                }
                sum += kp * gain[b * m + c]
                c += 1usize
            }
            p[a * n + b] = pn[a * n + b] - sum
            b += 1usize
        }
        a += 1usize
    }
    ret ok
}

// The lower Cholesky factor of a symmetric positive-definite matrix.
fn cholesky(p: []const f64, n: usize, out: []f64) -> err {
    var i = 0usize
    while i < n * n {
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var sum = p[i * n + j]
            var k = 0usize
            while k < j {
                sum -= out[i * n + k] * out[j * n + k]
                k += 1usize
            }
            if i == j {
                if sum <= 0.0f64 { ret Singular }
                out[i * n + i] = math.sqrt[f64](sum)
            } else {
                out[i * n + j] = sum / out[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// A bootstrap particle filter step over `count` particles of `n` entries in
// `particles` (row-major) and `weights`: `propagate(ctx, r, particle)` moves a
// particle with process noise, `likelihood(ctx, particle, z)` weighs it; the
// weights are normalised and the set resampled systematically when the
// effective sample size drops below `count / 2`. `scratch.len >= count * (n + 1)`.
fn particle_step[Ctx: type](ctx: *Ctx, r: *rand.Pcg64, propagate: fn(*Ctx, *rand.Pcg64, []f64), likelihood: fn(*Ctx, []const f64, []const f64) -> f64, particles: []f64, weights: []f64, count: usize, n: usize, z: []const f64, scratch: []f64) -> err {
    ret particle[Ctx](ctx, r, propagate, likelihood, particles, weights, count, n, z, 0.5f64, scratch)
}

// The particle filter cycle with a chosen resampling rule: as `particle_step`,
// but the set is resampled (systematically, one draw from `r`) when the
// effective sample size `1 / sum w^2` drops below `resample_threshold * count`
// (`0` never resamples, `1` always does).
fn particle[Ctx: type](ctx: *Ctx, r: *rand.Pcg64, propagate: fn(*Ctx, *rand.Pcg64, []f64), likelihood: fn(*Ctx, []const f64, []const f64) -> f64, particles: []f64, weights: []f64, count: usize, n: usize, z: []const f64, resample_threshold: f64, scratch: []f64) -> err {
    if particles.len < count * n || weights.len < count || scratch.len < count * (n + 1usize) { ret TooSmall }
    var total = 0.0f64
    var i = 0usize
    while i < count {
        propagate(ctx, r, particles[i * n..(i + 1usize) * n])
        weights[i] = weights[i] * likelihood(ctx, particles[i * n..(i + 1usize) * n], z)
        total += weights[i]
        i += 1usize
    }
    if total <= 0.0f64 {
        i = 0usize
        while i < count {
            weights[i] = 1.0f64 / f64(count)
            i += 1usize
        }
        ret ok
    }
    var sum_squares = 0.0f64
    i = 0usize
    while i < count {
        weights[i] = weights[i] / total
        sum_squares += weights[i] * weights[i]
        i += 1usize
    }
    if 1.0f64 / sum_squares >= resample_threshold * f64(count) { ret ok }
    // Systematic resampling into scratch, then copy back.
    var copy = scratch[..count * n]
    var cumulative = scratch[count * n..count * (n + 1usize)]
    var acc = 0.0f64
    i = 0usize
    while i < count {
        acc += weights[i]
        cumulative[i] = acc
        i += 1usize
    }
    let start = rand.pcg64_f64(r) / f64(count)
    var source = 0usize
    i = 0usize
    while i < count {
        let u = start + f64(i) / f64(count)
        while source + 1usize < count && cumulative[source] < u { source += 1usize }
        var k = 0usize
        while k < n {
            copy[i * n + k] = particles[source * n + k]
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < count * n {
        particles[i] = copy[i]
        i += 1usize
    }
    i = 0usize
    while i < count {
        weights[i] = 1.0f64 / f64(count)
        i += 1usize
    }
    ret ok
}

// The weighted mean of the particle set into `out`.
fn particle_mean(particles: []const f64, weights: []const f64, count: usize, n: usize, out: []f64) -> err {
    if out.len < n || particles.len < count * n || weights.len < count { ret TooSmall }
    var k = 0usize
    while k < n {
        out[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < count {
        k = 0usize
        while k < n {
            out[k] += weights[i] * particles[i * n + k]
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

// A complementary filter for one angle: the gyro-integrated estimate blended
// with the accelerometer's angle by `alpha` (near 1 trusts the gyro).
fn complementary(angle: f64, rate: f64, accelerometer_angle: f64, dt: f64, alpha: f64) -> f64 {
    ret alpha * (angle + rate * dt) + (1.0f64 - alpha) * accelerometer_angle
}

// Normalises a quaternion `w, x, y, z` in place.
fn quaternion_normalize(q: []f64) {
    let norm = math.sqrt[f64](q[0usize] * q[0usize] + q[1usize] * q[1usize] + q[2usize] * q[2usize] + q[3usize] * q[3usize])
    if norm == 0.0f64 { ret }
    var i = 0usize
    while i < 4usize {
        q[i] = q[i] / norm
        i += 1usize
    }
}

// Madgwick's IMU filter (gyro in rad/s, accelerometer in any unit) over the
// quaternion `q` (`w, x, y, z`, earth-to-sensor) with gain `beta`.
fn madgwick(q: []f64, gx: f64, gy: f64, gz: f64, ax: f64, ay: f64, az: f64, dt: f64, beta: f64) -> err {
    if q.len < 4usize { ret TooSmall }
    let q0 = q[0usize]
    let q1 = q[1usize]
    let q2 = q[2usize]
    let q3 = q[3usize]
    var dq0 = 0.5f64 * (0.0f64 - q1 * gx - q2 * gy - q3 * gz)
    var dq1 = 0.5f64 * (q0 * gx + q2 * gz - q3 * gy)
    var dq2 = 0.5f64 * (q0 * gy - q1 * gz + q3 * gx)
    var dq3 = 0.5f64 * (q0 * gz + q1 * gy - q2 * gx)
    let norm = math.sqrt[f64](ax * ax + ay * ay + az * az)
    if norm > 0.0f64 {
        let nx = ax / norm
        let ny = ay / norm
        let nz = az / norm
        // Gradient of the objective f = R'(q) g - a.
        let f1 = 2.0f64 * (q1 * q3 - q0 * q2) - nx
        let f2 = 2.0f64 * (q0 * q1 + q2 * q3) - ny
        let f3 = 2.0f64 * (0.5f64 - q1 * q1 - q2 * q2) - nz
        var s0 = 0.0f64 - 2.0f64 * q2 * f1 + 2.0f64 * q1 * f2
        var s1 = 2.0f64 * q3 * f1 + 2.0f64 * q0 * f2 - 4.0f64 * q1 * f3
        var s2 = 0.0f64 - 2.0f64 * q0 * f1 + 2.0f64 * q3 * f2 - 4.0f64 * q2 * f3
        var s3 = 2.0f64 * q1 * f1 + 2.0f64 * q2 * f2
        let s_norm = math.sqrt[f64](s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3)
        if s_norm > 0.0f64 {
            dq0 -= beta * s0 / s_norm
            dq1 -= beta * s1 / s_norm
            dq2 -= beta * s2 / s_norm
            dq3 -= beta * s3 / s_norm
        }
    }
    q[0usize] = q0 + dq0 * dt
    q[1usize] = q1 + dq1 * dt
    q[2usize] = q2 + dq2 * dt
    q[3usize] = q3 + dq3 * dt
    quaternion_normalize(q)
    ret ok
}

// Mahony's IMU filter with proportional gain `kp` and integral gain `ki`;
// `integral` holds the three integrated error terms between calls.
fn mahony(q: []f64, integral: []f64, gx: f64, gy: f64, gz: f64, ax: f64, ay: f64, az: f64, dt: f64, kp: f64, ki: f64) -> err {
    if q.len < 4usize || integral.len < 3usize { ret TooSmall }
    var wx = gx
    var wy = gy
    var wz = gz
    let norm = math.sqrt[f64](ax * ax + ay * ay + az * az)
    if norm > 0.0f64 {
        let nx = ax / norm
        let ny = ay / norm
        let nz = az / norm
        // Estimated gravity direction from the quaternion.
        let vx = 2.0f64 * (q[1usize] * q[3usize] - q[0usize] * q[2usize])
        let vy = 2.0f64 * (q[0usize] * q[1usize] + q[2usize] * q[3usize])
        let vz = q[0usize] * q[0usize] - q[1usize] * q[1usize] - q[2usize] * q[2usize] + q[3usize] * q[3usize]
        let ex = ny * vz - nz * vy
        let ey = nz * vx - nx * vz
        let ez = nx * vy - ny * vx
        integral[0usize] += ki * ex * dt
        integral[1usize] += ki * ey * dt
        integral[2usize] += ki * ez * dt
        wx += kp * ex + integral[0usize]
        wy += kp * ey + integral[1usize]
        wz += kp * ez + integral[2usize]
    }
    let q0 = q[0usize]
    let q1 = q[1usize]
    let q2 = q[2usize]
    let q3 = q[3usize]
    q[0usize] = q0 + 0.5f64 * dt * (0.0f64 - q1 * wx - q2 * wy - q3 * wz)
    q[1usize] = q1 + 0.5f64 * dt * (q0 * wx + q2 * wz - q3 * wy)
    q[2usize] = q2 + 0.5f64 * dt * (q0 * wy - q1 * wz + q3 * wx)
    q[3usize] = q3 + 0.5f64 * dt * (q0 * wz + q1 * wy - q2 * wx)
    quaternion_normalize(q)
    ret ok
}

// Roll, pitch and yaw (radians) of a `w, x, y, z` quaternion.
fn quaternion_to_euler(q: []const f64) -> (f64, f64, f64) {
    let w = q[0usize]
    let x = q[1usize]
    let y = q[2usize]
    let z = q[3usize]
    let roll = math.atan2[f64](2.0f64 * (w * x + y * z), 1.0f64 - 2.0f64 * (x * x + y * y))
    var sinp = 2.0f64 * (w * y - z * x)
    if sinp > 1.0f64 { sinp = 1.0f64 }
    if sinp < 0.0f64 - 1.0f64 { sinp = 0.0f64 - 1.0f64 }
    let pitch = math.asin[f64](sinp)
    let yaw = math.atan2[f64](2.0f64 * (w * z + x * y), 1.0f64 - 2.0f64 * (y * y + z * z))
    ret (roll, pitch, yaw)
}
