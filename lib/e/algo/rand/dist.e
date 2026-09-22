// Random variates over `e.algo.rand`'s PCG generator: the normal by the polar
// method and by Box-Muller, exponential, Poisson, binomial, gamma, beta,
// Dirichlet, a multivariate normal from a covariance, inverse-transform and
// rejection sampling over caller-supplied functions, the alias table for a
// discrete distribution, weighted reservoir sampling, stratified and Latin
// hypercube designs, and the Sobol and Halton low-discrepancy sequences.
//
// Every variate draws from a `*rand.Pcg64`; nothing here keeps hidden state
// except the alias table and the reservoir, which live in caller storage.

use e.algo.rand
use e.math
use e.math.special

type Alias = struct { probability: []f64, alias: []usize }
type WeightedReservoir = struct { items: []u64, keys: []f64, count: usize }
error TooSmall
error Invalid

// A uniform variate in the open interval (0, 1).
fn uniform_open(r: *rand.Pcg64) -> f64 {
    var u = rand.pcg64_f64(r)
    while u == 0.0f64 { u = rand.pcg64_f64(r) }
    ret u
}

// A standard normal by Marsaglia's polar method.
fn normal(r: *rand.Pcg64) -> f64 {
    while true {
        let u = 2.0f64 * rand.pcg64_f64(r) - 1.0f64
        let v = 2.0f64 * rand.pcg64_f64(r) - 1.0f64
        let s = u * u + v * v
        if s > 0.0f64 && s < 1.0f64 {
            ret u * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s) / s)
        }
    }
    ret 0.0f64
}

// Two independent standard normals by the Box-Muller transform.
fn normal_box_muller(r: *rand.Pcg64) -> (f64, f64) {
    let u1 = uniform_open(r)
    let u2 = rand.pcg64_f64(r)
    let radius = math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](u1))
    let angle = 6.283185307179586f64 * u2
    ret (radius * math.cos[f64](angle), radius * math.sin[f64](angle))
}

fn exponential(r: *rand.Pcg64, rate: f64) -> f64 {
    ret 0.0f64 - math.log[f64](uniform_open(r)) / rate
}

// Poisson by Knuth's product for small means and a normal approximation with
// rounding above 500.
fn poisson(r: *rand.Pcg64, mean: f64) -> u64 {
    if mean <= 0.0f64 { ret 0u64 }
    if mean > 500.0f64 {
        let x = mean + math.sqrt[f64](mean) * normal(r) + 0.5f64
        if x < 0.0f64 { ret 0u64 }
        ret u64(x)
    }
    let limit = math.exp[f64](0.0f64 - mean)
    var k = 0u64
    var product = rand.pcg64_f64(r)
    while product > limit {
        k += 1u64
        product = product * rand.pcg64_f64(r)
    }
    ret k
}

// Binomial by inversion for small `n * p` and by the normal approximation with
// continuity correction otherwise (exact enough for sampling; not BTPE).
fn binomial(r: *rand.Pcg64, n: u64, p: f64) -> u64 {
    if n == 0u64 || p <= 0.0f64 { ret 0u64 }
    if p >= 1.0f64 { ret n }
    let mean = f64(n) * p
    if mean < 30.0f64 || f64(n) * (1.0f64 - p) < 30.0f64 {
        // Inversion over the CDF.
        let q = 1.0f64 - p
        var probability = 1.0f64
        var i = 0u64
        while i < n {
            probability = probability * q
            i += 1u64
        }
        var u = rand.pcg64_f64(r)
        var k = 0u64
        var cumulative = probability
        while u > cumulative && k < n {
            k += 1u64
            probability = probability * (f64(n - k + 1u64) / f64(k)) * (p / q)
            cumulative += probability
        }
        ret k
    }
    let x = mean + math.sqrt[f64](mean * (1.0f64 - p)) * normal(r) + 0.5f64
    if x < 0.0f64 { ret 0u64 }
    if x > f64(n) { ret n }
    ret u64(x)
}

// Gamma with shape `k > 0` and scale `theta` by Marsaglia and Tsang, with the
// shape-below-one boost.
fn gamma(r: *rand.Pcg64, shape: f64, scale: f64) -> f64 {
    if shape <= 0.0f64 || scale <= 0.0f64 { ret 0.0f64 }
    if shape < 1.0f64 {
        let boosted = gamma(r, shape + 1.0f64, 1.0f64)
        ret boosted * math.pow[f64](uniform_open(r), 1.0f64 / shape) * scale
    }
    let d = shape - 1.0f64 / 3.0f64
    let c = 1.0f64 / math.sqrt[f64](9.0f64 * d)
    while true {
        var x = 0.0f64
        var v = 0.0f64
        while true {
            x = normal(r)
            v = 1.0f64 + c * x
            if v > 0.0f64 { break }
        }
        v = v * v * v
        let u = uniform_open(r)
        if u < 1.0f64 - 0.0331f64 * x * x * x * x { ret d * v * scale }
        if math.log[f64](u) < 0.5f64 * x * x + d * (1.0f64 - v + math.log[f64](v)) { ret d * v * scale }
    }
    ret 0.0f64
}

fn beta(r: *rand.Pcg64, alpha: f64, b: f64) -> f64 {
    let x = gamma(r, alpha, 1.0f64)
    let y = gamma(r, b, 1.0f64)
    if x + y == 0.0f64 { ret 0.5f64 }
    ret x / (x + y)
}

// A Dirichlet variate with concentrations `alphas`, written to `out`.
fn dirichlet(r: *rand.Pcg64, alphas: []const f64, out: []f64) -> err {
    if out.len < alphas.len || alphas.len == 0usize { ret TooSmall }
    var sum = 0.0f64
    var i = 0usize
    while i < alphas.len {
        out[i] = gamma(r, alphas[i], 1.0f64)
        sum += out[i]
        i += 1usize
    }
    if sum == 0.0f64 { ret Invalid }
    i = 0usize
    while i < alphas.len {
        out[i] = out[i] / sum
        i += 1usize
    }
    ret ok
}

// The Cholesky factor of a symmetric positive-definite `n x n` matrix in
// row-major order, written lower-triangular into `factor`.
fn cholesky(covariance: []const f64, n: usize, factor: []f64) -> err {
    if covariance.len < n * n || factor.len < n * n { ret TooSmall }
    var i = 0usize
    while i < n * n {
        factor[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var sum = covariance[i * n + j]
            var k = 0usize
            while k < j {
                sum -= factor[i * n + k] * factor[j * n + k]
                k += 1usize
            }
            if i == j {
                if sum <= 0.0f64 { ret Invalid }
                factor[i * n + i] = math.sqrt[f64](sum)
            } else {
                factor[i * n + j] = sum / factor[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// A multivariate normal variate from the mean and a Cholesky factor (see
// `cholesky`); `scratch.len >= n` holds the standard normals.
fn multivariate_normal(r: *rand.Pcg64, mean: []const f64, factor: []const f64, n: usize, out: []f64, scratch: []f64) -> err {
    if mean.len < n || factor.len < n * n || out.len < n || scratch.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        scratch[i] = normal(r)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var sum = mean[i]
        var j = 0usize
        while j <= i {
            sum += factor[i * n + j] * scratch[j]
            j += 1usize
        }
        out[i] = sum
        i += 1usize
    }
    ret ok
}

// Inverse transform sampling: `quantile(ctx, u)` maps a uniform in (0, 1).
fn inverse_transform[Ctx: type](r: *rand.Pcg64, ctx: *Ctx, quantile: fn(*Ctx, f64) -> f64) -> f64 {
    ret quantile(ctx, uniform_open(r))
}

// Rejection sampling over `low..high` with a density bounded by `bound`:
// `density(ctx, x)` is evaluated at uniform proposals until one is accepted.
// Answers `false` after `max_tries` rejections.
fn rejection[Ctx: type](r: *rand.Pcg64, low: f64, high: f64, bound: f64, max_tries: u32, ctx: *Ctx, density: fn(*Ctx, f64) -> f64) -> (f64, bool) {
    var tries = 0u32
    while tries < max_tries {
        let x = low + (high - low) * rand.pcg64_f64(r)
        let y = bound * rand.pcg64_f64(r)
        if y < density(ctx, x) { ret (x, true) }
        tries += 1u32
    }
    ret (low, false)
}

// The importance weight `target(x) / proposal(x)` of a sample.
fn importance_weight[Ctx: type](x: f64, ctx: *Ctx, target_density: fn(*Ctx, f64) -> f64, proposal_density: fn(*Ctx, f64) -> f64) -> f64 {
    let q = proposal_density(ctx, x)
    if q == 0.0f64 { ret 0.0f64 }
    ret target_density(ctx, x) / q
}

// Walker's alias table over `weights` (any positive scale); both slices need
// `weights.len` entries, and `scratch` as many too.
fn alias_build(weights: []const f64, probability: []f64, alias: []usize, scratch: []usize) -> (Alias, err) {
    let n = weights.len
    if n == 0usize { ret (zero, Invalid) }
    if probability.len < n || alias.len < n || scratch.len < n { ret (zero, TooSmall) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        if weights[i] < 0.0f64 { ret (zero, Invalid) }
        total += weights[i]
        i += 1usize
    }
    if total <= 0.0f64 { ret (zero, Invalid) }
    i = 0usize
    while i < n {
        probability[i] = weights[i] * f64(n) / total
        alias[i] = i
        i += 1usize
    }
    // Two stacks share `scratch`: small from the front, large from the back.
    var small_top = 0usize
    var large_bottom = n
    i = 0usize
    while i < n {
        if probability[i] < 1.0f64 {
            scratch[small_top] = i
            small_top += 1usize
        } else {
            large_bottom -= 1usize
            scratch[large_bottom] = i
        }
        i += 1usize
    }
    while small_top > 0usize && large_bottom < n {
        small_top -= 1usize
        let s = scratch[small_top]
        let l = scratch[large_bottom]
        large_bottom += 1usize
        alias[s] = l
        probability[l] = probability[l] + probability[s] - 1.0f64
        if probability[l] < 1.0f64 {
            scratch[small_top] = l
            small_top += 1usize
        } else {
            large_bottom -= 1usize
            scratch[large_bottom] = l
        }
    }
    while small_top > 0usize {
        small_top -= 1usize
        probability[scratch[small_top]] = 1.0f64
    }
    while large_bottom < n {
        probability[scratch[large_bottom]] = 1.0f64
        large_bottom += 1usize
    }
    ret (Alias { probability: probability[..n], alias: alias[..n] }, ok)
}

// An index drawn in `O(1)`.
fn alias_sample(t: *const Alias, r: *rand.Pcg64) -> usize {
    let column = usize(rand.pcg64_bounded(r, u64(t.probability.len)))
    if rand.pcg64_f64(r) < t.probability[column] { ret column }
    ret t.alias[column]
}

// Weighted reservoir sampling (Efraimidis-Spirakis): keeps the `items.len`
// keys with the largest `u^(1/w)`; `keys` as long as `items`.
fn weighted_reservoir(items: []u64, keys: []f64) -> (WeightedReservoir, err) {
    if keys.len < items.len || items.len == 0usize { ret (zero, TooSmall) }
    ret (WeightedReservoir { items: items, keys: keys[..items.len], count: 0usize }, ok)
}

fn weighted_reservoir_offer(s: *WeightedReservoir, r: *rand.Pcg64, item: u64, weight: f64) {
    if weight <= 0.0f64 { ret }
    let key = math.pow[f64](uniform_open(r), 1.0f64 / weight)
    if s.count < s.items.len {
        s.items[s.count] = item
        s.keys[s.count] = key
        s.count += 1usize
        ret
    }
    // Replace the smallest key when the new one beats it.
    var least = 0usize
    var i = 1usize
    while i < s.count {
        if s.keys[i] < s.keys[least] { least = i }
        i += 1usize
    }
    if key > s.keys[least] {
        s.items[least] = item
        s.keys[least] = key
    }
}

// Stratified sampling of `out.len` points in (0, 1): one uniform per stratum.
fn stratified(r: *rand.Pcg64, out: []f64) {
    let n = out.len
    var i = 0usize
    while i < n {
        out[i] = (f64(i) + rand.pcg64_f64(r)) / f64(n)
        i += 1usize
    }
}

// Latin hypercube: `points` rows of `dims` columns (row-major), each column a
// shuffled stratified sample; `scratch.len >= points`.
fn latin_hypercube(r: *rand.Pcg64, points: usize, dims: usize, out: []f64, scratch: []usize) -> err {
    if out.len < points * dims || scratch.len < points { ret TooSmall }
    var d = 0usize
    while d < dims {
        var i = 0usize
        while i < points {
            scratch[i] = i
            i += 1usize
        }
        rand.shuffle[usize](r, scratch[..points])
        i = 0usize
        while i < points {
            out[i * dims + d] = (f64(scratch[i]) + rand.pcg64_f64(r)) / f64(points)
            i += 1usize
        }
        d += 1usize
    }
    ret ok
}

// The van der Corput radical inverse of `index` in `base`.
fn radical_inverse(index: u64, base: u64) -> f64 {
    var result = 0.0f64
    var denominator = 1.0f64
    var n = index
    while n > 0u64 {
        denominator = denominator * f64(base)
        result += f64(n % base) / denominator
        n = n / base
    }
    ret result
}

// The `index`-th Halton point in `out.len` dimensions (bases 2, 3, 5, 7, ...).
fn halton(index: u64, out: []f64) -> err {
    var primes: [16]u64 = zero
    primes[0usize] = 2u64
    primes[1usize] = 3u64
    primes[2usize] = 5u64
    primes[3usize] = 7u64
    primes[4usize] = 11u64
    primes[5usize] = 13u64
    primes[6usize] = 17u64
    primes[7usize] = 19u64
    primes[8usize] = 23u64
    primes[9usize] = 29u64
    primes[10usize] = 31u64
    primes[11usize] = 37u64
    primes[12usize] = 41u64
    primes[13usize] = 43u64
    primes[14usize] = 47u64
    primes[15usize] = 53u64
    if out.len > 16usize { ret Invalid }
    var d = 0usize
    while d < out.len {
        out[d] = radical_inverse(index, primes[d])
        d += 1usize
    }
    ret ok
}

// The `index`-th Sobol point in up to four dimensions, from the direction
// numbers of Joe and Kuo's first three polynomials (dimension 1 is van der
// Corput in base 2).
fn sobol(index: u64, out: []f64) -> err {
    if out.len > 4usize { ret Invalid }
    // Gray-code form: the point differs from its predecessor in one direction.
    let gray = index ^ (index >> 1u64)
    var d = 0usize
    while d < out.len {
        var x = 0u64
        var bit = 0u64
        while bit < 32u64 {
            if ((gray >> bit) & 1u64) == 1u64 { x = x ^ direction(d, bit) }
            bit += 1u64
        }
        out[d] = f64(x) / 4294967296.0f64
        d += 1usize
    }
    ret ok
}

// Direction number `bit` of dimension `d` as a 32-bit fraction.
fn direction(d: usize, bit: u64) -> u64 {
    if d == 0usize { ret 1u64 << (31u64 - bit) }
    // Initial m values and primitive polynomials (Joe-Kuo new-joe-kuo-6.21201).
    var m: [32]u64 = zero
    var degree = 0u64
    var poly = 0u64
    if d == 1usize {
        degree = 1u64
        poly = 0u64
        m[0usize] = 1u64
    } else if d == 2usize {
        degree = 2u64
        poly = 1u64
        m[0usize] = 1u64
        m[1usize] = 3u64
    } else {
        degree = 3u64
        poly = 1u64
        m[0usize] = 1u64
        m[1usize] = 3u64
        m[2usize] = 1u64
    }
    var i = degree
    while i < 32u64 {
        var value = m[usize(i - degree)] ^ (m[usize(i - degree)] << degree)
        var k = 1u64
        while k < degree {
            if ((poly >> (degree - 1u64 - k)) & 1u64) == 1u64 { value = value ^ (m[usize(i - k)] << k) }
            k += 1u64
        }
        m[usize(i)] = value
        i += 1u64
    }
    ret m[usize(bit)] << (31u64 - bit)
}

// The additions below are D885: the planned names over what was already here.

// Marsaglia's polar method answering both normals of the pair (`normal` keeps
// only the first and draws the same uniforms).
fn normal_polar(r: *rand.Pcg64) -> (f64, f64) {
    while true {
        let u = 2.0f64 * rand.pcg64_f64(r) - 1.0f64
        let v = 2.0f64 * rand.pcg64_f64(r) - 1.0f64
        let s = u * u + v * v
        if s > 0.0f64 && s < 1.0f64 {
            let m = math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s) / s)
            ret (u * m, v * m)
        }
    }
    ret (0.0f64, 0.0f64)
}

// Self-normalised importance weights of `samples` into `out` (each
// `importance_weight` over the total); answers the effective sample size
// `(sum w)^2 / sum w^2`, which is `samples.len` when the proposal is the target.
fn importance_weights[Ctx: type](samples: []const f64, ctx: *Ctx, target_density: fn(*Ctx, f64) -> f64, proposal_density: fn(*Ctx, f64) -> f64, out: []f64) -> (f64, err) {
    let n = samples.len
    if out.len < n { ret (0.0f64, TooSmall) }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        out[i] = importance_weight[Ctx](samples[i], ctx, target_density, proposal_density)
        total += out[i]
        i += 1usize
    }
    if total <= 0.0f64 { ret (0.0f64, Invalid) }
    var squares = 0.0f64
    i = 0usize
    while i < n {
        out[i] = out[i] / total
        squares += out[i] * out[i]
        i += 1usize
    }
    ret (1.0f64 / squares, ok)
}

// One draw of a Gaussian copula: `n` uniform marginals whose dependence is
// the correlation matrix with Cholesky factor `factor` (see `cholesky`).
// Correlated normals come from `multivariate_normal` about zero and each is
// mapped through the normal CDF, scaled by its row's norm so a covariance
// rather than a correlation still yields uniform marginals. `scratch.len >= 2n`.
fn copula_gaussian(r: *rand.Pcg64, factor: []const f64, n: usize, out: []f64, scratch: []f64) -> err {
    if scratch.len < 2usize * n { ret TooSmall }
    var i = 0usize
    while i < n {
        scratch[i] = 0.0f64
        i += 1usize
    }
    let e = multivariate_normal(r, scratch[..n], factor, n, out, scratch[n..2usize * n])
    if e != ok { ret e }
    i = 0usize
    while i < n {
        var variance = 0.0f64
        var j = 0usize
        while j <= i {
            variance += factor[i * n + j] * factor[i * n + j]
            j += 1usize
        }
        out[i] = special.normal_cdf(out[i] / math.sqrt[f64](variance))
        i += 1usize
    }
    ret ok
}
