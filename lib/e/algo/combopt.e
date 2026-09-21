// Combinatorial optimisation in caller storage. Tours are permutations of
// `0..n` over a row-major `n × n` distance matrix: `tsp_nearest_neighbor`
// builds one, `tsp_two_opt` and `tsp_or_opt` improve one (segment
// reversal; segment relocation of one to three cities) until no move
// helps, `tsp_held_karp` is the exact dynamic programme for `n <= 16`.
// `set_cover_greedy` is Chvátal's greedy, `bin_pack_ffd` first fit
// decreasing, `vrp_savings` Clarke-Wright with a vehicle capacity,
// `knapsack_branch_and_bound` the 0/1 knapsack with the fractional bound,
// `branch_and_bound` a generic depth-first search over the caller's
// branching and bounding, and `large_neighborhood_search` repeats the
// caller's destroy and repair while a better solution appears.

use e.algo.rand

error TooSmall
error Invalid

fn at(d: []const f64, n: usize, i: usize, j: usize) -> f64 { ret d[i * n + j] }

fn tour_length(d: []const f64, n: usize, tour: []const usize) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < n {
        total += at(d, n, tour[i], tour[(i + 1usize) % n])
        i += 1usize
    }
    ret total
}

// A tour from `start`, always to the nearest unvisited city; `visited.len >= n`.
fn tsp_nearest_neighbor(d: []const f64, n: usize, start: usize, tour: []usize, visited: []u8) -> (f64, err) {
    if d.len < n * n || tour.len < n || visited.len < n { ret (0.0f64, TooSmall) }
    if n == 0usize || start >= n { ret (0.0f64, Invalid) }
    var i = 0usize
    while i < n {
        visited[i] = 0u8
        i += 1usize
    }
    tour[0usize] = start
    visited[start] = 1u8
    var placed = 1usize
    while placed < n {
        let last = tour[placed - 1usize]
        var best = n
        var j = 0usize
        while j < n {
            if visited[j] == 0u8 && (best == n || at(d, n, last, j) < at(d, n, last, best)) { best = j }
            j += 1usize
        }
        tour[placed] = best
        visited[best] = 1u8
        placed += 1usize
    }
    ret (tour_length(d, n, tour), ok)
}

fn reverse(tour: []usize, i: usize, j: usize) {
    var a = i
    var b = j
    while a < b {
        let t = tour[a]
        tour[a] = tour[b]
        tour[b] = t
        a += 1usize
        b -= 1usize
    }
}

// 2-opt: reverse the segment `i + 1 ..= j` while that shortens the tour;
// answers the length and the improving moves made.
fn tsp_two_opt(d: []const f64, n: usize, tour: []usize) -> (f64, usize, err) {
    if d.len < n * n || tour.len < n { ret (0.0f64, 0usize, TooSmall) }
    if n < 4usize { ret (tour_length(d, n, tour), 0usize, ok) }
    var moves = 0usize
    var improved = true
    while improved {
        improved = false
        var i = 0usize
        while i + 2usize < n {
            var j = i + 2usize
            while j < n && !(i == 0usize && j == n - 1usize) {
                let a = tour[i]
                let b = tour[i + 1usize]
                let c = tour[j]
                let e = tour[(j + 1usize) % n]
                let delta = at(d, n, a, c) + at(d, n, b, e) - at(d, n, a, b) - at(d, n, c, e)
                if delta < 0.0f64 - 1.0e-12f64 {
                    reverse(tour, i + 1usize, j)
                    moves += 1usize
                    improved = true
                }
                j += 1usize
            }
            i += 1usize
        }
    }
    ret (tour_length(d, n, tour), moves, ok)
}

// Or-opt: move a segment of one to three consecutive cities elsewhere
// (either orientation) while that shortens the tour; `scratch.len >= n`.
fn tsp_or_opt(d: []const f64, n: usize, tour: []usize, scratch: []usize) -> (f64, usize, err) {
    if d.len < n * n || tour.len < n || scratch.len < n { ret (0.0f64, 0usize, TooSmall) }
    if n < 5usize { ret (tour_length(d, n, tour), 0usize, ok) }
    var moves = 0usize
    var improved = true
    while improved {
        improved = false
        var length = 1usize
        while length <= 3usize && !improved {
            var i = 0usize
            while i < n && !improved {
                // Segment tour[i .. i + length) with predecessor p and successor s.
                let p = tour[(i + n - 1usize) % n]
                let first = tour[i]
                let last = tour[(i + length - 1usize) % n]
                let s = tour[(i + length) % n]
                let removed_gain = at(d, n, p, first) + at(d, n, last, s) - at(d, n, p, s)
                // Insert between tour[k] and tour[k + 1] for k outside the segment.
                var k = 0usize
                while k < n && !improved {
                    var inside = false
                    var q = 0usize
                    while q < length {
                        if (i + q) % n == k || (i + q) % n == (k + 1usize) % n { inside = true }
                        q += 1usize
                    }
                    if !inside && k != (i + n - 1usize) % n {
                        let u = tour[k]
                        let v = tour[(k + 1usize) % n]
                        let forward = at(d, n, u, first) + at(d, n, last, v) - at(d, n, u, v)
                        let backward = at(d, n, u, last) + at(d, n, first, v) - at(d, n, u, v)
                        var cost = forward
                        var flip = false
                        if backward < forward {
                            cost = backward
                            flip = true
                        }
                        if cost < removed_gain - 1.0e-12f64 {
                            // Rebuild the tour in scratch: walk from s, inserting the segment after u.
                            var m = 0usize
                            var w = (i + length) % n
                            var steps = 0usize
                            while steps < n - length {
                                scratch[m] = tour[w]
                                m += 1usize
                                if tour[w] == u {
                                    var q2 = 0usize
                                    while q2 < length {
                                        var index = i + q2
                                        if flip { index = i + length - 1usize - q2 }
                                        scratch[m] = tour[index % n]
                                        m += 1usize
                                        q2 += 1usize
                                    }
                                }
                                w = (w + 1usize) % n
                                steps += 1usize
                            }
                            var c = 0usize
                            while c < n {
                                tour[c] = scratch[c]
                                c += 1usize
                            }
                            moves += 1usize
                            improved = true
                        }
                    }
                    k += 1usize
                }
                i += 1usize
            }
            length += 1usize
        }
    }
    ret (tour_length(d, n, tour), moves, ok)
}

// Held-Karp: the optimal tour from city 0 for `n <= 16`; `table.len >= 2^n * n`
// floats and `parent.len >= 2^n * n` indices.
fn tsp_held_karp(d: []const f64, n: usize, tour: []usize, table: []f64, parent: []usize) -> (f64, err) {
    if n < 2usize || n > 16usize { ret (0.0f64, Invalid) }
    let subsets = 1usize << u32(n)
    if d.len < n * n || tour.len < n || table.len < subsets * n || parent.len < subsets * n { ret (0.0f64, TooSmall) }
    let none = 1.0e300f64
    var s = 0usize
    while s < subsets * n {
        table[s] = none
        s += 1usize
    }
    table[1usize * n + 0usize] = 0.0f64
    s = 1usize
    while s < subsets {
        if (s & 1usize) == 1usize {
            var last = 0usize
            while last < n {
                if (s >> u32(last)) & 1usize == 1usize && table[s * n + last] < none {
                    var next = 1usize
                    while next < n {
                        if (s >> u32(next)) & 1usize == 0usize {
                            let t = s | (1usize << u32(next))
                            let cost = table[s * n + last] + at(d, n, last, next)
                            if cost < table[t * n + next] {
                                table[t * n + next] = cost
                                parent[t * n + next] = last
                            }
                        }
                        next += 1usize
                    }
                }
                last += 1usize
            }
        }
        s += 1usize
    }
    let full = subsets - 1usize
    var best = none
    var last = 0usize
    var c = 1usize
    while c < n {
        let cost = table[full * n + c] + at(d, n, c, 0usize)
        if cost < best {
            best = cost
            last = c
        }
        c += 1usize
    }
    var set = full
    var position = n
    while position > 0usize {
        position -= 1usize
        tour[position] = last
        let previous = parent[set * n + last]
        set = set & (set ^ (1usize << u32(last)))
        last = previous
    }
    ret (best, ok)
}

// Chvátal: `membership` is `sets × universe` bytes; the chosen set indices
// go to `chosen` until every element with any cover is covered; `covered.len >= universe`.
fn set_cover_greedy(membership: []const u8, sets: usize, universe: usize, chosen: []usize, covered: []u8) -> (usize, err) {
    if membership.len < sets * universe || chosen.len < sets || covered.len < universe { ret (0usize, TooSmall) }
    var i = 0usize
    while i < universe {
        covered[i] = 0u8
        i += 1usize
    }
    var count = 0usize
    var progressing = true
    while progressing {
        var best = sets
        var best_new = 0usize
        var s = 0usize
        while s < sets {
            var fresh = 0usize
            i = 0usize
            while i < universe {
                if membership[s * universe + i] != 0u8 && covered[i] == 0u8 { fresh += 1usize }
                i += 1usize
            }
            if fresh > best_new {
                best_new = fresh
                best = s
            }
            s += 1usize
        }
        if best == sets {
            progressing = false
        } else {
            chosen[count] = best
            count += 1usize
            i = 0usize
            while i < universe {
                if membership[best * universe + i] != 0u8 { covered[i] = 1u8 }
                i += 1usize
            }
        }
    }
    ret (count, ok)
}

// First fit decreasing over `capacity`; `bins` receives the bin of each
// item, `loads.len >= items` the bin loads; answers the bin count.
// `order.len >= items`.
fn bin_pack_ffd(sizes: []const f64, capacity: f64, bins: []usize, loads: []f64, order: []usize) -> (usize, err) {
    let n = sizes.len
    if bins.len < n || loads.len < n || order.len < n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        if sizes[i] > capacity || sizes[i] < 0.0f64 { ret (0usize, Invalid) }
        order[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = order[i]
        var k = i
        while k > 0usize && sizes[order[k - 1usize]] < sizes[v] {
            order[k] = order[k - 1usize]
            k -= 1usize
        }
        order[k] = v
        i += 1usize
    }
    var count = 0usize
    i = 0usize
    while i < n {
        let item = order[i]
        var b = 0usize
        while b < count && loads[b] + sizes[item] > capacity + 1.0e-12f64 { b += 1usize }
        if b == count {
            loads[count] = 0.0f64
            count += 1usize
        }
        loads[b] += sizes[item]
        bins[item] = b
        i += 1usize
    }
    ret (count, ok)
}

// Clarke-Wright: customers `1..n` with `demand` served from depot 0 by
// vehicles of `capacity`; routes merge at their ends in order of falling
// saving `d(0,i) + d(0,j) - d(i,j)`. `route` receives each customer's route
// id, `next`/`previous` the chain within a route (0 marks an end), and
// `load.len >= n` the route loads; `savings.len >= n * n` and
// `order.len >= n * n` sort the pairs. Answers the route count.
fn vrp_savings(d: []const f64, n: usize, demand: []const f64, capacity: f64, route: []usize, next: []usize, previous: []usize, load: []f64, savings: []f64, order: []usize) -> (usize, err) {
    if d.len < n * n || demand.len < n || route.len < n || next.len < n || previous.len < n || load.len < n || savings.len < n * n || order.len < n * n { ret (0usize, TooSmall) }
    if n < 2usize { ret (0usize, Invalid) }
    var i = 1usize
    while i < n {
        if demand[i] > capacity { ret (0usize, Invalid) }
        route[i] = i
        next[i] = 0usize
        previous[i] = 0usize
        load[i] = demand[i]
        i += 1usize
    }
    var pairs = 0usize
    i = 1usize
    while i < n {
        var j = i + 1usize
        while j < n {
            savings[pairs] = at(d, n, 0usize, i) + at(d, n, 0usize, j) - at(d, n, i, j)
            order[pairs] = i * n + j
            pairs += 1usize
            j += 1usize
        }
        i += 1usize
    }
    // Sort pair indices by falling saving (insertion sort over the saving values kept alongside).
    i = 1usize
    while i < pairs {
        let o = order[i]
        let s = savings[i]
        var k = i
        while k > 0usize && savings[k - 1usize] < s {
            order[k] = order[k - 1usize]
            savings[k] = savings[k - 1usize]
            k -= 1usize
        }
        order[k] = o
        savings[k] = s
        i += 1usize
    }
    var routes = n - 1usize
    var p = 0usize
    while p < pairs {
        let a = order[p] / n
        let b = order[p] % n
        if route[a] != route[b] && savings[p] > 0.0f64 {
            // Both must be route ends: a with a free tail and b with a free head, or the reverse.
            var head = 0usize
            var tail = 0usize
            if next[a] == 0usize && previous[b] == 0usize {
                tail = a
                head = b
            } else if next[b] == 0usize && previous[a] == 0usize {
                tail = b
                head = a
            }
            if head != 0usize && load[route[tail]] + load[route[head]] <= capacity {
                next[tail] = head
                previous[head] = tail
                let from = route[head]
                let into = route[tail]
                load[into] += load[from]
                var c = head
                while c != 0usize {
                    route[c] = into
                    c = next[c]
                }
                routes -= 1usize
            }
        }
        p += 1usize
    }
    ret (routes, ok)
}

// 0/1 knapsack by branch and bound: items sorted by value density, the
// fractional relaxation as the bound; `taken` receives the best subset,
// `order.len >= items`, `current.len >= items` scratch. Answers the best value.
fn knapsack_branch_and_bound(weights: []const f64, values: []const f64, capacity: f64, taken: []u8, order: []usize, current: []u8) -> (f64, err) {
    let n = weights.len
    if values.len < n || taken.len < n || order.len < n || current.len < n { ret (0.0f64, TooSmall) }
    var i = 0usize
    while i < n {
        if weights[i] < 0.0f64 { ret (0.0f64, Invalid) }
        order[i] = i
        taken[i] = 0u8
        current[i] = 0u8
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = order[i]
        var k = i
        while k > 0usize && density(weights, values, order[k - 1usize]) < density(weights, values, v) {
            order[k] = order[k - 1usize]
            k -= 1usize
        }
        order[k] = v
        i += 1usize
    }
    var best = 0.0f64
    let (found, _) = knapsack_search(weights, values, capacity, order, 0usize, 0.0f64, 0.0f64, best, current, taken)
    best = found
    ret (best, ok)
}

fn density(weights: []const f64, values: []const f64, i: usize) -> f64 {
    if weights[i] <= 0.0f64 { ret 1.0e300f64 }
    ret values[i] / weights[i]
}

fn knapsack_bound(weights: []const f64, values: []const f64, capacity: f64, order: []const usize, from: usize, weight: f64, value: f64) -> f64 {
    var room = capacity - weight
    var bound = value
    var i = from
    while i < order.len && room > 0.0f64 {
        let item = order[i]
        if weights[item] <= room {
            room -= weights[item]
            bound += values[item]
        } else {
            bound += values[item] * room / weights[item]
            room = 0.0f64
        }
        i += 1usize
    }
    ret bound
}

fn knapsack_search(weights: []const f64, values: []const f64, capacity: f64, order: []const usize, from: usize, weight: f64, value: f64, best: f64, current: []u8, taken: []u8) -> (f64, bool) {
    var record = best
    var improved = false
    if value > record {
        record = value
        improved = true
        var i = 0usize
        while i < taken.len {
            taken[i] = current[i]
            i += 1usize
        }
    }
    if from >= order.len { ret (record, improved) }
    if knapsack_bound(weights, values, capacity, order, from, weight, value) <= record { ret (record, improved) }
    let item = order[from]
    if weight + weights[item] <= capacity {
        current[item] = 1u8
        let (with, with_improved) = knapsack_search(weights, values, capacity, order, from + 1usize, weight + weights[item], value + values[item], record, current, taken)
        if with_improved { improved = true }
        record = with
        current[item] = 0u8
    }
    let (without, without_improved) = knapsack_search(weights, values, capacity, order, from + 1usize, weight, value, record, current, taken)
    if without_improved { improved = true }
    ret (without, improved)
}

// Generic branch and bound (minimisation): `bound(ctx, depth)` answers a lower
// bound for the partial solution at `depth` (the caller's state), `branch(ctx,
// depth, i)` applies the i-th of `choices(ctx, depth)` choices and `undo(ctx,
// depth, i)` reverts it; a partial solution at `depth == leaf_depth(ctx)` is
// complete with cost `bound`. Answers the best cost found and the leaves reached.
fn branch_and_bound[Ctx: type](ctx: *Ctx, leaf_depth: fn(*Ctx) -> usize, choices: fn(*Ctx, usize) -> usize, bound: fn(*Ctx, usize) -> f64, branch: fn(*Ctx, usize, usize), undo: fn(*Ctx, usize, usize), record: fn(*Ctx), start: f64) -> (f64, usize) {
    let (best, leaves) = bb_search[Ctx](ctx, leaf_depth, choices, bound, branch, undo, record, 0usize, start)
    ret (best, leaves)
}

fn bb_search[Ctx: type](ctx: *Ctx, leaf_depth: fn(*Ctx) -> usize, choices: fn(*Ctx, usize) -> usize, bound: fn(*Ctx, usize) -> f64, branch: fn(*Ctx, usize, usize), undo: fn(*Ctx, usize, usize), record: fn(*Ctx), depth: usize, best: f64) -> (f64, usize) {
    let b = bound(ctx, depth)
    if b >= best { ret (best, 0usize) }
    if depth == leaf_depth(ctx) {
        record(ctx)
        ret (b, 1usize)
    }
    var incumbent = best
    var leaves = 0usize
    let count = choices(ctx, depth)
    var i = 0usize
    while i < count {
        branch(ctx, depth, i)
        let (found, seen) = bb_search[Ctx](ctx, leaf_depth, choices, bound, branch, undo, record, depth + 1usize, incumbent)
        undo(ctx, depth, i)
        incumbent = found
        leaves += seen
        i += 1usize
    }
    ret (incumbent, leaves)
}

// Large neighbourhood search: `destroy(ctx, r)` frees part of the current
// solution, `repair(ctx, r)` rebuilds it and answers its cost; a worse
// result is undone by `restore(ctx)`, a better one kept by `accept(ctx)`.
// Answers the best cost after `iterations` and how many improved.
fn large_neighborhood_search[Ctx: type](ctx: *Ctx, r: *rand.Pcg64, iterations: usize, start: f64, destroy: fn(*Ctx, *rand.Pcg64), repair: fn(*Ctx, *rand.Pcg64) -> f64, accept: fn(*Ctx), restore: fn(*Ctx)) -> (f64, usize) {
    var best = start
    var improvements = 0usize
    var i = 0usize
    while i < iterations {
        destroy(ctx, r)
        let cost = repair(ctx, r)
        if cost < best - 1.0e-12f64 {
            best = cost
            improvements += 1usize
            accept(ctx)
        } else {
            restore(ctx)
        }
        i += 1usize
    }
    ret (best, improvements)
}
