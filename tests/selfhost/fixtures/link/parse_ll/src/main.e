// `e.parse.ll`: nullable/FIRST/FOLLOW and the LL(1) table of the
// left-factored expression grammar `E -> T E'; E' -> + T E' | ε; T -> F T';
// T' -> * F T' | ε; F -> ( E ) | id` hashed against Python, the leftmost
// derivations of ten LCG-grown sentences, rejections, the conflict count of
// the left-recursive grammar, and a too-small table. Each check exits with
// its own code. Expected values: scratchpad parse_lr_ref.py.

use e.io
use e.mem
use e.os
use e.parse as base
use e.parse.ll as ll

fn fold_u32(h: u64, xs: []const u32) -> u64 {
    var r = h
    var i = 0usize
    while i < xs.len {
        r = r *% 1000003u64 +% u64(xs[i])
        i += 1usize
    }
    ret r
}

fn fold_u64(xs: []const u64) -> u64 {
    var r = 0u64
    var i = 0usize
    while i < xs.len {
        r = r *% 1000003u64 +% xs[i]
        i += 1usize
    }
    ret r
}

// Grow sentence `k`: `id` then 3 + k % 4 steps of `+ id`, `* id` or `( .. )`.
fn sentence(state: *u64, k: usize, buf: []u32) -> usize {
    buf[0usize] = 0u32
    var n = 1usize
    var step = 0usize
    while step < 3usize + k % 4usize {
        *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r = (*state >> 33u32) % 3u64
        if r == 2u64 {
            var j = n
            while j > 0usize {
                buf[j] = buf[j - 1usize]
                j -= 1usize
            }
            buf[0usize] = 3u32
            buf[n + 1usize] = 4u32
            n += 2usize
        } else {
            buf[n] = u32(r) + 1u32
            buf[n + 1usize] = 0u32
            n += 2usize
        }
        step += 1usize
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    // terminals id=0 +=1 *=2 (=3 )=4; E=5 E'=6 T=7 T'=8 F=9
    let lhs = [8]u32 { 5u32, 6u32, 6u32, 7u32, 8u32, 8u32, 9u32, 9u32 }
    let rhs = [14]u32 { 7u32, 6u32, 1u32, 7u32, 6u32, 9u32, 8u32, 2u32, 9u32, 8u32, 3u32, 5u32, 4u32, 0u32 }
    let rule_start = [9]usize { 0usize, 2usize, 5usize, 5usize, 7usize, 10usize, 10usize, 13usize, 14usize }
    let g = base.grammar(lhs[..], rhs[..], rule_start[..], 5u32)
    var nullable: [10]bool = zero
    var first: [10]u64 = zero
    var follow: [10]u64 = zero
    var tbl: [30]u32 = zero

    // 1: the three sets.
    if ll.symbol_count(&g) != 10usize { os.exit(1i32) }
    if ll.nullable(&g, nullable[..]) != ok { os.exit(1i32) }
    var bits: [10]u32 = zero
    var i = 0usize
    while i < 10usize {
        if nullable[i] { bits[i] = 1u32 }
        i += 1usize
    }
    if fold_u32(0u64, bits[..]) != 1000009000028000030u64 { os.exit(1i32) }
    if ll.first(&g, nullable[..], first[..]) != ok || fold_u64(first[..]) != 6865435706103269886u64 { os.exit(1i32) }
    if ll.follow(&g, 5u32, nullable[..], first[..], follow[..]) != ok || fold_u64(follow[..]) != 760736982088531534u64 { os.exit(1i32) }

    // 2: the table.
    let (conflicts, table_error) = ll.table(&g, 5u32, nullable[..], first[..], follow[..], tbl[..])
    if table_error != ok || conflicts != 0usize { os.exit(2i32) }
    if fold_u32(0u64, tbl[..]) != 9150921121323671618u64 { os.exit(2i32) }

    // 3: ten sentences, leftmost derivations.
    var state = 42u64
    var buf: [32]u32 = zero
    var stack: [64]u32 = zero
    var rules: [64]u32 = zero
    var lengths: [10]u32 = zero
    var rule_hash = 0u64
    var k = 0usize
    while k < 10usize {
        let n = sentence(&state, k, buf[..])
        let (count, parse_error) = ll.parse(&g, 5u32, tbl[..], buf[..n], stack[..], rules[..])
        if parse_error != ok { os.exit(3i32) }
        lengths[k] = u32(count)
        rule_hash = fold_u32(rule_hash, rules[..count])
        k += 1usize
    }
    if fold_u32(0u64, lengths[..]) != 15189286796399729222u64 || rule_hash != 8266909166286172082u64 { os.exit(3i32) }

    // 4: rejections.
    let bad1 = [2]u32 { 0u32, 1u32 }
    let (_, reject1) = ll.parse(&g, 5u32, tbl[..], bad1[..], stack[..], rules[..])
    if reject1 != ll.Invalid { os.exit(4i32) }
    let bad2 = [2]u32 { 0u32, 0u32 }
    let (_, reject2) = ll.parse(&g, 5u32, tbl[..], bad2[..], stack[..], rules[..])
    if reject2 != ll.Invalid { os.exit(4i32) }
    let (_, room) = ll.parse(&g, 5u32, tbl[..], buf[..], stack[..3usize], rules[..])
    if room != ll.TooSmall { os.exit(4i32) }

    // 5: the left-recursive grammar is not LL(1); a table too small.
    let dr_lhs = [6]u32 { 5u32, 5u32, 6u32, 6u32, 7u32, 7u32 }
    let dr_rhs = [12]u32 { 5u32, 1u32, 6u32, 6u32, 6u32, 2u32, 7u32, 7u32, 3u32, 5u32, 4u32, 0u32 }
    let dr_start = [7]usize { 0usize, 3usize, 4usize, 7usize, 8usize, 11usize, 12usize }
    let dr = base.grammar(dr_lhs[..], dr_rhs[..], dr_start[..], 5u32)
    let (dr_conflicts, dr_error) = ll.table(&dr, 5u32, nullable[..8usize], first[..8usize], follow[..8usize], tbl[..])
    if dr_error != ok || dr_conflicts != 4usize { os.exit(5i32) }
    let (_, small) = ll.table(&g, 5u32, nullable[..], first[..], follow[..], tbl[..29usize])
    if small != ll.TooSmall { os.exit(5i32) }

    try io.print("parse ll ok\n")
    ret ok
}
