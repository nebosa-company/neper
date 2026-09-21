// Probabilistic summaries over caller storage: membership filters, frequency
// sketches, cardinality estimation, heavy hitters and similarity signatures.
//
// Every structure lives in slices the caller owns, sized with the helpers here,
// so a sketch can sit in an arena, on the stack or in a mapped file alike. Items
// are bytes; the hash is `e.algo.hash.xxhash64`, and the `k` positions a filter
// needs are derived from one 64-bit hash by double hashing. The heavy-hitter and
// signature entry points take items already reduced to `u64` keys so a caller
// hashes each item once for every summary it feeds.

use e.algo.hash
use e.bytes
use e.math

type Bloom = struct { bits: []u64, hashes: u32 }
type CountingBloom = struct { counts: []u8, hashes: u32 }
type CountMin = struct { counts: []u32, width: usize, depth: usize }
type HyperLogLog = struct { registers: []u8, precision: u8 }
type Counter = struct { key: u64, count: u64 }
error Invalid
error TooSmall

// The bit count and hash count that hold `items` items at false-positive `rate`.
fn bloom_size(items: usize, rate: f64) -> (usize, u32) {
    if items == 0usize || rate <= 0.0f64 || rate >= 1.0f64 { ret (64usize, 1u32) }
    let ln2 = 0.6931471805599453f64
    let bits = 0.0f64 - f64(items) * math.log[f64](rate) / (ln2 * ln2)
    var hashes = u32(math.round[f64](f64(bits) / f64(items) * ln2))
    if hashes == 0u32 { hashes = 1u32 }
    var words = usize(bits) / 64usize + 1usize
    ret (words * 64usize, hashes)
}

fn bloom_init(bits: []u64, hashes: u32) -> (Bloom, err) {
    if bits.len == 0usize || hashes == 0u32 { ret (zero, Invalid) }
    var i = 0usize
    while i < bits.len {
        bits[i] = 0u64
        i += 1usize
    }
    ret (Bloom { bits: bits, hashes: hashes }, ok)
}

fn bloom_insert(b: *Bloom, item: []const u8) {
    let h = hash.xxhash64(item, 0u64)
    let h1 = h & 4294967295u64
    let h2 = h >> 32u64
    let span = u64(b.bits.len) * 64u64
    var k = 0u64
    while k < u64(b.hashes) {
        let bit = (h1 +% k *% h2) % span
        b.bits[usize(bit / 64u64)] = b.bits[usize(bit / 64u64)] | (1u64 << (bit % 64u64))
        k += 1u64
    }
}

// `true` may be a false positive; `false` never is.
fn bloom_contains(b: *const Bloom, item: []const u8) -> bool {
    let h = hash.xxhash64(item, 0u64)
    let h1 = h & 4294967295u64
    let h2 = h >> 32u64
    let span = u64(b.bits.len) * 64u64
    var k = 0u64
    while k < u64(b.hashes) {
        let bit = (h1 +% k *% h2) % span
        if (b.bits[usize(bit / 64u64)] & (1u64 << (bit % 64u64))) == 0u64 { ret false }
        k += 1u64
    }
    ret true
}

// The union of two filters of the same shape, left in `dst`.
fn bloom_merge(dst: *Bloom, src: *const Bloom) -> err {
    if dst.bits.len != src.bits.len || dst.hashes != src.hashes { ret Invalid }
    var i = 0usize
    while i < dst.bits.len {
        dst.bits[i] = dst.bits[i] | src.bits[i]
        i += 1usize
    }
    ret ok
}

// A counting filter: one saturating byte per slot, so removal is possible.
fn counting_bloom_init(counts: []u8, hashes: u32) -> (CountingBloom, err) {
    if counts.len == 0usize || hashes == 0u32 { ret (zero, Invalid) }
    var i = 0usize
    while i < counts.len {
        counts[i] = 0u8
        i += 1usize
    }
    ret (CountingBloom { counts: counts, hashes: hashes }, ok)
}

fn counting_bloom_insert(b: *CountingBloom, item: []const u8) {
    let h = hash.xxhash64(item, 0u64)
    let h1 = h & 4294967295u64
    let h2 = h >> 32u64
    var k = 0u64
    while k < u64(b.hashes) {
        let slot = usize((h1 +% k *% h2) % u64(b.counts.len))
        if b.counts[slot] != 255u8 { b.counts[slot] += 1u8 }
        k += 1u64
    }
}

// Removes one insertion; `false` when the item was never present (nothing changes).
fn counting_bloom_remove(b: *CountingBloom, item: []const u8) -> bool {
    if !counting_bloom_contains(b, item) { ret false }
    let h = hash.xxhash64(item, 0u64)
    let h1 = h & 4294967295u64
    let h2 = h >> 32u64
    var k = 0u64
    while k < u64(b.hashes) {
        let slot = usize((h1 +% k *% h2) % u64(b.counts.len))
        if b.counts[slot] != 255u8 { b.counts[slot] -= 1u8 }
        k += 1u64
    }
    ret true
}

fn counting_bloom_contains(b: *const CountingBloom, item: []const u8) -> bool {
    let h = hash.xxhash64(item, 0u64)
    let h1 = h & 4294967295u64
    let h2 = h >> 32u64
    var k = 0u64
    while k < u64(b.hashes) {
        let slot = usize((h1 +% k *% h2) % u64(b.counts.len))
        if b.counts[slot] == 0u8 { ret false }
        k += 1u64
    }
    ret true
}

// Count-Min: `depth` rows of `width` counters; `counts.len >= width * depth`.
fn count_min_init(counts: []u32, width: usize, depth: usize) -> (CountMin, err) {
    if width == 0usize || depth == 0usize { ret (zero, Invalid) }
    if counts.len < width * depth { ret (zero, TooSmall) }
    var i = 0usize
    while i < width * depth {
        counts[i] = 0u32
        i += 1usize
    }
    ret (CountMin { counts: counts[..width * depth], width: width, depth: depth }, ok)
}

fn count_min_add(s: *CountMin, item: []const u8, amount: u32) {
    var row = 0usize
    while row < s.depth {
        let slot = row * s.width + usize(hash.xxhash64(item, u64(row)) % u64(s.width))
        let sum = u64(s.counts[slot]) + u64(amount)
        if sum > 4294967295u64 { s.counts[slot] = 4294967295u32 } else { s.counts[slot] = u32(sum) }
        row += 1usize
    }
}

// Conservative update: only the rows at the current minimum are raised, which
// tightens the estimate for items that share slots with heavier ones.
fn count_min_add_conservative(s: *CountMin, item: []const u8, amount: u32) {
    let floor = count_min_estimate(s, item)
    var want = u64(floor) + u64(amount)
    if want > 4294967295u64 { want = 4294967295u64 }
    var row = 0usize
    while row < s.depth {
        let slot = row * s.width + usize(hash.xxhash64(item, u64(row)) % u64(s.width))
        if u64(s.counts[slot]) < want { s.counts[slot] = u32(want) }
        row += 1usize
    }
}

// Never below the true count; above it only by hash collisions.
fn count_min_estimate(s: *const CountMin, item: []const u8) -> u32 {
    var least = 4294967295u32
    var row = 0usize
    while row < s.depth {
        let slot = row * s.width + usize(hash.xxhash64(item, u64(row)) % u64(s.width))
        if s.counts[slot] < least { least = s.counts[slot] }
        row += 1usize
    }
    ret least
}

// HyperLogLog with `2^precision` registers, `precision` in `4..=18`;
// `registers.len >= 1 << precision`.
fn hll_init(registers: []u8, precision: u8) -> (HyperLogLog, err) {
    if precision < 4u8 || precision > 18u8 { ret (zero, Invalid) }
    let m = 1usize << usize(precision)
    if registers.len < m { ret (zero, TooSmall) }
    var i = 0usize
    while i < m {
        registers[i] = 0u8
        i += 1usize
    }
    ret (HyperLogLog { registers: registers[..m], precision: precision }, ok)
}

fn hll_add(h: *HyperLogLog, item: []const u8) {
    let x = hash.xxhash64(item, 0u64)
    let index = usize(x >> (64u64 - u64(h.precision)))
    let rest = (x << u64(h.precision)) | (1u64 << (u64(h.precision) - 1u64))
    let rank = u8(bytes.leading_zeros[u64](rest)) + 1u8
    if rank > h.registers[index] { h.registers[index] = rank }
}

// The estimated number of distinct items: the harmonic-mean estimator with the
// linear-counting correction while many registers are still empty.
fn hll_estimate(h: *const HyperLogLog) -> f64 {
    let m = f64(h.registers.len)
    var alpha = 0.7213f64 / (1.0f64 + 1.079f64 / m)
    if h.registers.len == 16usize { alpha = 0.673f64 }
    if h.registers.len == 32usize { alpha = 0.697f64 }
    if h.registers.len == 64usize { alpha = 0.709f64 }
    var sum = 0.0f64
    var empty = 0usize
    var i = 0usize
    while i < h.registers.len {
        sum += math.exp2[f64](0.0f64 - f64(h.registers[i]))
        if h.registers[i] == 0u8 { empty += 1usize }
        i += 1usize
    }
    let raw = alpha * m * m / sum
    if raw <= 2.5f64 * m && empty > 0usize {
        ret m * math.log[f64](m / f64(empty))
    }
    ret raw
}

// The union of two sketches of the same precision, left in `dst`.
fn hll_merge(dst: *HyperLogLog, src: *const HyperLogLog) -> err {
    if dst.precision != src.precision { ret Invalid }
    var i = 0usize
    while i < dst.registers.len {
        if src.registers[i] > dst.registers[i] { dst.registers[i] = src.registers[i] }
        i += 1usize
    }
    ret ok
}

fn counters_clear(counters: []Counter) {
    var i = 0usize
    while i < counters.len {
        counters[i] = Counter { key: 0u64, count: 0u64 }
        i += 1usize
    }
}

// Misra-Gries: every key with frequency above `n / (counters.len + 1)` ends up
// tracked; a tracked count is below the true count by at most that bound.
fn misra_gries_add(counters: []Counter, key: u64) {
    var i = 0usize
    while i < counters.len {
        if counters[i].count != 0u64 && counters[i].key == key {
            counters[i].count += 1u64
            ret
        }
        i += 1usize
    }
    i = 0usize
    while i < counters.len {
        if counters[i].count == 0u64 {
            counters[i] = Counter { key: key, count: 1u64 }
            ret
        }
        i += 1usize
    }
    i = 0usize
    while i < counters.len {
        counters[i].count -= 1u64
        i += 1usize
    }
}

// Space-Saving: the smallest counter is handed to a new key and inherits its
// count, so a tracked count is never below the true count.
fn space_saving_add(counters: []Counter, key: u64) {
    var least = 0usize
    var i = 0usize
    while i < counters.len {
        if counters[i].count != 0u64 && counters[i].key == key {
            counters[i].count += 1u64
            ret
        }
        if counters[i].count < counters[least].count { least = i }
        i += 1usize
    }
    if counters.len == 0usize { ret }
    counters[least] = Counter { key: key, count: counters[least].count + 1u64 }
}

// The tracked counter for `key`, if any.
fn counter_get(counters: []const Counter, key: u64) -> (u64, bool) {
    var i = 0usize
    while i < counters.len {
        if counters[i].count != 0u64 && counters[i].key == key { ret (counters[i].count, true) }
        i += 1usize
    }
    ret (0u64, false)
}

// Mixes a key with a permutation index into a new 64-bit value.
fn minhash_mix(key: u64, permutation: u64) -> u64 {
    var x = key ^ (permutation *% 11400714819323198485u64)
    x = (x ^ (x >> 30u64)) *% 13787848793156543929u64
    x = (x ^ (x >> 27u64)) *% 10723151780598845931u64
    ret x ^ (x >> 31u64)
}

// The MinHash signature of a set of keys: `signature[k]` is the least mixed key
// under permutation `k`. An empty set signs as all ones.
fn minhash(keys: []const u64, signature: []u64) {
    var k = 0usize
    while k < signature.len {
        var least = 18446744073709551615u64
        var i = 0usize
        while i < keys.len {
            let mixed = minhash_mix(keys[i], u64(k))
            if mixed < least { least = mixed }
            i += 1usize
        }
        signature[k] = least
        k += 1usize
    }
}

// The fraction of agreeing signature slots estimates the Jaccard similarity.
fn minhash_similarity(a: []const u64, b: []const u64) -> f64 {
    if a.len == 0usize || a.len != b.len { ret 0.0f64 }
    var same = 0usize
    var i = 0usize
    while i < a.len {
        if a[i] == b[i] { same += 1usize }
        i += 1usize
    }
    ret f64(same) / f64(a.len)
}

// SimHash of weighted features: each bit is the sign of the weighted vote of the
// feature hashes, so near-duplicate feature sets differ in few bits.
fn simhash(features: []const u64, weights: []const u32) -> u64 {
    var votes: [64]i64 = zero
    var i = 0usize
    while i < features.len {
        var weight = 1i64
        if i < weights.len { weight = i64(weights[i]) }
        let h = minhash_mix(features[i], 0u64)
        var bit = 0usize
        while bit < 64usize {
            if ((h >> u64(bit)) & 1u64) == 1u64 { votes[bit] += weight } else { votes[bit] -= weight }
            bit += 1usize
        }
        i += 1usize
    }
    var out = 0u64
    var bit = 0usize
    while bit < 64usize {
        if votes[bit] > 0i64 { out = out | (1u64 << u64(bit)) }
        bit += 1usize
    }
    ret out
}

// The Hamming distance between two SimHash values.
fn simhash_distance(a: u64, b: u64) -> u32 { ret bytes.count_ones[u64](a ^ b) }
