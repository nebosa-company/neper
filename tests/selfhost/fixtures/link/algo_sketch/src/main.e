// `e.algo.sketch`: a Bloom filter sized for a rate has no false negatives and
// few false positives and merges as a union; a counting filter forgets what is
// removed; Count-Min never underestimates and the conservative form is at least
// as tight; HyperLogLog counts a few thousand distinct keys within a few percent
// and merges; Misra-Gries and Space-Saving keep the heavy key; MinHash tracks
// Jaccard similarity and SimHash keeps near-duplicates close. Each check exits
// with its own code.

use e.algo.sketch
use e.io
use e.mem
use e.os

// Writes the decimal digits of `n` into `out` and returns the slice used.
fn key(out: []u8, n: usize) -> []u8 {
    var digits = 0usize
    var v = n
    while true {
        digits += 1usize
        v = v / 10usize
        if v == 0usize { break }
    }
    var at = digits
    v = n
    while at > 0usize {
        at -= 1usize
        out[at] = u8(48usize + v % 10usize)
        v = v / 10usize
    }
    ret out[..digits]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buffer: [16]u8 = zero

    // 1: Bloom filter over 1000 keys at a 1% rate.
    let (bit_count, hashes) = sketch.bloom_size(1000usize, 0.01f64)
    if bit_count < 9000usize || bit_count > 11000usize || hashes < 5u32 || hashes > 8u32 { os.exit(1i32) }
    var words: [256]u64 = zero
    let (bloom, bloom_error) = sketch.bloom_init(words[..bit_count / 64usize], hashes)
    if bloom_error != ok { os.exit(1i32) }
    var filter = bloom
    var n = 0usize
    while n < 1000usize {
        sketch.bloom_insert(&filter, key(buffer[..], n))
        n += 1usize
    }
    n = 0usize
    while n < 1000usize {
        if !sketch.bloom_contains(&filter, key(buffer[..], n)) { os.exit(1i32) }
        n += 1usize
    }
    var false_positives = 0usize
    n = 1000usize
    while n < 11000usize {
        if sketch.bloom_contains(&filter, key(buffer[..], n)) { false_positives += 1usize }
        n += 1usize
    }
    if false_positives > 300usize { os.exit(1i32) }
    // A second filter holding other keys, merged in, answers for both.
    var other_words: [256]u64 = zero
    let (other, other_error) = sketch.bloom_init(other_words[..bit_count / 64usize], hashes)
    if other_error != ok { os.exit(1i32) }
    var second = other
    sketch.bloom_insert(&second, "merged-key")
    if sketch.bloom_contains(&filter, "merged-key") { os.exit(1i32) }
    if sketch.bloom_merge(&filter, &second) != ok { os.exit(1i32) }
    if !sketch.bloom_contains(&filter, "merged-key") || !sketch.bloom_contains(&filter, key(buffer[..], 17usize)) { os.exit(1i32) }
    var short_words: [4]u64 = zero
    let (small_filter, small_error) = sketch.bloom_init(short_words[..], hashes)
    if small_error != ok { os.exit(1i32) }
    var small = small_filter
    if sketch.bloom_merge(&filter, &small) != sketch.Invalid { os.exit(1i32) }
    let (_, empty_error) = sketch.bloom_init(words[..0usize], 1u32)
    if empty_error != sketch.Invalid { os.exit(1i32) }

    // 2: the counting filter forgets removed items and refuses to remove absent ones.
    var counts8: [1024]u8 = zero
    let (counting, counting_error) = sketch.counting_bloom_init(counts8[..], 4u32)
    if counting_error != ok { os.exit(2i32) }
    var cbf = counting
    sketch.counting_bloom_insert(&cbf, "apple")
    sketch.counting_bloom_insert(&cbf, "apple")
    sketch.counting_bloom_insert(&cbf, "pear")
    if !sketch.counting_bloom_contains(&cbf, "apple") || !sketch.counting_bloom_contains(&cbf, "pear") { os.exit(2i32) }
    if sketch.counting_bloom_remove(&cbf, "plum") { os.exit(2i32) }
    if !sketch.counting_bloom_remove(&cbf, "apple") || !sketch.counting_bloom_contains(&cbf, "apple") { os.exit(2i32) }
    if !sketch.counting_bloom_remove(&cbf, "apple") || sketch.counting_bloom_contains(&cbf, "apple") { os.exit(2i32) }
    if !sketch.counting_bloom_contains(&cbf, "pear") { os.exit(2i32) }

    // 3: Count-Min over a skewed stream never underestimates.
    var counts32: [2048]u32 = zero
    let (cm, cm_error) = sketch.count_min_init(counts32[..], 512usize, 4usize)
    if cm_error != ok { os.exit(3i32) }
    var counted = cm
    var conservative_store: [2048]u32 = zero
    let (cmc, cmc_error) = sketch.count_min_init(conservative_store[..], 512usize, 4usize)
    if cmc_error != ok { os.exit(3i32) }
    var conservative = cmc
    // Key i occurs 1000 / (i + 1) times for i in 0..100.
    var i = 0usize
    while i < 100usize {
        let times = 1000usize / (i + 1usize)
        var r = 0usize
        while r < times {
            sketch.count_min_add(&counted, key(buffer[..], i), 1u32)
            sketch.count_min_add_conservative(&conservative, key(buffer[..], i), 1u32)
            r += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < 100usize {
        let truth = u32(1000usize / (i + 1usize))
        let plain = sketch.count_min_estimate(&counted, key(buffer[..], i))
        let tight = sketch.count_min_estimate(&conservative, key(buffer[..], i))
        if plain < truth || tight < truth || tight > plain { os.exit(3i32) }
        if plain > truth + 40u32 { os.exit(3i32) }
        i += 1usize
    }
    if sketch.count_min_estimate(&counted, "never") > 40u32 { os.exit(3i32) }
    let (_, narrow_error) = sketch.count_min_init(counts32[..], 512usize, 5usize)
    if narrow_error != sketch.TooSmall { os.exit(3i32) }
    let (_, zero_error) = sketch.count_min_init(counts32[..], 0usize, 5usize)
    if zero_error != sketch.Invalid { os.exit(3i32) }

    // 4: HyperLogLog at precision 12 over 5000 distinct keys, each seen twice.
    var registers: [4096]u8 = zero
    let (hll, hll_error) = sketch.hll_init(registers[..], 12u8)
    if hll_error != ok { os.exit(4i32) }
    var counter = hll
    if sketch.hll_estimate(&counter) != 0.0f64 { os.exit(4i32) }
    n = 0usize
    while n < 5000usize {
        sketch.hll_add(&counter, key(buffer[..], n))
        sketch.hll_add(&counter, key(buffer[..], n))
        n += 1usize
    }
    let estimate = sketch.hll_estimate(&counter)
    if estimate < 4700.0f64 || estimate > 5300.0f64 { os.exit(4i32) }
    // Small cardinalities go through linear counting and land close.
    var few_registers: [4096]u8 = zero
    let (few_hll, few_error) = sketch.hll_init(few_registers[..], 12u8)
    if few_error != ok { os.exit(4i32) }
    var few = few_hll
    n = 0usize
    while n < 50usize {
        sketch.hll_add(&few, key(buffer[..], 100000usize + n))
        n += 1usize
    }
    let few_estimate = sketch.hll_estimate(&few)
    if few_estimate < 45.0f64 || few_estimate > 55.0f64 { os.exit(4i32) }
    // Merging disjoint sketches adds their cardinalities.
    if sketch.hll_merge(&counter, &few) != ok { os.exit(4i32) }
    let merged = sketch.hll_estimate(&counter)
    if merged < 4740.0f64 || merged > 5360.0f64 { os.exit(4i32) }
    var tiny_registers: [16]u8 = zero
    let (tiny_hll, tiny_error) = sketch.hll_init(tiny_registers[..], 4u8)
    if tiny_error != ok { os.exit(4i32) }
    var tiny = tiny_hll
    if sketch.hll_merge(&counter, &tiny) != sketch.Invalid { os.exit(4i32) }
    let (_, precision_error) = sketch.hll_init(registers[..], 3u8)
    if precision_error != sketch.Invalid { os.exit(4i32) }
    let (_, room_error) = sketch.hll_init(tiny_registers[..], 5u8)
    if room_error != sketch.TooSmall { os.exit(4i32) }

    // 5: heavy hitters: key 7 is 40% of a stream of 1000 over 20 other keys.
    var mg: [8]sketch.Counter = zero
    var ss: [8]sketch.Counter = zero
    sketch.counters_clear(mg[..])
    sketch.counters_clear(ss[..])
    n = 0usize
    while n < 1000usize {
        var k = 7u64
        if n % 5usize != 0usize { k = 100u64 + u64(n % 21usize) }
        sketch.misra_gries_add(mg[..], k)
        sketch.space_saving_add(ss[..], k)
        n += 1usize
    }
    let (mg_count, mg_found) = sketch.counter_get(mg[..], 7u64)
    if !mg_found || mg_count > 200u64 || mg_count + 112u64 < 200u64 { os.exit(5i32) }
    let (ss_count, ss_found) = sketch.counter_get(ss[..], 7u64)
    if !ss_found || ss_count < 200u64 { os.exit(5i32) }
    let (_, absent) = sketch.counter_get(mg[..], 999u64)
    if absent { os.exit(5i32) }

    // 6: MinHash similarity follows Jaccard; SimHash keeps near-duplicates close.
    var set_a: [100]u64 = zero
    var set_b: [100]u64 = zero
    i = 0usize
    while i < 100usize {
        set_a[i] = u64(i)
        set_b[i] = u64(i + 50usize)
        i += 1usize
    }
    var sig_a: [128]u64 = zero
    var sig_b: [128]u64 = zero
    var sig_a2: [128]u64 = zero
    sketch.minhash(set_a[..], sig_a[..])
    sketch.minhash(set_b[..], sig_b[..])
    sketch.minhash(set_a[..], sig_a2[..])
    // Jaccard of {0..99} and {50..149} is 50 / 150.
    let similarity = sketch.minhash_similarity(sig_a[..], sig_b[..])
    if similarity < 0.2f64 || similarity > 0.47f64 { os.exit(6i32) }
    if sketch.minhash_similarity(sig_a[..], sig_a2[..]) != 1.0f64 { os.exit(6i32) }
    if sketch.minhash_similarity(sig_a[..], sig_b[..64usize]) != 0.0f64 { os.exit(6i32) }
    var no_keys: [0]u64 = zero
    var sig_empty: [4]u64 = zero
    sketch.minhash(no_keys[..], sig_empty[..])
    if sig_empty[0usize] != 18446744073709551615u64 { os.exit(6i32) }
    var same_weights: [0]u32 = zero
    let fp_a = sketch.simhash(set_a[..], same_weights[..])
    var nearly: [100]u64 = zero
    i = 0usize
    while i < 100usize {
        nearly[i] = u64(i)
        i += 1usize
    }
    nearly[3usize] = 7777u64
    nearly[40usize] = 8888u64
    let fp_near = sketch.simhash(nearly[..], same_weights[..])
    let fp_far = sketch.simhash(set_b[..], same_weights[..])
    if sketch.simhash_distance(fp_a, fp_a) != 0u32 { os.exit(6i32) }
    if sketch.simhash_distance(fp_a, fp_near) > 12u32 { os.exit(6i32) }
    if sketch.simhash_distance(fp_a, fp_far) <= sketch.simhash_distance(fp_a, fp_near) { os.exit(6i32) }
    // A heavy weight on one feature dominates the fingerprint.
    var one_feature: [1]u64 = zero
    one_feature[0usize] = 4242u64
    var heavy: [100]u32 = zero
    i = 0usize
    while i < 100usize {
        heavy[i] = 1u32
        i += 1usize
    }
    heavy[0usize] = 1000u32
    var weighted: [100]u64 = zero
    i = 0usize
    while i < 100usize {
        weighted[i] = u64(i) + 500u64
        i += 1usize
    }
    weighted[0usize] = 4242u64
    if sketch.simhash(weighted[..], heavy[..]) != sketch.simhash(one_feature[..], same_weights[..]) { os.exit(6i32) }

    try io.print("algo sketch ok\n")
    ret ok
}
