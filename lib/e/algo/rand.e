// Deterministic pseudorandom generators. None of these is cryptographic: the state
// is fully recoverable from the output and is meant to be, because reproducing a run
// exactly is the point.
//
// Each generator is a named published algorithm rather than a variation on one, so a
// stream produced here matches the reference implementation bit for bit and a seed
// carries between languages. D91 records which variant each name is.

use e.math

error TooSmall
error Invalid

type Pcg64 = struct { state: u64, stream: u64 }

// Knuth's MMIX linear congruential generator; the output is the whole state.
type Lcg = struct { state: u64 }

// xorshift64*: a 64-bit xorshift state, the output multiplied by 2685821657736338717.
type Xorshift = struct { state: u64 }

// A 32-bit Galois LFSR with taps 0x80200003 (x^32 + x^22 + x^2 + x + 1, maximal).
type Lfsr = struct { state: u32 }

// A weighted reservoir (Efraimidis-Spirakis A-Res): `items` and `keys` are one
// min-heap on the keys, `count` how many slots are filled.
type WeightedReservoir[T: type] = struct { items: []T, keys: []f64, count: usize }

type Xoshiro256 = struct { s0: u64, s1: u64, s2: u64, s3: u64 }

type Mt19937 = struct { state: [624]u32, index: u32 }

// A reservoir sample in progress: `items` is the sample, `seen` the stream length.
type Reservoir[T: type] = struct { items: []T, seen: u64 }

// PCG, `setseq_64_rxs_m_xs_64`: 64 bits of state, 64 bits out, and a stream selector
// that picks one of 2**63 distinct sequences. `stream` holds the odd increment the
// selector becomes, which is what makes two streams from one seed independent.
fn pcg64(seed: u64, stream: u64) -> Pcg64 {
    var r: Pcg64 = zero
    r.state = 0u64
    r.stream = (stream << 1u64) | 1u64
    r.state = r.state *% 6364136223846793005u64 +% r.stream
    r.state = r.state +% seed
    r.state = r.state *% 6364136223846793005u64 +% r.stream
    ret r
}

fn pcg64_next(r: *Pcg64) -> u64 {
    // The output function reads the state the step started from, so the value handed
    // out is never the state the generator is left in.
    let previous = r.state
    r.state = r.state *% 6364136223846793005u64 +% r.stream
    let shift = (previous >> 59u64) + 5u64
    let mixed = (previous >> shift) ^ previous
    let word = mixed *% 12605985483714917081u64
    let folded = word >> 43u64
    ret folded ^ word
}

// Unbiased by rejection: `2**64 % upper` low values would otherwise have one more
// representative than the rest, so a draw below that many is thrown away.
fn pcg64_bounded(r: *Pcg64, upper: u64) -> u64 {
    if upper == 0u64 { ret 0u64 }
    let threshold = (0u64 -% upper) % upper
    while true {
        let draw = pcg64_next(r)
        if draw >= threshold { ret draw % upper }
    }
    ret 0u64
}

// The top 53 bits over 2**53, which is every double in [0, 1) with the same spacing
// and no rounding.
fn pcg64_f64(r: *Pcg64) -> f64 {
    let draw = pcg64_next(r)
    ret f64(draw >> 11u64) / 9007199254740992.0f64
}

// xoshiro256**, the general-purpose member of the family. The four words are the
// state itself; an all-zero state is the one the generator cannot leave, so it is
// replaced rather than accepted.
fn xoshiro256(seed: [4]u64) -> Xoshiro256 {
    var r: Xoshiro256 = zero
    r.s0 = seed[0usize]
    r.s1 = seed[1usize]
    r.s2 = seed[2usize]
    r.s3 = seed[3usize]
    if r.s0 == 0u64 && r.s1 == 0u64 && r.s2 == 0u64 && r.s3 == 0u64 {
        r.s0 = 11400714819323198485u64
        r.s1 = 14029467366897019727u64
        r.s2 = 1609587929392839161u64
        r.s3 = 9650029242287828579u64
    }
    ret r
}

fn xoshiro256_next(r: *Xoshiro256) -> u64 {
    let scaled = r.s1 *% 5u64
    let rotated = (scaled << 7u64) | (scaled >> 57u64)
    let result = rotated *% 9u64
    let lifted = r.s1 << 17u64
    r.s2 = r.s2 ^ r.s0
    r.s3 = r.s3 ^ r.s1
    r.s1 = r.s1 ^ r.s2
    r.s0 = r.s0 ^ r.s3
    r.s2 = r.s2 ^ lifted
    r.s3 = (r.s3 << 45u64) | (r.s3 >> 19u64)
    ret result
}

fn xoshiro256_bounded(r: *Xoshiro256, upper: u64) -> u64 {
    if upper == 0u64 { ret 0u64 }
    let threshold = (0u64 -% upper) % upper
    while true {
        let draw = xoshiro256_next(r)
        if draw >= threshold { ret draw % upper }
    }
    ret 0u64
}

fn xoshiro256_f64(r: *Xoshiro256) -> f64 {
    let draw = xoshiro256_next(r)
    ret f64(draw >> 11u64) / 9007199254740992.0f64
}

// MT19937, seeded the way the reference `init_genrand` does. `index` counts words
// consumed from the current block; starting it at the block size means the first
// call twists before it reads.
fn mt19937(seed: u32) -> Mt19937 {
    var r: Mt19937 = zero
    r.state[0usize] = seed
    var at = 1usize
    while at < 624usize {
        let previous = r.state[at - 1usize]
        let mixed = previous ^ (previous >> 30u32)
        r.state[at] = 1812433253u32 *% mixed +% u32(at)
        at += 1usize
    }
    r.index = 624u32
    ret r
}

fn mt19937_next(r: *Mt19937) -> u32 {
    if r.index >= 624u32 {
        // The twist, over the whole block at once.
        var at = 0usize
        while at < 624usize {
            var following = at + 1usize
            if following == 624usize { following = 0usize }
            var offset = at + 397usize
            if offset >= 624usize { offset = offset - 624usize }
            let joined = (r.state[at] & 2147483648u32) | (r.state[following] & 2147483647u32)
            var twisted = r.state[offset] ^ (joined >> 1u32)
            if joined % 2u32 == 1u32 { twisted = twisted ^ 2567483615u32 }
            r.state[at] = twisted
            at += 1usize
        }
        r.index = 0u32
    }
    var word = r.state[usize(r.index)]
    r.index += 1u32
    // The tempering, which is what makes the output equidistributed.
    word = word ^ (word >> 11u32)
    word = word ^ ((word << 7u32) & 2636928640u32)
    word = word ^ ((word << 15u32) & 4022730752u32)
    ret word ^ (word >> 18u32)
}

// Fisher-Yates (Durstenfeld): an unbiased uniform permutation in place.
fn shuffle[T: type](r: *Pcg64, items: []T) {
    var i = items.len
    while i > 1usize {
        let j = usize(pcg64_bounded(r, u64(i)))
        i -= 1usize
        let swap = items[i]
        items[i] = items[j]
        items[j] = swap
    }
}

// Sattolo's algorithm: a uniform random permutation with a single cycle.
fn cycle_permutation[T: type](r: *Pcg64, items: []T) {
    var i = items.len
    while i > 1usize {
        i -= 1usize
        let j = usize(pcg64_bounded(r, u64(i)))
        let swap = items[i]
        items[i] = items[j]
        items[j] = swap
    }
}

// Reservoir sampling: `items` holds the sample and fills first; after that each
// offered item replaces a random slot with probability `items.len / seen`.
fn reservoir[T: type](items: []T) -> Reservoir[T] { ret Reservoir[T] { items: items, seen: 0u64 } }

fn reservoir_offer[T: type](s: *Reservoir[T], r: *Pcg64, item: T) {
    s.seen += 1u64
    if s.seen <= u64(s.items.len) {
        s.items[usize(s.seen - 1u64)] = item
        ret
    }
    let slot = pcg64_bounded(r, s.seen)
    if slot < u64(s.items.len) { s.items[usize(slot)] = item }
}

// The sample so far: all of `items` once `seen` reached its length.
fn reservoir_sample[T: type](s: *const Reservoir[T]) -> []T {
    if s.seen < u64(s.items.len) { ret s.items[..usize(s.seen)] }
    ret s.items
}

// The generators and samplers below are D882. `Pcg64` is the randomness source of
// every sampler, so a seed and a stream reproduce a sample exactly.

fn lcg(seed: u64) -> Lcg { ret Lcg { state: seed } }

fn lcg_next(r: *Lcg) -> u64 {
    r.state = r.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret r.state
}

// A zero state is the fixed point xorshift cannot leave, so it is replaced.
fn xorshift(seed: u64) -> Xorshift {
    if seed == 0u64 { ret Xorshift { state: 11400714819323198485u64 } }
    ret Xorshift { state: seed }
}

fn xorshift_next(r: *Xorshift) -> u64 {
    var x = r.state
    x = x ^ (x >> 12u64)
    x = x ^ (x << 25u64)
    x = x ^ (x >> 27u64)
    r.state = x
    ret x *% 2685821657736338717u64
}

fn lfsr(seed: u32) -> Lfsr {
    if seed == 0u32 { ret Lfsr { state: 1u32 } }
    ret Lfsr { state: seed }
}

// Answers the output bit and advances; the period is 2**32 - 1 from any seed.
fn lfsr_next(r: *Lfsr) -> u32 {
    let bit = r.state & 1u32
    r.state = r.state >> 1u32
    if bit == 1u32 { r.state = r.state ^ 2149580803u32 }
    ret bit
}

// Walker's alias table over `weights` (any positive scale): `probability`, `alias`
// and `scratch` each need `weights.len` slots. This duplicates
// `e.algo.rand.dist.alias_build`, which cannot be imported from here because
// `dist` imports this module.
fn alias_table(weights: []const f64, probability: []f64, alias: []usize, scratch: []usize) -> err {
    let n = weights.len
    if n == 0usize { ret Invalid }
    if probability.len < n || alias.len < n || scratch.len < n { ret TooSmall }
    var total = 0.0f64
    var i = 0usize
    while i < n {
        if weights[i] < 0.0f64 { ret Invalid }
        total += weights[i]
        i += 1usize
    }
    if total <= 0.0f64 { ret Invalid }
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
    ret ok
}

// An index drawn from a built alias table in O(1): a column, then a coin.
fn alias_pick(r: *Pcg64, probability: []const f64, alias: []const usize) -> usize {
    let column = usize(pcg64_bounded(r, u64(probability.len)))
    if pcg64_f64(r) < probability[column] { ret column }
    ret alias[column]
}

// `out.len` stratified uniforms: one draw in each of the equal strata of [0, 1).
fn stratified(r: *Pcg64, out: []f64) {
    let n = out.len
    var i = 0usize
    while i < n {
        out[i] = (f64(i) + pcg64_f64(r)) / f64(n)
        i += 1usize
    }
}

// A Latin hypercube of `points` rows by `dims` columns into `out` (row-major, at
// least `points * dims` slots), each column an independent random permutation of
// the strata with a uniform draw inside each. `perm` needs `points` slots.
fn latin_hypercube(r: *Pcg64, out: []f64, points: usize, dims: usize, perm: []usize) -> err {
    if out.len < points * dims || perm.len < points { ret TooSmall }
    var d = 0usize
    while d < dims {
        var p = 0usize
        while p < points {
            perm[p] = p
            p += 1usize
        }
        shuffle[usize](r, perm[..points])
        p = 0usize
        while p < points {
            out[p * dims + d] = (f64(perm[p]) + pcg64_f64(r)) / f64(points)
            p += 1usize
        }
        d += 1usize
    }
    ret ok
}

// A weighted reservoir over caller storage; the capacity is the shorter of the two.
fn reservoir_weighted[T: type](items: []T, keys: []f64) -> WeightedReservoir[T] {
    var n = items.len
    if keys.len < n { n = keys.len }
    ret WeightedReservoir[T] { items: items[..n], keys: keys[..n], count: 0usize }
}

// A-Res: the item's key is `u^(1/weight)` and the reservoir keeps the largest keys,
// so a heavier item survives with probability proportional to its weight. A weight
// of zero or less is never taken.
fn reservoir_weighted_offer[T: type](s: *WeightedReservoir[T], r: *Pcg64, item: T, weight: f64) {
    if weight <= 0.0f64 { ret }
    let key = math.pow[f64](pcg64_f64(r), 1.0f64 / weight)
    if s.count < s.keys.len {
        var node = s.count
        s.items[node] = item
        s.keys[node] = key
        s.count += 1usize
        while node > 0usize {
            let parent = (node - 1usize) / 2usize
            if s.keys[parent] <= s.keys[node] { break }
            let carried_key = s.keys[parent]
            s.keys[parent] = s.keys[node]
            s.keys[node] = carried_key
            let carried = s.items[parent]
            s.items[parent] = s.items[node]
            s.items[node] = carried
            node = parent
        }
        ret
    }
    if key <= s.keys[0usize] { ret }
    s.items[0usize] = item
    s.keys[0usize] = key
    var node = 0usize
    while true {
        let left = node * 2usize + 1usize
        if left >= s.count { break }
        var smallest = left
        let right = left + 1usize
        if right < s.count && s.keys[right] < s.keys[left] { smallest = right }
        if s.keys[smallest] >= s.keys[node] { break }
        let carried_key = s.keys[smallest]
        s.keys[smallest] = s.keys[node]
        s.keys[node] = carried_key
        let carried = s.items[smallest]
        s.items[smallest] = s.items[node]
        s.items[node] = carried
        node = smallest
    }
}

// The exponentially time-decayed reservoir (forward decay): an item offered at
// `time` with `weight` enters A-Res with the effective weight
// `weight * exp(rate * time)`, so its key is `u^(1 / (weight * e^(rate * time)))`
// and an item offered `d` later with the same weight is `e^(rate * d)` times as
// likely to be kept. `time` is the caller's clock (any unit); `rate` its decay.
fn reservoir_decayed_offer[T: type](s: *WeightedReservoir[T], r: *Pcg64, item: T, weight: f64, time: f64, rate: f64) {
    reservoir_weighted_offer[T](s, r, item, weight * math.exp[f64](rate * time))
}

// The sample so far, in heap order (the smallest key first).
fn reservoir_weighted_sample[T: type](s: *const WeightedReservoir[T]) -> []T { ret s.items[..s.count] }

// Priority sampling (Duffield, Lund, Thorup): priority `w / u`, keep the
// `chosen.len` largest, and the threshold is the largest priority not kept. Each
// kept item's `adjusted` weight is `max(w, threshold)`, which is an unbiased
// estimator of its weight; the answer is the threshold. `chosen` is in heap order.
fn priority_sample(r: *Pcg64, weights: []const f64, chosen: []usize, adjusted: []f64) -> (f64, err) {
    let k = chosen.len
    if adjusted.len < k { ret (0.0f64, TooSmall) }
    var count = 0usize
    var threshold = 0.0f64
    var i = 0usize
    while i < weights.len {
        var u = pcg64_f64(r)
        if u == 0.0f64 { u = 1.1102230246251565e-16f64 }
        let priority = weights[i] / u
        if count < k {
            var node = count
            chosen[node] = i
            adjusted[node] = priority
            count += 1usize
            while node > 0usize {
                let parent = (node - 1usize) / 2usize
                if adjusted[parent] <= adjusted[node] { break }
                let carried_key = adjusted[parent]
                adjusted[parent] = adjusted[node]
                adjusted[node] = carried_key
                let carried = chosen[parent]
                chosen[parent] = chosen[node]
                chosen[node] = carried
                node = parent
            }
        } else {
            if priority > adjusted[0usize] {
                if adjusted[0usize] > threshold { threshold = adjusted[0usize] }
                chosen[0usize] = i
                adjusted[0usize] = priority
                var node = 0usize
                while true {
                    let left = node * 2usize + 1usize
                    if left >= count { break }
                    var smallest = left
                    let right = left + 1usize
                    if right < count && adjusted[right] < adjusted[left] { smallest = right }
                    if adjusted[smallest] >= adjusted[node] { break }
                    let carried_key = adjusted[smallest]
                    adjusted[smallest] = adjusted[node]
                    adjusted[node] = carried_key
                    let carried = chosen[smallest]
                    chosen[smallest] = chosen[node]
                    chosen[node] = carried
                    node = smallest
                }
            } else {
                if priority > threshold { threshold = priority }
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < count {
        adjusted[i] = weights[chosen[i]]
        if threshold > adjusted[i] { adjusted[i] = threshold }
        i += 1usize
    }
    ret (threshold, ok)
}

// VarOpt_k (Cohen, Duffield, Kaplan, Lund, Thorup): a sample of `k` items whose
// adjusted weights are `max(w, threshold)` and sum exactly to the total weight.
// `chosen` and `adjusted` need `k + 1` slots and hold the sample in ascending
// adjusted-weight order in their first `min(k, weights.len)`. Each arrival joins the
// sorted `k + 1`; the threshold is the smallest `t` with `sum(w_i <= t) = t * (m - 1)`
// over the `m` smallest, one of those `m` is dropped with probability `1 - w_i / t`,
// and the survivors among them take the weight `t`. The answer is the threshold.
fn varopt_sample(r: *Pcg64, weights: []const f64, k: usize, chosen: []usize, adjusted: []f64) -> (f64, err) {
    if chosen.len < k + 1usize || adjusted.len < k + 1usize { ret (0.0f64, TooSmall) }
    var count = 0usize
    var threshold = 0.0f64
    var i = 0usize
    while i < weights.len {
        let w = weights[i]
        var pos = count
        while pos > 0usize && adjusted[pos - 1usize] > w {
            adjusted[pos] = adjusted[pos - 1usize]
            chosen[pos] = chosen[pos - 1usize]
            pos -= 1usize
        }
        adjusted[pos] = w
        chosen[pos] = i
        count += 1usize
        if count > k {
            var m = 2usize
            var total = adjusted[0usize] + adjusted[1usize]
            var tau = total
            while m < count && adjusted[m] < tau {
                total += adjusted[m]
                m += 1usize
                tau = total / f64(m - 1usize)
            }
            let u = pcg64_f64(r)
            var accumulated = 0.0f64
            var dropped = m - 1usize
            var j = 0usize
            while j < m {
                accumulated += 1.0f64 - adjusted[j] / tau
                if u < accumulated {
                    dropped = j
                    j = m
                } else {
                    j += 1usize
                }
            }
            j = 0usize
            while j < m {
                adjusted[j] = tau
                j += 1usize
            }
            j = dropped
            while j + 1usize < count {
                adjusted[j] = adjusted[j + 1usize]
                chosen[j] = chosen[j + 1usize]
                j += 1usize
            }
            count -= 1usize
            threshold = tau
        }
        i += 1usize
    }
    ret (threshold, ok)
}
