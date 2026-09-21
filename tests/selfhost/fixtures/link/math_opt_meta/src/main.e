// `e.math.opt.meta`: simulated annealing, hill climbing and tabu search over a
// Gaussian-free uniform neighbour move find the global minimum of Rastrigin
// in two dimensions from a far start where hill climbing settles in a local
// one; the genetic algorithm, particle swarm and differential evolution
// minimise Rosenbrock in a box from seeded populations; ant colony finds the
// optimal tour of eight points on a circle. Each check exits with its own
// code.

use e.algo.rand
use e.io
use e.math
use e.math.opt.meta
use e.mem
use e.os

type Nothing = struct { unused: u8 }

// Rastrigin: global minimum 0 at the origin, local minima on the integer lattice.
fn rastrigin(ctx: *Nothing, x: []const f64) -> f64 {
    var sum = 10.0f64 * f64(x.len)
    var i = 0usize
    while i < x.len {
        sum += x[i] * x[i] - 10.0f64 * math.cos[f64](6.283185307179586f64 * x[i])
        i += 1usize
    }
    ret sum
}
fn rosenbrock(ctx: *Nothing, x: []const f64) -> f64 {
    let a = 1.0f64 - x[0usize]
    let b = x[1usize] - x[0usize] * x[0usize]
    ret a * a + 100.0f64 * b * b
}
// A uniform move of up to half a unit in every coordinate.
fn nudge(ctx: *Nothing, r: *rand.Pcg64, x: []const f64, out: []f64) {
    var i = 0usize
    while i < x.len {
        out[i] = x[i] + rand.pcg64_f64(r) - 0.5f64
        i += 1usize
    }
}
// A move of up to a unit, wide enough to cross a Rastrigin basin.
fn wide(ctx: *Nothing, r: *rand.Pcg64, x: []const f64, out: []f64) {
    var i = 0usize
    while i < x.len {
        out[i] = x[i] + 2.0f64 * rand.pcg64_f64(r) - 1.0f64
        i += 1usize
    }
}
// A tiny move, which cannot leave a Rastrigin basin.
fn tiny(ctx: *Nothing, r: *rand.Pcg64, x: []const f64, out: []f64) {
    var i = 0usize
    while i < x.len {
        out[i] = x[i] + 0.1f64 * (rand.pcg64_f64(r) - 0.5f64)
        i += 1usize
    }
}

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var nothing = Nothing { unused: 0u8 }
    var r = rand.pcg64(11u64, 3u64)
    var scratch: [512]f64 = zero
    var x: [2]f64 = zero

    // 1: simulated annealing escapes Rastrigin's local minima from (3.5, -2.5).
    x[0usize] = 3.5f64
    x[1usize] = 0.0f64 - 2.5f64
    let (sa, sa_error) = meta.simulated_annealing[Nothing](&nothing, rastrigin, nudge, &r, x[..], 5.0f64, 0.001f64, 40000u32, scratch[..])
    if sa_error != ok || sa.iterations != 40000u32 { os.exit(1i32) }
    if !near(x[0usize], 0.0f64, 0.05f64) || !near(x[1usize], 0.0f64, 0.05f64) || sa.value > 0.5f64 { os.exit(1i32) }
    let (_, sa_room) = meta.simulated_annealing[Nothing](&nothing, rastrigin, nudge, &r, x[..], 5.0f64, 0.001f64, 10u32, scratch[..3usize])
    if sa_room != meta.TooSmall { os.exit(1i32) }
    let (_, sa_invalid) = meta.simulated_annealing[Nothing](&nothing, rastrigin, nudge, &r, x[..], 0.001f64, 5.0f64, 10u32, scratch[..])
    if sa_invalid != meta.Invalid { os.exit(1i32) }

    // 2: hill climbing with a tiny move settles in the basin it starts in (3, -2)
    // and stops on patience; with the wide move it still cannot beat the basin
    // reliably, so only its monotone descent is checked.
    x[0usize] = 3.2f64
    x[1usize] = 0.0f64 - 2.2f64
    let start = rastrigin(&nothing, x[..])
    let (hc, hc_error) = meta.hill_climb[Nothing](&nothing, rastrigin, tiny, &r, x[..], 200u32, 100000u32, scratch[..])
    if hc_error != ok || hc.value >= start || hc.iterations >= 100000u32 { os.exit(2i32) }
    if !near(x[0usize], 3.0f64, 0.05f64) || !near(x[1usize], 0.0f64 - 2.0f64, 0.05f64) || !near(hc.value, 13.0f64, 0.1f64) { os.exit(2i32) }
    if !near(rastrigin(&nothing, x[..]), hc.value, 0.0f64) { os.exit(2i32) }

    // 3: tabu search with the wide move leaves the same basin and reaches the origin.
    x[0usize] = 3.2f64
    x[1usize] = 0.0f64 - 2.2f64
    let (tb, tb_error) = meta.tabu[Nothing](&nothing, rastrigin, wide, &r, x[..], 20usize, 10usize, 0.05f64, 2000u32, scratch[..])
    if tb_error != ok || tb.iterations != 2000u32 { os.exit(3i32) }
    if !near(x[0usize], 0.0f64, 0.05f64) || !near(x[1usize], 0.0f64, 0.05f64) || tb.value > 0.5f64 { os.exit(3i32) }
    let (_, tb_invalid) = meta.tabu[Nothing](&nothing, rastrigin, wide, &r, x[..], 0usize, 10usize, 0.05f64, 10u32, scratch[..])
    if tb_invalid != meta.Invalid { os.exit(3i32) }

    // 4: population methods on Rosenbrock in [-2, 2]^2.
    var low: [2]f64 = zero
    var high: [2]f64 = zero
    low[0usize] = 0.0f64 - 2.0f64
    low[1usize] = 0.0f64 - 2.0f64
    high[0usize] = 2.0f64
    high[1usize] = 2.0f64
    var population: [120]f64 = zero
    if meta.seed_population(&r, population[..], 60usize, 2usize, low[..], high[..]) != ok { os.exit(4i32) }
    var i = 0usize
    while i < 120usize {
        if population[i] < 0.0f64 - 2.0f64 || population[i] > 2.0f64 { os.exit(4i32) }
        i += 1usize
    }
    let (ga, ga_error) = meta.genetic[Nothing](&nothing, rosenbrock, &r, population[..], 60usize, 2usize, low[..], high[..], 0.2f64, 0.1f64, 300u32, x[..], scratch[..])
    if ga_error != ok || ga.iterations != 300u32 || ga.value > 0.01f64 { os.exit(4i32) }
    if !near(x[0usize], 1.0f64, 0.1f64) || !near(x[1usize], 1.0f64, 0.15f64) { os.exit(4i32) }
    if meta.seed_population(&r, population[..], 60usize, 2usize, low[..], high[..]) != ok { os.exit(4i32) }
    let (ps, ps_error) = meta.particle_swarm[Nothing](&nothing, rosenbrock, &r, population[..], 60usize, 2usize, low[..], high[..], 0.7f64, 1.5f64, 1.5f64, 300u32, x[..], scratch[..])
    if ps_error != ok || ps.value > 0.0001f64 { os.exit(4i32) }
    if !near(x[0usize], 1.0f64, 0.01f64) || !near(x[1usize], 1.0f64, 0.02f64) { os.exit(4i32) }
    if meta.seed_population(&r, population[..], 60usize, 2usize, low[..], high[..]) != ok { os.exit(4i32) }
    let (de, de_error) = meta.differential_evolution[Nothing](&nothing, rosenbrock, &r, population[..], 60usize, 2usize, low[..], high[..], 0.8f64, 0.9f64, 300u32, x[..], scratch[..])
    if de_error != ok || de.value > 0.000001f64 { os.exit(4i32) }
    if !near(x[0usize], 1.0f64, 0.001f64) || !near(x[1usize], 1.0f64, 0.002f64) { os.exit(4i32) }
    let (_, de_invalid) = meta.differential_evolution[Nothing](&nothing, rosenbrock, &r, population[..], 3usize, 2usize, low[..], high[..], 0.8f64, 0.9f64, 3u32, x[..], scratch[..])
    if de_invalid != meta.Invalid { os.exit(4i32) }
    let (_, ga_room) = meta.genetic[Nothing](&nothing, rosenbrock, &r, population[..], 60usize, 2usize, low[..], high[..], 0.2f64, 0.1f64, 3u32, x[..], scratch[..100usize])
    if ga_room != meta.TooSmall { os.exit(4i32) }

    // 5: ant colony on eight points of a circle: the optimal tour visits them in order.
    var distance: [64]f64 = zero
    var px: [8]f64 = zero
    var py: [8]f64 = zero
    i = 0usize
    while i < 8usize {
        let angle = 6.283185307179586f64 * f64(i) / 8.0f64
        px[i] = math.cos[f64](angle)
        py[i] = math.sin[f64](angle)
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        var j = 0usize
        while j < 8usize {
            let dx = px[i] - px[j]
            let dy = py[i] - py[j]
            distance[i * 8usize + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    var tour: [8]usize = zero
    var marks: [16]usize = zero
    let (length, ac_error) = meta.ant_colony(&r, distance[..], 8usize, 10usize, 1.0f64, 3.0f64, 0.3f64, 50u32, tour[..], scratch[..], marks[..])
    // Eight chords of the octagon: 8 * 2 sin(pi / 8).
    if ac_error != ok || !near(length, 6.122934917841435f64, 0.000000001f64) { os.exit(5i32) }
    var seen: [8]usize = zero
    i = 0usize
    while i < 8usize {
        seen[tour[i]] += 1usize
        let step = (tour[(i + 1usize) % 8usize] + 8usize - tour[i]) % 8usize
        if step != 1usize && step != 7usize { os.exit(5i32) }
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        if seen[i] != 1usize { os.exit(5i32) }
        i += 1usize
    }
    let (_, ac_invalid) = meta.ant_colony(&r, distance[..], 1usize, 10usize, 1.0f64, 3.0f64, 0.3f64, 5u32, tour[..], scratch[..], marks[..])
    if ac_invalid != meta.Invalid { os.exit(5i32) }
    let (_, ac_room) = meta.ant_colony(&r, distance[..], 8usize, 10usize, 1.0f64, 3.0f64, 0.3f64, 5u32, tour[..], scratch[..], marks[..8usize])
    if ac_room != meta.TooSmall { os.exit(5i32) }

    try io.print("math opt meta ok\n")
    ret ok
}
