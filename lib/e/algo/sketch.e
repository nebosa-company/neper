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
type CountSketch = struct { counts: []i64, width: usize, depth: usize }
type Kmv = struct { hashes: []u64, size: usize }
type Theta = struct { hashes: []u64, size: usize, theta: u64 }
type StaticFilter = struct { fingerprints: []u8, seed: u64, kind: u8, segment_length: usize, segment_count_length: usize }
type CuckooFilter = struct { slots: []u8, buckets: usize, state: u64 }
type QuotientFilter = struct { slots: []u64, counts: []u32, quotient_bits: u8, remainder_bits: u8, size: usize }
type StableBloom = struct { cells: []u8, hashes: u32, decrements: u32, max: u8, state: u64 }
type WindowedBloom = struct { bits: []u64, slice_words: usize, hashes: u32, slices: u32, head: u32, generation: usize, inserted: usize }
type DdSketch = struct { bins: []u64, offset: i64, count: u64, zeros: u64, gamma: f64, log_gamma: f64 }
type Gk = struct { values: []f64, gaps: []u64, deltas: []u64, size: usize, count: u64, epsilon: f64 }
type Kll = struct { items: []f64, sizes: []usize, k: usize, levels: usize, total: u64, state: u64 }
type TDigest = struct { means: []f64, weights: []f64, buffer: []f64, size: usize, buffered: usize, compression: f64, total: f64, min: f64, max: f64 }
type PSquare = struct { heights: []f64, positions: []f64, desired: []f64, increments: []f64, count: usize, p: f64 }
type SparseHll = struct { entries: []u32, size: usize, precision: u8 }
type SlidingHll = struct { entries: []u64, depth: usize, precision: u8 }
type TopK = struct { sketch: CountMin, heap: []Counter, size: usize }
type LossyCounter = struct { counters: []Counter, deltas: []u64, size: usize, seen: u64, width: u64 }
error Invalid
error TooSmall
error Full

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

// ---------------------------------------------------------------------------
// Everything below takes items already reduced to `u64` keys and hashes them
// with `minhash_mix`, so a caller hashes each item once for every summary.

fn pi() -> f64 { ret 3.141592653589793f64 }

fn sort_f64(xs: []f64) {
    var i = 1usize
    while i < xs.len {
        let x = xs[i]
        var j = i
        while j > 0usize && xs[j - 1usize] > x {
            xs[j] = xs[j - 1usize]
            j -= 1usize
        }
        xs[j] = x
        i += 1usize
    }
}

// The unit-interval value of a hash, never exactly zero.
fn unit(h: u64) -> f64 { ret (f64(h >> 11u64) + 0.5f64) / 9007199254740992.0f64 }

// Inserts `h` into the sorted, duplicate-free prefix `xs[..size]`, dropping the
// largest value when the slice is full; returns the new size.
fn sorted_insert(xs: []u64, size: usize, h: u64) -> usize {
    var lo = 0usize
    var hi = size
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if xs[mid] < h { lo = mid + 1usize } else { hi = mid }
    }
    if lo < size && xs[lo] == h { ret size }
    var n = size
    if n == xs.len {
        if lo == n { ret n }
        n -= 1usize
    }
    var j = n
    while j > lo {
        xs[j] = xs[j - 1usize]
        j -= 1usize
    }
    xs[lo] = h
    ret n + 1usize
}

fn sorted_contains(xs: []const u64, h: u64) -> bool {
    var lo = 0usize
    var hi = xs.len
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if xs[mid] < h { lo = mid + 1usize } else { hi = mid }
    }
    ret lo < xs.len && xs[lo] == h
}

// Misra-Gries over a whole stream: the counters end up tracking every key with
// frequency above `keys.len / (counters.len + 1)`.
fn misra_gries(counters: []Counter, keys: []const u64) {
    counters_clear(counters)
    var i = 0usize
    while i < keys.len {
        misra_gries_add(counters, keys[i])
        i += 1usize
    }
}

// Space-Saving over a whole stream; tracked counts never fall below the truth.
fn space_saving(counters: []Counter, keys: []const u64) {
    counters_clear(counters)
    var i = 0usize
    while i < keys.len {
        space_saving_add(counters, keys[i])
        i += 1usize
    }
}

// Count-Min over keys rather than bytes.
fn count_min_add_key(s: *CountMin, key: u64, amount: u32) {
    var row = 0usize
    while row < s.depth {
        let slot = row * s.width + usize(minhash_mix(key, u64(row)) % u64(s.width))
        let sum = u64(s.counts[slot]) + u64(amount)
        if sum > 4294967295u64 { s.counts[slot] = 4294967295u32 } else { s.counts[slot] = u32(sum) }
        row += 1usize
    }
}

fn count_min_estimate_key(s: *const CountMin, key: u64) -> u32 {
    var least = 4294967295u32
    var row = 0usize
    while row < s.depth {
        let slot = row * s.width + usize(minhash_mix(key, u64(row)) % u64(s.width))
        if s.counts[slot] < least { least = s.counts[slot] }
        row += 1usize
    }
    ret least
}

// Dyadic range counting: `levels[j]` counts `key >> j`, so any range is the sum
// of at most `2 * levels.len` point estimates.
fn count_min_range_add(levels: []CountMin, key: u64, amount: u32) {
    var j = 0usize
    while j < levels.len {
        count_min_add_key(&levels[j], key >> u64(j), amount)
        j += 1usize
    }
}

// The estimated total frequency of keys in `lo..=hi`; never below the truth.
fn count_min_range(levels: []const CountMin, lo: u64, hi: u64) -> u64 {
    if levels.len == 0usize || lo > hi { ret 0u64 }
    var total = 0u64
    var at = lo
    var more = true
    while more {
        var j = 0usize
        while j + 1usize < levels.len && at % (1u64 << u64(j + 1usize)) == 0u64 && hi - at >= (1u64 << u64(j + 1usize)) - 1u64 {
            j += 1usize
        }
        total += u64(count_min_estimate_key(&levels[j], at >> u64(j)))
        let step = 1u64 << u64(j)
        if hi - at < step { more = false } else { at += step }
    }
    ret total
}

// Count Sketch: `depth` rows of signed counters; the median row is an unbiased
// frequency estimate. `depth` is at most 64.
fn count_sketch_init(counts: []i64, width: usize, depth: usize) -> (CountSketch, err) {
    if width == 0usize || depth == 0usize || depth > 64usize { ret (zero, Invalid) }
    if counts.len < width * depth { ret (zero, TooSmall) }
    var i = 0usize
    while i < width * depth {
        counts[i] = 0i64
        i += 1usize
    }
    ret (CountSketch { counts: counts[..width * depth], width: width, depth: depth }, ok)
}

fn count_sketch_add(s: *CountSketch, key: u64, amount: i64) {
    var row = 0usize
    while row < s.depth {
        let h = minhash_mix(key, u64(row))
        let slot = row * s.width + usize((h >> 1u64) % u64(s.width))
        if (h & 1u64) == 1u64 { s.counts[slot] += amount } else { s.counts[slot] -= amount }
        row += 1usize
    }
}

fn count_sketch(s: *const CountSketch, key: u64) -> i64 {
    var rows: [64]i64 = zero
    var row = 0usize
    while row < s.depth {
        let h = minhash_mix(key, u64(row))
        let slot = row * s.width + usize((h >> 1u64) % u64(s.width))
        var v = s.counts[slot]
        if (h & 1u64) == 0u64 { v = 0i64 - v }
        var j = row
        while j > 0usize && rows[j - 1usize] > v {
            rows[j] = rows[j - 1usize]
            j -= 1usize
        }
        rows[j] = v
        row += 1usize
    }
    if s.depth % 2usize == 1usize { ret rows[s.depth / 2usize] }
    ret (rows[s.depth / 2usize - 1usize] + rows[s.depth / 2usize]) / 2i64
}

// AMS: every counter adds `amount` with a key-dependent sign, so the mean of the
// squared counters estimates the second frequency moment.
fn ams_f2_add(counters: []i64, key: u64, amount: i64) {
    var j = 0usize
    while j < counters.len {
        if (minhash_mix(key, u64(j)) & 1u64) == 1u64 { counters[j] += amount } else { counters[j] -= amount }
        j += 1usize
    }
}

fn ams_f2(counters: []const i64) -> f64 {
    if counters.len == 0usize { ret 0.0f64 }
    var sum = 0.0f64
    var j = 0usize
    while j < counters.len {
        sum += f64(counters[j]) * f64(counters[j])
        j += 1usize
    }
    ret sum / f64(counters.len)
}

// Flajolet-Martin: each bitmap records the trailing-zero counts seen under its
// own hash; the lowest unset bit, averaged over bitmaps, estimates the count.
fn flajolet_martin_add(bitmaps: []u64, key: u64) {
    var i = 0usize
    while i < bitmaps.len {
        let h = minhash_mix(key, u64(i))
        var t = 63u32
        if h != 0u64 { t = bytes.trailing_zeros[u64](h) }
        bitmaps[i] = bitmaps[i] | (1u64 << u64(t))
        i += 1usize
    }
}

fn flajolet_martin(bitmaps: []const u64) -> f64 {
    if bitmaps.len == 0usize { ret 0.0f64 }
    var sum = 0.0f64
    var i = 0usize
    while i < bitmaps.len {
        var r = 64u32
        if bitmaps[i] != 18446744073709551615u64 { r = bytes.trailing_zeros[u64](~bitmaps[i]) }
        sum += f64(r)
        i += 1usize
    }
    ret math.exp2[f64](sum / f64(bitmaps.len)) / 0.77351f64
}

// Linear counting: one bit per hashed key; the fraction still unset gives the count.
fn linear_counting_add(bits: []u64, key: u64) {
    let bit = minhash_mix(key, 0u64) % (u64(bits.len) * 64u64)
    bits[usize(bit / 64u64)] = bits[usize(bit / 64u64)] | (1u64 << (bit % 64u64))
}

fn linear_counting(bits: []const u64) -> f64 {
    let m = f64(bits.len) * 64.0f64
    var set = 0u32
    var i = 0usize
    while i < bits.len {
        set += bytes.count_ones[u64](bits[i])
        i += 1usize
    }
    let empty = m - f64(set)
    if empty <= 0.0f64 { ret m * math.log[f64](m) }
    ret m * math.log[f64](m / empty)
}

// KMV: the `k` smallest hashes seen; the k-th one places the cardinality.
fn kmv_init(hashes: []u64) -> Kmv { ret Kmv { hashes: hashes, size: 0usize } }

fn kmv_add(s: *Kmv, key: u64) { s.size = sorted_insert(s.hashes, s.size, minhash_mix(key, 0u64)) }

fn kmv(s: *const Kmv) -> f64 {
    if s.size < s.hashes.len { ret f64(s.size) }
    ret f64(s.size - 1usize) * 18446744073709551616.0f64 / f64(s.hashes[s.size - 1usize])
}

// Theta sketch: the hashes below `theta`, at most `hashes.len - 1` of them; when
// one more arrives `theta` drops to the value that no longer fits.
fn theta_init(hashes: []u64) -> Theta { ret Theta { hashes: hashes, size: 0usize, theta: 18446744073709551615u64 } }

fn theta_push(s: *Theta, h: u64) {
    if h >= s.theta { ret }
    s.size = sorted_insert(s.hashes, s.size, h)
    if s.size == s.hashes.len {
        s.size -= 1usize
        s.theta = s.hashes[s.size]
    }
}

fn theta_add(s: *Theta, key: u64) { theta_push(s, minhash_mix(key, 0u64)) }

fn theta_estimate(s: *const Theta) -> f64 {
    if s.theta == 18446744073709551615u64 { ret f64(s.size) }
    ret f64(s.size) * 18446744073709551616.0f64 / f64(s.theta)
}

// The union, left in `dst`: the lower theta wins and both retained sets merge under it.
fn theta_union(dst: *Theta, src: *const Theta) {
    if src.theta < dst.theta {
        dst.theta = src.theta
        while dst.size > 0usize && dst.hashes[dst.size - 1usize] >= dst.theta { dst.size -= 1usize }
    }
    var i = 0usize
    while i < src.size {
        theta_push(dst, src.hashes[i])
        i += 1usize
    }
}

// The intersection, written to `out`: hashes both sketches retain below the lower theta.
fn theta_intersection(a: *const Theta, b: *const Theta, out: *Theta) -> err {
    out.size = 0usize
    out.theta = a.theta
    if b.theta < out.theta { out.theta = b.theta }
    var i = 0usize
    while i < a.size {
        let h = a.hashes[i]
        if h < out.theta && sorted_contains(b.hashes[..b.size], h) {
            if out.size == out.hashes.len { ret TooSmall }
            out.hashes[out.size] = h
            out.size += 1usize
        }
        i += 1usize
    }
    ret ok
}

// --- Static filters: xor, binary fuse and ribbon -------------------------------
//
// All three are built once over distinct keys and then only queried, with 8-bit
// fingerprints (a false-positive rate near 1/256). Construction is retried with
// fresh seeds a bounded number of times before giving up with `Invalid`.

fn static_seed(attempt: usize) -> u64 { ret u64(attempt) *% 6364136223846793005u64 +% 1442695040888963407u64 }

fn static_fingerprint(h: u64) -> u8 { ret u8((h ^ (h >> 32u64)) & 255u64) }

fn reduce(x: u64, n: usize) -> usize { ret usize(((x & 4294967295u64) *% u64(n)) >> 32u64) }

// The three slots a hash touches: three equal blocks for the xor filter, three
// consecutive segments of a window for the binary fuse filter.
fn static_positions(f: *const StaticFilter, h: u64) -> (usize, usize, usize) {
    if f.kind == 0u8 {
        let block = f.segment_length
        let r1 = (h << 21u64) | (h >> 43u64)
        let r2 = (h << 42u64) | (h >> 22u64)
        ret (reduce(h, block), block + reduce(r1, block), 2usize * block + reduce(r2, block))
    }
    let mask = u64(f.segment_length - 1usize)
    let hi = usize(((h >> 32u64) *% u64(f.segment_count_length)) >> 32u64)
    let h1 = usize(u64(hi + f.segment_length) ^ ((h >> 18u64) & mask))
    let h2 = usize(u64(hi + 2usize * f.segment_length) ^ (h & mask))
    ret (hi, h1, h2)
}

// Peels the 3-hypergraph of `keys` over `f.fingerprints` and assigns the
// fingerprints in reverse peeling order; `false` when a seed does not peel.
fn static_peel(keys: []const u64, f: *StaticFilter, scratch: []u64) -> bool {
    let cap = f.fingerprints.len
    let n = keys.len
    var t2hash = scratch[..cap]
    var t2count = scratch[cap..2usize * cap]
    var queue = scratch[2usize * cap..3usize * cap]
    var rev_hash = scratch[3usize * cap..3usize * cap + n]
    var rev_slot = scratch[3usize * cap + n..3usize * cap + 2usize * n]
    var i = 0usize
    while i < cap {
        t2hash[i] = 0u64
        t2count[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let h = minhash_mix(keys[i], f.seed)
        let (a, b, c) = static_positions(f, h)
        t2count[a] += 1u64
        t2hash[a] = t2hash[a] ^ h
        t2count[b] += 1u64
        t2hash[b] = t2hash[b] ^ h
        t2count[c] += 1u64
        t2hash[c] = t2hash[c] ^ h
        i += 1usize
    }
    var queued = 0usize
    i = 0usize
    while i < cap {
        if t2count[i] == 1u64 {
            queue[queued] = u64(i)
            queued += 1usize
        }
        i += 1usize
    }
    var stack = 0usize
    while queued > 0usize {
        queued -= 1usize
        let slot = usize(queue[queued])
        if t2count[slot] == 1u64 {
            let h = t2hash[slot]
            rev_hash[stack] = h
            rev_slot[stack] = u64(slot)
            stack += 1usize
            let (a, b, c) = static_positions(f, h)
            t2count[a] -= 1u64
            t2hash[a] = t2hash[a] ^ h
            if t2count[a] == 1u64 {
                queue[queued] = u64(a)
                queued += 1usize
            }
            t2count[b] -= 1u64
            t2hash[b] = t2hash[b] ^ h
            if t2count[b] == 1u64 {
                queue[queued] = u64(b)
                queued += 1usize
            }
            t2count[c] -= 1u64
            t2hash[c] = t2hash[c] ^ h
            if t2count[c] == 1u64 {
                queue[queued] = u64(c)
                queued += 1usize
            }
        }
    }
    if stack != n { ret false }
    i = 0usize
    while i < cap {
        f.fingerprints[i] = 0u8
        i += 1usize
    }
    while stack > 0usize {
        stack -= 1usize
        let h = rev_hash[stack]
        let slot = usize(rev_slot[stack])
        let (a, b, c) = static_positions(f, h)
        f.fingerprints[slot] = static_fingerprint(h) ^ f.fingerprints[a] ^ f.fingerprints[b] ^ f.fingerprints[c]
    }
    ret true
}

fn static_build(keys: []const u64, f: *StaticFilter, scratch: []u64) -> err {
    if scratch.len < 3usize * f.fingerprints.len + 2usize * keys.len { ret TooSmall }
    var attempt = 0usize
    while attempt < 32usize {
        f.seed = static_seed(attempt)
        if static_peel(keys, f, scratch) { ret ok }
        attempt += 1usize
    }
    ret Invalid
}

// The fingerprint slots and scratch words an xor filter over `n` keys needs.
fn xor_filter_size(n: usize) -> (usize, usize) {
    var cap = 32usize + (123usize * n) / 100usize
    cap += (3usize - cap % 3usize) % 3usize
    ret (cap, 3usize * cap + 2usize * n)
}

// Xor filter (Graf & Lemire): three blocks, one 8-bit fingerprint per slot.
fn xor_filter(keys: []const u64, fingerprints: []u8, scratch: []u64) -> (StaticFilter, err) {
    let (cap, _) = xor_filter_size(keys.len)
    if fingerprints.len < cap { ret (zero, TooSmall) }
    var f = StaticFilter { fingerprints: fingerprints[..cap], seed: 0u64, kind: 0u8, segment_length: cap / 3usize, segment_count_length: 0usize }
    let e = static_build(keys, &f, scratch)
    ret (f, e)
}

// The slot count, segment length and segment-count length of a 3-wise binary
// fuse filter over `n` keys, as the reference implementation sizes it.
fn binary_fuse_layout(n: usize) -> (usize, usize, usize) {
    var size = n
    if size < 2usize { size = 2usize }
    var segment_length = 1usize << usize(math.floor[f64](math.log[f64](f64(size)) / math.log[f64](3.33f64) + 2.25f64))
    if segment_length > 262144usize { segment_length = 262144usize }
    var size_factor = 0.875f64 + 0.25f64 * math.log[f64](1000000.0f64) / math.log[f64](f64(size))
    if size_factor < 1.125f64 { size_factor = 1.125f64 }
    let capacity = usize(f64(size) * size_factor)
    var segment_count = (capacity + segment_length - 1usize) / segment_length
    if segment_count <= 2usize { segment_count = 1usize } else { segment_count -= 2usize }
    let array_length = (segment_count + 2usize) * segment_length
    ret (array_length, segment_length, segment_count * segment_length)
}

// The fingerprint slots and scratch words a binary fuse filter over `n` keys needs.
fn binary_fuse_size(n: usize) -> (usize, usize) {
    let (cap, _, _) = binary_fuse_layout(n)
    ret (cap, 3usize * cap + 2usize * n)
}

// Binary fuse filter (Graf & Lemire): three consecutive segments per key, which
// peels at a lower load than three disjoint blocks.
fn binary_fuse_filter(keys: []const u64, fingerprints: []u8, scratch: []u64) -> (StaticFilter, err) {
    let (cap, segment_length, segment_count_length) = binary_fuse_layout(keys.len)
    if fingerprints.len < cap { ret (zero, TooSmall) }
    var f = StaticFilter { fingerprints: fingerprints[..cap], seed: 0u64, kind: 1u8, segment_length: segment_length, segment_count_length: segment_count_length }
    let e = static_build(keys, &f, scratch)
    ret (f, e)
}

// A key's ribbon row: the start column and a 64-bit coefficient word with bit 0 set.
fn ribbon_row(f: *const StaticFilter, h: u64) -> (usize, u64) {
    ret (reduce(h, f.fingerprints.len - 63usize), minhash_mix(h, 1u64) | 1u64)
}

// The solution slots a ribbon filter over `n` keys needs.
fn ribbon_size(n: usize) -> usize { ret 64usize + n + n / 20usize }

// Ribbon filter (Dillinger & Walzer): one row per key in a 64-wide band, solved
// by banded Gaussian elimination into `solution`; `scratch` holds `2 * m` words.
// ponytail: row-major solution bytes, not the interleaved column-major layout.
fn ribbon_filter(keys: []const u64, solution: []u8, scratch: []u64) -> (StaticFilter, err) {
    let m = solution.len
    if m < 64usize || m < ribbon_size(keys.len) { ret (zero, TooSmall) }
    if scratch.len < 2usize * m { ret (zero, TooSmall) }
    var coeff = scratch[..m]
    var result = scratch[m..2usize * m]
    var f = StaticFilter { fingerprints: solution, seed: 0u64, kind: 2u8, segment_length: 0usize, segment_count_length: 0usize }
    var attempt = 0usize
    while attempt < 32usize {
        f.seed = static_seed(attempt)
        var i = 0usize
        while i < m {
            coeff[i] = 0u64
            result[i] = 0u64
            i += 1usize
        }
        var solved = true
        i = 0usize
        while i < keys.len && solved {
            let h = minhash_mix(keys[i], f.seed)
            let (start, row) = ribbon_row(&f, h)
            var c = row
            var r = u64(static_fingerprint(h))
            var at = start
            var placing = true
            while placing {
                if coeff[at] == 0u64 {
                    coeff[at] = c
                    result[at] = r
                    placing = false
                } else {
                    c = c ^ coeff[at]
                    r = r ^ result[at]
                    if c == 0u64 {
                        if r != 0u64 { solved = false }
                        placing = false
                    } else {
                        let t = bytes.trailing_zeros[u64](c)
                        at += usize(t)
                        c = c >> u64(t)
                    }
                }
            }
            i += 1usize
        }
        if solved {
            var back = m
            while back > 0usize {
                back -= 1usize
                var z = result[back]
                var j = 1usize
                while j < 64usize && back + j < m {
                    if ((coeff[back] >> u64(j)) & 1u64) == 1u64 { z = z ^ u64(solution[back + j]) }
                    j += 1usize
                }
                solution[back] = u8(z & 255u64)
            }
            ret (f, ok)
        }
        attempt += 1usize
    }
    ret (zero, Invalid)
}

// `true` may be a false positive at about 1/256; `false` never is.
fn static_filter_contains(f: *const StaticFilter, key: u64) -> bool {
    let h = minhash_mix(key, f.seed)
    if f.kind == 2u8 {
        let (start, row) = ribbon_row(f, h)
        var x = 0u8
        var j = 0usize
        while j < 64usize {
            if ((row >> u64(j)) & 1u64) == 1u64 { x = x ^ f.fingerprints[start + j] }
            j += 1usize
        }
        ret x == static_fingerprint(h)
    }
    let (a, b, c) = static_positions(f, h)
    ret (f.fingerprints[a] ^ f.fingerprints[b] ^ f.fingerprints[c]) == static_fingerprint(h)
}

// --- Cuckoo filter -------------------------------------------------------------
//
// Buckets of four 8-bit fingerprints (zero is empty), a power-of-two bucket
// count, and partial-key cuckoo hashing so the alternate bucket follows from
// the fingerprint alone.

fn cuckoo_init(slots: []u8) -> (CuckooFilter, err) {
    let buckets = slots.len / 4usize
    if buckets == 0usize || (buckets & (buckets - 1usize)) != 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i < buckets * 4usize {
        slots[i] = 0u8
        i += 1usize
    }
    ret (CuckooFilter { slots: slots[..buckets * 4usize], buckets: buckets, state: 1u64 }, ok)
}

fn cuckoo_split(f: *const CuckooFilter, key: u64) -> (u8, usize, usize) {
    let h = minhash_mix(key, 0u64)
    var fp = u8(h & 255u64)
    if fp == 0u8 { fp = 1u8 }
    let i1 = usize(h >> 32u64) & (f.buckets - 1usize)
    ret (fp, i1, i1 ^ (usize(minhash_mix(u64(fp), 7u64)) & (f.buckets - 1usize)))
}

fn cuckoo_slot(f: *const CuckooFilter, bucket: usize, fp: u8) -> (usize, bool) {
    var j = 0usize
    while j < 4usize {
        if f.slots[bucket * 4usize + j] == fp { ret (bucket * 4usize + j, true) }
        j += 1usize
    }
    ret (0usize, false)
}

// Inserts a fingerprint into either bucket, kicking residents to their alternate
// bucket up to 500 times; `Full` when the chain does not settle.
// ponytail: the last evicted fingerprint is dropped on `Full` (no victim cache).
fn cuckoo_insert(f: *CuckooFilter, key: u64) -> err {
    let (fp, i1, i2) = cuckoo_split(f, key)
    let (s1, e1) = cuckoo_slot(f, i1, 0u8)
    if e1 {
        f.slots[s1] = fp
        ret ok
    }
    let (s2, e2) = cuckoo_slot(f, i2, 0u8)
    if e2 {
        f.slots[s2] = fp
        ret ok
    }
    var at = i1
    if (f.state & 1u64) == 1u64 { at = i2 }
    var cur = fp
    var kicks = 0usize
    while kicks < 500usize {
        f.state = f.state *% 6364136223846793005u64 +% 1442695040888963407u64
        let j = usize((f.state >> 33u64) & 3u64)
        let victim = f.slots[at * 4usize + j]
        f.slots[at * 4usize + j] = cur
        cur = victim
        at = at ^ (usize(minhash_mix(u64(cur), 7u64)) & (f.buckets - 1usize))
        let (s, e) = cuckoo_slot(f, at, 0u8)
        if e {
            f.slots[s] = cur
            ret ok
        }
        kicks += 1usize
    }
    ret Full
}

fn cuckoo_contains(f: *const CuckooFilter, key: u64) -> bool {
    let (fp, i1, i2) = cuckoo_split(f, key)
    let (_, a) = cuckoo_slot(f, i1, fp)
    let (_, b) = cuckoo_slot(f, i2, fp)
    ret a || b
}

// Removes one copy of the fingerprint; `false` when neither bucket holds it.
fn cuckoo_remove(f: *CuckooFilter, key: u64) -> bool {
    let (fp, i1, i2) = cuckoo_split(f, key)
    let (s1, a) = cuckoo_slot(f, i1, fp)
    if a {
        f.slots[s1] = 0u8
        ret true
    }
    let (s2, b) = cuckoo_slot(f, i2, fp)
    if b {
        f.slots[s2] = 0u8
        ret true
    }
    ret false
}

// --- Quotient filter -----------------------------------------------------------
//
// Bender et al.: a hash splits into a `q`-bit quotient (the home slot) and an
// `r`-bit remainder stored in the slot with three metadata bits: is_occupied
// (some key has this home), is_continuation (same run as the slot before) and
// is_shifted (not in its home slot). Runs stay sorted by remainder. The counting
// variant pairs every slot with a count that travels with the remainder.
// ponytail: counts are fixed 32-bit words per slot, not the variable-length
// encoding of the CQF paper; a count that reaches zero leaves its slot in place.

fn quotient_filter_setup(slots: []u64, counts: []u32, quotient_bits: u8, remainder_bits: u8) -> (QuotientFilter, err) {
    if quotient_bits == 0u8 || quotient_bits > 32u8 || remainder_bits == 0u8 || remainder_bits > 61u8 { ret (zero, Invalid) }
    if quotient_bits + remainder_bits > 64u8 { ret (zero, Invalid) }
    let m = 1usize << usize(quotient_bits)
    if slots.len < m || (counts.len != 0usize && counts.len < m) { ret (zero, TooSmall) }
    var i = 0usize
    while i < m {
        slots[i] = 0u64
        if counts.len != 0usize { counts[i] = 0u32 }
        i += 1usize
    }
    var c = counts
    if counts.len != 0usize { c = counts[..m] }
    ret (QuotientFilter { slots: slots[..m], counts: c, quotient_bits: quotient_bits, remainder_bits: remainder_bits, size: 0usize }, ok)
}

fn quotient_filter(slots: []u64, quotient_bits: u8, remainder_bits: u8) -> (QuotientFilter, err) {
    var none: []u32 = zero
    let (f, e) = quotient_filter_setup(slots, none, quotient_bits, remainder_bits)
    ret (f, e)
}

fn counting_quotient_filter(slots: []u64, counts: []u32, quotient_bits: u8, remainder_bits: u8) -> (QuotientFilter, err) {
    if counts.len == 0usize { ret (zero, Invalid) }
    let (f, e) = quotient_filter_setup(slots, counts, quotient_bits, remainder_bits)
    ret (f, e)
}

fn quotient_split(f: *const QuotientFilter, key: u64) -> (usize, u64) {
    let h = minhash_mix(key, 0u64)
    let fq = usize(h >> u64(64u8 - f.quotient_bits))
    let fr = (h >> u64(64u8 - f.quotient_bits - f.remainder_bits)) & ((1u64 << u64(f.remainder_bits)) - 1u64)
    ret (fq, fr)
}

// The slot where the run of home `fq` starts (the cluster start, then one run per
// occupied home up to `fq`).
fn quotient_run_start(f: *const QuotientFilter, fq: usize) -> usize {
    let mask = f.slots.len - 1usize
    var b = fq
    while (f.slots[b] & 4u64) != 0u64 { b = (b + mask) & mask }
    var s = b
    while b != fq {
        s = (s + 1usize) & mask
        while (f.slots[s] & 2u64) != 0u64 { s = (s + 1usize) & mask }
        b = (b + 1usize) & mask
        while (f.slots[b] & 1u64) == 0u64 { b = (b + 1usize) & mask }
    }
    ret s
}

fn quotient_find(f: *const QuotientFilter, fq: usize, fr: u64) -> (usize, bool) {
    if (f.slots[fq] & 1u64) == 0u64 { ret (0usize, false) }
    let mask = f.slots.len - 1usize
    var s = quotient_run_start(f, fq)
    var scanning = true
    while scanning {
        let rem = f.slots[s] >> 3u64
        if rem == fr { ret (s, true) }
        if rem > fr { ret (0usize, false) }
        s = (s + 1usize) & mask
        scanning = (f.slots[s] & 2u64) != 0u64
    }
    ret (0usize, false)
}

// Inserts a key; a duplicate raises its count in the counting variant and is a
// no-op otherwise. `Full` once every slot holds a remainder.
fn quotient_filter_insert(f: *QuotientFilter, key: u64) -> err {
    let (fq, fr) = quotient_split(f, key)
    let mask = f.slots.len - 1usize
    let counting = f.counts.len != 0usize
    if (f.slots[fq] & 7u64) == 0u64 {
        f.slots[fq] = (fr << 3u64) | 1u64
        if counting { f.counts[fq] = 1u32 }
        f.size += 1usize
        ret ok
    }
    let was_occupied = (f.slots[fq] & 1u64) == 1u64
    if was_occupied {
        let (found, present) = quotient_find(f, fq, fr)
        if present {
            if counting && f.counts[found] != 4294967295u32 { f.counts[found] += 1u32 }
            ret ok
        }
    }
    if f.size >= f.slots.len { ret Full }
    f.slots[fq] = f.slots[fq] | 1u64
    var s = quotient_run_start(f, fq)
    var entry = fr << 3u64
    if was_occupied {
        let start = s
        var scanning = true
        while scanning {
            if (f.slots[s] >> 3u64) > fr {
                scanning = false
            } else {
                s = (s + 1usize) & mask
                scanning = (f.slots[s] & 2u64) != 0u64
            }
        }
        if s == start { f.slots[start] = f.slots[start] | 2u64 } else { entry = entry | 2u64 }
    }
    if s != fq { entry = entry | 4u64 }
    var cur = entry
    var cur_count = 1u32
    var at = s
    var placing = true
    while placing {
        let prev = f.slots[at]
        var prev_count = 0u32
        if counting { prev_count = f.counts[at] }
        f.slots[at] = (prev & 1u64) | (cur & 18446744073709551614u64)
        if counting { f.counts[at] = cur_count }
        if (prev & 7u64) == 0u64 {
            placing = false
        } else {
            cur = (prev & 18446744073709551614u64) | 4u64
            cur_count = prev_count
            at = (at + 1usize) & mask
        }
    }
    f.size += 1usize
    ret ok
}

fn quotient_filter_contains(f: *const QuotientFilter, key: u64) -> bool {
    let (fq, fr) = quotient_split(f, key)
    let (s, present) = quotient_find(f, fq, fr)
    if !present { ret false }
    ret f.counts.len == 0usize || f.counts[s] > 0u32
}

// The count stored for a key in a counting quotient filter (zero when absent).
fn counting_quotient_filter_count(f: *const QuotientFilter, key: u64) -> u32 {
    if f.counts.len == 0usize { ret 0u32 }
    let (fq, fr) = quotient_split(f, key)
    let (s, present) = quotient_find(f, fq, fr)
    if !present { ret 0u32 }
    ret f.counts[s]
}

// Lowers a key's count by one; `false` when the count was already zero.
fn counting_quotient_filter_remove(f: *QuotientFilter, key: u64) -> bool {
    if f.counts.len == 0usize { ret false }
    let (fq, fr) = quotient_split(f, key)
    let (s, present) = quotient_find(f, fq, fr)
    if !present || f.counts[s] == 0u32 { ret false }
    f.counts[s] -= 1u32
    ret true
}

// --- Stable and age-partitioned Bloom filters ---------------------------------

// Stable Bloom filter (Deng & Rafiei): `decrements` random cells lose one before
// every insertion sets its `hashes` cells to `max`, so old items fade out and
// the false-positive rate settles instead of climbing.
fn stable_bloom(cells: []u8, hashes: u32, decrements: u32, max: u8) -> (StableBloom, err) {
    if cells.len == 0usize || hashes == 0u32 || max == 0u8 { ret (zero, Invalid) }
    var i = 0usize
    while i < cells.len {
        cells[i] = 0u8
        i += 1usize
    }
    ret (StableBloom { cells: cells, hashes: hashes, decrements: decrements, max: max, state: 7u64 }, ok)
}

fn stable_bloom_insert(s: *StableBloom, key: u64) {
    var p = 0u32
    while p < s.decrements {
        s.state = s.state *% 6364136223846793005u64 +% 1442695040888963407u64
        let cell = usize((s.state >> 33u64) % u64(s.cells.len))
        if s.cells[cell] > 0u8 { s.cells[cell] -= 1u8 }
        p += 1u32
    }
    var k = 0u32
    while k < s.hashes {
        s.cells[usize(minhash_mix(key, u64(k)) % u64(s.cells.len))] = s.max
        k += 1u32
    }
}

fn stable_bloom_contains(s: *const StableBloom, key: u64) -> bool {
    var k = 0u32
    while k < s.hashes {
        if s.cells[usize(minhash_mix(key, u64(k)) % u64(s.cells.len))] == 0u8 { ret false }
        k += 1u32
    }
    ret true
}

// Age-partitioned Bloom filter: `hashes + extra` slices, each key set in the
// `hashes` youngest, one slice retired every `generation` insertions. A key is
// reported present while `hashes` consecutive slices hold it, which is certain
// for the last `extra * generation` insertions and impossible after
// `(hashes + extra) * generation`.
fn bloom_windowed(bits: []u64, hashes: u32, extra: u32, generation: usize) -> (WindowedBloom, err) {
    let slices = hashes + extra
    if hashes == 0u32 || generation == 0usize || bits.len < usize(slices) { ret (zero, Invalid) }
    let words = bits.len / usize(slices)
    var i = 0usize
    while i < words * usize(slices) {
        bits[i] = 0u64
        i += 1usize
    }
    ret (WindowedBloom { bits: bits[..words * usize(slices)], slice_words: words, hashes: hashes, slices: slices, head: 0u32, generation: generation, inserted: 0usize }, ok)
}

fn windowed_bit(w: *const WindowedBloom, slice: u32, key: u64) -> (usize, u64) {
    let bit = minhash_mix(key, u64(slice)) % (u64(w.slice_words) * 64u64)
    ret (usize(slice) * w.slice_words + usize(bit / 64u64), 1u64 << (bit % 64u64))
}

fn bloom_windowed_insert(w: *WindowedBloom, key: u64) {
    if w.inserted == w.generation {
        w.inserted = 0usize
        w.head = (w.head + w.slices - 1u32) % w.slices
        var i = usize(w.head) * w.slice_words
        while i < usize(w.head + 1u32) * w.slice_words {
            w.bits[i] = 0u64
            i += 1usize
        }
    }
    var k = 0u32
    while k < w.hashes {
        let (word, mask) = windowed_bit(w, (w.head + k) % w.slices, key)
        w.bits[word] = w.bits[word] | mask
        k += 1u32
    }
    w.inserted += 1usize
}

fn bloom_windowed_contains(w: *const WindowedBloom, key: u64) -> bool {
    var run = 0u32
    var i = 0u32
    while i < w.slices {
        let (word, mask) = windowed_bit(w, (w.head + i) % w.slices, key)
        if (w.bits[word] & mask) != 0u64 {
            run += 1u32
            if run == w.hashes { ret true }
        } else {
            run = 0u32
        }
        i += 1u32
    }
    ret false
}

// --- Quantiles -----------------------------------------------------------------

// DDSketch (Masson, Lee & Rim): logarithmic bins with base `gamma = (1 + alpha)
// / (1 - alpha)`, so any quantile answers within relative error `alpha`. Bins
// are laid out from the first non-zero value's index minus half the store.
// ponytail: no bin collapsing; a value outside the store answers `Invalid`.
fn ddsketch(bins: []u64, alpha: f64) -> (DdSketch, err) {
    if bins.len == 0usize || alpha <= 0.0f64 || alpha >= 1.0f64 { ret (zero, Invalid) }
    var i = 0usize
    while i < bins.len {
        bins[i] = 0u64
        i += 1usize
    }
    let gamma = (1.0f64 + alpha) / (1.0f64 - alpha)
    ret (DdSketch { bins: bins, offset: 0i64, count: 0u64, zeros: 0u64, gamma: gamma, log_gamma: math.log[f64](gamma) }, ok)
}

fn ddsketch_add(s: *DdSketch, x: f64) -> err {
    if x < 0.0f64 { ret Invalid }
    if x == 0.0f64 {
        s.zeros += 1u64
        s.count += 1u64
        ret ok
    }
    let index = i64(math.ceil[f64](math.log[f64](x) / s.log_gamma))
    if s.count == s.zeros { s.offset = index - i64(s.bins.len / 2usize) }
    let pos = index - s.offset
    if pos < 0i64 || pos >= i64(s.bins.len) { ret Invalid }
    s.bins[usize(pos)] += 1u64
    s.count += 1u64
    ret ok
}

fn ddsketch_quantile(s: *const DdSketch, q: f64) -> f64 {
    if s.count == 0u64 { ret 0.0f64 }
    let rank = u64(q * f64(s.count - 1u64))
    if rank < s.zeros { ret 0.0f64 }
    var seen = s.zeros
    var i = 0usize
    var last = 0usize
    while i < s.bins.len {
        seen += s.bins[i]
        if s.bins[i] != 0u64 { last = i }
        if seen > rank { ret 2.0f64 * math.pow[f64](s.gamma, f64(s.offset + i64(i))) / (s.gamma + 1.0f64) }
        i += 1usize
    }
    ret 2.0f64 * math.pow[f64](s.gamma, f64(s.offset + i64(last))) / (s.gamma + 1.0f64)
}

// Greenwald-Khanna: sorted tuples `(value, gap, delta)` whose rank uncertainty
// stays within `epsilon * count`; neighbours merge when their combined width fits.
fn gk_quantiles(values: []f64, gaps: []u64, deltas: []u64, epsilon: f64) -> (Gk, err) {
    if values.len == 0usize || gaps.len < values.len || deltas.len < values.len { ret (zero, Invalid) }
    if epsilon <= 0.0f64 || epsilon >= 1.0f64 { ret (zero, Invalid) }
    ret (Gk { values: values, gaps: gaps[..values.len], deltas: deltas[..values.len], size: 0usize, count: 0u64, epsilon: epsilon }, ok)
}

fn gk_compress(s: *Gk) {
    if s.size < 3usize { ret }
    let threshold = u64(2.0f64 * s.epsilon * f64(s.count))
    var i = s.size - 2usize
    while i >= 1usize {
        if s.gaps[i] + s.gaps[i + 1usize] + s.deltas[i + 1usize] < threshold {
            s.gaps[i + 1usize] += s.gaps[i]
            var j = i
            while j + 1usize < s.size {
                s.values[j] = s.values[j + 1usize]
                s.gaps[j] = s.gaps[j + 1usize]
                s.deltas[j] = s.deltas[j + 1usize]
                j += 1usize
            }
            s.size -= 1usize
        }
        i -= 1usize
    }
}

fn gk_add(s: *Gk, x: f64) -> err {
    if s.size == s.values.len {
        gk_compress(s)
        if s.size == s.values.len { ret TooSmall }
    }
    var i = 0usize
    while i < s.size && s.values[i] <= x { i += 1usize }
    var delta = 0u64
    if i != 0usize && i != s.size { delta = u64(2.0f64 * s.epsilon * f64(s.count)) }
    var j = s.size
    while j > i {
        s.values[j] = s.values[j - 1usize]
        s.gaps[j] = s.gaps[j - 1usize]
        s.deltas[j] = s.deltas[j - 1usize]
        j -= 1usize
    }
    s.values[i] = x
    s.gaps[i] = 1u64
    s.deltas[i] = delta
    s.size += 1usize
    s.count += 1u64
    let period = u64(1.0f64 / (2.0f64 * s.epsilon))
    if period > 0u64 && s.count % period == 0u64 { gk_compress(s) }
    ret ok
}

// A value whose rank is within `epsilon * count` of `q * count`.
fn gk_quantile(s: *const Gk, q: f64) -> f64 {
    if s.size == 0usize { ret 0.0f64 }
    let goal = math.ceil[f64](q * f64(s.count))
    let slack = s.epsilon * f64(s.count)
    var rmin = 0u64
    var i = 0usize
    while i < s.size {
        rmin += s.gaps[i]
        let rmax = f64(rmin + s.deltas[i])
        if goal - f64(rmin) <= slack && rmax - goal <= slack { ret s.values[i] }
        i += 1usize
    }
    ret s.values[s.size - 1usize]
}

// KLL (Karnin, Lang & Liberty): level `h` holds items of weight `2^h` in a
// region of `2k` slots; a level over its capacity `k * (2/3)^(top - h)` is
// sorted and every other item moves up, the parity chosen by a coin.
fn kll(items: []f64, sizes: []usize, k: usize) -> (Kll, err) {
    if k < 2usize || sizes.len == 0usize || items.len < sizes.len * 2usize * k { ret (zero, Invalid) }
    var h = 0usize
    while h < sizes.len {
        sizes[h] = 0usize
        h += 1usize
    }
    ret (Kll { items: items[..sizes.len * 2usize * k], sizes: sizes, k: k, levels: 1usize, total: 0u64, state: 3u64 }, ok)
}

fn kll_capacity(s: *const Kll, h: usize) -> usize {
    var cap = f64(s.k)
    var d = s.levels - 1usize - h
    while d > 0usize {
        cap = cap * 2.0f64 / 3.0f64
        d -= 1usize
    }
    var c = usize(math.ceil[f64](cap))
    if c < 2usize { c = 2usize }
    ret c
}

fn kll_add(s: *Kll, x: f64) -> err {
    let region = 2usize * s.k
    s.items[s.sizes[0usize]] = x
    s.sizes[0usize] += 1usize
    s.total += 1u64
    var h = 0usize
    while h < s.levels {
        if s.sizes[h] > kll_capacity(s, h) {
            if h + 1usize == s.sizes.len { ret TooSmall }
            if h + 1usize == s.levels { s.levels += 1usize }
            let n = s.sizes[h]
            var level = s.items[h * region..h * region + n]
            sort_f64(level)
            s.state = s.state *% 6364136223846793005u64 +% 1442695040888963407u64
            var i = usize((s.state >> 33u64) & 1u64)
            let base = (h + 1usize) * region
            while i < n - (n % 2usize) {
                s.items[base + s.sizes[h + 1usize]] = level[i]
                s.sizes[h + 1usize] += 1usize
                i += 2usize
            }
            if n % 2usize == 1usize {
                s.items[h * region] = level[n - 1usize]
                s.sizes[h] = 1usize
            } else {
                s.sizes[h] = 0usize
            }
        }
        h += 1usize
    }
    ret ok
}

// The estimated number of items at most `x`.
fn kll_rank(s: *const Kll, x: f64) -> f64 {
    var total = 0.0f64
    var h = 0usize
    while h < s.levels {
        let base = h * 2usize * s.k
        var below = 0usize
        var i = 0usize
        while i < s.sizes[h] {
            if s.items[base + i] <= x { below += 1usize }
            i += 1usize
        }
        total += f64(below) * math.exp2[f64](f64(h))
        h += 1usize
    }
    ret total
}

// The smallest stored item whose estimated rank reaches `q * total`; `scratch`
// holds every stored item.
fn kll_quantile(s: *const Kll, q: f64, scratch: []f64) -> (f64, err) {
    var n = 0usize
    var h = 0usize
    while h < s.levels {
        let base = h * 2usize * s.k
        var i = 0usize
        while i < s.sizes[h] {
            if n == scratch.len { ret (0.0f64, TooSmall) }
            scratch[n] = s.items[base + i]
            n += 1usize
            i += 1usize
        }
        h += 1usize
    }
    if n == 0usize { ret (0.0f64, Invalid) }
    sort_f64(scratch[..n])
    let goal = q * f64(s.total)
    var i = 0usize
    while i < n {
        if kll_rank(s, scratch[i]) >= goal { ret (scratch[i], ok) }
        i += 1usize
    }
    ret (scratch[n - 1usize], ok)
}

// t-digest (Dunning & Ertl), merging form: points buffer up, then centroids and
// buffer merge in value order under the `k1` scale function, which keeps the
// tails fine and the middle coarse.
fn tdigest(means: []f64, weights: []f64, buffer: []f64, compression: f64) -> (TDigest, err) {
    if compression < 10.0f64 || buffer.len == 0usize || means.len == 0usize || weights.len < means.len { ret (zero, Invalid) }
    ret (TDigest { means: means, weights: weights[..means.len], buffer: buffer, size: 0usize, buffered: 0usize, compression: compression, total: 0.0f64, min: 0.0f64, max: 0.0f64 }, ok)
}

fn tdigest_limit(s: *const TDigest, q: f64) -> f64 {
    let k = s.compression / (2.0f64 * pi()) * math.asin[f64](2.0f64 * q - 1.0f64) + 1.0f64
    if k >= s.compression / 4.0f64 { ret 1.0f64 }
    ret (math.sin[f64](2.0f64 * pi() * k / s.compression) + 1.0f64) / 2.0f64
}

// Merges the buffer into the centroids.
fn tdigest_flush(s: *TDigest) -> err {
    if s.buffered == 0usize { ret ok }
    if s.size + s.buffered > s.means.len { ret TooSmall }
    var i = 0usize
    while i < s.buffered {
        s.means[s.size] = s.buffer[i]
        s.weights[s.size] = 1.0f64
        s.size += 1usize
        i += 1usize
    }
    s.buffered = 0usize
    i = 1usize
    while i < s.size {
        let m = s.means[i]
        let w = s.weights[i]
        var j = i
        while j > 0usize && s.means[j - 1usize] > m {
            s.means[j] = s.means[j - 1usize]
            s.weights[j] = s.weights[j - 1usize]
            j -= 1usize
        }
        s.means[j] = m
        s.weights[j] = w
        i += 1usize
    }
    var out = 0usize
    var sofar = 0.0f64
    var limit = tdigest_limit(s, 0.0f64)
    var cur_mean = s.means[0usize]
    var cur_w = s.weights[0usize]
    i = 1usize
    while i < s.size {
        let proposed = cur_w + s.weights[i]
        if (sofar + proposed) / s.total <= limit {
            cur_mean = (cur_mean * cur_w + s.means[i] * s.weights[i]) / proposed
            cur_w = proposed
        } else {
            s.means[out] = cur_mean
            s.weights[out] = cur_w
            out += 1usize
            sofar += cur_w
            limit = tdigest_limit(s, sofar / s.total)
            cur_mean = s.means[i]
            cur_w = s.weights[i]
        }
        i += 1usize
    }
    s.means[out] = cur_mean
    s.weights[out] = cur_w
    s.size = out + 1usize
    ret ok
}

fn tdigest_add(s: *TDigest, x: f64) -> err {
    if s.total == 0.0f64 || x < s.min { s.min = x }
    if s.total == 0.0f64 || x > s.max { s.max = x }
    s.total += 1.0f64
    s.buffer[s.buffered] = x
    s.buffered += 1usize
    if s.buffered == s.buffer.len { ret tdigest_flush(s) }
    ret ok
}

// Interpolates between centroid centres; the ends run to the stored min and max.
fn tdigest_quantile(s: *TDigest, q: f64) -> (f64, err) {
    let e = tdigest_flush(s)
    if e != ok { ret (0.0f64, e) }
    if s.size == 0usize { ret (0.0f64, Invalid) }
    let goal = q * s.total
    var sofar = 0.0f64
    var prev_center = 0.0f64
    var prev_mean = s.min
    var i = 0usize
    while i < s.size {
        let center = sofar + s.weights[i] / 2.0f64
        if goal <= center {
            if center == prev_center { ret (s.means[i], ok) }
            ret (prev_mean + (s.means[i] - prev_mean) * (goal - prev_center) / (center - prev_center), ok)
        }
        sofar += s.weights[i]
        prev_center = center
        prev_mean = s.means[i]
        i += 1usize
    }
    if s.total == prev_center { ret (s.max, ok) }
    ret (prev_mean + (s.max - prev_mean) * (goal - prev_center) / (s.total - prev_center), ok)
}

// P-square (Jain & Chlamtac): five markers whose heights move by parabolic
// interpolation toward the positions the `p`-quantile would put them.
// `state` holds twenty words: heights, positions, desired positions, increments.
fn p_square(state: []f64, p: f64) -> (PSquare, err) {
    if state.len < 20usize || p <= 0.0f64 || p >= 1.0f64 { ret (zero, Invalid) }
    var i = 0usize
    while i < 20usize {
        state[i] = 0.0f64
        i += 1usize
    }
    var s = PSquare { heights: state[..5usize], positions: state[5usize..10usize], desired: state[10usize..15usize], increments: state[15usize..20usize], count: 0usize, p: p }
    s.increments[1usize] = p / 2.0f64
    s.increments[2usize] = p
    s.increments[3usize] = (1.0f64 + p) / 2.0f64
    s.increments[4usize] = 1.0f64
    ret (s, ok)
}

fn p_square_add(s: *PSquare, x: f64) {
    if s.count < 5usize {
        s.heights[s.count] = x
        s.count += 1usize
        if s.count == 5usize {
            sort_f64(s.heights)
            var i = 0usize
            while i < 5usize {
                s.positions[i] = f64(i + 1usize)
                i += 1usize
            }
            s.desired[0usize] = 1.0f64
            s.desired[1usize] = 1.0f64 + 2.0f64 * s.p
            s.desired[2usize] = 1.0f64 + 4.0f64 * s.p
            s.desired[3usize] = 3.0f64 + 2.0f64 * s.p
            s.desired[4usize] = 5.0f64
        }
        ret
    }
    var k = 3usize
    if x < s.heights[0usize] {
        s.heights[0usize] = x
        k = 0usize
    } else if x < s.heights[1usize] {
        k = 0usize
    } else if x < s.heights[2usize] {
        k = 1usize
    } else if x < s.heights[3usize] {
        k = 2usize
    } else if x > s.heights[4usize] {
        s.heights[4usize] = x
    }
    var i = k + 1usize
    while i < 5usize {
        s.positions[i] += 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        s.desired[i] += s.increments[i]
        i += 1usize
    }
    i = 1usize
    while i < 4usize {
        let d = s.desired[i] - s.positions[i]
        let up = d >= 1.0f64 && s.positions[i + 1usize] - s.positions[i] > 1.0f64
        let down = d <= 0.0f64 - 1.0f64 && s.positions[i - 1usize] - s.positions[i] < 0.0f64 - 1.0f64
        if up || down {
            var ds = 1.0f64
            if down { ds = 0.0f64 - 1.0f64 }
            let n0 = s.positions[i - 1usize]
            let n1 = s.positions[i]
            let n2 = s.positions[i + 1usize]
            let q0 = s.heights[i - 1usize]
            let q1 = s.heights[i]
            let q2 = s.heights[i + 1usize]
            var candidate = q1 + ds / (n2 - n0) * ((n1 - n0 + ds) * (q2 - q1) / (n2 - n1) + (n2 - n1 - ds) * (q1 - q0) / (n1 - n0))
            if !(q0 < candidate && candidate < q2) {
                if up { candidate = q1 + (q2 - q1) / (n2 - n1) } else { candidate = q1 - (q1 - q0) / (n1 - n0) }
            }
            s.heights[i] = candidate
            s.positions[i] += ds
        }
        i += 1usize
    }
    s.count += 1usize
}

// The current estimate of the `p`-quantile.
fn p_square_estimate(s: *const PSquare) -> f64 {
    if s.count == 0usize { ret 0.0f64 }
    if s.count >= 5usize { ret s.heights[2usize] }
    var few: [5]f64 = zero
    var i = 0usize
    while i < s.count {
        few[i] = s.heights[i]
        i += 1usize
    }
    sort_f64(few[..s.count])
    ret few[usize(s.p * f64(s.count - 1usize))]
}

// Frugal-1U (Ma, Muthukrishnan & Sandler): the median estimate steps by one
// toward every arriving value.
fn frugal_median(estimate: i64, x: i64) -> i64 {
    if x > estimate { ret estimate + 1i64 }
    if x < estimate { ret estimate - 1i64 }
    ret estimate
}

// --- Cardinality variants ------------------------------------------------------

// HyperLogLog over a key rather than bytes.
fn hll_add_key(h: *HyperLogLog, key: u64) {
    let x = minhash_mix(key, 0u64)
    let index = usize(x >> (64u64 - u64(h.precision)))
    let rest = (x << u64(h.precision)) | (1u64 << (u64(h.precision) - 1u64))
    let rank = u8(bytes.leading_zeros[u64](rest)) + 1u8
    if rank > h.registers[index] { h.registers[index] = rank }
}

// HyperLogLog++ sparse mode: sorted `(index at precision 25, rank)` pairs packed
// into `u32`s, estimated by linear counting over `2^25` registers; `false` from
// an add means the list is full and the sketch should go dense.
fn hll_sparse(entries: []u32, precision: u8) -> (SparseHll, err) {
    if precision < 4u8 || precision > 18u8 || entries.len == 0usize { ret (zero, Invalid) }
    ret (SparseHll { entries: entries, size: 0usize, precision: precision }, ok)
}

fn hll_sparse_add(s: *SparseHll, key: u64) -> bool {
    let x = minhash_mix(key, 0u64)
    let index = u32(x >> 39u64)
    let rest = (x << u64(s.precision)) | (1u64 << (u64(s.precision) - 1u64))
    let rank = bytes.leading_zeros[u64](rest) + 1u32
    var lo = 0usize
    var hi = s.size
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if (s.entries[mid] >> 6u32) < index { lo = mid + 1usize } else { hi = mid }
    }
    if lo < s.size && (s.entries[lo] >> 6u32) == index {
        if (s.entries[lo] & 63u32) < rank { s.entries[lo] = (index << 6u32) | rank }
        ret true
    }
    if s.size == s.entries.len { ret false }
    var j = s.size
    while j > lo {
        s.entries[j] = s.entries[j - 1usize]
        j -= 1usize
    }
    s.entries[lo] = (index << 6u32) | rank
    s.size += 1usize
    ret true
}

fn hll_sparse_estimate(s: *const SparseHll) -> f64 {
    let m = 33554432.0f64
    if s.size == 0usize { ret 0.0f64 }
    ret m * math.log[f64](m / (m - f64(s.size)))
}

// Folds the sparse entries into a dense sketch of the same precision.
fn hll_sparse_to_dense(s: *const SparseHll, h: *HyperLogLog) -> err {
    if h.precision != s.precision { ret Invalid }
    var i = 0usize
    while i < s.size {
        let index = usize((s.entries[i] >> 6u32) >> u32(25u8 - s.precision))
        let rank = u8(s.entries[i] & 63u32)
        if rank > h.registers[index] { h.registers[index] = rank }
        i += 1usize
    }
    ret ok
}

// Sliding HyperLogLog (Chabchoub & Hebrail): every register keeps up to `depth`
// timestamped ranks, newest last and ranks strictly falling with age, so the
// oldest entry inside any window is that window's maximum.
fn hll_sliding(entries: []u64, depth: usize, precision: u8) -> (SlidingHll, err) {
    if precision < 4u8 || precision > 18u8 || depth == 0usize { ret (zero, Invalid) }
    let m = 1usize << usize(precision)
    if entries.len < m * depth { ret (zero, TooSmall) }
    var i = 0usize
    while i < m * depth {
        entries[i] = 0u64
        i += 1usize
    }
    ret (SlidingHll { entries: entries[..m * depth], depth: depth, precision: precision }, ok)
}

// Records a key seen at `time` (times must not decrease).
// ponytail: a full register list drops its oldest entry.
fn hll_sliding_add(s: *SlidingHll, key: u64, time: u64) {
    let x = minhash_mix(key, 0u64)
    let index = usize(x >> (64u64 - u64(s.precision)))
    let rest = (x << u64(s.precision)) | (1u64 << (u64(s.precision) - 1u64))
    let rank = u64(bytes.leading_zeros[u64](rest) + 1u32)
    let base = index * s.depth
    var w = base
    var r = base
    while r < base + s.depth {
        let e = s.entries[r]
        if e != 0u64 && (e & 255u64) > rank {
            s.entries[w] = e
            w += 1usize
        }
        r += 1usize
    }
    if w == base + s.depth {
        r = base
        while r + 1usize < base + s.depth {
            s.entries[r] = s.entries[r + 1usize]
            r += 1usize
        }
        w -= 1usize
    }
    s.entries[w] = (time << 8u64) | rank
    w += 1usize
    while w < base + s.depth {
        s.entries[w] = 0u64
        w += 1usize
    }
}

// The distinct keys seen in the last `window` time units before `now`, folded
// into `registers` (scratch of `2^precision` bytes) and estimated as a dense sketch.
fn hll_sliding_estimate(s: *const SlidingHll, registers: []u8, now: u64, window: u64) -> (f64, err) {
    let (dense, e) = hll_init(registers, s.precision)
    if e != ok { ret (0.0f64, e) }
    var h = dense
    var index = 0usize
    while index < h.registers.len {
        var r = index * s.depth
        while r < (index + 1usize) * s.depth {
            let entry = s.entries[r]
            if entry != 0u64 && now - (entry >> 8u64) < window {
                let rank = u8(entry & 255u64)
                if rank > h.registers[index] { h.registers[index] = rank }
            }
            r += 1usize
        }
        index += 1usize
    }
    ret (hll_estimate(&h), ok)
}

// --- Locality-sensitive hashing and MinHash variants ---------------------------

// The bucket of one band of a MinHash signature: `rows` consecutive slots hash
// to one value, so sets that agree on the whole band collide.
fn lsh_bucket(signature: []const u64, band: usize, rows: usize) -> u64 {
    if rows == 0usize || (band + 1usize) * rows > signature.len { ret 0u64 }
    var h = u64(band)
    var r = 0usize
    while r < rows {
        h = minhash_mix(signature[band * rows + r] ^ h, u64(r))
        r += 1usize
    }
    ret h
}

// Random-projection LSH: bit `b` is the sign of the dot product with the `b`-th
// pseudo-random hyperplane, so the Hamming distance tracks the angle.
fn lsh_random_projection(vector: []const f64, bits: u32, seed: u64) -> u64 {
    var out = 0u64
    var b = 0u32
    while b < bits && b < 64u32 {
        var dot = 0.0f64
        var i = 0usize
        while i < vector.len {
            dot += vector[i] * (2.0f64 * unit(minhash_mix(seed, u64(b) * u64(vector.len) + u64(i))) - 1.0f64)
            i += 1usize
        }
        if dot > 0.0f64 { out = out | (1u64 << u64(b)) }
        b += 1u32
    }
    ret out
}

// p-stable LSH (Datar et al.) for Euclidean distance: the quantised projection
// onto a Gaussian vector with a random offset, `floor((a . v + b) / width)`.
fn lsh_p_stable(vector: []const f64, width: f64, seed: u64) -> i64 {
    var dot = 0.0f64
    var i = 0usize
    while i < vector.len {
        let u1 = unit(minhash_mix(seed, 2u64 * u64(i)))
        let u2 = unit(minhash_mix(seed, 2u64 * u64(i) + 1u64))
        let g = math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](u1)) * math.cos[f64](2.0f64 * pi() * u2)
        dot += vector[i] * g
        i += 1usize
    }
    let b = unit(minhash_mix(seed, 2u64 * u64(vector.len) + 1u64)) * width
    ret i64(math.floor[f64]((dot + b) / width))
}

// One-permutation hashing (Li, Owen & Zhang): one hash per key, binned by its
// value; each bin keeps its minimum, an empty bin signs as all ones.
fn minhash_one_permutation(keys: []const u64, signature: []u64) {
    var k = 0usize
    while k < signature.len {
        signature[k] = 18446744073709551615u64
        k += 1usize
    }
    if signature.len == 0usize { ret }
    var i = 0usize
    while i < keys.len {
        let h = minhash_mix(keys[i], 0u64)
        let bin = usize(h % u64(signature.len))
        if h < signature[bin] { signature[bin] = h }
        i += 1usize
    }
}

// Agreement over the bins that are not empty in both signatures.
fn minhash_one_permutation_similarity(a: []const u64, b: []const u64) -> f64 {
    if a.len == 0usize || a.len != b.len { ret 0.0f64 }
    var same = 0usize
    var live = 0usize
    var i = 0usize
    while i < a.len {
        let empty = 18446744073709551615u64
        if a[i] != empty || b[i] != empty {
            live += 1usize
            if a[i] == b[i] { same += 1usize }
        }
        i += 1usize
    }
    if live == 0usize { ret 0.0f64 }
    ret f64(same) / f64(live)
}

// b-bit MinHash (Li & Konig): keeps the low `bits` of every signature slot,
// packed `64 / bits` to a word; `bits` divides 64. Returns the words used.
fn minhash_b_bit(signature: []const u64, bits: u32, out: []u64) -> (usize, err) {
    if bits == 0u32 || bits > 64u32 || 64u32 % bits != 0u32 { ret (0usize, Invalid) }
    let per = usize(64u32 / bits)
    let words = (signature.len + per - 1usize) / per
    if out.len < words { ret (0usize, TooSmall) }
    var w = 0usize
    while w < words {
        out[w] = 0u64
        w += 1usize
    }
    var mask = 18446744073709551615u64
    if bits < 64u32 { mask = (1u64 << u64(bits)) - 1u64 }
    var i = 0usize
    while i < signature.len {
        out[i / per] = out[i / per] | ((signature[i] & mask) << (u64(i % per) * u64(bits)))
        i += 1usize
    }
    ret (words, ok)
}

// The Jaccard estimate from two b-bit signatures of `count` slots: the match
// rate corrected for the `2^-bits` chance agreement.
fn minhash_b_bit_similarity(a: []const u64, b: []const u64, bits: u32, count: usize) -> f64 {
    if bits == 0u32 || bits > 64u32 || 64u32 % bits != 0u32 || count == 0usize { ret 0.0f64 }
    let per = usize(64u32 / bits)
    if a.len * per < count || b.len * per < count { ret 0.0f64 }
    var mask = 18446744073709551615u64
    if bits < 64u32 { mask = (1u64 << u64(bits)) - 1u64 }
    var same = 0usize
    var i = 0usize
    while i < count {
        let shift = u64(i % per) * u64(bits)
        if ((a[i / per] >> shift) & mask) == ((b[i / per] >> shift) & mask) { same += 1usize }
        i += 1usize
    }
    let chance = math.exp2[f64](0.0f64 - f64(bits))
    let rate = f64(same) / f64(count)
    if chance >= 1.0f64 { ret rate }
    var j = (rate - chance) / (1.0f64 - chance)
    if j < 0.0f64 { j = 0.0f64 }
    ret j
}

// --- Heavy hitters -------------------------------------------------------------

// Top-k over Count-Min: a min-heap of the `heap.len` keys with the largest
// sketch estimates, updated as estimates grow.
fn top_k(counts: []u32, width: usize, depth: usize, heap: []Counter) -> (TopK, err) {
    let (sketch, e) = count_min_init(counts, width, depth)
    if e != ok { ret (zero, e) }
    if heap.len == 0usize { ret (zero, Invalid) }
    counters_clear(heap)
    ret (TopK { sketch: sketch, heap: heap, size: 0usize }, ok)
}

fn top_k_sift_down(heap: []Counter, size: usize, start: usize) {
    var i = start
    var moving = true
    while moving {
        var least = i
        if 2usize * i + 1usize < size && heap[2usize * i + 1usize].count < heap[least].count { least = 2usize * i + 1usize }
        if 2usize * i + 2usize < size && heap[2usize * i + 2usize].count < heap[least].count { least = 2usize * i + 2usize }
        if least == i {
            moving = false
        } else {
            let t = heap[i]
            heap[i] = heap[least]
            heap[least] = t
            i = least
        }
    }
}

fn top_k_add(t: *TopK, key: u64) {
    count_min_add_key(&t.sketch, key, 1u32)
    let estimate = u64(count_min_estimate_key(&t.sketch, key))
    var i = 0usize
    while i < t.size {
        if t.heap[i].key == key {
            t.heap[i].count = estimate
            top_k_sift_down(t.heap, t.size, i)
            ret
        }
        i += 1usize
    }
    if t.size < t.heap.len {
        var at = t.size
        t.heap[at] = Counter { key: key, count: estimate }
        t.size += 1usize
        while at > 0usize && t.heap[(at - 1usize) / 2usize].count > t.heap[at].count {
            let parent = (at - 1usize) / 2usize
            let tmp = t.heap[parent]
            t.heap[parent] = t.heap[at]
            t.heap[at] = tmp
            at = parent
        }
        ret
    }
    if estimate > t.heap[0usize].count {
        t.heap[0usize] = Counter { key: key, count: estimate }
        top_k_sift_down(t.heap, t.size, 0usize)
    }
}

// The tracked estimate for `key`, if it is among the top k.
fn top_k_get(t: *const TopK, key: u64) -> (u64, bool) {
    let (count, found) = counter_get(t.heap[..t.size], key)
    ret (count, found)
}

// Lossy counting (Manku & Motwani): entries carry the bucket they arrived in as
// `delta`; at every bucket boundary (`ceil(1 / epsilon)` items) entries whose
// `count + delta` fall at or below the bucket number are dropped. Every key with
// frequency above `epsilon * seen` survives, undercounted by at most that much.
fn lossy_counting(counters: []Counter, deltas: []u64, epsilon: f64) -> (LossyCounter, err) {
    if counters.len == 0usize || deltas.len < counters.len || epsilon <= 0.0f64 || epsilon >= 1.0f64 { ret (zero, Invalid) }
    counters_clear(counters)
    ret (LossyCounter { counters: counters, deltas: deltas[..counters.len], size: 0usize, seen: 0u64, width: u64(math.ceil[f64](1.0f64 / epsilon)) }, ok)
}

fn lossy_counting_add(s: *LossyCounter, key: u64) -> err {
    let bucket = s.seen / s.width + 1u64
    var i = 0usize
    var found = false
    while i < s.size && !found {
        if s.counters[i].key == key {
            s.counters[i].count += 1u64
            found = true
        }
        i += 1usize
    }
    if !found {
        if s.size == s.counters.len { ret TooSmall }
        s.counters[s.size] = Counter { key: key, count: 1u64 }
        s.deltas[s.size] = bucket - 1u64
        s.size += 1usize
    }
    s.seen += 1u64
    if s.seen % s.width == 0u64 {
        var w = 0usize
        i = 0usize
        while i < s.size {
            if s.counters[i].count + s.deltas[i] > bucket {
                s.counters[w] = s.counters[i]
                s.deltas[w] = s.deltas[i]
                w += 1usize
            }
            i += 1usize
        }
        s.size = w
    }
    ret ok
}

fn lossy_counting_get(s: *const LossyCounter, key: u64) -> (u64, bool) {
    let (count, found) = counter_get(s.counters[..s.size], key)
    ret (count, found)
}
