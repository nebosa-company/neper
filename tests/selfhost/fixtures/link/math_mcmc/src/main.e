// `e.math.mcmc` on a bivariate normal with unit variances and correlation
// 0.5: random-walk Metropolis-Hastings, Gibbs sampling through the exact
// conditionals, Hamiltonian Monte Carlo and NUTS each recover the means,
// variances and covariance from a few thousand samples; the chains report
// their acceptance, the storage checks answer, and NUTS moves nearly every
// step where the random walk rejects about half. Variational inference (L060)
// fits mean-field Gaussians to a correlated normal (sd sqrt(1 - rho^2)), a banana
// and a log-gamma against Gauss-Hermite quadrature optima from
// scripts/gen_vi_test.py, with the ELBO below log Z. Each check exits with its
// own code.

use e.algo.rand
use e.algo.rand.dist
use e.io
use e.math
use e.math.mcmc
use e.mem
use e.os

type Target = struct { rho: f64 }

fn log_density(t: *Target, x: []const f64) -> f64 {
    let s = 1.0f64 - t.rho * t.rho
    ret 0.0f64 - (x[0usize] * x[0usize] - 2.0f64 * t.rho * x[0usize] * x[1usize] + x[1usize] * x[1usize]) / (2.0f64 * s)
}
fn grad(t: *Target, x: []const f64, g: []f64) {
    let s = 1.0f64 - t.rho * t.rho
    g[0usize] = 0.0f64 - (x[0usize] - t.rho * x[1usize]) / s
    g[1usize] = 0.0f64 - (x[1usize] - t.rho * x[0usize]) / s
}
// x_k | x_other ~ N(rho x_other, 1 - rho^2).
fn conditional(t: *Target, r: *rand.Pcg64, k: usize, x: []f64) {
    let other = x[1usize - k]
    x[k] = t.rho * other + dist.normal(r) * 0.8660254037844386f64
}

// A banana f = -x^2 / 2 - (y - x^2 / 2)^2 / (2 s^2).
type Banana = struct { scale: f64 }

fn banana_density(b: *Banana, x: []const f64) -> f64 {
    let bend = x[1usize] - 0.5f64 * x[0usize] * x[0usize]
    ret 0.0f64 - 0.5f64 * x[0usize] * x[0usize] - bend * bend / (2.0f64 * b.scale * b.scale)
}
fn banana_grad(b: *Banana, x: []const f64, g: []f64) {
    let bend = x[1usize] - 0.5f64 * x[0usize] * x[0usize]
    g[0usize] = 0.0f64 - x[0usize] + bend * x[0usize] / (b.scale * b.scale)
    g[1usize] = 0.0f64 - bend / (b.scale * b.scale)
}
// f(z) = 3 z - exp(z), the log of a Gamma(3, 1) in z = log x.
fn log_gamma(t: *Target, x: []const f64) -> f64 {
    ret 3.0f64 * x[0usize] - math.exp[f64](x[0usize])
}
fn grad_gamma(t: *Target, x: []const f64, g: []f64) {
    g[0usize] = 3.0f64 - math.exp[f64](x[0usize])
}

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

// Means, variances and the covariance of the rows after the first `skip`.
fn moments(samples: []const f64, count: usize, skip: usize, out: []f64) {
    var sx = 0.0f64
    var sy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var sxy = 0.0f64
    var i = skip
    while i < count {
        let x = samples[2usize * i]
        let y = samples[2usize * i + 1usize]
        sx += x
        sy += y
        sxx += x * x
        syy += y * y
        sxy += x * y
        i += 1usize
    }
    let n = f64(count - skip)
    out[0usize] = sx / n
    out[1usize] = sy / n
    out[2usize] = sxx / n - out[0usize] * out[0usize]
    out[3usize] = syy / n - out[1usize] * out[1usize]
    out[4usize] = sxy / n - out[0usize] * out[1usize]
}
fn plausible(m: []const f64, tolerance: f64) -> bool {
    ret near(m[0usize], 0.0f64, tolerance) && near(m[1usize], 0.0f64, tolerance) && near(m[2usize], 1.0f64, 1.5f64 * tolerance) && near(m[3usize], 1.0f64, 1.5f64 * tolerance) && near(m[4usize], 0.5f64, 1.5f64 * tolerance)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var goal = Target { rho: 0.5f64 }
    var r = rand.pcg64(21u64, 9u64)
    let count = 6000usize
    let (samples, alloc_error) = mem.alloc[f64](a, 2usize * count)
    if alloc_error != ok { ret alloc_error }
    var scratch: [256]f64 = zero
    var x: [2]f64 = zero
    var m: [5]f64 = zero

    // 1: Metropolis-Hastings from a far start.
    x[0usize] = 4.0f64
    x[1usize] = 0.0f64 - 4.0f64
    let (mh, mh_error) = mcmc.metropolis_hastings[Target](&goal, log_density, &r, x[..], 1.0f64, samples, count, scratch[..])
    if mh_error != ok || mh.proposed != count || mh.accepted < count / 4usize || mh.accepted > 3usize * count / 4usize { os.exit(1i32) }
    moments(samples, count, 500usize, m[..])
    if !plausible(m[..], 0.12f64) { os.exit(1i32) }
    if samples[2usize * count - 2usize] != x[0usize] || samples[2usize * count - 1usize] != x[1usize] { os.exit(1i32) }
    let (_, mh_room) = mcmc.metropolis_hastings[Target](&goal, log_density, &r, x[..], 1.0f64, samples, count, scratch[..1usize])
    if mh_room != mcmc.TooSmall { os.exit(1i32) }

    // 2: Gibbs through the exact conditionals.
    x[0usize] = 4.0f64
    x[1usize] = 0.0f64 - 4.0f64
    if mcmc.gibbs[Target](&goal, conditional, &r, x[..], samples, count) != ok { os.exit(2i32) }
    moments(samples, count, 100usize, m[..])
    if !plausible(m[..], 0.08f64) { os.exit(2i32) }
    if mcmc.gibbs[Target](&goal, conditional, &r, x[..], samples[..10usize], count) != mcmc.TooSmall { os.exit(2i32) }

    // 3: Hamiltonian Monte Carlo accepts nearly every trajectory.
    x[0usize] = 4.0f64
    x[1usize] = 0.0f64 - 4.0f64
    let (hm, hm_error) = mcmc.hmc[Target](&goal, log_density, grad, &r, x[..], 0.2f64, 10usize, samples, count, scratch[..])
    if hm_error != ok || hm.accepted < 9usize * count / 10usize { os.exit(3i32) }
    moments(samples, count, 100usize, m[..])
    if !plausible(m[..], 0.08f64) { os.exit(3i32) }
    let (_, hm_invalid) = mcmc.hmc[Target](&goal, log_density, grad, &r, x[..], 0.2f64, 0usize, samples, count, scratch[..])
    if hm_invalid != mcmc.Invalid { os.exit(3i32) }

    // 4: NUTS moves nearly every step and matches the moments too.
    x[0usize] = 4.0f64
    x[1usize] = 0.0f64 - 4.0f64
    let (nt, nt_error) = mcmc.nuts[Target](&goal, log_density, grad, &r, x[..], 0.3f64, 6usize, samples, count, scratch[..])
    if nt_error != ok || nt.accepted < 9usize * count / 10usize { os.exit(4i32) }
    moments(samples, count, 100usize, m[..])
    if !plausible(m[..], 0.08f64) { os.exit(4i32) }
    let (_, nt_room) = mcmc.nuts[Target](&goal, log_density, grad, &r, x[..], 0.3f64, 6usize, samples, count, scratch[..80usize])
    if nt_room != mcmc.TooSmall { os.exit(4i32) }
    let (_, nt_invalid) = mcmc.nuts[Target](&goal, log_density, grad, &r, x[..], 0.3f64, 0usize, samples, count, scratch[..])
    if nt_invalid != mcmc.Invalid { os.exit(4i32) }

    // 5: variational inference (L060). Mean-field ADVI on the correlation-0.8 normal
    // finds mean 0 and sd sqrt(1 - rho^2) = 0.6 (the mean-field theorem), ELBO
    // 0.8162; the references in the checks below come from scripts/gen_vi_test.py
    // (Gauss-Hermite quadrature, BFGS).
    var tight = Target { rho: 0.8f64 }
    var vmean: [2]f64 = zero
    var vlog: [2]f64 = zero
    var vscratch: [32]f64 = zero
    vmean[0usize] = 1.5f64
    vmean[1usize] = 0.0f64 - 1.5f64
    let (fit_a, fit_a_error) = mcmc.advi[Target](&tight, log_density, grad, &r, vmean[..], vlog[..], 3000usize, 8usize, 0.05f64, vscratch[..])
    if fit_a_error != ok || fit_a.steps != 3000usize { os.exit(5i32) }
    if !near(vmean[0usize], 0.0f64, 0.06f64) || !near(vmean[1usize], 0.0f64, 0.06f64) { os.exit(5i32) }
    if !near(math.exp[f64](vlog[0usize]), 0.6f64, 0.05f64) || !near(math.exp[f64](vlog[1usize]), 0.6f64, 0.05f64) { os.exit(5i32) }
    if !near(fit_a.bound, 0.8162258f64, 0.06f64) { os.exit(5i32) }
    // The bound is below log Z = 1.3270514 by the KL the factorisation costs.
    if fit_a.bound > 1.3270514f64 { os.exit(5i32) }
    // elbo() at the fit beats elbo() at a shifted mean.
    let (at_fit, at_fit_error) = mcmc.elbo[Target](&tight, log_density, &r, vmean[..], vlog[..], 4000usize, vscratch[..])
    if at_fit_error != ok { os.exit(5i32) }
    var shifted: [2]f64 = zero
    shifted[0usize] = vmean[0usize] + 1.0f64
    shifted[1usize] = vmean[1usize]
    let (at_shift, at_shift_error) = mcmc.elbo[Target](&tight, log_density, &r, shifted[..], vlog[..], 4000usize, vscratch[..])
    if at_shift_error != ok || at_shift >= at_fit - 0.3f64 { os.exit(5i32) }
    // 6: a banana, mean (0, 0.1292), sd (0.5083, 0.3), ELBO 0.1426.
    var banana = Banana { scale: 0.3f64 }
    vmean[0usize] = 1.0f64
    vmean[1usize] = 1.0f64
    vlog[0usize] = 0.0f64
    vlog[1usize] = 0.0f64
    let (fit_b, fit_b_error) = mcmc.advi[Banana](&banana, banana_density, banana_grad, &r, vmean[..], vlog[..], 4000usize, 8usize, 0.03f64, vscratch[..])
    if fit_b_error != ok { os.exit(6i32) }
    if !near(vmean[0usize], 0.0f64, 0.08f64) || !near(vmean[1usize], 0.1292f64, 0.06f64) { os.exit(6i32) }
    if !near(math.exp[f64](vlog[0usize]), 0.5083f64, 0.06f64) || !near(math.exp[f64](vlog[1usize]), 0.3f64, 0.04f64) { os.exit(6i32) }
    if !near(fit_b.bound, 0.1426f64, 0.08f64) { os.exit(6i32) }
    // 7: one dimension, the log-gamma 3 z - exp(z): mean 0.9319, sd 0.5774, ELBO
    // 0.6655 under log Gamma(3) = 0.6931.
    var gamma_target = Target { rho: 0.0f64 }
    var one_mean: [1]f64 = zero
    var one_log: [1]f64 = zero
    let (fit_c, fit_c_error) = mcmc.advi[Target](&gamma_target, log_gamma, grad_gamma, &r, one_mean[..], one_log[..], 3000usize, 8usize, 0.05f64, vscratch[..])
    if fit_c_error != ok { os.exit(7i32) }
    if !near(one_mean[0usize], 0.9319f64, 0.07f64) || !near(math.exp[f64](one_log[0usize]), 0.5774f64, 0.06f64) { os.exit(7i32) }
    if !near(fit_c.bound, 0.6655f64, 0.06f64) || fit_c.bound > 0.6931f64 + 0.03f64 { os.exit(7i32) }
    // 8: draws from the fit have the fitted moments; refusals.
    if mcmc.variational_samples(&r, one_mean[..], one_log[..], samples, count) != ok { os.exit(8i32) }
    var sum = 0.0f64
    var sum_sq = 0.0f64
    var si = 0usize
    while si < count {
        sum += samples[si]
        sum_sq += samples[si] * samples[si]
        si += 1usize
    }
    let q_mean = sum / f64(count)
    let q_sd = math.sqrt[f64](sum_sq / f64(count) - q_mean * q_mean)
    if !near(q_mean, one_mean[0usize], 0.03f64) || !near(q_sd, math.exp[f64](one_log[0usize]), 0.03f64) { os.exit(8i32) }
    let (_, vi_room) = mcmc.advi[Target](&gamma_target, log_gamma, grad_gamma, &r, one_mean[..], one_log[..], 10usize, 2usize, 0.05f64, vscratch[..10usize])
    if vi_room != mcmc.TooSmall { os.exit(8i32) }
    let (_, vi_steps) = mcmc.advi[Target](&gamma_target, log_gamma, grad_gamma, &r, one_mean[..], one_log[..], 0usize, 2usize, 0.05f64, vscratch[..])
    if vi_steps != mcmc.Invalid { os.exit(8i32) }
    let (_, vi_shape) = mcmc.advi[Target](&gamma_target, log_gamma, grad_gamma, &r, vmean[..], one_log[..], 10usize, 2usize, 0.05f64, vscratch[..])
    if vi_shape != mcmc.Invalid { os.exit(8i32) }
    if mcmc.variational_samples(&r, one_mean[..], one_log[..], samples[..3usize], 4usize) != mcmc.TooSmall { os.exit(8i32) }

    try io.print("math mcmc ok\n")
    ret ok
}
