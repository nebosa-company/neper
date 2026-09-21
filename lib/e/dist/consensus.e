// Consensus protocols as pure in-process state machines over caller
// storage: nodes are indices, a `Message` is a record the caller delivers
// through a `Pool` (push, take by position), and time is whatever `now`
// the caller passes. Raft (`raft_election_step`, `raft_replicate_step`,
// `raft_snapshot`, `membership_change` by joint consensus, all dispatched
// by `raft_step`), single-decree `paxos` with proposers, acceptors and
// learners, `multi_paxos` with a stable leader skipping Prepare per slot,
// and `viewstamped` replication with a view change. No threads, no e.net.
// Node ids are bits of a `u64` mask, so a cluster holds at most 64 nodes.
// The replicated state machine is `state += value`.

use e.algo.rand
use e.bytes

type Kind = enum u8 { None, RequestVote, VoteResponse, AppendEntries, AppendResponse, InstallSnapshot, SnapshotResponse, Prepare, Promise, Accept, Accepted, VrPrepare, VrPrepareOk, VrCommit, StartViewChange, DoViewChange, StartView }

// A log entry; `cfg_new != 0` marks a configuration entry (joint while
// `cfg_old != cfg_new`).
type Entry = struct { term: u64, value: i64, cfg_old: u64, cfg_new: u64 }

// One record for every protocol: `term` is the term, ballot or view,
// `index` the log index, slot or op number, `term2` a second term
// (prevLogTerm, lastIncludedTerm, last normal view), `commit` a commit
// index, `flag` a grant/success bit, `entry` the shipped log entry.
type Message = struct { from: u32, to: u32, kind: Kind, term: u64, index: u64, term2: u64, commit: u64, value: i64, flag: bool, entry: Entry }
type Pool = struct { items: []Message, len: usize }

type Role = enum u8 { Follower, Candidate, Leader }
type Node = struct { id: u32, role: Role, term: u64, voted_for: u32, votes: u64, leader: u32, log: []Entry, log_len: usize, snap_index: u64, snap_term: u64, snap_state: i64, commit: u64, applied: u64, state: i64, next_index: []u64, match_index: []u64, cfg_old: u64, cfg_new: u64, timeout_at: u64, heartbeat_at: u64 }
type Cluster = struct { nodes: []Node, rng: rand.Pcg64, timeout_min: u64, timeout_max: u64, heartbeat: u64 }

type Acceptor = struct { promised: u64, accepted_n: u64, accepted_value: i64 }
type Proposer = struct { round: u64, n: u64, value: i64, phase: u8, promises: u64, best_n: u64, best_value: i64, learned_n: u64, learned_mask: u64, decided: bool, decided_value: i64 }
type Paxos = struct { acceptors: []Acceptor, proposers: []Proposer }

type MpNode = struct { promised: u64, slot_n: []u64, slot_value: []i64, ballot: u64, leading: bool, promises: u64, next_slot: u64, proposed: []i64, accept_mask: []u64, decided: []bool }
type MultiPaxos = struct { nodes: []MpNode }

type VrStatus = enum u8 { Normal, ViewChange }
type VrNode = struct { id: u32, view: u64, status: VrStatus, last_normal: u64, op: u64, commit: u64, state: i64, log: []i64, prepare_ok: []u64, svc_mask: u64, dvc_sent: bool, dvc_mask: u64, best_from: u32, best_view: u64, best_op: u64, best_commit: u64 }
type Vr = struct { nodes: []VrNode }

error TooSmall
error Invalid
error NotLeader

const NONE: u32 = 4294967295u32

fn pool(items: []Message) -> Pool { ret Pool { items: items, len: 0usize } }

fn pool_push(p: *Pool, m: Message) -> err {
    if p.len >= p.items.len { ret TooSmall }
    p.items[p.len] = m
    p.len += 1usize
    ret ok
}

// Remove and answer the message at `at` (the last one moves into its slot).
fn pool_take(p: *Pool, at: usize) -> Message {
    let m = p.items[at]
    p.len -= 1usize
    p.items[at] = p.items[p.len]
    ret m
}

// Remove and answer the oldest message (FIFO delivery).
fn pool_pop(p: *Pool) -> Message {
    let m = p.items[0usize]
    var i = 1usize
    while i < p.len {
        p.items[i - 1usize] = p.items[i]
        i += 1usize
    }
    p.len -= 1usize
    ret m
}

fn has_bit(mask: u64, i: u32) -> bool { ret ((mask >> i) & 1u64) == 1u64 }

fn majority(mask: u64, cfg: u64) -> bool { ret usize(bytes.count_ones[u64](mask & cfg)) * 2usize > usize(bytes.count_ones[u64](cfg)) }

fn has_majority(n: *const Node, mask: u64) -> bool {
    if !majority(mask, n.cfg_old) { ret false }
    ret n.cfg_old == n.cfg_new || majority(mask, n.cfg_new)
}

// ---- Raft ----

fn raft_node(id: u32, log: []Entry, next_index: []u64, match_index: []u64, config: u64) -> Node {
    ret Node { id: id, role: .Follower, term: 0u64, voted_for: NONE, votes: 0u64, leader: NONE, log: log, log_len: 0usize, snap_index: 0u64, snap_term: 0u64, snap_state: 0i64, commit: 0u64, applied: 0u64, state: 0i64, next_index: next_index, match_index: match_index, cfg_old: config, cfg_new: config, timeout_at: 0u64, heartbeat_at: 0u64 }
}

// Election timeouts are drawn uniformly from [timeout_min, timeout_max].
fn raft_cluster(nodes: []Node, seed: u64, timeout_min: u64, timeout_max: u64, heartbeat: u64) -> Cluster {
    var c = Cluster { nodes: nodes, rng: rand.pcg64(seed, 1u64), timeout_min: timeout_min, timeout_max: timeout_max, heartbeat: heartbeat }
    var i = 0usize
    while i < nodes.len {
        reset_timeout(&c, &c.nodes[i], 0u64)
        i += 1usize
    }
    ret c
}

fn reset_timeout(c: *Cluster, n: *Node, now: u64) {
    n.timeout_at = now + c.timeout_min + rand.pcg64_bounded(&c.rng, c.timeout_max - c.timeout_min + 1u64)
}

fn last_index(n: *const Node) -> u64 { ret n.snap_index + u64(n.log_len) }

fn term_at(n: *const Node, index: u64) -> u64 {
    if index == n.snap_index { ret n.snap_term }
    if index > n.snap_index && index <= last_index(n) { ret n.log[usize(index - n.snap_index - 1u64)].term }
    ret 0u64
}

fn step_down(n: *Node, term: u64) {
    n.role = .Follower
    n.term = term
    n.voted_for = NONE
    n.votes = 0u64
}

fn append_entry(n: *Node, e: Entry) -> err {
    if n.log_len >= n.log.len { ret TooSmall }
    n.log[n.log_len] = e
    n.log_len += 1usize
    if e.cfg_new != 0u64 {
        n.cfg_old = e.cfg_old
        n.cfg_new = e.cfg_new
    }
    ret ok
}

// Apply committed entries; a leader that applies a joint configuration
// appends the final one.
fn apply(n: *Node) -> err {
    while n.applied < n.commit {
        n.applied += 1u64
        let e = n.log[usize(n.applied - n.snap_index - 1u64)]
        if e.cfg_new == 0u64 {
            n.state = n.state +% e.value
        } else if e.cfg_old != e.cfg_new && n.role == .Leader && n.cfg_old != n.cfg_new {
            try append_entry(n, Entry { term: n.term, value: 0i64, cfg_old: e.cfg_new, cfg_new: e.cfg_new })
            n.match_index[usize(n.id)] = last_index(n)
        }
    }
    ret ok
}

fn broadcast(c: *Cluster, n: *const Node, out: *Pool, m: Message) -> err {
    let members = n.cfg_old | n.cfg_new
    var p = 0usize
    while p < c.nodes.len {
        if p != usize(n.id) && has_bit(members, u32(p)) {
            var copy = m
            copy.to = u32(p)
            try pool_push(out, copy)
        }
        p += 1usize
    }
    ret ok
}

fn become_leader(c: *Cluster, n: *Node, now: u64, out: *Pool) -> err {
    n.role = .Leader
    n.leader = n.id
    // The no-op of the new term lets earlier terms' entries commit by count.
    try append_entry(n, Entry { term: n.term, value: 0i64, cfg_old: 0u64, cfg_new: 0u64 })
    let last = last_index(n)
    var p = 0usize
    while p < c.nodes.len {
        n.next_index[p] = last + 1u64
        n.match_index[p] = 0u64
        p += 1usize
    }
    n.match_index[usize(n.id)] = last
    ret send_appends(c, n, now, out)
}

// One AppendEntries (or InstallSnapshot for a follower behind the
// snapshot) to `to`, carrying at most one entry.
fn send_append(c: *Cluster, n: *const Node, to: u32, out: *Pool) -> err {
    var m: Message = zero
    m.from = n.id
    m.to = to
    m.term = n.term
    let next = n.next_index[usize(to)]
    if next <= n.snap_index {
        m.kind = .InstallSnapshot
        m.index = n.snap_index
        m.term2 = n.snap_term
        m.value = n.snap_state
        // ponytail: the snapshot ships the current configuration, not the one as of snap_index
        m.entry = Entry { term: n.snap_term, value: 0i64, cfg_old: n.cfg_old, cfg_new: n.cfg_new }
        ret pool_push(out, m)
    }
    m.kind = .AppendEntries
    m.index = next - 1u64
    m.term2 = term_at(n, m.index)
    m.commit = n.commit
    if next <= last_index(n) {
        m.flag = true
        m.entry = n.log[usize(next - n.snap_index - 1u64)]
    }
    ret pool_push(out, m)
}

fn send_appends(c: *Cluster, n: *Node, now: u64, out: *Pool) -> err {
    n.heartbeat_at = now + c.heartbeat
    let members = n.cfg_old | n.cfg_new
    var p = 0usize
    while p < c.nodes.len {
        if p != usize(n.id) && has_bit(members, u32(p)) { try send_append(c, n, u32(p), out) }
        p += 1usize
    }
    ret ok
}

// Leader election: a follower or candidate past its timeout starts a term
// and asks for votes; a vote goes to the first candidate of the term whose
// log is at least as complete; a majority (of both configurations while
// joint) makes a leader. `msg.kind == .None` is a clock tick.
fn raft_election_step(c: *Cluster, node: usize, now: u64, msg: *const Message, out: *Pool) -> err {
    let n = &c.nodes[node]
    if msg.kind == .None {
        // ponytail: a node outside its own configuration never starts an election
        if n.role != .Leader && now >= n.timeout_at && has_bit(n.cfg_old | n.cfg_new, n.id) {
            n.role = .Candidate
            n.term += 1u64
            n.voted_for = n.id
            n.votes = 1u64 << n.id
            n.leader = NONE
            reset_timeout(c, n, now)
            var m: Message = zero
            m.from = n.id
            m.kind = .RequestVote
            m.term = n.term
            m.index = last_index(n)
            m.term2 = term_at(n, m.index)
            try broadcast(c, n, out, m)
            if has_majority(n, n.votes) { try become_leader(c, n, now, out) }
        }
        ret ok
    }
    if msg.term > n.term { step_down(n, msg.term) }
    if msg.kind == .RequestVote {
        var grant = false
        if msg.term == n.term && (n.voted_for == NONE || n.voted_for == msg.from) {
            let my_last = last_index(n)
            let my_term = term_at(n, my_last)
            if msg.term2 > my_term || (msg.term2 == my_term && msg.index >= my_last) { grant = true }
        }
        if grant {
            n.voted_for = msg.from
            reset_timeout(c, n, now)
        }
        var r: Message = zero
        r.from = n.id
        r.to = msg.from
        r.kind = .VoteResponse
        r.term = n.term
        r.flag = grant
        ret pool_push(out, r)
    }
    if msg.kind == .VoteResponse {
        if n.role == .Candidate && msg.term == n.term && msg.flag {
            n.votes |= 1u64 << msg.from
            if has_majority(n, n.votes) { try become_leader(c, n, now, out) }
        }
        ret ok
    }
    ret Invalid
}

// Commit index: the highest current-term index replicated on a majority.
fn advance_commit(c: *Cluster, n: *Node) -> err {
    var candidate = last_index(n)
    while candidate > n.commit {
        if term_at(n, candidate) == n.term {
            var mask = 0u64
            var p = 0usize
            while p < c.nodes.len {
                if n.match_index[p] >= candidate { mask |= 1u64 << u32(p) }
                p += 1usize
            }
            if has_majority(n, mask) {
                n.commit = candidate
                break
            }
        }
        candidate -= 1u64
    }
    ret apply(n)
}

// Log replication: AppendEntries with the prevLogIndex/prevLogTerm check,
// truncation of a conflicting follower suffix, and the leader's commit
// index from match indexes. A tick sends heartbeats from a leader.
fn raft_replicate_step(c: *Cluster, node: usize, now: u64, msg: *const Message, out: *Pool) -> err {
    let n = &c.nodes[node]
    if msg.kind == .None {
        if n.role == .Leader && now >= n.heartbeat_at { ret send_appends(c, n, now, out) }
        ret ok
    }
    if msg.term > n.term { step_down(n, msg.term) }
    if msg.kind == .AppendEntries {
        var r: Message = zero
        r.from = n.id
        r.to = msg.from
        r.kind = .AppendResponse
        r.term = n.term
        if msg.term < n.term { ret pool_push(out, r) }
        n.role = .Follower
        n.leader = msg.from
        reset_timeout(c, n, now)
        if msg.index > last_index(n) {
            r.index = last_index(n)
            ret pool_push(out, r)
        }
        if msg.index < n.snap_index {
            r.flag = true
            r.index = n.snap_index
            ret pool_push(out, r)
        }
        if term_at(n, msg.index) != msg.term2 {
            n.log_len = usize(msg.index - n.snap_index - 1u64)
            r.index = msg.index - 1u64
            ret pool_push(out, r)
        }
        var matched = msg.index
        if msg.flag {
            let at_index = msg.index + 1u64
            if at_index <= last_index(n) && term_at(n, at_index) != msg.entry.term { n.log_len = usize(at_index - n.snap_index - 1u64) }
            if at_index > last_index(n) { try append_entry(n, msg.entry) }
            matched = at_index
        }
        if msg.commit > n.commit {
            n.commit = msg.commit
            if matched < n.commit { n.commit = matched }
        }
        try apply(n)
        r.flag = true
        r.index = matched
        ret pool_push(out, r)
    }
    if msg.kind == .AppendResponse {
        if n.role != .Leader || msg.term != n.term { ret ok }
        let p = usize(msg.from)
        if msg.flag {
            if msg.index > n.match_index[p] { n.match_index[p] = msg.index }
            n.next_index[p] = n.match_index[p] + 1u64
            try advance_commit(c, n)
            if n.next_index[p] <= last_index(n) { try send_append(c, n, msg.from, out) }
            ret ok
        }
        var next = msg.index + 1u64
        if next >= n.next_index[p] { next = n.next_index[p] - 1u64 }
        if next < 1u64 { next = 1u64 }
        n.next_index[p] = next
        ret send_append(c, n, msg.from, out)
    }
    ret Invalid
}

// Append a value at the leader; answers its index.
fn raft_propose(c: *Cluster, node: usize, value: i64) -> (u64, err) {
    let n = &c.nodes[node]
    if n.role != .Leader { ret (0u64, NotLeader) }
    let append_error = append_entry(n, Entry { term: n.term, value: value, cfg_old: 0u64, cfg_new: 0u64 })
    if append_error != ok { ret (0u64, append_error) }
    n.match_index[usize(n.id)] = last_index(n)
    let commit_error = advance_commit(c, n)
    ret (last_index(n), commit_error)
}

// Joint consensus: the leader appends C_old,new (majorities of both count
// until it commits), then C_new on its own once that is applied.
fn membership_change(c: *Cluster, node: usize, new_config: u64) -> err {
    let n = &c.nodes[node]
    if n.role != .Leader { ret NotLeader }
    if n.cfg_old != n.cfg_new || new_config == 0u64 { ret Invalid }
    try append_entry(n, Entry { term: n.term, value: 0i64, cfg_old: n.cfg_old, cfg_new: new_config })
    n.match_index[usize(n.id)] = last_index(n)
    ret advance_commit(c, n)
}

// Compact the applied prefix of a node's log into its snapshot record.
fn raft_snapshot(c: *Cluster, node: usize) -> err {
    let n = &c.nodes[node]
    if n.applied <= n.snap_index { ret ok }
    let count = usize(n.applied - n.snap_index)
    n.snap_term = term_at(n, n.applied)
    n.snap_index = n.applied
    n.snap_state = n.state
    var i = 0usize
    while i + count < n.log_len {
        n.log[i] = n.log[i + count]
        i += 1usize
    }
    n.log_len -= count
    ret ok
}

// InstallSnapshot at a lagging follower and the leader's bookkeeping.
fn raft_snapshot_step(c: *Cluster, node: usize, now: u64, msg: *const Message, out: *Pool) -> err {
    let n = &c.nodes[node]
    if msg.term > n.term { step_down(n, msg.term) }
    if msg.kind == .InstallSnapshot {
        var r: Message = zero
        r.from = n.id
        r.to = msg.from
        r.kind = .SnapshotResponse
        r.term = n.term
        if msg.term < n.term { ret pool_push(out, r) }
        n.role = .Follower
        n.leader = msg.from
        reset_timeout(c, n, now)
        if msg.index > n.snap_index {
            if msg.index <= last_index(n) && term_at(n, msg.index) == msg.term2 {
                let drop = usize(msg.index - n.snap_index)
                var i = 0usize
                while i + drop < n.log_len {
                    n.log[i] = n.log[i + drop]
                    i += 1usize
                }
                n.log_len -= drop
            } else {
                n.log_len = 0usize
            }
            n.snap_index = msg.index
            n.snap_term = msg.term2
            n.snap_state = msg.value
            if msg.index > n.applied {
                n.applied = msg.index
                n.state = msg.value
            }
            if msg.index > n.commit { n.commit = msg.index }
            if msg.entry.cfg_new != 0u64 {
                n.cfg_old = msg.entry.cfg_old
                n.cfg_new = msg.entry.cfg_new
            }
        }
        r.flag = true
        r.index = n.snap_index
        ret pool_push(out, r)
    }
    if msg.kind == .SnapshotResponse {
        if n.role != .Leader || msg.term != n.term { ret ok }
        let p = usize(msg.from)
        if msg.index > n.match_index[p] { n.match_index[p] = msg.index }
        n.next_index[p] = n.match_index[p] + 1u64
        try advance_commit(c, n)
        if n.next_index[p] <= last_index(n) { try send_append(c, n, msg.from, out) }
        ret ok
    }
    ret Invalid
}

// Deliver one message (or a tick with `.None`) to `node`.
fn raft_step(c: *Cluster, node: usize, now: u64, msg: *const Message, out: *Pool) -> err {
    if msg.kind == .None {
        try raft_election_step(c, node, now, msg, out)
        ret raft_replicate_step(c, node, now, msg, out)
    }
    if msg.kind == .RequestVote || msg.kind == .VoteResponse { ret raft_election_step(c, node, now, msg, out) }
    if msg.kind == .AppendEntries || msg.kind == .AppendResponse { ret raft_replicate_step(c, node, now, msg, out) }
    if msg.kind == .InstallSnapshot || msg.kind == .SnapshotResponse { ret raft_snapshot_step(c, node, now, msg, out) }
    ret Invalid
}

// ---- single-decree Paxos ----

// Node `i` is acceptor `i`, proposer `i` and learner `i`; a proposal number
// is `round * proposers + id`, so numbers are unique and ordered by round.
fn paxos(acceptors: []Acceptor, proposers: []Proposer) -> Paxos { ret Paxos { acceptors: acceptors, proposers: proposers } }

fn simple_majority(mask: u64, count: usize) -> bool { ret usize(bytes.count_ones[u64](mask)) * 2usize > count }

fn to_all(count: usize, out: *Pool, m: Message) -> err {
    var i = 0usize
    while i < count {
        var copy = m
        copy.to = u32(i)
        try pool_push(out, copy)
        i += 1usize
    }
    ret ok
}

// Start (or retry with a higher number) a proposal of `value` from `node`.
fn paxos_propose(p: *Paxos, node: usize, value: i64, out: *Pool) -> err {
    let pr = &p.proposers[node]
    pr.round += 1u64
    pr.n = pr.round * u64(p.proposers.len) + u64(node)
    pr.value = value
    pr.phase = 1u8
    pr.promises = 0u64
    pr.best_n = 0u64
    var m: Message = zero
    m.from = u32(node)
    m.kind = .Prepare
    m.term = pr.n
    ret to_all(p.acceptors.len, out, m)
}

fn paxos_step(p: *Paxos, node: usize, msg: *const Message, out: *Pool) -> err {
    if msg.kind == .Prepare {
        let a = &p.acceptors[node]
        if msg.term <= a.promised { ret ok }
        a.promised = msg.term
        var r: Message = zero
        r.from = u32(node)
        r.to = msg.from
        r.kind = .Promise
        r.term = msg.term
        r.index = a.accepted_n
        r.value = a.accepted_value
        ret pool_push(out, r)
    }
    if msg.kind == .Promise {
        let pr = &p.proposers[node]
        if pr.phase != 1u8 || msg.term != pr.n { ret ok }
        pr.promises |= 1u64 << msg.from
        if msg.index > pr.best_n {
            pr.best_n = msg.index
            pr.best_value = msg.value
        }
        if !simple_majority(pr.promises, p.acceptors.len) { ret ok }
        pr.phase = 2u8
        if pr.best_n > 0u64 { pr.value = pr.best_value }
        var m: Message = zero
        m.from = u32(node)
        m.kind = .Accept
        m.term = pr.n
        m.value = pr.value
        ret to_all(p.acceptors.len, out, m)
    }
    if msg.kind == .Accept {
        let a = &p.acceptors[node]
        if msg.term < a.promised { ret ok }
        a.promised = msg.term
        a.accepted_n = msg.term
        a.accepted_value = msg.value
        var m: Message = zero
        m.from = u32(node)
        m.kind = .Accepted
        m.term = msg.term
        m.value = msg.value
        ret to_all(p.proposers.len, out, m)
    }
    if msg.kind == .Accepted {
        let l = &p.proposers[node]
        if msg.term > l.learned_n {
            l.learned_n = msg.term
            l.learned_mask = 0u64
        }
        if msg.term == l.learned_n {
            l.learned_mask |= 1u64 << msg.from
            if simple_majority(l.learned_mask, p.acceptors.len) && !l.decided {
                l.decided = true
                l.decided_value = msg.value
            }
        }
        ret ok
    }
    ret Invalid
}

// ---- Multi-Paxos ----

fn multi_paxos(nodes: []MpNode) -> MultiPaxos { ret MultiPaxos { nodes: nodes } }

fn mp_node(slot_n: []u64, slot_value: []i64, proposed: []i64, accept_mask: []u64, decided: []bool) -> MpNode {
    ret MpNode { promised: 0u64, slot_n: slot_n, slot_value: slot_value, ballot: 0u64, leading: false, promises: 0u64, next_slot: 0u64, proposed: proposed, accept_mask: accept_mask, decided: decided }
}

// One Prepare for every slot at once: a ballot unique to `node`.
fn multi_paxos_lead(m: *MultiPaxos, node: usize, out: *Pool) -> err {
    let n = &m.nodes[node]
    let count = u64(m.nodes.len)
    n.ballot = (n.ballot / count + 1u64) * count + u64(node)
    n.leading = false
    n.promises = 0u64
    var msg: Message = zero
    msg.from = u32(node)
    msg.kind = .Prepare
    msg.term = n.ballot
    ret to_all(m.nodes.len, out, msg)
}

// A stable leader skips Prepare: Accept straight into the next slot.
fn multi_paxos_propose(m: *MultiPaxos, node: usize, value: i64, out: *Pool) -> (u64, err) {
    let n = &m.nodes[node]
    if !n.leading { ret (0u64, NotLeader) }
    let slot = n.next_slot
    if usize(slot) >= n.proposed.len { ret (0u64, TooSmall) }
    n.next_slot += 1u64
    n.proposed[usize(slot)] = value
    n.accept_mask[usize(slot)] = 0u64
    n.decided[usize(slot)] = false
    var msg: Message = zero
    msg.from = u32(node)
    msg.kind = .Accept
    msg.term = n.ballot
    msg.index = slot
    msg.value = value
    let send_error = to_all(m.nodes.len, out, msg)
    ret (slot, send_error)
}

fn multi_paxos_step(m: *MultiPaxos, node: usize, msg: *const Message, out: *Pool) -> err {
    let n = &m.nodes[node]
    if msg.kind == .Prepare {
        if msg.term <= n.promised { ret ok }
        n.promised = msg.term
        // ponytail: the promise carries only the first free slot, not the
        // accepted values; a new leader must start past every accepted slot
        var free = 0u64
        var i = 0usize
        while i < n.slot_n.len {
            if n.slot_n[i] != 0u64 { free = u64(i) + 1u64 }
            i += 1usize
        }
        var r: Message = zero
        r.from = u32(node)
        r.to = msg.from
        r.kind = .Promise
        r.term = msg.term
        r.index = free
        ret pool_push(out, r)
    }
    if msg.kind == .Promise {
        if n.leading || msg.term != n.ballot { ret ok }
        n.promises |= 1u64 << msg.from
        if msg.index > n.next_slot { n.next_slot = msg.index }
        if simple_majority(n.promises, m.nodes.len) { n.leading = true }
        ret ok
    }
    if msg.kind == .Accept {
        if msg.term < n.promised || usize(msg.index) >= n.slot_n.len { ret ok }
        n.promised = msg.term
        n.slot_n[usize(msg.index)] = msg.term
        n.slot_value[usize(msg.index)] = msg.value
        var r: Message = zero
        r.from = u32(node)
        r.to = msg.from
        r.kind = .Accepted
        r.term = msg.term
        r.index = msg.index
        r.value = msg.value
        ret pool_push(out, r)
    }
    if msg.kind == .Accepted {
        if !n.leading || msg.term != n.ballot || msg.index >= n.next_slot { ret ok }
        let slot = usize(msg.index)
        n.accept_mask[slot] |= 1u64 << msg.from
        if simple_majority(n.accept_mask[slot], m.nodes.len) { n.decided[slot] = true }
        ret ok
    }
    ret Invalid
}

// ---- Viewstamped Replication ----

fn viewstamped(nodes: []VrNode) -> Vr { ret Vr { nodes: nodes } }

fn vr_node(id: u32, log: []i64, prepare_ok: []u64) -> VrNode {
    ret VrNode { id: id, view: 0u64, status: .Normal, last_normal: 0u64, op: 0u64, commit: 0u64, state: 0i64, log: log, prepare_ok: prepare_ok, svc_mask: 0u64, dvc_sent: false, dvc_mask: 0u64, best_from: NONE, best_view: 0u64, best_op: 0u64, best_commit: 0u64 }
}

fn vr_primary(v: *const Vr, view: u64) -> u32 { ret u32(view % u64(v.nodes.len)) }

fn vr_execute(n: *VrNode, up_to: u64) {
    var limit = up_to
    if limit > n.op { limit = n.op }
    while n.commit < limit {
        n.state = n.state +% n.log[usize(n.commit)]
        n.commit += 1u64
    }
}

fn vr_others(v: *const Vr, node: usize, out: *Pool, m: Message) -> err {
    var i = 0usize
    while i < v.nodes.len {
        if i != node {
            var copy = m
            copy.to = u32(i)
            try pool_push(out, copy)
        }
        i += 1usize
    }
    ret ok
}

// A client request at the primary: the next op number, Prepare to backups.
fn vr_request(v: *Vr, node: usize, value: i64, out: *Pool) -> err {
    let n = &v.nodes[node]
    if n.status != .Normal || vr_primary(v, n.view) != n.id { ret NotLeader }
    if usize(n.op) >= n.log.len { ret TooSmall }
    n.log[usize(n.op)] = value
    n.prepare_ok[usize(n.op)] = 1u64 << n.id
    n.op += 1u64
    var m: Message = zero
    m.from = n.id
    m.kind = .VrPrepare
    m.term = n.view
    m.index = n.op
    m.value = value
    m.commit = n.commit
    ret vr_others(v, node, out, m)
}

// A backup that suspects the primary: it starts the next view.
fn vr_primary_dead(v: *Vr, node: usize, out: *Pool) -> err {
    let n = &v.nodes[node]
    if n.status == .Normal { n.last_normal = n.view }
    n.view += 1u64
    n.status = .ViewChange
    n.svc_mask = 1u64 << n.id
    n.dvc_sent = false
    n.dvc_mask = 0u64
    n.best_from = NONE
    var m: Message = zero
    m.from = n.id
    m.kind = .StartViewChange
    m.term = n.view
    ret vr_others(v, node, out, m)
}

fn vr_copy_log(v: *Vr, node: usize, from: u32, count: u64) {
    var i = 0usize
    while u64(i) < count {
        v.nodes[node].log[i] = v.nodes[usize(from)].log[i]
        i += 1usize
    }
}

fn vr_step(v: *Vr, node: usize, msg: *const Message, out: *Pool) -> err {
    let n = &v.nodes[node]
    if msg.kind == .VrPrepare {
        // ponytail: an out-of-order Prepare is dropped (no buffering, no state transfer)
        if msg.term != n.view || n.status != .Normal || msg.index != n.op + 1u64 { ret ok }
        if usize(n.op) >= n.log.len { ret TooSmall }
        n.log[usize(n.op)] = msg.value
        n.op = msg.index
        vr_execute(n, msg.commit)
        var r: Message = zero
        r.from = n.id
        r.to = msg.from
        r.kind = .VrPrepareOk
        r.term = n.view
        r.index = n.op
        ret pool_push(out, r)
    }
    if msg.kind == .VrPrepareOk {
        if msg.term != n.view || n.status != .Normal || msg.index > n.op || msg.index == 0u64 { ret ok }
        n.prepare_ok[usize(msg.index - 1u64)] |= 1u64 << msg.from
        let before = n.commit
        while n.commit < n.op && simple_majority(n.prepare_ok[usize(n.commit)], v.nodes.len) { vr_execute(n, n.commit + 1u64) }
        if n.commit == before { ret ok }
        var m: Message = zero
        m.from = n.id
        m.kind = .VrCommit
        m.term = n.view
        m.commit = n.commit
        ret vr_others(v, node, out, m)
    }
    if msg.kind == .VrCommit {
        if msg.term == n.view && n.status == .Normal { vr_execute(n, msg.commit) }
        ret ok
    }
    if msg.kind == .StartViewChange {
        if msg.term > n.view {
            if n.status == .Normal { n.last_normal = n.view }
            n.view = msg.term
            n.status = .ViewChange
            n.svc_mask = (1u64 << n.id) | (1u64 << msg.from)
            n.dvc_sent = false
            n.dvc_mask = 0u64
            n.best_from = NONE
            var m: Message = zero
            m.from = n.id
            m.kind = .StartViewChange
            m.term = n.view
            try vr_others(v, node, out, m)
        } else if msg.term == n.view && n.status == .ViewChange {
            n.svc_mask |= 1u64 << msg.from
        } else {
            ret ok
        }
        if n.dvc_sent || !simple_majority(n.svc_mask, v.nodes.len) { ret ok }
        n.dvc_sent = true
        var d: Message = zero
        d.from = n.id
        d.to = vr_primary(v, n.view)
        d.kind = .DoViewChange
        d.term = n.view
        d.term2 = n.last_normal
        d.index = n.op
        d.commit = n.commit
        ret pool_push(out, d)
    }
    if msg.kind == .DoViewChange {
        if msg.term != n.view || n.status != .ViewChange || vr_primary(v, n.view) != n.id { ret ok }
        n.dvc_mask |= 1u64 << msg.from
        if n.best_from == NONE || msg.term2 > n.best_view || (msg.term2 == n.best_view && msg.index > n.best_op) {
            n.best_from = msg.from
            n.best_view = msg.term2
            n.best_op = msg.index
        }
        if msg.commit > n.best_commit { n.best_commit = msg.commit }
        if !simple_majority(n.dvc_mask, v.nodes.len) { ret ok }
        // ponytail: the log rides in-process by copying from the chosen replica, not in the message
        if n.best_from != n.id { vr_copy_log(v, node, n.best_from, n.best_op) }
        n.op = n.best_op
        n.status = .Normal
        n.last_normal = n.view
        var i = n.commit
        while i < n.op {
            n.prepare_ok[usize(i)] = 1u64 << n.id
            i += 1u64
        }
        vr_execute(n, n.best_commit)
        var s: Message = zero
        s.from = n.id
        s.kind = .StartView
        s.term = n.view
        s.index = n.op
        s.commit = n.commit
        ret vr_others(v, node, out, s)
    }
    if msg.kind == .StartView {
        if msg.term < n.view || (msg.term == n.view && n.status == .Normal) { ret ok }
        n.view = msg.term
        n.status = .Normal
        n.last_normal = n.view
        vr_copy_log(v, node, msg.from, msg.index)
        n.op = msg.index
        vr_execute(n, msg.commit)
        var i = n.commit
        while i < n.op {
            var r: Message = zero
            r.from = n.id
            r.to = msg.from
            r.kind = .VrPrepareOk
            r.term = n.view
            r.index = i + 1u64
            try pool_push(out, r)
            i += 1u64
        }
        ret ok
    }
    ret Invalid
}
