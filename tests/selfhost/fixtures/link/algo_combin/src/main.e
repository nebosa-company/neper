// `e.algo.combin`: binomials against Python's `math.comb` up to the last that
// fits, factorials to 20!, lexicographic permutations and combinations counted
// and ordered, Heap's algorithm visiting n! arrangements once each, subsets and
// submasks by mask, Gosper's hack, and the subset-sum transforms against a
// direct count. Each check exits with its own code.

use e.algo.combin
use e.io
use e.mem
use e.os

type Seen = struct { count: usize, sum: u64, stop_at: usize, last: u64 }

fn note_mask(ctx: *Seen, mask: u64) -> bool {
    ctx.count += 1usize
    ctx.sum += mask
    ctx.last = mask
    ret ctx.count != ctx.stop_at
}

fn note_permutation(ctx: *Seen, items: []const i64) -> bool {
    ctx.count += 1usize
    // Encode the arrangement in base 10 so distinct permutations sum distinctly.
    var code = 0u64
    var i = 0usize
    while i < items.len {
        code = code * 10u64 + u64(items[i])
        i += 1usize
    }
    ctx.sum += code
    ret ctx.count != ctx.stop_at
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: binomials and factorials.
    let (c10_3, fit10) = combin.binomial(10u64, 3u64)
    if !fit10 || c10_3 != 120u64 { os.exit(1i32) }
    let (c64_32, fit64) = combin.binomial(64u64, 32u64)
    if !fit64 || c64_32 != 1832624140942590534u64 { os.exit(1i32) }
    let (c66_33, fit66) = combin.binomial(66u64, 33u64)
    if !fit66 || c66_33 != 7219428434016265740u64 { os.exit(1i32) }
    let (_, fit68) = combin.binomial(68u64, 34u64)
    if fit68 { os.exit(1i32) }
    let (c5_7, fit_over) = combin.binomial(5u64, 7u64)
    if !fit_over || c5_7 != 0u64 { os.exit(1i32) }
    let (c0_0, fit0) = combin.binomial(0u64, 0u64)
    if !fit0 || c0_0 != 1u64 { os.exit(1i32) }
    let (f20, fit20) = combin.factorial(20u64)
    if !fit20 || f20 != 2432902008176640000u64 { os.exit(1i32) }
    let (_, fit21) = combin.factorial(21u64)
    if fit21 { os.exit(1i32) }
    let (f0, fit_f0) = combin.factorial(0u64)
    if !fit_f0 || f0 != 1u64 { os.exit(1i32) }

    // 2: lexicographic permutations of 1..4: 24 of them, ascending, then wrap.
    var items: [4]i64 = zero
    items[0usize] = 1i64
    items[1usize] = 2i64
    items[2usize] = 3i64
    items[3usize] = 4i64
    var count = 1usize
    var previous = 1234u64
    while combin.next_permutation[i64](items[..]) {
        let code = u64(items[0usize]) * 1000u64 + u64(items[1usize]) * 100u64 + u64(items[2usize]) * 10u64 + u64(items[3usize])
        if code <= previous { os.exit(2i32) }
        previous = code
        count += 1usize
    }
    if count != 24usize || previous != 4321u64 { os.exit(2i32) }
    if items[0usize] != 1i64 || items[3usize] != 4i64 { os.exit(2i32) }
    // Duplicates: 1,1,2 has three distinct permutations.
    var dupes: [3]i64 = zero
    dupes[0usize] = 1i64
    dupes[1usize] = 1i64
    dupes[2usize] = 2i64
    count = 1usize
    while combin.next_permutation[i64](dupes[..]) { count += 1usize }
    if count != 3usize { os.exit(2i32) }
    var single: [1]i64 = zero
    if combin.next_permutation[i64](single[..]) { os.exit(2i32) }

    // 3: Heap's algorithm visits 5! arrangements, all distinct, and can be stopped.
    var five: [5]i64 = zero
    var i = 0usize
    while i < 5usize {
        five[i] = i64(i + 1usize)
        i += 1usize
    }
    var scratch: [8]usize = zero
    var seen = Seen { count: 0usize, sum: 0u64, stop_at: 0usize, last: 0u64 }
    let (finished, heap_error) = combin.permutations[i64, Seen](five[..], scratch[..], &seen, note_permutation)
    if heap_error != ok || !finished || seen.count != 120usize { os.exit(3i32) }
    // The sum of all 120 codes: each digit position sees every value 24 times.
    if seen.sum != 24u64 * 15u64 * 11111u64 { os.exit(3i32) }
    seen = Seen { count: 0usize, sum: 0u64, stop_at: 7usize, last: 0u64 }
    let (stopped, stop_error) = combin.permutations[i64, Seen](five[..], scratch[..], &seen, note_permutation)
    if stop_error != ok || stopped || seen.count != 7usize { os.exit(3i32) }
    let (_, small_error) = combin.permutations[i64, Seen](five[..], scratch[..2usize], &seen, note_permutation)
    if small_error != combin.TooSmall { os.exit(3i32) }

    // 4: combinations of 3 from 6: 20 of them in order, then wrap.
    var indices: [3]usize = zero
    indices[0usize] = 0usize
    indices[1usize] = 1usize
    indices[2usize] = 2usize
    count = 1usize
    var last_code = 12usize
    while combin.next_combination(indices[..], 6usize) {
        let code = indices[0usize] * 100usize + indices[1usize] * 10usize + indices[2usize]
        if code <= last_code || indices[0usize] >= indices[1usize] || indices[1usize] >= indices[2usize] { os.exit(4i32) }
        last_code = code
        count += 1usize
    }
    if count != 20usize || last_code != 345usize || indices[0usize] != 0usize || indices[2usize] != 2usize { os.exit(4i32) }
    var too_many: [7]usize = zero
    if combin.next_combination(too_many[..], 6usize) { os.exit(4i32) }

    // 5: subsets by mask.
    seen = Seen { count: 0usize, sum: 0u64, stop_at: 0usize, last: 0u64 }
    let (all, subsets_error) = combin.subsets[Seen](4u32, &seen, note_mask)
    if subsets_error != ok || !all || seen.count != 16usize || seen.sum != 120u64 || seen.last != 15u64 { os.exit(5i32) }
    seen = Seen { count: 0usize, sum: 0u64, stop_at: 0usize, last: 0u64 }
    let (none, none_error) = combin.subsets[Seen](0u32, &seen, note_mask)
    if none_error != ok || !none || seen.count != 1usize { os.exit(5i32) }
    let (_, wide_error) = combin.subsets[Seen](65u32, &seen, note_mask)
    if wide_error != combin.Invalid { os.exit(5i32) }
    seen = Seen { count: 0usize, sum: 0u64, stop_at: 0usize, last: 0u64 }
    // Submasks of 0b1011: 8 of them, descending, ending at 0.
    if !combin.subsets_of_mask[Seen](11u64, &seen, note_mask) || seen.count != 8usize || seen.sum != 44u64 || seen.last != 0u64 { os.exit(5i32) }
    let (after, more) = combin.next_submask(11u64, 11u64)
    if !more || after != 10u64 { os.exit(5i32) }
    let (_, done) = combin.next_submask(0u64, 11u64)
    if done { os.exit(5i32) }
    // Gosper's hack walks every 3-of-6 mask: 20 of them, ascending, starting at 0b111.
    var mask = 7u64
    count = 1usize
    while true {
        let next = combin.next_subset_same_popcount(mask)
        if next >= 64u64 || next == 0u64 { break }
        if next <= mask { os.exit(5i32) }
        mask = next
        count += 1usize
    }
    if count != 20usize || mask != 56u64 { os.exit(5i32) }
    if combin.next_subset_same_popcount(0u64) != 0u64 { os.exit(5i32) }
    if combin.next_subset_same_popcount(18446744073709551615u64) != 0u64 { os.exit(5i32) }
    if combin.next_subset_same_popcount(1u64 << 63u64) != 0u64 { os.exit(5i32) }
    if combin.next_subset_same_popcount(3u64 << 62u64) != 0u64 { os.exit(5i32) }

    // 6: the subset-sum transforms against a direct count, and their inverse.
    var values: [16]i64 = zero
    i = 0usize
    while i < 16usize {
        values[i] = i64(i * i + 1usize)
        i += 1usize
    }
    var original: [16]i64 = zero
    i = 0usize
    while i < 16usize {
        original[i] = values[i]
        i += 1usize
    }
    if combin.subset_sums(values[..], 4u32) != ok { os.exit(6i32) }
    var m = 0usize
    while m < 16usize {
        var want = 0i64
        var sub = 0usize
        while sub < 16usize {
            if (sub & m) == sub { want += original[sub] }
            sub += 1usize
        }
        if values[m] != want { os.exit(6i32) }
        m += 1usize
    }
    if combin.subset_sums_inverse(values[..], 4u32) != ok { os.exit(6i32) }
    i = 0usize
    while i < 16usize {
        if values[i] != original[i] { os.exit(6i32) }
        i += 1usize
    }
    if combin.superset_sums(values[..], 4u32) != ok { os.exit(6i32) }
    m = 0usize
    while m < 16usize {
        var want = 0i64
        var sup = 0usize
        while sup < 16usize {
            if (sup & m) == m { want += original[sup] }
            sup += 1usize
        }
        if values[m] != want { os.exit(6i32) }
        m += 1usize
    }
    if combin.subset_sums(values[..], 3u32) != combin.Invalid { os.exit(6i32) }

    try io.print("algo combin ok\n")
    ret ok
}
