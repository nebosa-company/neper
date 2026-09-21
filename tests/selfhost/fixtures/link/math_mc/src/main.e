// `e.math.mc`: a Black-Scholes call (spot and strike 100, volatility 0.2,
// one year, no rate) priced by the plain estimator lands within a few
// standard errors of 7.9656; antithetic pairs and a control variate on the
// terminal price both cut the standard error and stay on the price; the
// second moment of the normal is 1; the count and storage checks answer.
// Each check exits with its own code.

use e.algo.rand
use e.io
use e.math
use e.math.mc
use e.mem
use e.os

type Option = struct { spot: f64, strike: f64, volatility: f64 }

fn terminal(o: *Option, z: f64) -> f64 { ret o.spot * math.exp[f64](0.0f64 - 0.5f64 * o.volatility * o.volatility + o.volatility * z) }
fn payoff(o: *Option, z: f64) -> f64 {
    let s = terminal(o, z)
    if s > o.strike { ret s - o.strike }
    ret 0.0f64
}
fn square(o: *Option, z: f64) -> f64 { ret z * z }
fn identity(o: *Option, z: f64) -> f64 { ret z }

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var option = Option { spot: 100.0f64, strike: 100.0f64, volatility: 0.2f64 }
    var r = rand.pcg64(5u64, 17u64)
    let price = 7.965567455405804f64
    let count = 20000usize

    // 1: the plain estimator.
    let (plain, plain_error) = mc.estimate[Option](&option, payoff, &r, count)
    if plain_error != ok || plain.count != count || plain.standard_error <= 0.0f64 { os.exit(1i32) }
    if !near(plain.mean, price, 4.0f64 * plain.standard_error) || plain.standard_error > 0.15f64 { os.exit(1i32) }
    let (moment, moment_error) = mc.estimate[Option](&option, square, &r, count)
    if moment_error != ok || !near(moment.mean, 1.0f64, 0.05f64) { os.exit(1i32) }
    let (_, few) = mc.estimate[Option](&option, payoff, &r, 1usize)
    if few != mc.Invalid { os.exit(1i32) }

    // 2: antithetic pairs on the price, with a smaller error per draw.
    let (anti, anti_error) = mc.antithetic[Option](&option, payoff, &r, count / 2usize)
    if anti_error != ok || anti.count != count / 2usize { os.exit(2i32) }
    if !near(anti.mean, price, 4.0f64 * anti.standard_error) || anti.standard_error >= plain.standard_error { os.exit(2i32) }
    // An odd payoff is estimated exactly by antithetic pairs.
    let (odd, odd_error) = mc.antithetic[Option](&option, identity, &r, 100usize)
    if odd_error != ok || !near(odd.mean, 0.0f64, 0.000000000001f64) || odd.standard_error > 0.000000000001f64 { os.exit(2i32) }

    // 3: the terminal price as a control variate (its mean is the spot).
    let (samples, alloc_error) = mem.alloc[f64](a, 2usize * count)
    if alloc_error != ok { ret alloc_error }
    let (control, control_error) = mc.control_variate[Option](&option, payoff, terminal, 100.0f64, &r, count, samples)
    if control_error != ok || !near(control.mean, price, 4.0f64 * control.standard_error) || control.standard_error >= 0.5f64 * plain.standard_error { os.exit(3i32) }
    let (_, control_room) = mc.control_variate[Option](&option, payoff, terminal, 100.0f64, &r, count, samples[..10usize])
    if control_room != mc.Invalid { os.exit(3i32) }

    try io.print("math mc ok\n")
    ret ok
}
