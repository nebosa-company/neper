// `e.audio.synth` against numpy replicas (scratchpad audio/synth_ref.py):
// the ADSR state machine through a note on and off, PolyBLEP oscillators
// (and the saw's energy above half Nyquist below the naive saw's), the
// additive wavetable with linear and cubic reads, and a Karplus-Strong pluck
// from the same PCG burst to 1e-12. Each check exits with its own code.

use e.algo.rand
use e.audio.synth as synth
use e.io
use e.math
use e.math.fft
use e.mem
use e.os

fn digest(xs: []const f64) -> f64 {
    var d = 0.0f64
    var i = 0usize
    while i < xs.len {
        d += xs[i] * math.cos[f64](f64(i))
        i += 1usize
    }
    ret d
}

fn near(x: f64, want: f64, tol: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tol
}

// The power of `y` (4096 samples) in FFT bins 1024 to 2047: above half Nyquist.
fn high_energy(y: []const f64, re: []f64, im: []f64) -> f64 {
    var i = 0usize
    while i < y.len {
        re[i] = y[i]
        im[i] = 0.0f64
        i += 1usize
    }
    if fft.fft(re[..y.len], im[..y.len]) != ok { ret 0.0f64 }
    var sum = 0.0f64
    var k = 1024usize
    while k < 2048usize {
        sum += re[k] * re[k] + im[k] * im[k]
        k += 1usize
    }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: the ADSR envelope.
    var e = synth.adsr(0.01f64, 0.02f64, 0.5f64, 0.05f64, 1000.0f64)
    if e.stage != .Idle || synth.adsr_next(&e) != 0.0f64 { os.exit(1i32) }
    synth.adsr_gate(&e, true)
    var sum = 0.0f64
    var i = 0usize
    while i < 40usize {
        let v = synth.adsr_next(&e)
        if i == 5usize && !near(v, 0.6f64, 1.0e-12f64) { os.exit(1i32) }
        if i == 15usize && !near(v, 0.7499999999999998f64, 1.0e-12f64) { os.exit(1i32) }
        sum += v
        i += 1usize
    }
    if e.stage != .Sustain { os.exit(1i32) }
    synth.adsr_gate(&e, false)
    i = 0usize
    while i < 40usize {
        sum += synth.adsr_next(&e)
        i += 1usize
    }
    if e.stage != .Idle || e.level != 0.0f64 || !near(sum, 29.25f64, 1.0e-12f64) { os.exit(1i32) }

    // 2: PolyBLEP oscillators against the replica and against the naive saw.
    let sr = 8192.0f64
    let dt = 440.0f64 / sr
    var saw: [4096]f64 = zero
    var naive: [4096]f64 = zero
    var square: [4096]f64 = zero
    var triangle: [4096]f64 = zero
    i = 0usize
    while i < 4096usize {
        let phase = f64(i) * dt
        saw[i] = synth.oscillator_polyblep(.Saw, phase, dt)
        naive[i] = synth.oscillator_naive(.Saw, phase)
        square[i] = synth.oscillator_polyblep(.Square, phase, dt)
        triangle[i] = synth.oscillator_polyblep(.Triangle, phase, dt)
        i += 1usize
    }
    if !near(digest(saw[..]), -1.4765723239663535f64, 1.0e-9f64) || !near(digest(naive[..]), -6.807059012494967f64, 1.0e-9f64) { os.exit(2i32) }
    if !near(digest(square[..]), 3.0136480213642622f64, 1.0e-9f64) || !near(digest(triangle[..]), -1.790467432572875f64, 1.0e-9f64) { os.exit(2i32) }
    var re: [4096]f64 = zero
    var im: [4096]f64 = zero
    let blep_alias = high_energy(saw[..], re[..], im[..])
    let naive_alias = high_energy(naive[..], re[..], im[..])
    if !near(blep_alias, 93011.57486242711f64, 1.0e-3f64) || !near(naive_alias, 293381.15101798385f64, 1.0e-3f64) || !(blep_alias < naive_alias) { os.exit(2i32) }

    // 3: the wavetable.
    var table: [64]f64 = zero
    if synth.wavetable_build(table[..], 8usize) != ok || !near(digest(table[..]), 0.03980459354609195f64, 1.0e-12f64) { os.exit(3i32) }
    if !near(synth.wavetable(table[..], 0.3f64, .Linear), 0.6226676537316057f64, 1.0e-12f64) { os.exit(3i32) }
    if !near(synth.wavetable(table[..], 0.3f64, .Cubic), 0.6234332285141173f64, 1.0e-12f64) { os.exit(3i32) }
    if !near(synth.wavetable(table[..], -0.01f64, .Cubic), -0.0008921756960567793f64, 1.0e-12f64) { os.exit(3i32) }
    if synth.wavetable_build(table[..], 0usize) != synth.Invalid || synth.wavetable(table[..0usize], 0.5f64, .Linear) != 0.0f64 { os.exit(3i32) }

    // 4: Karplus-Strong from a PCG burst.
    var r = rand.pcg64(5u64, 11u64)
    var pluck: [4096]f64 = zero
    if synth.karplus_strong(220.0f64, sr, 0.996f64, &r, pluck[..]) != ok { os.exit(4i32) }
    if !near(pluck[0usize], -0.3626118207247844f64, 1.0e-12f64) || !near(pluck[100usize], 0.42744251691763674f64, 1.0e-12f64) || !near(pluck[4095usize], -0.09586689641364618f64, 1.0e-12f64) { os.exit(4i32) }
    sum = 0.0f64
    i = 0usize
    while i < 4096usize {
        sum += pluck[i]
        i += 1usize
    }
    if !near(sum, -178.63335558331764f64, 1.0e-12f64) { os.exit(4i32) }
    if synth.karplus_strong(220.0f64, sr, 0.996f64, &r, pluck[..10usize]) != synth.TooSmall || synth.karplus_strong(0.0f64, sr, 0.996f64, &r, pluck[..]) != synth.Invalid { os.exit(4i32) }

    try io.print("audio synth ok\n")
    ret ok
}
