// `e.parse.lr`: on the dragon-book grammar `E -> E + T | T; T -> T * F | F;
// F -> ( E ) | id` the LR(0) collection has 12 states (34 items) and the
// LR(1) one 22 (158), the SLR, canonical and LALR tables hash as Python's
// (LALR's equals SLR's) with no conflicts, ten LCG-grown sentences reduce in
// the same order under each, rejections; on `S -> L = R | R; L -> * R | id;
// R -> L` SLR reports a conflict and LALR/canonical none; and a too-small
// pool. Each check exits with its own code. Expected values: scratchpad
// parse_lr_ref.py.

use e.io
use e.mem
use e.os
use e.parse as base
use e.parse.lr as lr

fn fold_u32(h: u64, xs: []const u32) -> u64 {
    var r = h
    var i = 0usize
    while i < xs.len {
        r = r *% 1000003u64 +% u64(xs[i])
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

// Parse the ten sentences with a table; answers (fold of counts, fold of rules).
fn drive(g: *const base.Grammar, action: []const u32, gotos: []const u32, code: i32) -> (u64, u64) {
    var state = 42u64
    var buf: [32]u32 = zero
    var stack: [64]u32 = zero
    var rules: [64]u32 = zero
    var lengths: [10]u32 = zero
    var rule_hash = 0u64
    var k = 0usize
    while k < 10usize {
        let n = sentence(&state, k, buf[..])
        let (count, parse_error) = lr.parse(g, action, gotos, buf[..n], stack[..], rules[..])
        if parse_error != ok { os.exit(code) }
        lengths[k] = u32(count)
        rule_hash = fold_u32(rule_hash, rules[..count])
        k += 1usize
    }
    let bad1 = [2]u32 { 0u32, 1u32 }
    let (_, reject1) = lr.parse(g, action, gotos, bad1[..], stack[..], rules[..])
    if reject1 != lr.Invalid { os.exit(code) }
    let bad2 = [2]u32 { 0u32, 0u32 }
    let (_, reject2) = lr.parse(g, action, gotos, bad2[..], stack[..], rules[..])
    if reject2 != lr.Invalid { os.exit(code) }
    ret (fold_u32(0u64, lengths[..]), rule_hash)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // terminals id=0 +=1 *=2 (=3 )=4; E=5 T=6 F=7
    let lhs = [6]u32 { 5u32, 5u32, 6u32, 6u32, 7u32, 7u32 }
    let rhs = [12]u32 { 5u32, 1u32, 6u32, 6u32, 6u32, 2u32, 7u32, 7u32, 3u32, 5u32, 4u32, 0u32 }
    let rule_start = [7]usize { 0usize, 3usize, 4usize, 7usize, 8usize, 11usize, 12usize }
    let g = base.grammar(lhs[..], rhs[..], rule_start[..], 5u32)
    var pool: [256]lr.Item = zero
    var set_start: [32]usize = zero
    var trans: [256]u32 = zero
    var nullable: [8]bool = zero
    var first: [8]u64 = zero
    var follow: [8]u64 = zero
    var merged: [32]u32 = zero
    var action: [160]u32 = zero
    var gotos: [96]u32 = zero
    var c = lr.collection(pool[..], set_start[..], trans[..], nullable[..], first[..], follow[..])

    // 1: the collections.
    if lr.items(&g, 5u32, &c) != ok || c.states != 12usize || c.used != 34usize { os.exit(1i32) }
    if lr.items1(&g, 5u32, &c) != ok || c.states != 22usize || c.used != 158usize { os.exit(1i32) }

    // 2: SLR.
    let (slr_states, slr_conflicts, slr_error) = lr.slr_table(&g, 5u32, &c, merged[..], action[..], gotos[..])
    if slr_error != ok || slr_states != 12usize || slr_conflicts != 0usize { os.exit(2i32) }
    if fold_u32(0u64, action[..72usize]) != 13771561146346196010u64 || fold_u32(0u64, gotos[..36usize]) != 13304798629258756858u64 { os.exit(2i32) }
    let (slr_lengths, slr_rules) = drive(&g, action[..], gotos[..], 2i32)
    if slr_lengths != 8138176064259274921u64 || slr_rules != 10929158226407036780u64 { os.exit(2i32) }

    // 3: canonical LR(1).
    let (lr1_states, lr1_conflicts, lr1_error) = lr.canonical_table(&g, 5u32, &c, merged[..], action[..], gotos[..])
    if lr1_error != ok || lr1_states != 22usize || lr1_conflicts != 0usize { os.exit(3i32) }
    if fold_u32(0u64, action[..132usize]) != 8484769496193882172u64 || fold_u32(0u64, gotos[..66usize]) != 6432708690264956265u64 { os.exit(3i32) }
    let (lr1_lengths, lr1_rules) = drive(&g, action[..], gotos[..], 3i32)
    if lr1_lengths != 8138176064259274921u64 || lr1_rules != 10929158226407036780u64 { os.exit(3i32) }

    // 4: LALR(1) merges back to 12 states and the SLR table.
    let (lalr_states, lalr_conflicts, lalr_error) = lr.lalr_table(&g, 5u32, &c, merged[..], action[..], gotos[..])
    if lalr_error != ok || lalr_states != 12usize || lalr_conflicts != 0usize { os.exit(4i32) }
    if fold_u32(0u64, action[..72usize]) != 13771561146346196010u64 || fold_u32(0u64, gotos[..36usize]) != 13304798629258756858u64 { os.exit(4i32) }
    let (lalr_lengths, lalr_rules) = drive(&g, action[..], gotos[..], 4i32)
    if lalr_lengths != 8138176064259274921u64 || lalr_rules != 10929158226407036780u64 { os.exit(4i32) }

    // 5: S -> L = R | R; L -> * R | id; R -> L (id=0 ==1 *=2; S=3 L=4 R=5).
    let s_lhs = [5]u32 { 3u32, 3u32, 4u32, 4u32, 5u32 }
    let s_rhs = [8]u32 { 4u32, 1u32, 5u32, 5u32, 2u32, 5u32, 0u32, 4u32 }
    let s_start = [6]usize { 0usize, 3usize, 4usize, 6usize, 7usize, 8usize }
    let sg = base.grammar(s_lhs[..], s_rhs[..], s_start[..], 3u32)
    let (s_slr_states, s_slr_conflicts, s_slr_error) = lr.slr_table(&sg, 3u32, &c, merged[..], action[..], gotos[..])
    if s_slr_error != ok || s_slr_states != 10usize || s_slr_conflicts != 1usize { os.exit(5i32) }
    if fold_u32(0u64, action[..40usize]) != 9227930508268107392u64 { os.exit(5i32) }
    let (s_lr1_states, s_lr1_conflicts, s_lr1_error) = lr.canonical_table(&sg, 3u32, &c, merged[..], action[..], gotos[..])
    if s_lr1_error != ok || s_lr1_states != 14usize || s_lr1_conflicts != 0usize { os.exit(5i32) }
    if fold_u32(0u64, action[..56usize]) != 11483435483925797260u64 { os.exit(5i32) }
    let (s_lalr_states, s_lalr_conflicts, s_lalr_error) = lr.lalr_table(&sg, 3u32, &c, merged[..], action[..], gotos[..])
    if s_lalr_error != ok || s_lalr_states != 10usize || s_lalr_conflicts != 0usize { os.exit(5i32) }
    if fold_u32(0u64, action[..40usize]) != 9227930508268107392u64 { os.exit(5i32) }
    let star = [4]u32 { 2u32, 0u32, 1u32, 0u32 }
    var stack: [16]u32 = zero
    var rules: [16]u32 = zero
    let (star_count, star_error) = lr.parse(&sg, action[..], gotos[..], star[..], stack[..], rules[..])
    let star_want = [6]u32 { 3u32, 4u32, 2u32, 3u32, 4u32, 0u32 }
    if star_error != ok || star_count != 6usize || fold_u32(0u64, rules[..6usize]) != fold_u32(0u64, star_want[..]) { os.exit(5i32) }

    // 6: a pool too small.
    var tiny = lr.collection(pool[..20usize], set_start[..], trans[..], nullable[..], first[..], follow[..])
    if lr.items1(&g, 5u32, &tiny) != lr.TooSmall { os.exit(6i32) }
    var few = lr.collection(pool[..], set_start[..4usize], trans[..], nullable[..], first[..], follow[..])
    if lr.items(&g, 5u32, &few) != lr.TooSmall { os.exit(6i32) }

    try io.print("parse lr ok\n")
    ret ok
}
