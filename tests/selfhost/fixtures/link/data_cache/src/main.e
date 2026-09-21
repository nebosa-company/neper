// `e.data.cache`: the keyed LRU under hits, overwrites, removals and evictions
// in recency order with its index kept consistent through a long churn; the
// slot policies FIFO, Clock, LFU, SLRU and 2Q named victims checked against
// their definitions. Each check exits with its own code.

use e.data.cache
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: the keyed LRU.
    var keys: [4]u64 = zero
    var values: [4]u64 = zero
    var prev: [4]u32 = zero
    var next: [4]u32 = zero
    var index: [8]u32 = zero
    let (lru, lru_error) = cache.lru_init(keys[..], values[..], prev[..], next[..], index[..], 4usize)
    if lru_error != ok { os.exit(1i32) }
    var c = lru
    var k = 1u64
    while k <= 4u64 {
        let (_, evicted) = cache.lru_put(&c, k * 100u64, k)
        if evicted { os.exit(1i32) }
        k += 1u64
    }
    if cache.lru_len(&c) != 4usize { os.exit(1i32) }
    // Touch 100 so 200 becomes the oldest; a fifth key evicts 200.
    let (v100, hit100) = cache.lru_get(&c, 100u64)
    if !hit100 || v100 != 1u64 { os.exit(1i32) }
    let (oldest, has_oldest) = cache.lru_oldest(&c)
    if !has_oldest || oldest != 200u64 { os.exit(1i32) }
    let (gone, evicted5) = cache.lru_put(&c, 500u64, 5u64)
    if !evicted5 || gone != 200u64 || cache.lru_contains(&c, 200u64) || cache.lru_len(&c) != 4usize { os.exit(1i32) }
    let (_, miss) = cache.lru_get(&c, 200u64)
    if miss { os.exit(1i32) }
    // Overwriting refreshes without evicting.
    let (_, evicted_over) = cache.lru_put(&c, 300u64, 33u64)
    if evicted_over { os.exit(1i32) }
    let (v300, hit300) = cache.lru_get(&c, 300u64)
    if !hit300 || v300 != 33u64 { os.exit(1i32) }
    // Removal frees a slot, so the next insert evicts nothing.
    if !cache.lru_remove(&c, 400u64) || cache.lru_remove(&c, 400u64) || cache.lru_len(&c) != 3usize { os.exit(1i32) }
    let (_, evicted6) = cache.lru_put(&c, 600u64, 6u64)
    if evicted6 || cache.lru_len(&c) != 4usize { os.exit(1i32) }
    // Recency order now: 600, 300, 500, 100 (oldest).
    let (gone7, evicted7) = cache.lru_put(&c, 700u64, 7u64)
    if !evicted7 || gone7 != 100u64 { os.exit(1i32) }
    let (gone8, evicted8) = cache.lru_put(&c, 800u64, 8u64)
    if !evicted8 || gone8 != 500u64 { os.exit(1i32) }
    // A long churn keeps the index consistent: the last four keys are present, no others.
    var n = 0u64
    while n < 1000u64 {
        let (_, churned) = cache.lru_put(&c, n * 7919u64, n)
        if !churned { os.exit(1i32) }
        n += 1u64
    }
    if cache.lru_len(&c) != 4usize { os.exit(1i32) }
    n = 996u64
    while n < 1000u64 {
        let (v, hit) = cache.lru_get(&c, n * 7919u64)
        if !hit || v != n { os.exit(1i32) }
        n += 1u64
    }
    if cache.lru_contains(&c, 995u64 * 7919u64) || cache.lru_contains(&c, 800u64) { os.exit(1i32) }
    let (_, tiny_error) = cache.lru_init(keys[..], values[..], prev[..], next[..], index[..6usize], 4usize)
    if tiny_error != cache.TooSmall { os.exit(1i32) }
    let (_, zero_error) = cache.lru_init(keys[..], values[..], prev[..], next[..], index[..], 0usize)
    if zero_error != cache.Invalid { os.exit(1i32) }

    // 2: FIFO reuses in arrival order regardless of hits.
    var order: [3]u32 = zero
    let (fifo, fifo_error) = cache.fifo_init(order[..], 3usize)
    if fifo_error != ok { os.exit(2i32) }
    var f = fifo
    let (_, full0) = cache.fifo_evict(&f)
    if full0 { os.exit(2i32) }
    cache.fifo_insert(&f, 2u32)
    cache.fifo_insert(&f, 0u32)
    cache.fifo_insert(&f, 1u32)
    let (victim_a, full_a) = cache.fifo_evict(&f)
    if !full_a || victim_a != 2u32 { os.exit(2i32) }
    cache.fifo_insert(&f, 2u32)
    let (victim_b, full_b) = cache.fifo_evict(&f)
    if !full_b || victim_b != 0u32 { os.exit(2i32) }
    cache.fifo_insert(&f, 0u32)
    let (victim_c, full_c) = cache.fifo_evict(&f)
    if !full_c || victim_c != 1u32 { os.exit(2i32) }

    // 3: Clock spares a referenced slot once.
    var referenced: [3]u8 = zero
    var filled: [3]u8 = zero
    let (clock, clock_error) = cache.clock_init(referenced[..], filled[..], 3usize)
    if clock_error != ok { os.exit(3i32) }
    var ck = clock
    var s = 0u32
    while s < 3u32 {
        if cache.clock_evict(&ck) != s { os.exit(3i32) }
        cache.clock_insert(&ck, s)
        s += 1u32
    }
    cache.clock_touch(&ck, 0u32)
    // Hand at 0: slot 0 is referenced (cleared, skipped), slot 1 is taken.
    if cache.clock_evict(&ck) != 1u32 { os.exit(3i32) }
    cache.clock_insert(&ck, 1u32)
    // Hand at 2: slot 2 unreferenced.
    if cache.clock_evict(&ck) != 2u32 { os.exit(3i32) }
    cache.clock_insert(&ck, 2u32)
    // Hand wraps to 0, now unreferenced.
    if cache.clock_evict(&ck) != 0u32 { os.exit(3i32) }

    // 4: LFU evicts the fewest hits, ties to the lowest slot.
    var hits: [3]u64 = zero
    var lfu_filled: [3]u8 = zero
    let (lfu, lfu_error) = cache.lfu_init(hits[..], lfu_filled[..], 3usize)
    if lfu_error != ok { os.exit(4i32) }
    var l = lfu
    s = 0u32
    while s < 3u32 {
        if cache.lfu_evict(&l) != s { os.exit(4i32) }
        cache.lfu_insert(&l, s)
        s += 1u32
    }
    cache.lfu_touch(&l, 0u32)
    cache.lfu_touch(&l, 0u32)
    cache.lfu_touch(&l, 2u32)
    if cache.lfu_evict(&l) != 1u32 { os.exit(4i32) }
    cache.lfu_insert(&l, 1u32)
    cache.lfu_touch(&l, 1u32)
    if cache.lfu_evict(&l) != 1u32 { os.exit(4i32) }
    cache.lfu_touch(&l, 1u32)
    if cache.lfu_evict(&l) != 2u32 { os.exit(4i32) }

    // 5: SLRU promotes on a second hit and evicts from probation first.
    var sprev: [4]u32 = zero
    var snext: [4]u32 = zero
    var protected: [4]u8 = zero
    let (slru, slru_error) = cache.slru_init(sprev[..], snext[..], protected[..], 4usize, 2usize)
    if slru_error != ok { os.exit(5i32) }
    var sl = slru
    s = 0u32
    while s < 4u32 {
        if cache.slru_evict(&sl) != s { os.exit(5i32) }
        cache.slru_insert(&sl, s)
        s += 1u32
    }
    // Probation order (front to back): 3 2 1 0. Hits promote 1 and 3.
    cache.slru_touch(&sl, 1u32)
    cache.slru_touch(&sl, 3u32)
    if !cache.slru_is_protected(&sl, 1u32) || !cache.slru_is_protected(&sl, 3u32) || cache.slru_is_protected(&sl, 2u32) { os.exit(5i32) }
    // Promoting 0 demotes 1 (the protected tail) back to probation.
    cache.slru_touch(&sl, 0u32)
    if cache.slru_is_protected(&sl, 1u32) || !cache.slru_is_protected(&sl, 0u32) { os.exit(5i32) }
    // Probation is now 1 (front), 2 (back): 2 is evicted first, then, refilled and
    // untouched, it sits in front of 1, so 1 goes next.
    if cache.slru_evict(&sl) != 2u32 { os.exit(5i32) }
    if cache.slru_evict(&sl) != 2u32 { os.exit(5i32) }
    cache.slru_insert(&sl, 2u32)
    if cache.slru_evict(&sl) != 1u32 { os.exit(5i32) }
    cache.slru_insert(&sl, 1u32)
    // A second hit on 1 promotes it and demotes 3, the protected tail.
    cache.slru_touch(&sl, 1u32)
    if !cache.slru_is_protected(&sl, 1u32) || cache.slru_is_protected(&sl, 3u32) || !cache.slru_is_protected(&sl, 0u32) { os.exit(5i32) }
    if cache.slru_evict(&sl) != 2u32 { os.exit(5i32) }
    cache.slru_insert(&sl, 2u32)
    if cache.slru_evict(&sl) != 3u32 { os.exit(5i32) }
    let (_, slru_invalid) = cache.slru_init(sprev[..], snext[..], protected[..], 4usize, 4usize)
    if slru_invalid != cache.Invalid { os.exit(5i32) }

    // 6: 2Q admits a remembered key to the main queue.
    var qprev: [4]u32 = zero
    var qnext: [4]u32 = zero
    var main_flags: [4]u8 = zero
    var ghosts: [2]u64 = zero
    var slot_keys: [4]u64 = zero
    let (two, two_error) = cache.two_queue_init(qprev[..], qnext[..], main_flags[..], ghosts[..], 4usize, 2usize)
    if two_error != ok { os.exit(6i32) }
    var q = two
    s = 0u32
    while s < 4u32 {
        let slot = cache.two_queue_evict(&q, slot_keys[..])
        if slot != s { os.exit(6i32) }
        slot_keys[usize(slot)] = 10u64 + u64(s)
        cache.two_queue_insert(&q, slot, slot_keys[usize(slot)])
        s += 1u32
    }
    // All four went to the FIFO (capacity 2 is only enforced at eviction): the
    // oldest, slot 0 holding key 10, is evicted and remembered as a ghost.
    let victim0 = cache.two_queue_evict(&q, slot_keys[..])
    if victim0 != 0u32 { os.exit(6i32) }
    slot_keys[0usize] = 10u64
    cache.two_queue_insert(&q, 0u32, 10u64)
    if !cache.two_queue_in_main(&q, 0u32) || cache.two_queue_in_main(&q, 1u32) { os.exit(6i32) }
    // A hit in the FIFO changes nothing; the FIFO tail (slot 1) goes next.
    cache.two_queue_touch(&q, 1u32)
    if cache.two_queue_evict(&q, slot_keys[..]) != 1u32 { os.exit(6i32) }
    slot_keys[1usize] = 99u64
    cache.two_queue_insert(&q, 1u32, 99u64)
    if cache.two_queue_in_main(&q, 1u32) { os.exit(6i32) }

    try io.print("data cache ok\n")
    ret ok
}
