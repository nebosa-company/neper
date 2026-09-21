// Leader election simulated over `n` nodes given as indices with an `alive`
// array; the messages the classic algorithms would send land in a caller
// `[]Message` (as many as fit, and every one is counted). `bully` is
// Garcia-Molina's bully algorithm: the initiator sends Election to every higher
// id, each alive higher node answers OK and runs its own election, and the
// highest alive node sends Coordinator to every alive lower node. `ring` is the
// ring algorithm: an Election message hops around `ring_order` between alive
// nodes collecting ids, then a Coordinator message makes the same trip, so it
// costs exactly two messages per alive node. Both answer the leader (the
// highest alive id) and the message count.

type Kind = enum u8 { Election, Ok, Coordinator }
type Message = struct { kind: Kind, from: u32, to: u32 }
type Sent = struct { out: []Message, count: usize }
error TooSmall
error Invalid

fn push(s: *Sent, kind: Kind, from: usize, to: usize) {
    if s.count < s.out.len { s.out[s.count] = Message { kind: kind, from: u32(from), to: u32(to) } }
    s.count += 1usize
}

fn highest_alive(alive: []const bool) -> usize {
    var i = alive.len
    while i > 0usize {
        i -= 1usize
        if alive[i] { ret i }
    }
    ret 0usize
}

// Answers (leader, message count, error): Invalid when the initiator is dead
// or out of range, TooSmall when `out` did not hold every message (the count
// is still exact).
fn bully(alive: []const bool, initiator: usize, out: []Message) -> (usize, usize, err) {
    if initiator >= alive.len || !alive[initiator] { ret (0usize, 0usize, Invalid) }
    var s = Sent { out: out, count: 0usize }
    // The initiator reaches every higher id, so every alive node at or above
    // it runs an election exactly once; ascending order is the causal order.
    var i = initiator
    while i < alive.len {
        if alive[i] {
            var h = i + 1usize
            while h < alive.len {
                push(&s, .Election, i, h)
                h += 1usize
            }
            h = i + 1usize
            while h < alive.len {
                if alive[h] { push(&s, .Ok, h, i) }
                h += 1usize
            }
        }
        i += 1usize
    }
    let leader = highest_alive(alive)
    var l = 0usize
    while l < leader {
        if alive[l] { push(&s, .Coordinator, leader, l) }
        l += 1usize
    }
    if s.count > out.len { ret (leader, s.count, TooSmall) }
    ret (leader, s.count, ok)
}

// Answers (leader, message count, error): Invalid when the initiator is dead
// or `ring_order` is not one entry per node, TooSmall when `out` overflowed.
fn ring(alive: []const bool, ring_order: []const usize, initiator: usize, out: []Message) -> (usize, usize, err) {
    if ring_order.len != alive.len || initiator >= alive.len || !alive[initiator] { ret (0usize, 0usize, Invalid) }
    var start = 0usize
    while start < ring_order.len && ring_order[start] != initiator { start += 1usize }
    if start == ring_order.len { ret (0usize, 0usize, Invalid) }
    var s = Sent { out: out, count: 0usize }
    let leader = highest_alive(alive)
    var pass = 0usize
    while pass < 2usize {
        var kind: Kind = .Election
        if pass == 1usize { kind = .Coordinator }
        var from = initiator
        var k = 1usize
        while k <= ring_order.len {
            let to = ring_order[(start + k) % ring_order.len]
            if alive[to] {
                push(&s, kind, from, to)
                from = to
            }
            k += 1usize
        }
        pass += 1usize
    }
    if s.count > out.len { ret (leader, s.count, TooSmall) }
    ret (leader, s.count, ok)
}
