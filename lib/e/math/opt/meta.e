// Metaheuristics over `f64` vectors in caller storage: simulated annealing,
// hill climbing and tabu search over a caller's neighbour move, and the
// population methods (genetic algorithm, particle swarm, differential
// evolution) over a caller's population in a box; ant colony optimisation
// walks a distance matrix for a short tour.
//
// An objective is `f(ctx, x) -> f64` and is minimised; a neighbour move is
// `neighbor(ctx, r, x, out)`, writing a candidate near `x`. Every method draws
// from a `*rand.Pcg64`, improves the caller's `x` in place, and answers the
// best value seen with the iteration count. Scratch is the caller's, sized
// per declaration.

use e.algo.rand
use e.math

type Result = struct { value: f64, iterations: u32 }
error TooSmall
error Invalid

fn copy(out: []f64, from: []const f64) {
    var i = 0usize
    while i < out.len {
        out[i] = from[i]
        i += 1usize
    }
}

fn distance2(a: []const f64, b: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < a.len {
        let d = a[i] - b[i]
        sum += d * d
        i += 1usize
    }
    ret sum
}

// Fill `population` (`count` rows of `n`) uniformly in the box `[low, high]`.
fn seed_population(r: *rand.Pcg64, population: []f64, count: usize, n: usize, low: []const f64, high: []const f64) -> err {
    if population.len < count * n || low.len < n || high.len < n { ret TooSmall }
    var i = 0usize
    while i < count * n {
        let k = i % n
        population[i] = low[k] + (high[k] - low[k]) * rand.pcg64_f64(r)
        i += 1usize
    }
    ret ok
}

fn clamp(x: []f64, low: []const f64, high: []const f64) {
    var i = 0usize
    while i < x.len {
        if x[i] < low[i] { x[i] = low[i] }
        if x[i] > high[i] { x[i] = high[i] }
        i += 1usize
    }
}

// Simulated annealing with geometric cooling from `start` to `finish` over
// `steps` moves; a worse candidate is accepted with probability
// exp(-delta / temperature). `x` ends at the best point seen;
// `scratch.len >= 2 * n`.
fn simulated_annealing[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, neighbor: fn(*Ctx, *rand.Pcg64, []const f64, []f64), r: *rand.Pcg64, x: []f64, start: f64, finish: f64, steps: u32, scratch: []f64) -> (Result, err) {
    let n = x.len
    if scratch.len < 2usize * n { ret (zero, TooSmall) }
    if start <= 0.0f64 || finish <= 0.0f64 || finish > start || steps == 0u32 { ret (zero, Invalid) }
    var candidate = scratch[..n]
    var best = scratch[n..2usize * n]
    var current = f(ctx, x)
    var best_value = current
    copy(best, x)
    let ratio = math.pow[f64](finish / start, 1.0f64 / f64(steps))
    var temperature = start
    var step = 0u32
    while step < steps {
        neighbor(ctx, r, x, candidate)
        let value = f(ctx, candidate)
        let delta = value - current
        if delta <= 0.0f64 || rand.pcg64_f64(r) < math.exp[f64](0.0f64 - delta / temperature) {
            copy(x, candidate)
            current = value
            if value < best_value {
                best_value = value
                copy(best, x)
            }
        }
        temperature = temperature * ratio
        step += 1u32
    }
    copy(x, best)
    ret (Result { value: best_value, iterations: steps }, ok)
}

// Hill climbing: a neighbour is taken only when it improves, and the search
// stops after `patience` rejections in a row or `max_iterations` moves;
// `scratch.len >= n`.
fn hill_climb[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, neighbor: fn(*Ctx, *rand.Pcg64, []const f64, []f64), r: *rand.Pcg64, x: []f64, patience: u32, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let n = x.len
    if scratch.len < n { ret (zero, TooSmall) }
    var candidate = scratch[..n]
    var current = f(ctx, x)
    var failures = 0u32
    var iteration = 0u32
    while iteration < max_iterations && failures < patience {
        neighbor(ctx, r, x, candidate)
        let value = f(ctx, candidate)
        if value < current {
            copy(x, candidate)
            current = value
            failures = 0u32
        } else {
            failures += 1u32
        }
        iteration += 1u32
    }
    ret (Result { value: current, iterations: iteration }, ok)
}

// Tabu search: each iteration draws `candidates` neighbours and moves to the
// best one farther than `radius` from every point of the last `tenure` moves,
// even when worse. `x` ends at the best point seen;
// `scratch.len >= (tenure + 3) * n`.
fn tabu[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, neighbor: fn(*Ctx, *rand.Pcg64, []const f64, []f64), r: *rand.Pcg64, x: []f64, candidates: usize, tenure: usize, radius: f64, max_iterations: u32, scratch: []f64) -> (Result, err) {
    let n = x.len
    if scratch.len < (tenure + 3usize) * n { ret (zero, TooSmall) }
    if candidates == 0usize || tenure == 0usize { ret (zero, Invalid) }
    var list = scratch[..tenure * n]
    var candidate = scratch[tenure * n..(tenure + 1usize) * n]
    var chosen = scratch[(tenure + 1usize) * n..(tenure + 2usize) * n]
    var best = scratch[(tenure + 2usize) * n..(tenure + 3usize) * n]
    var best_value = f(ctx, x)
    copy(best, x)
    var stored = 0usize
    var head = 0usize
    let radius2 = radius * radius
    var iteration = 0u32
    while iteration < max_iterations {
        var found = false
        var chosen_value = 0.0f64
        var c = 0usize
        while c < candidates {
            neighbor(ctx, r, x, candidate)
            var banned = false
            var k = 0usize
            while k < stored && !banned {
                if distance2(candidate, list[k * n..(k + 1usize) * n]) <= radius2 { banned = true }
                k += 1usize
            }
            if !banned {
                let value = f(ctx, candidate)
                if !found || value < chosen_value {
                    found = true
                    chosen_value = value
                    copy(chosen, candidate)
                }
            }
            c += 1usize
        }
        if !found { ret (Result { value: best_value, iterations: iteration }, ok) }
        copy(list[head * n..(head + 1usize) * n], x)
        head = (head + 1usize) % tenure
        if stored < tenure { stored += 1usize }
        copy(x, chosen)
        if chosen_value < best_value {
            best_value = chosen_value
            copy(best, x)
        }
        iteration += 1u32
    }
    copy(x, best)
    ret (Result { value: best_value, iterations: iteration }, ok)
}

fn evaluate_all[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, population: []const f64, count: usize, n: usize, values: []f64) {
    var i = 0usize
    while i < count {
        values[i] = f(ctx, population[i * n..(i + 1usize) * n])
        i += 1usize
    }
}

fn best_of(values: []const f64, count: usize) -> usize {
    var best = 0usize
    var i = 1usize
    while i < count {
        if values[i] < values[best] { best = i }
        i += 1usize
    }
    ret best
}

// A genetic algorithm over `population` (`count` rows of `n`, already seeded):
// binary tournament selection, blend crossover, uniform mutation of each gene
// with probability `mutation_rate` by up to `mutation_scale` of the box, and
// the best row carried over unchanged. `x` receives the best row;
// `scratch.len >= count * n + 2 * count`.
fn genetic[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, r: *rand.Pcg64, population: []f64, count: usize, n: usize, low: []const f64, high: []const f64, mutation_rate: f64, mutation_scale: f64, generations: u32, x: []f64, scratch: []f64) -> (Result, err) {
    if population.len < count * n || scratch.len < count * n + 2usize * count || x.len < n || low.len < n || high.len < n { ret (zero, TooSmall) }
    if count < 2usize { ret (zero, Invalid) }
    var next = scratch[..count * n]
    var values = scratch[count * n..count * n + count]
    var next_values = scratch[count * n + count..count * n + 2usize * count]
    evaluate_all[Ctx](ctx, f, population, count, n, values)
    var generation = 0u32
    while generation < generations {
        let elite = best_of(values, count)
        copy(next[..n], population[elite * n..(elite + 1usize) * n])
        next_values[0usize] = values[elite]
        var i = 1usize
        while i < count {
            let parent_a = tournament(r, values, count)
            let parent_b = tournament(r, values, count)
            var child = next[i * n..(i + 1usize) * n]
            let mix = rand.pcg64_f64(r)
            var k = 0usize
            while k < n {
                child[k] = mix * population[parent_a * n + k] + (1.0f64 - mix) * population[parent_b * n + k]
                if rand.pcg64_f64(r) < mutation_rate {
                    child[k] += mutation_scale * (high[k] - low[k]) * (2.0f64 * rand.pcg64_f64(r) - 1.0f64)
                }
                k += 1usize
            }
            clamp(child, low, high)
            next_values[i] = f(ctx, child)
            i += 1usize
        }
        copy(population[..count * n], next)
        copy(values, next_values)
        generation += 1u32
    }
    let best = best_of(values, count)
    copy(x[..n], population[best * n..(best + 1usize) * n])
    ret (Result { value: values[best], iterations: generations }, ok)
}

fn tournament(r: *rand.Pcg64, values: []const f64, count: usize) -> usize {
    let a = usize(rand.pcg64_bounded(r, u64(count)))
    let b = usize(rand.pcg64_bounded(r, u64(count)))
    if values[a] <= values[b] { ret a }
    ret b
}

// Particle swarm over `positions` (`count` rows of `n`, already seeded) with
// the standard velocity update; `x` receives the swarm's best;
// `scratch.len >= 2 * count * n + count`.
fn particle_swarm[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, r: *rand.Pcg64, positions: []f64, count: usize, n: usize, low: []const f64, high: []const f64, inertia: f64, cognitive: f64, social: f64, iterations: u32, x: []f64, scratch: []f64) -> (Result, err) {
    if positions.len < count * n || scratch.len < 2usize * count * n + count || x.len < n || low.len < n || high.len < n { ret (zero, TooSmall) }
    if count == 0usize { ret (zero, Invalid) }
    var velocity = scratch[..count * n]
    var personal = scratch[count * n..2usize * count * n]
    var personal_values = scratch[2usize * count * n..2usize * count * n + count]
    var i = 0usize
    while i < count * n {
        velocity[i] = 0.0f64
        i += 1usize
    }
    copy(personal, positions[..count * n])
    evaluate_all[Ctx](ctx, f, positions, count, n, personal_values)
    var best = best_of(personal_values, count)
    copy(x[..n], personal[best * n..(best + 1usize) * n])
    var best_value = personal_values[best]
    var iteration = 0u32
    while iteration < iterations {
        i = 0usize
        while i < count {
            var position = positions[i * n..(i + 1usize) * n]
            var k = 0usize
            while k < n {
                let at = i * n + k
                velocity[at] = inertia * velocity[at] + cognitive * rand.pcg64_f64(r) * (personal[at] - position[k]) + social * rand.pcg64_f64(r) * (x[k] - position[k])
                position[k] += velocity[at]
                k += 1usize
            }
            clamp(position, low, high)
            let value = f(ctx, position)
            if value < personal_values[i] {
                personal_values[i] = value
                copy(personal[i * n..(i + 1usize) * n], position)
                if value < best_value {
                    best_value = value
                    copy(x[..n], position)
                }
            }
            i += 1usize
        }
        iteration += 1u32
    }
    ret (Result { value: best_value, iterations: iterations }, ok)
}

// Differential evolution (DE/rand/1/bin) over `population` (`count >= 4` rows
// of `n`, already seeded) with differential weight `weight` and crossover
// probability `crossover`; `x` receives the best row;
// `scratch.len >= n + count`.
fn differential_evolution[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, r: *rand.Pcg64, population: []f64, count: usize, n: usize, low: []const f64, high: []const f64, weight: f64, crossover: f64, generations: u32, x: []f64, scratch: []f64) -> (Result, err) {
    if population.len < count * n || scratch.len < n + count || x.len < n || low.len < n || high.len < n { ret (zero, TooSmall) }
    if count < 4usize { ret (zero, Invalid) }
    var trial = scratch[..n]
    var values = scratch[n..n + count]
    evaluate_all[Ctx](ctx, f, population, count, n, values)
    var generation = 0u32
    while generation < generations {
        var i = 0usize
        while i < count {
            var a = i
            var b = i
            var c = i
            while a == i { a = usize(rand.pcg64_bounded(r, u64(count))) }
            while b == i || b == a { b = usize(rand.pcg64_bounded(r, u64(count))) }
            while c == i || c == a || c == b { c = usize(rand.pcg64_bounded(r, u64(count))) }
            let forced = usize(rand.pcg64_bounded(r, u64(n)))
            var k = 0usize
            while k < n {
                if k == forced || rand.pcg64_f64(r) < crossover {
                    trial[k] = population[a * n + k] + weight * (population[b * n + k] - population[c * n + k])
                } else {
                    trial[k] = population[i * n + k]
                }
                k += 1usize
            }
            clamp(trial, low, high)
            let value = f(ctx, trial)
            if value <= values[i] {
                copy(population[i * n..(i + 1usize) * n], trial)
                values[i] = value
            }
            i += 1usize
        }
        generation += 1u32
    }
    let best = best_of(values, count)
    copy(x[..n], population[best * n..(best + 1usize) * n])
    ret (Result { value: values[best], iterations: generations }, ok)
}

// Ant colony optimisation for a closed tour over the `n × n` distance matrix
// `distance`: `ants` ants per iteration choose the next city by pheromone^alpha
// × (1/distance)^beta, pheromone evaporates by `evaporation` and every ant
// deposits 1/length on its tour. `tour` receives the best tour found and its
// length is answered; `scratch.len >= n * n + n`, `marks.len >= 2 * n`.
fn ant_colony(r: *rand.Pcg64, distance: []const f64, n: usize, ants: usize, alpha: f64, beta: f64, evaporation: f64, iterations: u32, tour: []usize, scratch: []f64, marks: []usize) -> (f64, err) {
    if distance.len < n * n || tour.len < n || scratch.len < n * n + n || marks.len < 2usize * n { ret (0.0f64, TooSmall) }
    if n < 2usize || ants == 0usize || evaporation < 0.0f64 || evaporation > 1.0f64 { ret (0.0f64, Invalid) }
    var pheromone = scratch[..n * n]
    var weights = scratch[n * n..n * n + n]
    var walk = marks[..n]
    var visited = marks[n..2usize * n]
    var i = 0usize
    while i < n * n {
        pheromone[i] = 1.0f64
        i += 1usize
    }
    var best_length = 0.0f64
    var have_best = false
    var iteration = 0u32
    while iteration < iterations {
        i = 0usize
        while i < n * n {
            pheromone[i] = pheromone[i] * (1.0f64 - evaporation)
            i += 1usize
        }
        var ant = 0usize
        while ant < ants {
            var k = 0usize
            while k < n {
                visited[k] = 0usize
                k += 1usize
            }
            var city = usize(rand.pcg64_bounded(r, u64(n)))
            walk[0usize] = city
            visited[city] = 1usize
            var length = 0.0f64
            var placed = 1usize
            while placed < n {
                var total = 0.0f64
                k = 0usize
                while k < n {
                    weights[k] = 0.0f64
                    if visited[k] == 0usize {
                        let d = distance[city * n + k]
                        var inverse = 1.0e12f64
                        if d > 0.0f64 { inverse = 1.0f64 / d }
                        weights[k] = math.pow[f64](pheromone[city * n + k], alpha) * math.pow[f64](inverse, beta)
                        total += weights[k]
                    }
                    k += 1usize
                }
                var pick = rand.pcg64_f64(r) * total
                var next = n
                k = 0usize
                while k < n && next == n {
                    if visited[k] == 0usize {
                        pick -= weights[k]
                        if pick <= 0.0f64 { next = k }
                    }
                    k += 1usize
                }
                if next == n {
                    k = n
                    while k > 0usize && next == n {
                        k -= 1usize
                        if visited[k] == 0usize { next = k }
                    }
                }
                length += distance[city * n + next]
                city = next
                visited[city] = 1usize
                walk[placed] = city
                placed += 1usize
            }
            length += distance[city * n + walk[0usize]]
            let deposit = 1.0f64 / length
            k = 0usize
            while k < n {
                let from = walk[k]
                let to = walk[(k + 1usize) % n]
                pheromone[from * n + to] += deposit
                pheromone[to * n + from] += deposit
                k += 1usize
            }
            if !have_best || length < best_length {
                have_best = true
                best_length = length
                k = 0usize
                while k < n {
                    tour[k] = walk[k]
                    k += 1usize
                }
            }
            ant += 1usize
        }
        iteration += 1u32
    }
    ret (best_length, ok)
}
