// `e.math.mcmc` on a bivariate normal with unit variances and correlation
// 0.5: random-walk Metropolis-Hastings, Gibbs sampling through the exact
// conditionals, Hamiltonian Monte Carlo and NUTS each recover the means,
// variances and covariance from a few thousand samples; the chains report
// their acceptance, the storage checks answer, and NUTS moves nearly every
// step where the random walk rejects about half. Each check exits with its
// own code.

use e.algo.rand
use e.algo.rand.dist
use e.io
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

    try io.print("math mcmc ok\n")
    ret ok
}
