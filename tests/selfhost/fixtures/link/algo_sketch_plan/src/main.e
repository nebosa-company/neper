// `e.algo.sketch`, the planned additions: static filters (xor, binary fuse,
// ribbon), cuckoo and quotient filters, stable and age-partitioned Bloom
// filters, dyadic Count-Min ranges, Count Sketch and AMS moments, the
// cardinality estimators (Flajolet-Martin, linear counting, KMV, theta with
// union and intersection, sparse and sliding HyperLogLog), the quantile
// sketches (DDSketch, GK, KLL, t-digest, P-square, Frugal), heavy hitters
// (lossy counting, top-k, whole-stream Misra-Gries and Space-Saving) and the
// similarity hashes (LSH banding, random projection, p-stable, one-permutation
// and b-bit MinHash). Expected values come from a bit-exact Python replica over
// an LCG stream of 20,000 distinct values seen 1.5 times each. Each check group
// exits with its own code.

use e.algo.sketch
use e.io
use e.mem
use e.os

fn fill_keys(out: []u64, from: usize) {
    var i = 0usize
    while i < out.len {
        out[i] = u64(from + i)
        i += 1usize
    }
}

fn near(x: f64, want: f64, rel: f64) -> bool { ret x >= want * (1.0f64 - rel) && x <= want * (1.0f64 + rel) }

fn main(a: *mem.Arena, args: []str) -> err {
    let (vals, vals_error) = mem.alloc[u64](a, 20000usize)
    if vals_error != ok { os.exit(99i32) }
    var state = 12345u64
    var i = 0usize
    while i < 20000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        vals[i] = state >> 33u64
        i += 1usize
    }
    let (hh, hh_error) = mem.alloc[u64](a, 10000usize)
    if hh_error != ok { os.exit(99i32) }
    i = 0usize
    while i < 10000usize {
        hh[i] = 100u64 + vals[i] % 50u64
        if i % 5usize == 0usize { hh[i] = 7u64 }
        i += 1usize
    }
    let (pos, pos_error) = mem.alloc[u64](a, 5000usize)
    if pos_error != ok { os.exit(99i32) }
    fill_keys(pos, 0usize)
    let (scratch, scratch_error) = mem.alloc[u64](a, 30000usize)
    if scratch_error != ok { os.exit(99i32) }
    let (bytes8k, bytes_error) = mem.alloc[u8](a, 8192usize)
    if bytes_error != ok { os.exit(99i32) }

    // 1: AMS F2 over the heavy-hitter stream lands near the exact 5290528.
    var ams: [64]i64 = zero
    i = 0usize
    while i < 10000usize {
        sketch.ams_f2_add(ams[..], hh[i], 1i64)
        i += 1usize
    }
    if !near(sketch.ams_f2(ams[..]), 5290528.0f64, 0.05f64) { os.exit(1i32) }

    // 2: binary fuse filter over 5000 keys: no false negatives, few false positives.
    let (fuse_cap, fuse_scratch) = sketch.binary_fuse_size(5000usize)
    if fuse_cap != 6656usize || fuse_scratch > scratch.len { os.exit(2i32) }
    let (fuse, fuse_error) = sketch.binary_fuse_filter(pos, bytes8k, scratch)
    if fuse_error != ok || fuse.seed != 1442695040888963407u64 { os.exit(2i32) }
    var misses = 0usize
    i = 0usize
    while i < 10000usize {
        let hit = sketch.static_filter_contains(&fuse, u64(i))
        if i < 5000usize && !hit { os.exit(2i32) }
        if i >= 5000usize && hit { misses += 1usize }
        i += 1usize
    }
    if misses != 26usize { os.exit(2i32) }

    // 3: age-partitioned Bloom filter keeps the last 3500 keys and forgets the old.
    var window_bits: [1024]u64 = zero
    let (windowed, windowed_error) = sketch.bloom_windowed(window_bits[..], 3u32, 7u32, 500usize)
    if windowed_error != ok { os.exit(3i32) }
    var wb = windowed
    i = 0usize
    while i < 10000usize {
        sketch.bloom_windowed_insert(&wb, u64(i))
        i += 1usize
    }
    misses = 0usize
    i = 0usize
    while i < 10000usize {
        let hit = sketch.bloom_windowed_contains(&wb, u64(i))
        if i >= 6500usize && !hit { os.exit(3i32) }
        if i < 5000usize && hit { misses += 1usize }
        i += 1usize
    }
    if misses != 259usize { os.exit(3i32) }

    // 4: dyadic Count-Min ranges never undercount the 3397 keys in 100..=1500.
    var level_store: [4096]u32 = zero
    var levels: [8]sketch.CountMin = zero
    i = 0usize
    while i < 8usize {
        let (level, level_error) = sketch.count_min_init(level_store[i * 512usize..(i + 1usize) * 512usize], 256usize, 2usize)
        if level_error != ok { os.exit(4i32) }
        levels[i] = level
        i += 1usize
    }
    i = 0usize
    while i < 10000usize {
        sketch.count_min_range_add(levels[..], vals[i] % 4096u64, 1u32)
        i += 1usize
    }
    if sketch.count_min_range(levels[..], 100u64, 1500u64) != 3486u64 { os.exit(4i32) }
    if sketch.count_min_range(levels[..], 1500u64, 100u64) != 0u64 { os.exit(4i32) }

    // 5: Count Sketch medians are unbiased: key 7 reads 2000 and key 120 reads 147.
    var cs_store: [2560]i64 = zero
    let (cs, cs_error) = sketch.count_sketch_init(cs_store[..], 512usize, 5usize)
    if cs_error != ok { os.exit(5i32) }
    var counted = cs
    i = 0usize
    while i < 10000usize {
        sketch.count_sketch_add(&counted, hh[i], 1i64)
        i += 1usize
    }
    if sketch.count_sketch(&counted, 7u64) != 2000i64 || sketch.count_sketch(&counted, 120u64) != 147i64 { os.exit(5i32) }

    // 6: counting quotient filter counts duplicates and decrements on removal.
    var cq_slots: [1024]u64 = zero
    var cq_counts: [1024]u32 = zero
    let (cq, cq_error) = sketch.counting_quotient_filter(cq_slots[..], cq_counts[..], 10u8, 16u8)
    if cq_error != ok { os.exit(6i32) }
    var cqf = cq
    i = 0usize
    while i < 500usize {
        if sketch.quotient_filter_insert(&cqf, u64(i)) != ok || sketch.quotient_filter_insert(&cqf, u64(i)) != ok { os.exit(6i32) }
        i += 1usize
    }
    if sketch.quotient_filter_insert(&cqf, 0u64) != ok { os.exit(6i32) }
    if sketch.counting_quotient_filter_count(&cqf, 0u64) != 3u32 || sketch.counting_quotient_filter_count(&cqf, 5u64) != 2u32 { os.exit(6i32) }
    if sketch.counting_quotient_filter_count(&cqf, 999u64) != 0u32 || sketch.quotient_filter_contains(&cqf, 999u64) { os.exit(6i32) }
    if !sketch.counting_quotient_filter_remove(&cqf, 5u64) || sketch.counting_quotient_filter_count(&cqf, 5u64) != 1u32 { os.exit(6i32) }
    if !sketch.counting_quotient_filter_remove(&cqf, 5u64) || sketch.counting_quotient_filter_remove(&cqf, 5u64) { os.exit(6i32) }
    if sketch.quotient_filter_contains(&cqf, 5u64) || !sketch.quotient_filter_contains(&cqf, 6u64) { os.exit(6i32) }

    // 7: cuckoo filter at 61% load: every key lands, removal forgets, 101 false positives.
    let (cuckoo, cuckoo_error) = sketch.cuckoo_init(bytes8k)
    if cuckoo_error != ok { os.exit(7i32) }
    var cf = cuckoo
    i = 0usize
    while i < 5000usize {
        if sketch.cuckoo_insert(&cf, u64(i)) != ok { os.exit(7i32) }
        i += 1usize
    }
    misses = 0usize
    i = 0usize
    while i < 10000usize {
        let hit = sketch.cuckoo_contains(&cf, u64(i))
        if i < 5000usize && !hit { os.exit(7i32) }
        if i >= 5000usize && hit { misses += 1usize }
        i += 1usize
    }
    if misses != 101usize { os.exit(7i32) }
    if !sketch.cuckoo_remove(&cf, 3u64) || sketch.cuckoo_contains(&cf, 3u64) || sketch.cuckoo_remove(&cf, 3u64) { os.exit(7i32) }

    // 8: DDSketch answers the median and the 99th percentile within 1% relative error.
    var dd_bins: [2048]u64 = zero
    let (dd, dd_error) = sketch.ddsketch(dd_bins[..], 0.01f64)
    if dd_error != ok { os.exit(8i32) }
    var dds = dd
    i = 0usize
    while i < 20000usize {
        if sketch.ddsketch_add(&dds, f64(vals[i])) != ok { os.exit(8i32) }
        i += 1usize
    }
    if !near(sketch.ddsketch_quantile(&dds, 0.5f64), 1081143373.0f64, 0.01f64) { os.exit(8i32) }
    if !near(sketch.ddsketch_quantile(&dds, 0.99f64), 2123931221.0f64, 0.01f64) { os.exit(8i32) }
    if sketch.ddsketch_add(&dds, 0.0f64 - 1.0f64) != sketch.Invalid { os.exit(8i32) }

    // 9: Flajolet-Martin over 64 bitmaps counts the 20000 distinct values within 1%.
    var bitmaps: [64]u64 = zero
    i = 0usize
    while i < 30000usize {
        sketch.flajolet_martin_add(bitmaps[..], vals[i % 20000usize])
        i += 1usize
    }
    if !near(sketch.flajolet_martin(bitmaps[..]), 19848.717f64, 0.001f64) { os.exit(9i32) }

    // 10: the Frugal median of the values modulo 100 settles on 50.
    var frugal = 0i64
    i = 0usize
    while i < 20000usize {
        frugal = sketch.frugal_median(frugal, i64(vals[i] % 100u64))
        i += 1usize
    }
    if frugal != 50i64 { os.exit(10i32) }

    // 11: GK at epsilon 0.01 keeps 77 tuples and answers the median at rank 0.4987.
    var gk_values: [400]f64 = zero
    var gk_gaps: [400]u64 = zero
    var gk_deltas: [400]u64 = zero
    let (gk, gk_error) = sketch.gk_quantiles(gk_values[..], gk_gaps[..], gk_deltas[..], 0.01f64)
    if gk_error != ok { os.exit(11i32) }
    var gks = gk
    i = 0usize
    while i < 20000usize {
        if sketch.gk_add(&gks, f64(vals[i])) != ok { os.exit(11i32) }
        i += 1usize
    }
    if gks.size != 77usize || sketch.gk_quantile(&gks, 0.5f64) != 1078457411.0f64 { os.exit(11i32) }

    // 12: sliding HyperLogLog counts the last 10000 items' distinct keys.
    var sliding_entries: [4096]u64 = zero
    let (sliding, sliding_error) = sketch.hll_sliding(sliding_entries[..], 4usize, 10u8)
    if sliding_error != ok { os.exit(12i32) }
    var sl = sliding
    i = 0usize
    while i < 30000usize {
        sketch.hll_sliding_add(&sl, vals[i % 20000usize], u64(i))
        i += 1usize
    }
    var registers: [4096]u8 = zero
    let (recent, recent_error) = sketch.hll_sliding_estimate(&sl, registers[..1024usize], 30000u64, 10000u64)
    if recent_error != ok || !near(recent, 9885.15f64, 0.001f64) { os.exit(12i32) }

    // 13: sparse HyperLogLog++ counts 2000 keys exactly enough and folds into a dense sketch.
    var sparse_entries: [4096]u32 = zero
    let (sparse, sparse_error) = sketch.hll_sparse(sparse_entries[..], 12u8)
    if sparse_error != ok { os.exit(13i32) }
    var sp = sparse
    i = 0usize
    while i < 4000usize {
        if !sketch.hll_sparse_add(&sp, vals[i % 2000usize]) { os.exit(13i32) }
        i += 1usize
    }
    if sp.size != 2000usize || !near(sketch.hll_sparse_estimate(&sp), 2000.0596f64, 0.0001f64) { os.exit(13i32) }
    let (dense, dense_error) = sketch.hll_init(registers[..], 12u8)
    if dense_error != ok { os.exit(13i32) }
    var dn = dense
    if sketch.hll_sparse_to_dense(&sp, &dn) != ok || !near(sketch.hll_estimate(&dn), 2004.2949f64, 0.0001f64) { os.exit(13i32) }
    i = 2000usize
    while i < 4200usize && sketch.hll_sparse_add(&sp, vals[i]) { i += 1usize }
    if i != 4096usize { os.exit(13i32) }

    // 14: KLL with k = 128 stores 242 items over 8 levels and answers the median at rank 0.5073.
    var kll_items: [4096]f64 = zero
    var kll_sizes: [16]usize = zero
    let (kll, kll_error) = sketch.kll(kll_items[..], kll_sizes[..], 128usize)
    if kll_error != ok { os.exit(14i32) }
    var ks = kll
    i = 0usize
    while i < 20000usize {
        if sketch.kll_add(&ks, f64(vals[i])) != ok { os.exit(14i32) }
        i += 1usize
    }
    var kll_scratch: [512]f64 = zero
    let (kll_median, kll_median_error) = sketch.kll_quantile(&ks, 0.5f64, kll_scratch[..])
    if kll_median_error != ok || ks.levels != 8usize || kll_median != 1095697944.0f64 { os.exit(14i32) }
    if sketch.kll_rank(&ks, kll_median) < 10000.0f64 { os.exit(14i32) }

    // 15: KMV over 256 minima counts the stream within 1%.
    var kmv_hashes: [256]u64 = zero
    var km = sketch.kmv_init(kmv_hashes[..])
    i = 0usize
    while i < 30000usize {
        sketch.kmv_add(&km, vals[i % 20000usize])
        i += 1usize
    }
    if !near(sketch.kmv(&km), 19910.338f64, 0.001f64) { os.exit(15i32) }

    // 16: linear counting over 131072 bits lands within 0.1% of 20000.
    var lc_bits: [2048]u64 = zero
    i = 0usize
    while i < 30000usize {
        sketch.linear_counting_add(lc_bits[..], vals[i % 20000usize])
        i += 1usize
    }
    if !near(sketch.linear_counting(lc_bits[..]), 20008.3186f64, 0.0001f64) { os.exit(16i32) }

    // 17: lossy counting keeps key 7 at its exact count and every key above the threshold.
    var lossy_counters: [200]sketch.Counter = zero
    var lossy_deltas: [200]u64 = zero
    let (lossy, lossy_error) = sketch.lossy_counting(lossy_counters[..], lossy_deltas[..], 0.01f64)
    if lossy_error != ok { os.exit(17i32) }
    var lc = lossy
    i = 0usize
    while i < 10000usize {
        if sketch.lossy_counting_add(&lc, hh[i]) != ok { os.exit(17i32) }
        i += 1usize
    }
    let (lossy_seven, lossy_found) = sketch.lossy_counting_get(&lc, 7u64)
    if !lossy_found || lossy_seven != 2000u64 || lc.size != 51usize { os.exit(17i32) }

    // 18: LSH banding: 28 of 32 bands agree for a near-duplicate set and none for a disjoint one.
    var set_a: [100]u64 = zero
    var set_b: [100]u64 = zero
    var set_near: [100]u64 = zero
    i = 0usize
    while i < 100usize {
        set_a[i] = u64(i)
        set_b[i] = u64(i + 50usize)
        set_near[i] = u64(i)
        i += 1usize
    }
    set_near[3usize] = 7777u64
    set_near[40usize] = 8888u64
    var sig_a: [128]u64 = zero
    var sig_b: [128]u64 = zero
    var sig_near: [128]u64 = zero
    sketch.minhash(set_a[..], sig_a[..])
    sketch.minhash(set_b[..], sig_b[..])
    sketch.minhash(set_near[..], sig_near[..])
    var agree_near = 0usize
    var agree_b = 0usize
    i = 0usize
    while i < 32usize {
        if sketch.lsh_bucket(sig_a[..], i, 4usize) == sketch.lsh_bucket(sig_near[..], i, 4usize) { agree_near += 1usize }
        if sketch.lsh_bucket(sig_a[..], i, 4usize) == sketch.lsh_bucket(sig_b[..], i, 4usize) { agree_b += 1usize }
        i += 1usize
    }
    if agree_near != 28usize || agree_b != 0usize || sketch.lsh_bucket(sig_a[..], 32usize, 4usize) != 0u64 { os.exit(18i32) }
    var point = [4]f64{ 1.0f64, 2.0f64, 3.0f64, 4.0f64 }
    var point_far = [4]f64{ 101.0f64, 102.0f64, 103.0f64, 104.0f64 }
    let sign_a = sketch.lsh_random_projection(point[..], 32u32, 5u64)
    if sketch.simhash_distance(sign_a, sketch.lsh_random_projection(point_far[..], 32u32, 5u64)) == 0u32 { os.exit(18i32) }
    if sign_a != sketch.lsh_random_projection(point[..], 32u32, 5u64) { os.exit(18i32) }

    // 19: p-stable LSH buckets a point with its near neighbour under all ten seeds and never with a far one.
    var point_near = [4]f64{ 1.01f64, 2.01f64, 3.01f64, 4.01f64 }
    var same_near = 0usize
    var same_far = 0usize
    i = 0usize
    while i < 10usize {
        let bucket = sketch.lsh_p_stable(point[..], 4.0f64, u64(i))
        if bucket == sketch.lsh_p_stable(point_near[..], 4.0f64, u64(i)) { same_near += 1usize }
        if bucket == sketch.lsh_p_stable(point_far[..], 4.0f64, u64(i)) { same_far += 1usize }
        i += 1usize
    }
    if same_near != 10usize || same_far != 0usize { os.exit(19i32) }

    // 20: b-bit MinHash at two bits packs 128 slots into four words and estimates Jaccard 1/3.
    var packed_a: [4]u64 = zero
    var packed_b: [4]u64 = zero
    let (words_a, pack_a_error) = sketch.minhash_b_bit(sig_a[..], 2u32, packed_a[..])
    let (words_b, pack_b_error) = sketch.minhash_b_bit(sig_b[..], 2u32, packed_b[..])
    if pack_a_error != ok || pack_b_error != ok || words_a != 4usize || words_b != 4usize { os.exit(20i32) }
    if !near(sketch.minhash_b_bit_similarity(packed_a[..], packed_b[..], 2u32, 128usize), 0.354166f64, 0.001f64) { os.exit(20i32) }
    if sketch.minhash_b_bit_similarity(packed_a[..], packed_a[..], 2u32, 128usize) != 1.0f64 { os.exit(20i32) }
    let (_, pack_bad) = sketch.minhash_b_bit(sig_a[..], 3u32, packed_a[..])
    if pack_bad != sketch.Invalid { os.exit(20i32) }

    // 21: one-permutation hashing over 64 bins estimates the same Jaccard.
    var oph_a: [64]u64 = zero
    var oph_b: [64]u64 = zero
    sketch.minhash_one_permutation(set_a[..], oph_a[..])
    sketch.minhash_one_permutation(set_b[..], oph_b[..])
    if !near(sketch.minhash_one_permutation_similarity(oph_a[..], oph_b[..]), 0.295082f64, 0.001f64) { os.exit(21i32) }
    if sketch.minhash_one_permutation_similarity(oph_a[..], oph_a[..]) != 1.0f64 { os.exit(21i32) }

    // 22: Misra-Gries over the whole stream tracks key 7 within the bound.
    var mg: [8]sketch.Counter = zero
    sketch.misra_gries(mg[..], hh)
    let (mg_count, mg_found) = sketch.counter_get(mg[..], 7u64)
    if !mg_found || mg_count > 2000u64 || mg_count + 10000u64 / 9u64 < 2000u64 { os.exit(22i32) }

    // 23: P-square tracks the median to within a hundredth of a percent.
    var p2_state: [20]f64 = zero
    let (p2, p2_error) = sketch.p_square(p2_state[..], 0.5f64)
    if p2_error != ok { os.exit(23i32) }
    var ps = p2
    i = 0usize
    while i < 20000usize {
        sketch.p_square_add(&ps, f64(vals[i]))
        i += 1usize
    }
    if !near(sketch.p_square_estimate(&ps), 1081066762.7192342f64, 0.0000001f64) { os.exit(23i32) }
    if !near(sketch.p_square_estimate(&ps), 1081148106.0f64, 0.001f64) { os.exit(23i32) }

    // 24: quotient filter with 4096 slots holds 3000 keys with no false positives at 20 remainder bits and fills at 4096.
    var qf_slots: [4096]u64 = zero
    let (qf, qf_error) = sketch.quotient_filter(qf_slots[..], 12u8, 20u8)
    if qf_error != ok { os.exit(24i32) }
    var q = qf
    i = 0usize
    while i < 3000usize {
        if sketch.quotient_filter_insert(&q, u64(i)) != ok { os.exit(24i32) }
        i += 1usize
    }
    i = 0usize
    while i < 10000usize {
        if sketch.quotient_filter_contains(&q, u64(i)) != (i < 3000usize) { os.exit(24i32) }
        i += 1usize
    }
    i = 3000usize
    while i < 5000usize && sketch.quotient_filter_insert(&q, u64(i)) == ok { i += 1usize }
    if i != 4096usize || q.size != 4096usize || sketch.quotient_filter_insert(&q, u64(i)) != sketch.Full { os.exit(24i32) }
    if !sketch.quotient_filter_contains(&q, 2999u64) || !sketch.quotient_filter_contains(&q, 4095u64) { os.exit(24i32) }

    // 25: ribbon filter over 5000 keys in 5314 slots: no false negatives, 19 false positives.
    let (ribbon, ribbon_error) = sketch.ribbon_filter(pos, bytes8k[..sketch.ribbon_size(5000usize)], scratch)
    if ribbon_error != ok || ribbon.seed != 1442695040888963407u64 { os.exit(25i32) }
    misses = 0usize
    i = 0usize
    while i < 10000usize {
        let hit = sketch.static_filter_contains(&ribbon, u64(i))
        if i < 5000usize && !hit { os.exit(25i32) }
        if i >= 5000usize && hit { misses += 1usize }
        i += 1usize
    }
    if misses != 19usize { os.exit(25i32) }

    // 26: Space-Saving over the whole stream never undercounts key 7.
    var ss: [8]sketch.Counter = zero
    sketch.space_saving(ss[..], hh)
    let (ss_count, ss_found) = sketch.counter_get(ss[..], 7u64)
    if !ss_found || ss_count < 2000u64 { os.exit(26i32) }

    // 27: stable Bloom filter keeps the newest keys, forgets old ones and settles at 1.5% false positives.
    var cells: [4096]u8 = zero
    let (stable, stable_error) = sketch.stable_bloom(cells[..], 3u32, 30u32, 3u8)
    if stable_error != ok { os.exit(27i32) }
    var sb = stable
    i = 0usize
    while i < 10000usize {
        sketch.stable_bloom_insert(&sb, u64(i))
        i += 1usize
    }
    misses = 0usize
    var stale = 0usize
    i = 0usize
    while i < 15000usize {
        let hit = sketch.stable_bloom_contains(&sb, u64(i))
        if i >= 9980usize && i < 10000usize && !hit { os.exit(27i32) }
        if i >= 10000usize && hit { misses += 1usize }
        if i < 1000usize && hit { stale += 1usize }
        i += 1usize
    }
    if misses != 75usize || stale != 12usize { os.exit(27i32) }

    // 28: t-digest at compression 100 ends with 59 centroids and answers both quantiles within rank 0.001.
    var td_means: [1000]f64 = zero
    var td_weights: [1000]f64 = zero
    var td_buffer: [500]f64 = zero
    let (td, td_error) = sketch.tdigest(td_means[..], td_weights[..], td_buffer[..], 100.0f64)
    if td_error != ok { os.exit(28i32) }
    var tds = td
    i = 0usize
    while i < 20000usize {
        if sketch.tdigest_add(&tds, f64(vals[i])) != ok { os.exit(28i32) }
        i += 1usize
    }
    let (td_median, td_median_error) = sketch.tdigest_quantile(&tds, 0.5f64)
    let (td_tail, td_tail_error) = sketch.tdigest_quantile(&tds, 0.99f64)
    if td_median_error != ok || td_tail_error != ok || tds.size != 59usize { os.exit(28i32) }
    if !near(td_median, 1080128190.4556f64, 0.000001f64) || !near(td_tail, 2123772402.4624f64, 0.000001f64) { os.exit(28i32) }

    // 29: theta sketches union to the full 20000 and intersect near the 4000 shared values.
    var theta_a: [1025]u64 = zero
    var theta_b: [1025]u64 = zero
    var theta_out: [1025]u64 = zero
    var ta = sketch.theta_init(theta_a[..])
    var tb = sketch.theta_init(theta_b[..])
    var tx = sketch.theta_init(theta_out[..])
    i = 0usize
    while i < 12000usize {
        sketch.theta_add(&ta, vals[i])
        sketch.theta_add(&tb, vals[i + 8000usize])
        i += 1usize
    }
    if !near(sketch.theta_estimate(&ta), 11979.97f64, 0.001f64) { os.exit(29i32) }
    if sketch.theta_intersection(&ta, &tb, &tx) != ok || !near(sketch.theta_estimate(&tx), 4311.85f64, 0.001f64) { os.exit(29i32) }
    sketch.theta_union(&ta, &tb)
    if !near(sketch.theta_estimate(&ta), 20041.94f64, 0.001f64) { os.exit(29i32) }

    // 30: top-k over Count-Min ranks key 7 first with its exact count.
    var tk_counts: [2048]u32 = zero
    var tk_heap: [8]sketch.Counter = zero
    let (tk, tk_error) = sketch.top_k(tk_counts[..], 512usize, 4usize, tk_heap[..])
    if tk_error != ok { os.exit(30i32) }
    var top = tk
    i = 0usize
    while i < 10000usize {
        sketch.top_k_add(&top, hh[i])
        i += 1usize
    }
    let (tk_seven, tk_found) = sketch.top_k_get(&top, 7u64)
    if !tk_found || tk_seven != 2000u64 || top.size != 8usize { os.exit(30i32) }
    let (_, tk_absent) = sketch.top_k_get(&top, 9u64)
    if tk_absent { os.exit(30i32) }

    // 31: xor filter over 5000 keys: no false negatives, 18 false positives.
    let (xor_cap, _) = sketch.xor_filter_size(5000usize)
    let (xor, xor_error) = sketch.xor_filter(pos, bytes8k, scratch)
    if xor_error != ok || xor_cap != 6183usize || xor.seed != 1442695040888963407u64 { os.exit(31i32) }
    misses = 0usize
    i = 0usize
    while i < 10000usize {
        let hit = sketch.static_filter_contains(&xor, u64(i))
        if i < 5000usize && !hit { os.exit(31i32) }
        if i >= 5000usize && hit { misses += 1usize }
        i += 1usize
    }
    if misses != 18usize { os.exit(31i32) }

    try io.print("algo sketch plan ok\n")
    ret ok
}
