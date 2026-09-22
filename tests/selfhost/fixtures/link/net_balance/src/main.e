// `e.net.balance`: smooth weighted round-robin reproduces nginx's sequence
// and proportions, power-of-two picks match the PCG64 replica and avoid the
// heaviest backend, a Maglev table over 65537 slots equals the reference,
// balances within 1%, answers 1000 LCG lookups like the reference, survives a
// backend removal with minimal disruption, and refuses a composite size.
// Each check exits with its own code; expected values from the Python
// reference in the scratchpad.

use e.algo.rand
use e.io
use e.mem
use e.net.balance
use e.os

fn fold(acc: u64, v: u64) -> u64 {
    ret acc *% 1000003u64 +% v
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: SWRR of {5, 1, 1} is a a b a c a a; {1, 2, 3} splits 60 picks 10/20/30.
    let weights3 = [3]u32{ 5u32, 1u32, 1u32 }
    var current: [3]i64 = zero
    let (w, w_error) = balance.wrr(weights3[..], current[..])
    if w_error != ok { os.exit(1i32) }
    var ww = w
    let expect = [7]usize{ 0usize, 0usize, 1usize, 0usize, 2usize, 0usize, 0usize }
    var i = 0usize
    while i < 7usize {
        if balance.weighted_round_robin(&ww) != expect[i] { os.exit(1i32) }
        i += 1usize
    }
    let weights123 = [3]u32{ 1u32, 2u32, 3u32 }
    let (w2, w2_error) = balance.wrr(weights123[..], current[..])
    if w2_error != ok { os.exit(1i32) }
    var ww2 = w2
    var counts: [3]usize = zero
    i = 0usize
    while i < 60usize {
        counts[balance.weighted_round_robin(&ww2)] += 1usize
        i += 1usize
    }
    if counts[0usize] != 10usize || counts[1usize] != 20usize || counts[2usize] != 30usize { os.exit(1i32) }
    let (_, too_small) = balance.wrr(weights3[..], current[..2usize])
    if too_small != balance.TooSmall { os.exit(1i32) }
    let zeros = [2]u32{ 0u32, 0u32 }
    let (_, invalid) = balance.wrr(zeros[..], current[..])
    if invalid != balance.Invalid { os.exit(1i32) }
    var rr = 0u32
    if balance.round_robin(&rr, 3usize) != 0usize || balance.round_robin(&rr, 3usize) != 1usize || balance.round_robin(&rr, 3usize) != 2usize || balance.round_robin(&rr, 3usize) != 0usize { os.exit(1i32) }
    if balance.weighted_random(weights123[..], 0u64) != 0usize || balance.weighted_random(weights123[..], 1u64) != 1usize || balance.weighted_random(weights123[..], 5u64) != 2usize || balance.weighted_random(weights123[..], 6u64) != 0usize { os.exit(1i32) }

    // 2: P2C over loads {3, 10, 1}: 20 picks equal the replica, never the heaviest.
    var r = rand.pcg64(42u64, 54u64)
    let loads = [3]u64{ 3u64, 10u64, 1u64 }
    if balance.least_connections(loads[..]) != 2usize { os.exit(2i32) }
    var picks = 0u64
    i = 0usize
    while i < 20usize {
        let pick = balance.power_of_two(loads[..], &r)
        if pick == 1usize { os.exit(2i32) }
        picks = fold(picks, u64(pick))
        i += 1usize
    }
    if picks != 2813608598828006018u64 { os.exit(2i32) }

    // 3: Maglev over M = 65537 with five backends.
    let m = 65537usize
    if balance.maglev_prime(1usize) != 101usize || balance.maglev_prime(5usize) != 503usize || balance.maglev_prime(655usize) != 65519usize { os.exit(3i32) }
    var names: [5]str = zero
    names[0usize] = "alpha"
    names[1usize] = "bravo"
    names[2usize] = "charlie"
    names[3usize] = "delta"
    names[4usize] = "echo"
    let (old_table, old_error) = mem.alloc[u32](a, m)
    if old_error != ok { os.exit(3i32) }
    let (new_table, new_error) = mem.alloc[u32](a, m)
    if new_error != ok { os.exit(3i32) }
    var scratch: [15]u32 = zero
    if balance.maglev_build(names[..], old_table, scratch[..], m) != ok { os.exit(3i32) }
    var table_fold = 0u64
    var slots: [5]usize = zero
    i = 0usize
    while i < m {
        table_fold = fold(table_fold, u64(old_table[i]))
        slots[usize(old_table[i])] += 1usize
        i += 1usize
    }
    if table_fold != 17203304009790105923u64 { os.exit(3i32) }
    i = 0usize
    while i < 5usize {
        // 20% of 65537 is 13107.4; within 1% is 12452..13762.
        if slots[i] < 12452usize || slots[i] > 13762usize { os.exit(3i32) }
        i += 1usize
    }
    var state = 12345u64
    var lookup_fold = 0u64
    i = 0usize
    while i < 1000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        lookup_fold = fold(lookup_fold, u64(balance.maglev_lookup(old_table, state >> 33u32)))
        i += 1usize
    }
    if lookup_fold != 9285628600559401045u64 { os.exit(3i32) }

    // 4: removing charlie: rebuild over the survivors, renumber to the old
    // indexes, and the disruption stays near one fifth of the table.
    var survivors: [4]str = zero
    survivors[0usize] = "alpha"
    survivors[1usize] = "bravo"
    survivors[2usize] = "delta"
    survivors[3usize] = "echo"
    if balance.maglev_build(survivors[..], new_table, scratch[..], m) != ok { os.exit(4i32) }
    let old_index = [4]u32{ 0u32, 1u32, 3u32, 4u32 }
    var new_fold = 0u64
    i = 0usize
    while i < m {
        new_table[i] = old_index[usize(new_table[i])]
        new_fold = fold(new_fold, u64(new_table[i]))
        i += 1usize
    }
    if new_fold != 17176810025827085714u64 { os.exit(4i32) }
    let disruption = balance.maglev_disruption(old_table, new_table)
    if disruption != 13170usize || disruption * 4usize >= m { os.exit(4i32) }
    state = 12345u64
    var surviving = 0usize
    var stable = 0usize
    i = 0usize
    while i < 1000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let before = balance.maglev_lookup(old_table, state >> 33u32)
        if before != 2u32 {
            surviving += 1usize
            if balance.maglev_lookup(new_table, state >> 33u32) == before { stable += 1usize }
        }
        i += 1usize
    }
    if surviving != 807usize || stable != 802usize || stable * 100usize < surviving * 95usize { os.exit(4i32) }

    // 5: a composite size and short storage are refused.
    if balance.maglev_build(names[..], old_table, scratch[..], 65536usize) != balance.Invalid { os.exit(5i32) }
    if balance.maglev_build(names[..], old_table[..100usize], scratch[..], m) != balance.TooSmall { os.exit(5i32) }
    if balance.maglev_build(names[..], old_table, scratch[..14usize], m) != balance.TooSmall { os.exit(5i32) }

    try io.print("net balance ok\n")
    ret ok
}
