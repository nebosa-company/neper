// The planned names of `e.math.fft` and `e.math.filter` against SciPy,
// PyWavelets and NumPy replicas: the orthonormal DCT of kinds 2, 3 and 4 and
// their inverses, the MDCT with its sine window and exact overlap-add
// reconstruction, the periodised Haar and db4 wavelet transforms one level and
// three levels deep, and the whole-cycle EKF, UKF and particle filters
// tracking a constant-velocity line through fifty LCG measurements (the
// particle filter bit for bit through a PCG64 replica). Each check exits with
// its own code.

use e.algo.rand
use e.io
use e.math
use e.math.fft
use e.math.filter
use e.mem
use e.os

type Model = struct { dt: f64 }

fn move(ctx: *Model, x: []const f64, next: []f64) {
    next[0usize] = x[0usize] + ctx.dt * x[1usize]
    next[1usize] = x[1usize]
}
fn move_jacobian(ctx: *Model, x: []const f64, f: []f64) {
    f[0usize] = 1.0f64
    f[1usize] = ctx.dt
    f[2usize] = 0.0f64
    f[3usize] = 1.0f64
}
fn range(ctx: *Model, x: []const f64, z: []f64) { z[0usize] = math.sqrt[f64](x[0usize] * x[0usize] + 100.0f64) }
fn range_jacobian(ctx: *Model, x: []const f64, h: []f64) {
    let d = math.sqrt[f64](x[0usize] * x[0usize] + 100.0f64)
    h[0usize] = x[0usize] / d
    h[1usize] = 0.0f64
}
fn jitter(ctx: *Model, r: *rand.Pcg64, particle: []f64) {
    particle[0usize] += 0.1f64 * particle[1usize] + 0.3f64 * (rand.pcg64_f64(r) - 0.5f64)
    particle[1usize] += 0.06f64 * (rand.pcg64_f64(r) - 0.5f64)
}
fn cauchy_likelihood(ctx: *Model, particle: []const f64, z: []const f64) -> f64 {
    let d = particle[0usize] - z[0usize]
    ret 1.0f64 / (1.0f64 + d * d)
}

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn draw(state: *u64) -> f64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64((*state >> 33u32) % 19u64) - 9.0f64
}

// A range measurement of the line `2 t` at step `step` with LCG noise.
fn measure(state: *u64, step: usize) -> f64 {
    let t = f64(step + 1usize) * 0.1f64
    let truth = 2.0f64 * t
    ret math.sqrt[f64](truth * truth + 100.0f64) + 0.05f64 * draw(state)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 7u64
    var sig: [48]f64 = zero
    var i = 0usize
    while i < 48usize {
        sig[i] = draw(&state)
        i += 1usize
    }
    var out: [16]f64 = zero
    var back: [16]f64 = zero
    let eps = 0.000000001f64

    // 1: the orthonormal DCT of kinds 2, 3 and 4 against SciPy, and the inverses.
    if fft.dct(sig[..16usize], out[..], 2u8, true) != ok { os.exit(1i32) }
    if !near(out[0usize], 6.999999999999999f64, eps) || !near(out[3usize], 1.5414150739441208f64, eps) || !near(out[15usize], 0.0f64 - 4.29671468993317f64, eps) { os.exit(1i32) }
    if fft.dct(out[..], back[..], 3u8, true) != ok { os.exit(1i32) }
    i = 0usize
    while i < 16usize {
        if !near(back[i], sig[i], eps) { os.exit(1i32) }
        i += 1usize
    }
    if fft.dct(sig[..16usize], out[..], 3u8, true) != ok { os.exit(1i32) }
    if !near(out[0usize], 7.100880763264215f64, eps) || !near(out[3usize], 0.4183704452584506f64, eps) || !near(out[15usize], 0.45505096706196707f64, eps) { os.exit(1i32) }
    if fft.dct(sig[..16usize], out[..], 4u8, true) != ok { os.exit(1i32) }
    if !near(out[0usize], 7.823314099526179f64, eps) || !near(out[3usize], 0.8205937751579109f64, eps) || !near(out[15usize], 0.0f64 - 3.273915858241749f64, eps) { os.exit(1i32) }
    if fft.dct(out[..], back[..], 4u8, true) != ok { os.exit(1i32) }
    if fft.dct(sig[..16usize], out[..], 2u8, false) != ok || fft.dct2(sig[..16usize], sig[16usize..32usize]) != ok { os.exit(1i32) }
    i = 0usize
    while i < 16usize {
        if !near(back[i], sig[i], eps) || out[i] != sig[16usize + i] { os.exit(1i32) }
        i += 1usize
    }
    if fft.dct(sig[..16usize], out[..], 5u8, true) != fft.Invalid || fft.dct(sig[..16usize], out[..4usize], 2u8, true) != fft.TooSmall { os.exit(1i32) }

    // 2: the MDCT of two overlapping frames, the window, and exact overlap-add.
    state = 7u64
    i = 0usize
    while i < 48usize {
        sig[i] = draw(&state)
        i += 1usize
    }
    var c1: [16]f64 = zero
    var y0: [32]f64 = zero
    var y1: [32]f64 = zero
    if fft.mdct(sig[..32usize], out[..]) != ok || fft.mdct(sig[16usize..48usize], c1[..]) != ok { os.exit(2i32) }
    if !near(out[0usize], 27.609423268278793f64, eps) || !near(out[7usize], 0.0f64 - 0.6955487095525392f64, eps) || !near(out[15usize], 0.0f64 - 12.617743803513441f64, eps) { os.exit(2i32) }
    if !near(c1[0usize], 0.0f64 - 6.468269105135406f64, eps) || !near(c1[7usize], 0.0f64 - 6.87759969563783f64, eps) || !near(c1[15usize], 13.54151675193971f64, eps) { os.exit(2i32) }
    if fft.imdct(out[..], y0[..]) != ok || fft.imdct(c1[..], y1[..]) != ok { os.exit(2i32) }
    i = 0usize
    while i < 16usize {
        if !near(y0[16usize + i] + y1[i], sig[16usize + i], eps) { os.exit(2i32) }
        i += 1usize
    }
    fft.mdct_window(y0[..])
    if !near(y0[0usize], 0.049067674327418015f64, eps) || !near(y0[31usize], 0.049067674327417966f64, eps) { os.exit(2i32) }
    i = 0usize
    while i < 16usize {
        if !near(y0[i] * y0[i] + y0[16usize + i] * y0[16usize + i], 1.0f64, eps) { os.exit(2i32) }
        i += 1usize
    }
    if fft.mdct(sig[..31usize], out[..]) != fft.Invalid || fft.mdct(sig[..32usize], out[..8usize]) != fft.TooSmall || fft.imdct(out[..], y0[..16usize]) != fft.TooSmall { os.exit(2i32) }

    // 3: Haar and db4 against PyWavelets' periodization, one level and three.
    var approx: [8]f64 = zero
    var detail: [8]f64 = zero
    if fft.dwt(sig[..16usize], .Haar, approx[..], detail[..]) != ok { os.exit(3i32) }
    if !near(approx[0usize], 3.535533905932738f64, eps) || !near(detail[0usize], 9.19238815542512f64, eps) || !near(approx[5usize], 1.4142135623730954f64, eps) || !near(detail[5usize], 7.0710678118654755f64, eps) { os.exit(3i32) }
    if fft.idwt(approx[..], detail[..], .Haar, back[..]) != ok { os.exit(3i32) }
    i = 0usize
    while i < 16usize {
        if !near(back[i], sig[i], eps) { os.exit(3i32) }
        i += 1usize
    }
    if fft.dwt(sig[..16usize], .Db4, approx[..], detail[..]) != ok { os.exit(3i32) }
    if !near(approx[0usize], 1.7726832605187524f64, eps) || !near(detail[0usize], 0.0f64 - 0.942982973098453f64, eps) || !near(approx[5usize], 0.0f64 - 0.3002080265658318f64, eps) || !near(detail[5usize], 4.4992530074018315f64, eps) { os.exit(3i32) }
    if fft.idwt(approx[..], detail[..], .Db4, back[..]) != ok { os.exit(3i32) }
    i = 0usize
    while i < 16usize {
        if !near(back[i], sig[i], eps) { os.exit(3i32) }
        i += 1usize
    }
    var scratch: [1024]f64 = zero
    if fft.wavedec(sig[..16usize], .Db4, 3usize, out[..], scratch[..]) != ok { os.exit(3i32) }
    if !near(out[0usize], 5.96572386191119f64, eps) || !near(out[1usize], 3.933771074700477f64, eps) || !near(out[2usize], 0.0f64 - 0.9726334770670287f64, eps) { os.exit(3i32) }
    if !near(out[5usize], 0.0f64 - 3.0122860603403327f64, eps) || !near(out[15usize], 0.0f64 - 10.214580565569046f64, eps) { os.exit(3i32) }
    if fft.waverec(out[..], .Db4, 3usize, back[..], scratch[..]) != ok { os.exit(3i32) }
    i = 0usize
    while i < 16usize {
        if !near(back[i], sig[i], eps) { os.exit(3i32) }
        i += 1usize
    }
    if fft.dwt(sig[..15usize], .Haar, approx[..], detail[..]) != fft.Invalid || fft.dwt(sig[..16usize], .Haar, approx[..4usize], detail[..]) != fft.TooSmall { os.exit(3i32) }
    if fft.wavedec(sig[..16usize], .Db4, 5usize, out[..], scratch[..]) != fft.Invalid || fft.waverec(out[..], .Db4, 2usize, back[..], scratch[..8usize]) != fft.TooSmall { os.exit(3i32) }

    // 4: the whole-cycle EKF over fifty range measurements against NumPy.
    var model = Model { dt: 0.1f64 }
    var q: [4]f64 = zero
    q[0usize] = 0.0001f64
    q[3usize] = 0.0001f64
    var rn: [1]f64 = zero
    rn[0usize] = 0.05f64
    var x: [2]f64 = zero
    var p: [4]f64 = zero
    var z: [1]f64 = zero
    x[0usize] = 5.0f64
    p[0usize] = 4.0f64
    p[3usize] = 4.0f64
    state = 11u64
    var step = 0usize
    while step < 50usize {
        z[0usize] = measure(&state, step)
        if filter.ekf[Model](&model, move, move_jacobian, range, range_jacobian, x[..], p[..], q[..], rn[..], z[..], 2usize, 1usize, scratch[..]) != ok { os.exit(4i32) }
        step += 1usize
    }
    if !near(x[0usize], 9.903523751420032f64, eps) || !near(x[1usize], 1.9093081167464139f64, eps) { os.exit(4i32) }
    if !near(p[0usize], 0.012580151802018357f64, eps) || !near(p[1usize], 0.00557357056356846f64, eps) || !near(p[3usize], 0.005078854175850229f64, eps) { os.exit(4i32) }
    if filter.ekf[Model](&model, move, move_jacobian, range, range_jacobian, x[..], p[..], q[..], rn[..], z[..], 2usize, 1usize, scratch[..5usize]) != filter.TooSmall { os.exit(4i32) }

    // 5: the scaled UKF (alpha 0.5, beta 2, kappa 0) on the same measurements.
    x[0usize] = 5.0f64
    x[1usize] = 0.0f64
    p[0usize] = 4.0f64
    p[1usize] = 0.0f64
    p[2usize] = 0.0f64
    p[3usize] = 4.0f64
    state = 11u64
    step = 0usize
    while step < 50usize {
        z[0usize] = measure(&state, step)
        if filter.ukf[Model](&model, move, range, x[..], p[..], q[..], rn[..], z[..], 2usize, 1usize, 0.5f64, 2.0f64, 0.0f64, scratch[..]) != ok { os.exit(5i32) }
        step += 1usize
    }
    if !near(x[0usize], 9.956357383450884f64, eps) || !near(x[1usize], 1.9661703916581021f64, eps) { os.exit(5i32) }
    if !near(p[0usize], 0.013019809532258538f64, eps) || !near(p[1usize], 0.005989759155581904f64, eps) || !near(p[3usize], 0.005520959584700725f64, eps) { os.exit(5i32) }
    if filter.ukf[Model](&model, move, range, x[..], p[..], q[..], rn[..], z[..], 2usize, 1usize, 0.5f64, 2.0f64, 0.0f64, scratch[..5usize]) != filter.TooSmall { os.exit(5i32) }

    // 6: the particle filter bit for bit through the PCG64 replica.
    var r = rand.pcg64(3u64, 5u64)
    var particles: [128]f64 = zero
    var weights: [64]f64 = zero
    i = 0usize
    while i < 64usize {
        particles[2usize * i] = 20.0f64 * (rand.pcg64_f64(&r) - 0.5f64)
        particles[2usize * i + 1usize] = 4.0f64 * (rand.pcg64_f64(&r) - 0.5f64) + 2.0f64
        weights[i] = 1.0f64 / 64.0f64
        i += 1usize
    }
    state = 13u64
    step = 0usize
    while step < 50usize {
        z[0usize] = 2.0f64 * (f64(step + 1usize) * 0.1f64) + 0.05f64 * draw(&state)
        if filter.particle[Model](&model, &r, jitter, cauchy_likelihood, particles[..], weights[..], 64usize, 2usize, z[..], 0.5f64, scratch[..]) != ok { os.exit(6i32) }
        step += 1usize
    }
    var mean: [2]f64 = zero
    if filter.particle_mean(particles[..], weights[..], 64usize, 2usize, mean[..]) != ok { os.exit(6i32) }
    if mean[0usize] != 9.020834133548696f64 || mean[1usize] != 1.4128974226174373f64 || weights[0usize] != 0.0009448143341615087f64 { os.exit(6i32) }
    // Threshold 1 always resamples: uniform weights and a copied particle.
    z[0usize] = 10.2f64
    if filter.particle[Model](&model, &r, jitter, cauchy_likelihood, particles[..], weights[..], 64usize, 2usize, z[..], 1.0f64, scratch[..]) != ok { os.exit(6i32) }
    if weights[0usize] != 0.015625f64 || particles[0usize] != 9.19300381309478f64 { os.exit(6i32) }
    if filter.particle[Model](&model, &r, jitter, cauchy_likelihood, particles[..], weights[..], 64usize, 2usize, z[..], 1.0f64, scratch[..5usize]) != filter.TooSmall { os.exit(6i32) }

    try io.print("math fft filter plan ok\n")
    ret ok
}
