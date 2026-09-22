// Gossip simulated in-process over `n` nodes given as indices. `disseminate`
// is push/pull rumour spreading in synchronous rounds: every node contacts
// `fanout` uniformly random peers from a caller `rand.Pcg64`, and a contact
// where either side knew the rumour at the start of the round informs both
// (`gossip_round` answers how many learned it, `gossip_rounds_until_all` runs
// to saturation). `membership` is a SWIM-style table of `Member` records with
// the incarnation precedence rules: a higher incarnation wins outright, and
// within one incarnation Dead beats Suspect beats Alive (`membership_merge`
// folds in what a peer sent; `membership_suspect` / `membership_confirm` move
// a member down; `membership_refute` is the member itself bumping its
// incarnation to override a suspicion).

use e.algo.rand

// One byte per node: 0 unaware, 1 informed, 2 informed during the current round.
type Gossip = struct { state: []u8, fanout: usize, informed: usize }

type Status = enum u8 { Alive, Suspect, Dead }
type Member = struct { id: u32, incarnation: u32, status: Status, heartbeat: u64 }
type Membership = struct { members: []Member, count: usize }
error TooSmall

// `origin` alone knows the rumour; `state` must hold one entry per node.
fn gossip(state: []u8, fanout: usize, origin: usize) -> Gossip {
    var i = 0usize
    while i < state.len {
        state[i] = 0u8
        i += 1usize
    }
    state[origin] = 1u8
    ret Gossip { state: state, fanout: fanout, informed: 1usize }
}

fn informed(g: *const Gossip, node: usize) -> bool { ret g.state[node] != 0u8 }

// One synchronous round; answers how many nodes were newly informed.
fn gossip_round(g: *Gossip, r: *rand.Pcg64) -> usize {
    let n = g.state.len
    if n < 2usize { ret 0usize }
    var node = 0usize
    while node < n {
        var k = 0usize
        while k < g.fanout {
            var peer = usize(rand.pcg64_bounded(r, u64(n - 1usize)))
            if peer >= node { peer += 1usize }
            if g.state[node] == 1u8 || g.state[peer] == 1u8 {
                if g.state[node] == 0u8 { g.state[node] = 2u8 }
                if g.state[peer] == 0u8 { g.state[peer] = 2u8 }
            }
            k += 1usize
        }
        node += 1usize
    }
    var fresh = 0usize
    node = 0usize
    while node < n {
        if g.state[node] == 2u8 {
            g.state[node] = 1u8
            fresh += 1usize
        }
        node += 1usize
    }
    g.informed += fresh
    ret fresh
}

// Rounds until every node knows, at most `limit` (0 is no limit).
fn gossip_rounds_until_all(g: *Gossip, r: *rand.Pcg64, limit: usize) -> usize {
    var rounds = 0usize
    while g.informed < g.state.len && (limit == 0usize || rounds < limit) {
        let _ = gossip_round(g, r)
        rounds += 1usize
    }
    ret rounds
}

fn membership(members: []Member) -> Membership { ret Membership { members: members, count: 0usize } }

fn membership_find(t: *const Membership, id: u32) -> (usize, bool) {
    var i = 0usize
    while i < t.count {
        if t.members[i].id == id { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn rank(s: Status) -> u32 {
    if s == .Dead { ret 2u32 }
    if s == .Suspect { ret 1u32 }
    ret 0u32
}

// Does `incoming` override what the table holds about the same member?
fn supersedes(incoming: Member, held: Member) -> bool {
    if incoming.incarnation != held.incarnation { ret incoming.incarnation > held.incarnation }
    ret rank(incoming.status) > rank(held.status)
}

// Fold one record in; answers whether the table changed. An unknown id is
// appended (TooSmall when the table is full).
fn membership_apply(t: *Membership, incoming: Member) -> (bool, err) {
    let (i, found) = membership_find(t, incoming.id)
    if found {
        if !supersedes(incoming, t.members[i]) { ret (false, ok) }
        t.members[i] = incoming
        ret (true, ok)
    }
    if t.count >= t.members.len { ret (false, TooSmall) }
    t.members[t.count] = incoming
    t.count += 1usize
    ret (true, ok)
}

// Fold a peer's table in; answers how many records changed ours.
fn membership_merge(t: *Membership, incoming: []const Member) -> (usize, err) {
    var changed = 0usize
    var i = 0usize
    while i < incoming.len {
        let (did, e) = membership_apply(t, incoming[i])
        if e != ok { ret (changed, e) }
        if did { changed += 1usize }
        i += 1usize
    }
    ret (changed, ok)
}

fn set_status(t: *Membership, id: u32, from: Status, to: Status, now: u64) -> bool {
    let (i, found) = membership_find(t, id)
    if !found || t.members[i].status != from { ret false }
    t.members[i].status = to
    t.members[i].heartbeat = now
    ret true
}

// Alive -> Suspect at the same incarnation; answers whether it applied.
fn membership_suspect(t: *Membership, id: u32, now: u64) -> bool { ret set_status(t, id, .Alive, .Suspect, now) }

// Suspect -> Dead; answers whether it applied.
fn membership_confirm(t: *Membership, id: u32, now: u64) -> bool { ret set_status(t, id, .Suspect, .Dead, now) }

// The member `id` refutes a suspicion about itself: a fresh incarnation, Alive.
// Answers the new incarnation (0 when `id` is unknown or already Dead).
fn membership_refute(t: *Membership, id: u32, now: u64) -> u32 {
    let (i, found) = membership_find(t, id)
    if !found || t.members[i].status == .Dead { ret 0u32 }
    t.members[i].incarnation += 1u32
    t.members[i].status = .Alive
    t.members[i].heartbeat = now
    ret t.members[i].incarnation
}

// Members whose last heartbeat is older than `now - timeout` and still Alive
// become Suspect; answers how many.
fn membership_sweep(t: *Membership, now: u64, timeout: u64) -> usize {
    var n = 0usize
    var i = 0usize
    while i < t.count {
        if t.members[i].status == .Alive && now >= timeout && t.members[i].heartbeat < now - timeout {
            t.members[i].status = .Suspect
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// Rumour spreading in one call: `origin` alone knows it, every node contacts
// `fanout` random peers per round for `rounds` rounds; answers how many nodes
// hold the rumour at the end.
fn disseminate(state: []u8, fanout: usize, origin: usize, r: *rand.Pcg64, rounds: usize) -> usize {
    var g = gossip(state, fanout, origin)
    var i = 0usize
    while i < rounds {
        let _ = gossip_round(&g, r)
        i += 1usize
    }
    ret g.informed
}
