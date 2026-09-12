// `e.data.stack` and `e.data.queue`, the two adapters, and `e.algo.disjoint_set`:
// order of push/pop and enqueue/dequeue, peek without removal, iteration without
// mutation, growth past the initial capacity, and union-find with path compression and
// union by rank on caller storage. Every check has its own exit code.
use e.os
use e.mem
use e.data.stack as stack
use e.data.queue as queue
use e.algo.disjoint_set as dsu

fn stacks(a: *mem.Arena) {
    let (initial, init_error) = stack.init[i64](a, 1usize)
    if init_error != ok { os.exit(10) }
    var s = initial
    let (_, empty) = stack.peek[i64](&s)
    if empty || stack.len[i64](&s) != 0usize { os.exit(11) }
    if stack.push[i64](&s, 1i64) != ok || stack.push[i64](&s, 2i64) != ok || stack.push[i64](&s, 3i64) != ok { os.exit(12) }
    if stack.len[i64](&s) != 3usize { os.exit(13) }
    let (top, has_top) = stack.peek[i64](&s)
    if !has_top || top != 3i64 || stack.len[i64](&s) != 3usize { os.exit(14) }
    var it = stack.iter[i64](&s)
    var seen: [3]i64 = zero
    var count = 0usize
    while true {
        let (value, has_value) = stack.iter_next[i64](&it)
        if !has_value { break }
        seen[count] = value
        count += 1usize
    }
    if count != 3usize || seen[0] != 3i64 || seen[1] != 2i64 || seen[2] != 1i64 { os.exit(15) }
    if stack.len[i64](&s) != 3usize { os.exit(16) }
    let (first, has_first) = stack.pop[i64](&s)
    let (second, has_second) = stack.pop[i64](&s)
    if !has_first || !has_second || first != 3i64 || second != 2i64 { os.exit(17) }
    if stack.reserve[i64](&s, 16usize) != ok { os.exit(18) }
    stack.clear[i64](&s)
    let (_, after_clear) = stack.pop[i64](&s)
    if after_clear || stack.len[i64](&s) != 0usize { os.exit(19) }
}

fn queues(a: *mem.Arena) {
    let (initial, init_error) = queue.init[u16](a, 2usize)
    if init_error != ok { os.exit(20) }
    var q = initial
    let (_, empty) = queue.dequeue[u16](&q)
    if empty { os.exit(21) }
    var n = 0u16
    while n < 5u16 {
        if queue.enqueue[u16](&q, n) != ok { os.exit(22) }
        n += 1u16
    }
    if queue.len[u16](&q) != 5usize { os.exit(23) }
    let (front, has_front) = queue.peek[u16](&q)
    if !has_front || front != 0u16 || queue.len[u16](&q) != 5usize { os.exit(24) }
    var it = queue.iter[u16](&q)
    var expected = 0u16
    while true {
        let (value, has_value) = queue.iter_next[u16](&it)
        if !has_value { break }
        if value != expected { os.exit(25) }
        expected += 1u16
    }
    if expected != 5u16 || queue.len[u16](&q) != 5usize { os.exit(26) }
    let (first, _) = queue.dequeue[u16](&q)
    let (second, _) = queue.dequeue[u16](&q)
    if first != 0u16 || second != 1u16 || queue.len[u16](&q) != 3usize { os.exit(27) }
    // Wrap around the ring: more in after some out.
    if queue.enqueue[u16](&q, 5u16) != ok || queue.enqueue[u16](&q, 6u16) != ok { os.exit(28) }
    let (third, _) = queue.dequeue[u16](&q)
    if third != 2u16 || queue.len[u16](&q) != 4usize { os.exit(29) }
    queue.clear[u16](&q)
    let (_, after_clear) = queue.peek[u16](&q)
    if after_clear || queue.len[u16](&q) != 0usize { os.exit(30) }
}

fn sets() {
    var parent: [8]u32 = zero
    var rank: [8]u8 = zero
    let (_, too_small) = dsu.init(parent[0..], rank[0..], 9usize)
    if too_small != dsu.TooSmall { os.exit(40) }
    let (initial, init_error) = dsu.init(parent[0..], rank[0..], 6usize)
    if init_error != ok { os.exit(41) }
    var s = initial
    if dsu.len(&s) != 6usize || dsu.set_count(&s) != 6usize { os.exit(42) }
    if dsu.same(&s, 0u32, 1u32) { os.exit(43) }
    if !dsu.join(&s, 0u32, 1u32) || !dsu.join(&s, 2u32, 3u32) || !dsu.join(&s, 1u32, 3u32) { os.exit(44) }
    if dsu.join(&s, 0u32, 2u32) { os.exit(45) }
    if dsu.set_count(&s) != 3usize { os.exit(46) }
    if !dsu.same(&s, 0u32, 3u32) || dsu.same(&s, 0u32, 4u32) { os.exit(47) }
    // After a find every element on the path points at the root directly.
    let root = dsu.find(&s, 0u32)
    if dsu.find(&s, 3u32) != root || s.parent[0] != root || s.parent[3] != root { os.exit(48) }
    // Union by rank: joining a singleton to a tree keeps the tree's root.
    if !dsu.join(&s, 4u32, 0u32) || dsu.find(&s, 4u32) != root { os.exit(49) }
    if dsu.set_count(&s) != 2usize { os.exit(50) }
    dsu.reset(&s)
    if dsu.set_count(&s) != 6usize || dsu.same(&s, 0u32, 1u32) || dsu.find(&s, 5u32) != 5u32 { os.exit(51) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    stacks(a)
    queues(a)
    sets()
    os.exit(0)
    ret ok
}
