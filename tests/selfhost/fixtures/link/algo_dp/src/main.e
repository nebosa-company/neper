// `e.algo.dp`: the three knapsacks on the textbook instance, LIS and LCS and
// their derived lengths, coin change by count and by ways, subset sum and equal
// partition, Kadane and the product variant with negatives, matrix-chain and
// optimal BST costs, the histogram rectangle, the monotonic stack, and the Li
// Chao tree and convex hull trick against a scan over all lines. Each check
// exits with its own code.

use e.algo.dp
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var table: [256]i64 = zero
    var utable: [256]u64 = zero
    var scratch: [256]usize = zero
    var bytes: [256]u8 = zero

    // 1: knapsacks. Weights 1,3,4,5 with values 1,4,5,7 in capacity 7: both forms give 9.
    var weights: [4]u64 = zero
    weights[0usize] = 1u64
    weights[1usize] = 3u64
    weights[2usize] = 4u64
    weights[3usize] = 5u64
    var values: [4]i64 = zero
    values[0usize] = 1i64
    values[1usize] = 4i64
    values[2usize] = 5i64
    values[3usize] = 7i64
    let (k01, k01_error) = dp.knapsack(weights[..], values[..], 7usize, table[..])
    if k01_error != ok || k01 != 9i64 { os.exit(1i32) }
    let (ku, ku_error) = dp.knapsack_unbounded(weights[..], values[..], 7usize, table[..])
    if ku_error != ok || ku != 9i64 { os.exit(1i32) }
    let (k0, k0_error) = dp.knapsack(weights[..], values[..], 0usize, table[..])
    if k0_error != ok || k0 != 0i64 { os.exit(1i32) }
    let (_, k_room) = dp.knapsack(weights[..], values[..], 7usize, table[..7usize])
    if k_room != dp.TooSmall { os.exit(1i32) }
    var fw: [3]f64 = zero
    fw[0usize] = 10.0f64
    fw[1usize] = 20.0f64
    fw[2usize] = 30.0f64
    var fv: [3]f64 = zero
    fv[0usize] = 60.0f64
    fv[1usize] = 100.0f64
    fv[2usize] = 120.0f64
    let (frac, frac_error) = dp.knapsack_fractional(fw[..], fv[..], 50.0f64, scratch[..])
    if frac_error != ok || frac != 240.0f64 { os.exit(1i32) }

    // 2: subsequences.
    var seq: [8]i64 = zero
    seq[0usize] = 10i64
    seq[1usize] = 9i64
    seq[2usize] = 2i64
    seq[3usize] = 5i64
    seq[4usize] = 3i64
    seq[5usize] = 7i64
    seq[6usize] = 101i64
    seq[7usize] = 18i64
    let (rising, rising_error) = dp.lis(seq[..], table[..])
    if rising_error != ok || rising != 4usize { os.exit(2i32) }
    var flat: [0]i64 = zero
    let (none, none_error) = dp.lis(flat[..], table[..])
    if none_error != ok || none != 0usize { os.exit(2i32) }
    let (common, common_error) = dp.lcs[u8]("ABCBDAB", "BDCABA", scratch[..])
    if common_error != ok || common != 4usize { os.exit(2i32) }
    let (super, super_error) = dp.shortest_common_supersequence[u8]("AGGTAB", "GXTXAYB", scratch[..])
    if super_error != ok || super != 9usize { os.exit(2i32) }
    let (pal, pal_error) = dp.longest_palindromic_subsequence("BBABCBCAB", scratch[..])
    if pal_error != ok || pal != 7usize { os.exit(2i32) }
    let (pal_empty, pal_empty_error) = dp.longest_palindromic_subsequence("", scratch[..])
    if pal_empty_error != ok || pal_empty != 0usize { os.exit(2i32) }
    let (_, lcs_room) = dp.lcs[u8]("ABCBDAB", "BDCABA", scratch[..4usize])
    if lcs_room != dp.TooSmall { os.exit(2i32) }

    // 3: coins.
    var coins: [3]u64 = zero
    coins[0usize] = 1u64
    coins[1usize] = 5u64
    coins[2usize] = 12u64
    let (fewest, fewest_found, fewest_error) = dp.coin_change_min(coins[..], 16usize, utable[..])
    if fewest_error != ok || !fewest_found || fewest != 4u64 { os.exit(3i32) }
    var odd_coins: [2]u64 = zero
    odd_coins[0usize] = 3u64
    odd_coins[1usize] = 7u64
    let (_, impossible, impossible_error) = dp.coin_change_min(odd_coins[..], 5usize, utable[..])
    if impossible_error != ok || impossible { os.exit(3i32) }
    var ways_coins: [4]u64 = zero
    ways_coins[0usize] = 1u64
    ways_coins[1usize] = 2u64
    ways_coins[2usize] = 5u64
    ways_coins[3usize] = 10u64
    let (ways, ways_error) = dp.coin_change_ways(ways_coins[..], 100usize, utable[..])
    if ways_error != ok || ways != 2156u64 { os.exit(3i32) }
    let (ways0, ways0_error) = dp.coin_change_ways(ways_coins[..], 0usize, utable[..])
    if ways0_error != ok || ways0 != 1u64 { os.exit(3i32) }

    // 4: subset sum and equal partition.
    var set: [6]u64 = zero
    set[0usize] = 3u64
    set[1usize] = 34u64
    set[2usize] = 4u64
    set[3usize] = 12u64
    set[4usize] = 5u64
    set[5usize] = 2u64
    let (has9, has9_error) = dp.subset_sum(set[..], 9usize, bytes[..])
    if has9_error != ok || !has9 { os.exit(4i32) }
    let (has30, has30_error) = dp.subset_sum(set[..], 30usize, bytes[..])
    if has30_error != ok || has30 { os.exit(4i32) }
    var halves: [4]u64 = zero
    halves[0usize] = 1u64
    halves[1usize] = 5u64
    halves[2usize] = 11u64
    halves[3usize] = 5u64
    let (splits, splits_error) = dp.partition_equal(halves[..], bytes[..])
    if splits_error != ok || !splits { os.exit(4i32) }
    halves[2usize] = 3u64
    let (no_split, no_split_error) = dp.partition_equal(halves[..], bytes[..])
    if no_split_error != ok || no_split { os.exit(4i32) }

    // 5: subarrays.
    var run: [9]i64 = zero
    run[0usize] = 0i64 - 2i64
    run[1usize] = 1i64
    run[2usize] = 0i64 - 3i64
    run[3usize] = 4i64
    run[4usize] = 0i64 - 1i64
    run[5usize] = 2i64
    run[6usize] = 1i64
    run[7usize] = 0i64 - 5i64
    run[8usize] = 4i64
    let (best, best_low, best_high) = dp.max_subarray(run[..])
    if best != 6i64 || best_low != 3usize || best_high != 7usize { os.exit(5i32) }
    var negatives: [3]i64 = zero
    negatives[0usize] = 0i64 - 3i64
    negatives[1usize] = 0i64 - 1i64
    negatives[2usize] = 0i64 - 2i64
    let (worst, worst_low, worst_high) = dp.max_subarray(negatives[..])
    if worst != 0i64 - 1i64 || worst_low != 1usize || worst_high != 2usize { os.exit(5i32) }
    var product: [5]i64 = zero
    product[0usize] = 2i64
    product[1usize] = 3i64
    product[2usize] = 0i64 - 2i64
    product[3usize] = 4i64
    product[4usize] = 0i64 - 3i64
    if dp.max_product_subarray(product[..]) != 144i64 { os.exit(5i32) }
    if dp.max_product_subarray(negatives[..]) != 3i64 { os.exit(5i32) }

    // 6: matrix chain and optimal BST.
    var dims: [5]u64 = zero
    dims[0usize] = 40u64
    dims[1usize] = 20u64
    dims[2usize] = 30u64
    dims[3usize] = 10u64
    dims[4usize] = 30u64
    let (chain, chain_error) = dp.matrix_chain(dims[..], utable[..])
    if chain_error != ok || chain != 26000u64 { os.exit(6i32) }
    let (_, chain_invalid) = dp.matrix_chain(dims[..1usize], utable[..])
    if chain_invalid != dp.Invalid { os.exit(6i32) }
    var freq: [3]u64 = zero
    freq[0usize] = 34u64
    freq[1usize] = 8u64
    freq[2usize] = 50u64
    let (bst, bst_error) = dp.optimal_bst(freq[..], utable[..])
    if bst_error != ok || bst != 142u64 { os.exit(6i32) }
    var freq7: [7]u64 = zero
    freq7[0usize] = 22u64
    freq7[1usize] = 18u64
    freq7[2usize] = 20u64
    freq7[3usize] = 5u64
    freq7[4usize] = 25u64
    freq7[5usize] = 2u64
    freq7[6usize] = 8u64
    let (bst7, bst7_error) = dp.optimal_bst(freq7[..], utable[..])
    if bst7_error != ok || bst7 != 215u64 { os.exit(6i32) }

    // 7: the histogram rectangle and the monotonic stack.
    var heights: [7]u64 = zero
    heights[0usize] = 6u64
    heights[1usize] = 2u64
    heights[2usize] = 5u64
    heights[3usize] = 4u64
    heights[4usize] = 5u64
    heights[5usize] = 1u64
    heights[6usize] = 6u64
    let (area, area_low, area_high, area_error) = dp.largest_rectangle_histogram(heights[..], scratch[..])
    if area_error != ok || area != 12u64 || area_low != 2usize || area_high != 5usize { os.exit(7i32) }
    var empty_heights: [0]u64 = zero
    let (no_area, _, _, no_area_error) = dp.largest_rectangle_histogram(empty_heights[..], scratch[..])
    if no_area_error != ok || no_area != 0u64 { os.exit(7i32) }
    var prev: [9]usize = zero
    var stack: [9]usize = zero
    if dp.previous_smaller(run[..], prev[..], stack[..]) != ok { os.exit(7i32) }
    // run: -2 1 -3 4 -1 2 1 -5 4 -> none, 0, none, 2, 2, 4, 4, none, 7
    if prev[0usize] != 9usize || prev[1usize] != 0usize || prev[2usize] != 9usize || prev[3usize] != 2usize { os.exit(7i32) }
    if prev[4usize] != 2usize || prev[5usize] != 4usize || prev[6usize] != 4usize || prev[7usize] != 9usize || prev[8usize] != 7usize { os.exit(7i32) }

    // 8: Li Chao tree and the convex hull trick agree with a scan over all lines.
    var lines: [8]dp.Line = zero
    lines[0usize] = dp.Line { slope: 5i64, intercept: 0i64 - 10i64 }
    lines[1usize] = dp.Line { slope: 3i64, intercept: 4i64 }
    lines[2usize] = dp.Line { slope: 1i64, intercept: 20i64 }
    lines[3usize] = dp.Line { slope: 0i64, intercept: 30i64 }
    lines[4usize] = dp.Line { slope: 0i64 - 2i64, intercept: 50i64 }
    lines[5usize] = dp.Line { slope: 0i64 - 4i64, intercept: 100i64 }
    var tree_lines: [256]dp.Line = zero
    var tree_filled: [256]u8 = zero
    let (tree, tree_error) = dp.li_chao_init(tree_lines[..], tree_filled[..], 0i64 - 20i64, 40i64)
    if tree_error != ok { os.exit(8i32) }
    var chao = tree
    let (_, empty_query) = dp.li_chao_query(&chao, 0i64)
    if empty_query { os.exit(8i32) }
    var hull: [8]dp.Line = zero
    var count = 0usize
    var i = 0usize
    while i < 6usize {
        dp.li_chao_insert(&chao, lines[i])
        let (next_count, hull_error) = dp.hull_add(hull[..], count, lines[i])
        if hull_error != ok { os.exit(8i32) }
        count = next_count
        i += 1usize
    }
    if count < 3usize || count > 6usize { os.exit(8i32) }
    var pointer = 0usize
    var x = 0i64 - 20i64
    while x <= 40i64 {
        var least = lines[0usize].slope * x + lines[0usize].intercept
        i = 1usize
        while i < 6usize {
            let v = lines[i].slope * x + lines[i].intercept
            if v < least { least = v }
            i += 1usize
        }
        let (from_tree, tree_found) = dp.li_chao_query(&chao, x)
        if !tree_found || from_tree != least { os.exit(8i32) }
        let (from_hull, hull_found) = dp.hull_query(hull[..], count, &pointer, x)
        if !hull_found || from_hull != least { os.exit(8i32) }
        x += 1i64
    }
    let (_, outside) = dp.li_chao_query(&chao, 41i64)
    if outside { os.exit(8i32) }
    let (_, init_error) = dp.li_chao_init(tree_lines[..], tree_filled[..], 0i64, 100i64)
    if init_error != dp.TooSmall { os.exit(8i32) }
    let (_, hull_full) = dp.hull_add(hull[..count], count, dp.Line { slope: 0i64 - 100i64, intercept: 1000000i64 })
    if hull_full != dp.TooSmall { os.exit(8i32) }

    try io.print("algo dp ok\n")
    ret ok
}
