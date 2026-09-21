// `e.data.trie` and `e.algo.consistent_hash`: insert, lookup, prefix tests,
// removal, longest-prefix matching and an ordered prefix walk over a small
// dictionary; a ring whose ownership is stable when a node leaves, rendezvous
// with the same property, and the jump hash against the reference values and
// its movement bound. Each check exits with its own code.

use e.algo.consistent_hash
use e.data.trie
use e.io
use e.mem
use e.os

type Walk = struct { count: usize, total: u64, first: [16]u8, first_len: usize, last: [16]u8, last_len: usize, stop_at: usize }

fn note(ctx: *Walk, key: []const u8, value: u64) -> bool {
    if ctx.count == 0usize {
        mem.copy[u8](ctx.first[..], key)
        ctx.first_len = key.len
    }
    mem.copy[u8](ctx.last[..], key)
    ctx.last_len = key.len
    ctx.count += 1usize
    ctx.total += value
    ret ctx.count != ctx.stop_at
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: trie insert, get, prefix and removal.
    var bytes: [64]u8 = zero
    var first: [64]u32 = zero
    var next: [64]u32 = zero
    var terminal: [64]u8 = zero
    var values: [64]u64 = zero
    let (t0, init_error) = trie.init(bytes[..], first[..], next[..], terminal[..], values[..], 64usize)
    if init_error != ok { os.exit(1i32) }
    var t = t0
    var words: [7]str = zero
    words[0usize] = "car"
    words[1usize] = "card"
    words[2usize] = "care"
    words[3usize] = "cart"
    words[4usize] = "cat"
    words[5usize] = "dog"
    words[6usize] = ""
    var w = 0usize
    while w < 7usize {
        let (fresh, insert_error) = trie.insert(&t, words[w], u64(w) + 1u64)
        if insert_error != ok || !fresh { os.exit(1i32) }
        w += 1usize
    }
    // The root, c-a-r, one node each for d, e, t and the t of "cat", and d-o-g: 11 nodes.
    if trie.len(&t) != 11usize { os.exit(1i32) }
    let (again, again_error) = trie.insert(&t, "car", 99u64)
    if again_error != ok || again { os.exit(1i32) }
    let (v_car, has_car) = trie.get(&t, "car")
    if !has_car || v_car != 99u64 { os.exit(1i32) }
    let (v_empty, has_empty) = trie.get(&t, "")
    if !has_empty || v_empty != 7u64 { os.exit(1i32) }
    if trie.contains(&t, "ca") || trie.contains(&t, "cards") || !trie.contains(&t, "cat") { os.exit(1i32) }
    if !trie.has_prefix(&t, "ca") || !trie.has_prefix(&t, "card") || trie.has_prefix(&t, "cab") || !trie.has_prefix(&t, "") { os.exit(1i32) }
    if !trie.remove(&t, "card") || trie.remove(&t, "card") || trie.contains(&t, "card") || trie.has_prefix(&t, "card") || !trie.has_prefix(&t, "car") { os.exit(1i32) }
    if trie.remove(&t, "ca") { os.exit(1i32) }
    let (len_cart, val_cart, any_cart) = trie.longest_prefix(&t, "cartoon")
    if !any_cart || len_cart != 4usize || val_cart != 4u64 { os.exit(1i32) }
    let (len_cab, val_cab, any_cab) = trie.longest_prefix(&t, "cab")
    if !any_cab || len_cab != 0usize || val_cab != 7u64 { os.exit(1i32) }
    var full_bytes: [4]u8 = zero
    var full_first: [4]u32 = zero
    var full_next: [4]u32 = zero
    var full_terminal: [4]u8 = zero
    var full_values: [4]u64 = zero
    let (small, small_error) = trie.init(full_bytes[..], full_first[..], full_next[..], full_terminal[..], full_values[..], 4usize)
    if small_error != ok { os.exit(1i32) }
    var s = small
    let (_, fits) = trie.insert(&s, "abc", 1u64)
    let (_, overflows) = trie.insert(&s, "abd", 2u64)
    if fits != ok || overflows != trie.TooSmall { os.exit(1i32) }

    // 2: the prefix walk visits keys in byte order and can stop.
    var scratch: [16]u8 = zero
    var walk = Walk { count: 0usize, total: 0u64, first: zero, first_len: 0usize, last: zero, last_len: 0usize, stop_at: 0usize }
    let (finished, walk_error) = trie.prefix_iter[Walk](&t, "ca", scratch[..], &walk, note)
    if walk_error != ok || !finished { os.exit(2i32) }
    // car (99), care (3), cart (4), cat (5): card was removed.
    if walk.count != 4usize || walk.total != 111u64 { os.exit(2i32) }
    if !mem.eq[u8](walk.first[..walk.first_len], "car") || !mem.eq[u8](walk.last[..walk.last_len], "cat") { os.exit(2i32) }
    walk = Walk { count: 0usize, total: 0u64, first: zero, first_len: 0usize, last: zero, last_len: 0usize, stop_at: 0usize }
    let (all, all_error) = trie.prefix_iter[Walk](&t, "", scratch[..], &walk, note)
    if all_error != ok || !all || walk.count != 6usize || walk.first_len != 0usize || !mem.eq[u8](walk.last[..walk.last_len], "dog") { os.exit(2i32) }
    walk = Walk { count: 0usize, total: 0u64, first: zero, first_len: 0usize, last: zero, last_len: 0usize, stop_at: 2usize }
    let (stopped, stop_error) = trie.prefix_iter[Walk](&t, "c", scratch[..], &walk, note)
    if stop_error != ok || stopped || walk.count != 2usize { os.exit(2i32) }
    walk.count = 0usize
    let (none, none_error) = trie.prefix_iter[Walk](&t, "x", scratch[..], &walk, note)
    if none_error != ok || !none || walk.count != 0usize { os.exit(2i32) }
    let (_, short_error) = trie.prefix_iter[Walk](&t, "ca", scratch[..3usize], &walk, note)
    if short_error != trie.TooSmall { os.exit(2i32) }

    // 3: the ring spreads keys and moves only the leaving node's keys.
    var nodes: [5]u64 = zero
    var n = 0usize
    while n < 5usize {
        nodes[n] = 1000u64 + u64(n)
        n += 1usize
    }
    var points: [500]consistent_hash.Point = zero
    let (ring, ring_error) = consistent_hash.ring_build(points[..], nodes[..], 100u32)
    if ring_error != ok || ring.len != 500usize { os.exit(3i32) }
    var i = 1usize
    while i < ring.len {
        if ring[i].position < ring[i - 1usize].position { os.exit(3i32) }
        i += 1usize
    }
    var owned: [5]usize = zero
    var key = 0u64
    while key < 2000u64 {
        let (owner, found) = consistent_hash.ring_lookup(ring, key)
        if !found { os.exit(3i32) }
        owned[usize(owner - 1000u64)] += 1usize
        key += 1u64
    }
    n = 0usize
    while n < 5usize {
        if owned[n] < 200usize || owned[n] > 600usize { os.exit(3i32) }
        n += 1usize
    }
    // Drop node 1004: every key it did not own keeps its owner.
    var fewer_points: [400]consistent_hash.Point = zero
    let (smaller, smaller_error) = consistent_hash.ring_build(fewer_points[..], nodes[..4usize], 100u32)
    if smaller_error != ok { os.exit(3i32) }
    var moved = 0usize
    key = 0u64
    while key < 2000u64 {
        let (before, _) = consistent_hash.ring_lookup(ring, key)
        let (after, _) = consistent_hash.ring_lookup(smaller, key)
        if before != 1004u64 && before != after { os.exit(3i32) }
        if before == 1004u64 && after == 1004u64 { os.exit(3i32) }
        if before != after { moved += 1usize }
        key += 1u64
    }
    if moved != owned[4usize] { os.exit(3i32) }
    var successors: [3]u64 = zero
    if consistent_hash.ring_successors(ring, 42u64, successors[..]) != 3usize { os.exit(3i32) }
    let (owner42, _) = consistent_hash.ring_lookup(ring, 42u64)
    if successors[0usize] != owner42 || successors[1usize] == successors[0usize] || successors[2usize] == successors[1usize] || successors[2usize] == successors[0usize] { os.exit(3i32) }
    var one_point: [1]consistent_hash.Point = zero
    let (lone, lone_error) = consistent_hash.ring_build(one_point[..], nodes[..1usize], 1u32)
    if lone_error != ok || consistent_hash.ring_successors(lone, 42u64, successors[..]) != 1usize { os.exit(3i32) }
    let (_, no_ring) = consistent_hash.ring_lookup(points[..0usize], 1u64)
    if no_ring { os.exit(3i32) }
    let (_, room_error) = consistent_hash.ring_build(points[..10usize], nodes[..], 100u32)
    if room_error != consistent_hash.TooSmall { os.exit(3i32) }

    // 4: rendezvous hashing has the same stability.
    n = 0usize
    while n < 5usize {
        owned[n] = 0usize
        n += 1usize
    }
    moved = 0usize
    key = 0u64
    while key < 2000u64 {
        let (before, before_ok) = consistent_hash.rendezvous(nodes[..], key)
        let (after, after_ok) = consistent_hash.rendezvous(nodes[..4usize], key)
        if !before_ok || !after_ok { os.exit(4i32) }
        owned[before] += 1usize
        if before != 4usize && before != after { os.exit(4i32) }
        if before == 4usize && after == 4usize { os.exit(4i32) }
        if before != after { moved += 1usize }
        key += 1u64
    }
    if moved != owned[4usize] { os.exit(4i32) }
    n = 0usize
    while n < 5usize {
        if owned[n] < 250usize || owned[n] > 550usize { os.exit(4i32) }
        n += 1usize
    }
    let (_, no_nodes) = consistent_hash.rendezvous(nodes[..0usize], 1u64)
    if no_nodes { os.exit(4i32) }

    // 5: jump consistent hash against a Python transcription of the paper's code and its movement bound.
    if consistent_hash.jump(0u64, 1u32) != 0u32 || consistent_hash.jump(0u64, 1000u32) != 0u32 { os.exit(5i32) }
    if consistent_hash.jump(1u64, 1u32) != 0u32 || consistent_hash.jump(1u64, 2u32) != 0u32 || consistent_hash.jump(1u64, 0u32) != 0u32 { os.exit(5i32) }
    if consistent_hash.jump(1u64, 1000u32) != 549u32 || consistent_hash.jump(2u64, 1000u32) != 338u32 { os.exit(5i32) }
    if consistent_hash.jump(18446744073709551615u64, 1000u32) != 313u32 { os.exit(5i32) }
    moved = 0usize
    key = 0u64
    while key < 10000u64 {
        let before = consistent_hash.jump(key, 10u32)
        let after = consistent_hash.jump(key, 11u32)
        if before >= 10u32 || after >= 11u32 { os.exit(5i32) }
        if before != after {
            if after != 10u32 { os.exit(5i32) }
            moved += 1usize
        }
        key += 1u64
    }
    if moved < 700usize || moved > 1100usize { os.exit(5i32) }

    try io.print("data trie hash ok\n")
    ret ok
}
