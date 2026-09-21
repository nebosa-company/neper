// Markov chain Monte Carlo over `f64` vectors in caller storage: random-walk
// Metropolis-Hastings, Gibbs sampling through the caller's conditional draw,
// Hamiltonian Monte Carlo with a fixed leapfrog trajectory, and the No-U-Turn
// sampler (Hoffman and Gelman's algorithm 3, the slice form) over a caller's
// unnormalised log density and its gradient.
//
// Every sampler starts from the caller's `x`, writes `count` rows of `n` into
// `samples` (the chain itself, repeats included) and leaves `x` at the last
// state. Draws come from a `*rand.Pcg64`; scratch is the caller's, sized per
// declaration.

use e.algo.rand
use e.algo.rand.dist
use e.math

type Chain = struct { accepted: usize, proposed: usize }
error TooSmall
error Invalid

fn copy(out: []f64, from: []const f64) {
    var i = 0usize
    while i < out.len {
        out[i] = from[i]
        i += 1usize
    }
}

fn dot(a: []const f64, b: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < a.len {
        sum += a[i] * b[i]
        i += 1usize
    }
    ret sum
}

// Random-walk Metropolis-Hastings with an isotropic normal proposal of scale
// `step`; `scratch.len >= n`.
fn metropolis_hastings[Ctx: type](ctx: *Ctx, log_density: fn(*Ctx, []const f64) -> f64, r: *rand.Pcg64, x: []f64, step: f64, samples: []f64, count: usize, scratch: []f64) -> (Chain, err) {
    let n = x.len
    if samples.len < count * n || scratch.len < n { ret (zero, TooSmall) }
    var candidate = scratch[..n]
    var current = log_density(ctx, x)
    var accepted = 0usize
    var i = 0usize
    while i < count {
        var k = 0usize
        while k < n {
            candidate[k] = x[k] + step * dist.normal(r)
            k += 1usize
        }
        let proposed = log_density(ctx, candidate)
        if proposed >= current || rand.pcg64_f64(r) < math.exp[f64](proposed - current) {
            copy(x, candidate)
            current = proposed
            accepted += 1usize
        }
        copy(samples[i * n..(i + 1usize) * n], x)
        i += 1usize
    }
    ret (Chain { accepted: accepted, proposed: count }, ok)
}

// Gibbs sampling: `draw(ctx, r, k, x)` replaces `x[k]` with a draw from its
// conditional given the rest; one sweep over every coordinate is one sample.
fn gibbs[Ctx: type](ctx: *Ctx, draw: fn(*Ctx, *rand.Pcg64, usize, []f64), r: *rand.Pcg64, x: []f64, samples: []f64, count: usize) -> err {
    let n = x.len
    if samples.len < count * n { ret TooSmall }
    var i = 0usize
    while i < count {
        var k = 0usize
        while k < n {
            draw(ctx, r, k, x)
            k += 1usize
        }
        copy(samples[i * n..(i + 1usize) * n], x)
        i += 1usize
    }
    ret ok
}

// One leapfrog step of size `step` on (`x`, `p`) with `gradient` as scratch.
fn leapfrog[Ctx: type](ctx: *Ctx, g: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, gradient: []f64, step: f64) {
    g(ctx, x, gradient)
    var k = 0usize
    while k < x.len {
        p[k] += 0.5f64 * step * gradient[k]
        x[k] += step * p[k]
        k += 1usize
    }
    g(ctx, x, gradient)
    k = 0usize
    while k < x.len {
        p[k] += 0.5f64 * step * gradient[k]
        k += 1usize
    }
}

// Hamiltonian Monte Carlo: a fresh standard-normal momentum, `leaps`
// leapfrog steps of `step`, and a Metropolis acceptance on the Hamiltonian;
// `scratch.len >= 3 * n`.
fn hmc[Ctx: type](ctx: *Ctx, log_density: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), r: *rand.Pcg64, x: []f64, step: f64, leaps: usize, samples: []f64, count: usize, scratch: []f64) -> (Chain, err) {
    let n = x.len
    if samples.len < count * n || scratch.len < 3usize * n { ret (zero, TooSmall) }
    if leaps == 0usize || step <= 0.0f64 { ret (zero, Invalid) }
    var candidate = scratch[..n]
    var p = scratch[n..2usize * n]
    var gradient = scratch[2usize * n..3usize * n]
    var current = log_density(ctx, x)
    var accepted = 0usize
    var i = 0usize
    while i < count {
        copy(candidate, x)
        var k = 0usize
        while k < n {
            p[k] = dist.normal(r)
            k += 1usize
        }
        let kinetic_before = 0.5f64 * dot(p, p)
        var leap = 0usize
        while leap < leaps {
            leapfrog[Ctx](ctx, g, candidate, p, gradient, step)
            leap += 1usize
        }
        let proposed = log_density(ctx, candidate)
        let change = (proposed - 0.5f64 * dot(p, p)) - (current - kinetic_before)
        if change >= 0.0f64 || rand.pcg64_f64(r) < math.exp[f64](change) {
            copy(x, candidate)
            current = proposed
            accepted += 1usize
        }
        copy(samples[i * n..(i + 1usize) * n], x)
        i += 1usize
    }
    ret (Chain { accepted: accepted, proposed: count }, ok)
}

// A NUTS tree record in scratch: the leftmost point and momentum, the
// rightmost point and momentum, and the proposed point, five rows of `n`.
fn tree_row(record: []f64, row: usize, n: usize) -> []f64 { ret record[row * n..(row + 1usize) * n] }

fn no_u_turn(record: []f64, n: usize) -> bool {
    let left = tree_row(record, 0usize, n)
    let left_p = tree_row(record, 1usize, n)
    let right = tree_row(record, 2usize, n)
    let right_p = tree_row(record, 3usize, n)
    var with_left = 0.0f64
    var with_right = 0.0f64
    var k = 0usize
    while k < n {
        let d = right[k] - left[k]
        with_left += d * left_p[k]
        with_right += d * right_p[k]
        k += 1usize
    }
    ret with_left >= 0.0f64 && with_right >= 0.0f64
}

// Build the subtree of depth `depth` from (`x`, `p`) in direction `direction`
// into `out`; `regions` holds one record per lower depth for the second
// child, `gradient` and `momentum` are shared work rows. Answers the number
// of acceptable points and whether the tree may still grow.
fn build_tree[Ctx: type](ctx: *Ctx, log_density: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), r: *rand.Pcg64, x: []const f64, p: []const f64, log_slice: f64, direction: f64, depth: usize, step: f64, out: []f64, regions: []f64, gradient: []f64, momentum: []f64, n: usize) -> (usize, bool) {
    if depth == 0usize {
        var point = tree_row(out, 4usize, n)
        copy(point, x)
        copy(momentum, p)
        leapfrog[Ctx](ctx, g, point, momentum, gradient, direction * step)
        let joint = log_density(ctx, point) - 0.5f64 * dot(momentum, momentum)
        copy(tree_row(out, 0usize, n), point)
        copy(tree_row(out, 1usize, n), momentum)
        copy(tree_row(out, 2usize, n), point)
        copy(tree_row(out, 3usize, n), momentum)
        var acceptable = 0usize
        if log_slice <= joint { acceptable = 1usize }
        ret (acceptable, log_slice < joint + 1000.0f64)
    }
    let (first, first_ok) = build_tree[Ctx](ctx, log_density, g, r, x, p, log_slice, direction, depth - 1usize, step, out, regions, gradient, momentum, n)
    var acceptable = first
    var growing = first_ok
    if growing {
        var child = regions[(depth - 1usize) * 5usize * n..depth * 5usize * n]
        var second = 0usize
        var second_ok = false
        if direction < 0.0f64 {
            let (s, s_ok) = build_tree[Ctx](ctx, log_density, g, r, tree_row(out, 0usize, n), tree_row(out, 1usize, n), log_slice, direction, depth - 1usize, step, child, regions, gradient, momentum, n)
            second = s
            second_ok = s_ok
            copy(tree_row(out, 0usize, n), tree_row(child, 0usize, n))
            copy(tree_row(out, 1usize, n), tree_row(child, 1usize, n))
        } else {
            let (s, s_ok) = build_tree[Ctx](ctx, log_density, g, r, tree_row(out, 2usize, n), tree_row(out, 3usize, n), log_slice, direction, depth - 1usize, step, child, regions, gradient, momentum, n)
            second = s
            second_ok = s_ok
            copy(tree_row(out, 2usize, n), tree_row(child, 2usize, n))
            copy(tree_row(out, 3usize, n), tree_row(child, 3usize, n))
        }
        if second > 0usize && rand.pcg64_f64(r) * f64(acceptable + second) < f64(second) {
            copy(tree_row(out, 4usize, n), tree_row(child, 4usize, n))
        }
        growing = second_ok && no_u_turn(out, n)
        acceptable += second
    }
    ret (acceptable, growing)
}

// The No-U-Turn sampler with step size `step` and trees of at most
// `max_depth` doublings; `scratch.len >= (5 * max_depth + 14) * n`.
fn nuts[Ctx: type](ctx: *Ctx, log_density: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), r: *rand.Pcg64, x: []f64, step: f64, max_depth: usize, samples: []f64, count: usize, scratch: []f64) -> (Chain, err) {
    let n = x.len
    if samples.len < count * n || scratch.len < (5usize * max_depth + 14usize) * n { ret (zero, TooSmall) }
    if step <= 0.0f64 || max_depth == 0usize { ret (zero, Invalid) }
    var regions = scratch[..max_depth * 5usize * n]
    var at = max_depth * 5usize * n
    var top = scratch[at..at + 5usize * n]
    at += 5usize * n
    var trajectory = scratch[at..at + 5usize * n]
    at += 5usize * n
    var gradient = scratch[at..at + n]
    at += n
    var momentum = scratch[at..at + n]
    at += n
    var p0 = scratch[at..at + n]
    at += n
    var chosen = scratch[at..at + n]
    var accepted = 0usize
    var i = 0usize
    while i < count {
        var k = 0usize
        while k < n {
            p0[k] = dist.normal(r)
            k += 1usize
        }
        var u = rand.pcg64_f64(r)
        while u == 0.0f64 { u = rand.pcg64_f64(r) }
        let log_slice = log_density(ctx, x) - 0.5f64 * dot(p0, p0) + math.log[f64](u)
        copy(tree_row(trajectory, 0usize, n), x)
        copy(tree_row(trajectory, 1usize, n), p0)
        copy(tree_row(trajectory, 2usize, n), x)
        copy(tree_row(trajectory, 3usize, n), p0)
        copy(chosen, x)
        var total = 1usize
        var depth = 0usize
        var growing = true
        var moved = false
        while growing && depth < max_depth {
            var direction = 1.0f64
            if rand.pcg64_f64(r) < 0.5f64 { direction = 0.0f64 - 1.0f64 }
            var fresh = 0usize
            var fresh_ok = false
            if direction < 0.0f64 {
                let (f, f_ok) = build_tree[Ctx](ctx, log_density, g, r, tree_row(trajectory, 0usize, n), tree_row(trajectory, 1usize, n), log_slice, direction, depth, step, top, regions, gradient, momentum, n)
                fresh = f
                fresh_ok = f_ok
                copy(tree_row(trajectory, 0usize, n), tree_row(top, 0usize, n))
                copy(tree_row(trajectory, 1usize, n), tree_row(top, 1usize, n))
            } else {
                let (f, f_ok) = build_tree[Ctx](ctx, log_density, g, r, tree_row(trajectory, 2usize, n), tree_row(trajectory, 3usize, n), log_slice, direction, depth, step, top, regions, gradient, momentum, n)
                fresh = f
                fresh_ok = f_ok
                copy(tree_row(trajectory, 2usize, n), tree_row(top, 2usize, n))
                copy(tree_row(trajectory, 3usize, n), tree_row(top, 3usize, n))
            }
            if fresh_ok && rand.pcg64_f64(r) * f64(total) < f64(fresh) {
                copy(chosen, tree_row(top, 4usize, n))
                moved = true
            }
            total += fresh
            growing = fresh_ok && no_u_turn(trajectory, n)
            depth += 1usize
        }
        copy(x, chosen)
        if moved { accepted += 1usize }
        copy(samples[i * n..(i + 1usize) * n], x)
        i += 1usize
    }
    ret (Chain { accepted: accepted, proposed: count }, ok)
}
