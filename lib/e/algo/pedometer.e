// A step detector (C138): the accelerometer's magnitude (m/s^2, gravity included) fed one sample at a time, steps
// counted by a peak-and-threshold rule. The signal is smoothed by a short moving average; a step is a local maximum
// of the smoothed signal that rises above an adaptive threshold -- the running mean plus half a standard deviation of the smoothed signal seen
// over the last couple of seconds -- and comes at least 250 ms after the last one. Walking and running are told apart by
// the cadence over the last few steps (above 2.6 steps a second is running). The rate is the sample rate in Hz,
// 20 to 100.
//
// Nothing here allocates: a `Pedometer` is plain data the caller keeps.
use e.math

const WINDOW: usize = 64usize

type Pedometer = struct {
    rate: usize,
    // The last three raw samples (the moving average), the smoothed history ring and its size.
    raw: [3]f64,
    raw_count: usize,
    smooth: [64]f64,
    at: usize,
    filled: usize,
    // The smoothed values around the candidate peak.
    previous: f64,
    current: f64,
    have_two: bool,
    samples_since_step: usize,
    steps: usize,
    // The sample indexes of the last six steps, for the cadence.
    last_steps: [6]usize,
    last_count: usize,
    index: usize,
    running: bool,
}

fn new(rate: usize) -> Pedometer {
    var p: Pedometer = zero
    p.rate = rate
    p.samples_since_step = 1000000usize
    ret p
}

// The mean and the standard deviation of the smoothed history.
fn history_mean_deviation(p: *Pedometer) -> (f64, f64) {
    if p.filled == 0usize { ret (0.0f64, 0.0f64) }
    var sum = 0.0f64
    var i = 0usize
    while i < p.filled {
        sum = sum + p.smooth[i]
        i += 1usize
    }
    let mean = sum / f64(p.filled)
    var spread = 0.0f64
    i = 0usize
    while i < p.filled {
        let d = p.smooth[i] - mean
        spread = spread + d * d
        i += 1usize
    }
    ret (mean, math.sqrt[f64](spread / f64(p.filled)))
}

// Add one sample of the acceleration magnitude. True when it completed a step.
fn feed(p: *Pedometer, magnitude: f64) -> bool {
    // Smooth over three samples.
    p.raw[0usize] = p.raw[1usize]
    p.raw[1usize] = p.raw[2usize]
    p.raw[2usize] = magnitude
    if p.raw_count < 3usize { p.raw_count += 1usize }
    var smoothed = magnitude
    if p.raw_count == 3usize { smoothed = (p.raw[0usize] + p.raw[1usize] + p.raw[2usize]) / 3.0f64 }
    p.index += 1usize
    p.samples_since_step += 1usize
    // The candidate is the middle of the last three smoothed values.
    let before = p.previous
    let middle = p.current
    p.previous = p.current
    p.current = smoothed
    var stepped = false
    if p.have_two {
        let (mean, deviation) = history_mean_deviation(p)
        let threshold = mean + 0.5f64 * deviation
        let min_gap = p.rate / 4usize
        if p.filled >= 5usize && middle > before && middle >= smoothed && middle > threshold && deviation > 0.3f64 && p.samples_since_step >= min_gap {
            stepped = true
            p.steps += 1usize
            p.samples_since_step = 0usize
            // The cadence from the last steps.
            if p.last_count < 6usize {
                p.last_steps[p.last_count] = p.index
                p.last_count += 1usize
            } else {
                var k = 1usize
                while k < 6usize {
                    p.last_steps[k - 1usize] = p.last_steps[k]
                    k += 1usize
                }
                p.last_steps[5usize] = p.index
            }
            if p.last_count >= 4usize {
                let span = p.last_steps[p.last_count - 1usize] - p.last_steps[0usize]
                if span > 0usize {
                    let per_second = f64(p.last_count - 1usize) * f64(p.rate) / f64(span)
                    p.running = per_second > 2.6f64
                }
            }
        }
    }
    p.have_two = true
    // The smoothed history ring.
    p.smooth[p.at] = smoothed
    p.at = (p.at + 1usize) % WINDOW
    if p.filled < WINDOW { p.filled += 1usize }
    ret stepped
}

fn steps(p: *Pedometer) -> usize { ret p.steps }

fn is_running(p: *Pedometer) -> bool { ret p.running }

// The distance in metres of `count` steps for a person `height_cm` tall: a stride of 41.5% of the height walking and 65%
// of it running (the usual fitness-tracker estimate).
fn distance_m(count: usize, height_cm: f64, running: bool) -> f64 {
    var factor = 0.415f64
    if running { factor = 0.65f64 }
    ret f64(count) * height_cm * factor / 100.0f64
}

// The energy in kilocalories of covering `metres` at `weight_kg`: about 0.75 kcal per kilogram per kilometre walking
// and 1.0 running (net of resting). An estimate, not a measurement.
fn calories_kcal(metres: f64, weight_kg: f64, running: bool) -> f64 {
    var per_kg_km = 0.75f64
    if running { per_kg_km = 1.0f64 }
    ret per_kg_km * weight_kg * metres / 1000.0f64
}
