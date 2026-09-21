// `e.dist.consensus`: five simulated Raft nodes elect a leader, replicate
// through a partition and heal to equal logs, install a snapshot on a
// lagging follower, and change membership by joint consensus; two Paxos
// proposers duel to one decided value; a Multi-Paxos leader fills six
// slots; VR replicates, survives a primary crash by a view change and
// carries on. Every schedule (delivery order, drops) is an LCG the Python
// replica repeats; the fixture also asserts no two leaders in one term and
// that committed entries never change. Each check exits with its own code.

use e.dist.consensus
use e.io
use e.mem
use e.os

type Sim = struct { lcg: u64, now: u64, leader_seen: [64]bool, leader_of: [64]u32, committed_seen: [64]bool, committed_term: [64]u64, committed_value: [64]i64 }

fn draw(s: *Sim) -> u64 {
    s.lcg = s.lcg *% 6364136223846793005u64 +% 1442695040888963407u64
    ret s.lcg >> 33u32
}

fn in_cut(cut: u64, m: *const consensus.Message) -> bool {
    ret ((cut >> m.from) & 1u64) == 1u64 || ((cut >> m.to) & 1u64) == 1u64
}

fn deliver_raft(s: *Sim, c: *consensus.Cluster, net: *consensus.Pool, cut: u64, drop: u64) -> err {
    while net.len > 0usize {
        let j = usize(draw(s) % u64(net.len))
        var m = consensus.pool_take(net, j)
        let r = draw(s) % 10u64
        if r < drop || in_cut(cut, &m) { continue }
        try consensus.raft_step(c, usize(m.to), s.now, &m, net)
    }
    ret ok
}

fn deliver_paxos(s: *Sim, p: *consensus.Paxos, net: *consensus.Pool, drop: u64) -> err {
    while net.len > 0usize {
        let j = usize(draw(s) % u64(net.len))
        var m = consensus.pool_take(net, j)
        let r = draw(s) % 10u64
        if r < drop { continue }
        try consensus.paxos_step(p, usize(m.to), &m, net)
    }
    ret ok
}

fn deliver_mp(s: *Sim, p: *consensus.MultiPaxos, net: *consensus.Pool) -> err {
    while net.len > 0usize {
        let j = usize(draw(s) % u64(net.len))
        var m = consensus.pool_take(net, j)
        // The drop draw is taken but never drops, keeping the schedule aligned.
        let _ = draw(s)
        try consensus.multi_paxos_step(p, usize(m.to), &m, net)
    }
    ret ok
}

fn deliver_vr(v: *consensus.Vr, net: *consensus.Pool, cut: u64) -> err {
    while net.len > 0usize {
        var m = consensus.pool_pop(net)
        if in_cut(cut, &m) { continue }
        try consensus.vr_step(v, usize(m.to), &m, net)
    }
    ret ok
}

fn check_safety(s: *Sim, c: *consensus.Cluster) -> err {
    var i = 0usize
    while i < c.nodes.len {
        let n = &c.nodes[i]
        if n.role == .Leader {
            let t = usize(n.term)
            if s.leader_seen[t] && s.leader_of[t] != n.id { ret consensus.Invalid }
            s.leader_seen[t] = true
            s.leader_of[t] = n.id
        }
        var k = n.snap_index + 1u64
        while k <= n.commit {
            let e = n.log[usize(k - n.snap_index - 1u64)]
            if s.committed_seen[usize(k)] && (s.committed_term[usize(k)] != e.term || s.committed_value[usize(k)] != e.value) { ret consensus.Invalid }
            s.committed_seen[usize(k)] = true
            s.committed_term[usize(k)] = e.term
            s.committed_value[usize(k)] = e.value
            k += 1u64
        }
        i += 1usize
    }
    ret ok
}

fn run_ticks(s: *Sim, c: *consensus.Cluster, net: *consensus.Pool, ticks: usize, cut: u64) -> err {
    var none: consensus.Message = zero
    var t = 0usize
    while t < ticks {
        s.now += 10u64
        var i = 0usize
        while i < c.nodes.len {
            try consensus.raft_step(c, i, s.now, &none, net)
            i += 1usize
        }
        try deliver_raft(s, c, net, cut, 2u64)
        try check_safety(s, c)
        t += 1usize
    }
    ret ok
}

// The leader of the highest term, or 99.
fn leader_of(c: *const consensus.Cluster) -> usize {
    var best = 99usize
    var i = 0usize
    while i < c.nodes.len {
        if c.nodes[i].role == .Leader && (best == 99usize || c.nodes[i].term > c.nodes[best].term) { best = i }
        i += 1usize
    }
    ret best
}

fn all_equal(c: *const consensus.Cluster, state: i64, commit: u64, log_len: usize) -> bool {
    var i = 0usize
    while i < c.nodes.len {
        let n = &c.nodes[i]
        if n.state != state || n.commit != commit || n.log_len != log_len { ret false }
        var k = 0usize
        while k < log_len {
            if n.log[k].term != c.nodes[0usize].log[k].term || n.log[k].value != c.nodes[0usize].log[k].value { ret false }
            k += 1usize
        }
        i += 1usize
    }
    ret true
}

fn build(nodes: []consensus.Node, logs: []consensus.Entry, nexts: []u64, matches: []u64, config: u64) {
    var i = 0usize
    while i < 5usize {
        nodes[i] = consensus.raft_node(u32(i), logs[i * 64usize..i * 64usize + 64usize], nexts[i * 5usize..i * 5usize + 5usize], matches[i * 5usize..i * 5usize + 5usize], config)
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var items: [512]consensus.Message = zero
    var net = consensus.pool(items[..])
    var logs: [320]consensus.Entry = zero
    var nexts: [25]u64 = zero
    var matches: [25]u64 = zero
    var nodes: [5]consensus.Node = zero
    build(nodes[..], logs[..], nexts[..], matches[..], 31u64)
    var c = consensus.raft_cluster(nodes[..], 7u64, 150u64, 300u64, 50u64)
    var s: Sim = zero
    s.lcg = 11u64

    // 1: an election.
    if run_ticks(&s, &c, &net, 60usize, 0u64) != ok { os.exit(1i32) }
    var leader = leader_of(&c)
    if leader != 2usize || c.nodes[leader].term != 1u64 { os.exit(1i32) }
    let (_, not_leader) = consensus.raft_propose(&c, 0usize, 1i64)
    if not_leader != consensus.NotLeader { os.exit(1i32) }

    // 2: replication through a partition of {3, 4}, then healed.
    var v = 1i64
    while v <= 8i64 {
        let (_, propose_error) = consensus.raft_propose(&c, leader, v * 3i64)
        if propose_error != ok { os.exit(2i32) }
        v += 1i64
    }
    if run_ticks(&s, &c, &net, 20usize, 24u64) != ok { os.exit(2i32) }
    if c.nodes[leader].commit != 9u64 { os.exit(2i32) }
    if run_ticks(&s, &c, &net, 80usize, 0u64) != ok { os.exit(2i32) }
    leader = leader_of(&c)
    if leader != 0usize || c.nodes[leader].term != 4u64 { os.exit(2i32) }
    if !all_equal(&c, 108i64, 11u64, 11usize) { os.exit(2i32) }

    // 3: a snapshot at the leader, installed on the lagging node 4.
    v = 1i64
    while v <= 4i64 {
        let (_, propose_error) = consensus.raft_propose(&c, leader, v * 7i64)
        if propose_error != ok { os.exit(3i32) }
        v += 1i64
    }
    if run_ticks(&s, &c, &net, 20usize, 16u64) != ok { os.exit(3i32) }
    var i = 0usize
    while i < 4usize {
        if consensus.raft_snapshot(&c, i) != ok { os.exit(3i32) }
        i += 1usize
    }
    if c.nodes[leader].snap_index != 15u64 || c.nodes[leader].log_len != 0usize { os.exit(3i32) }
    if run_ticks(&s, &c, &net, 60usize, 0u64) != ok { os.exit(3i32) }
    i = 0usize
    while i < 5usize {
        if c.nodes[i].state != 178i64 { os.exit(3i32) }
        i += 1usize
    }
    if c.nodes[4usize].snap_index != 15u64 || c.nodes[4usize].log_len != 1usize { os.exit(3i32) }
    leader = leader_of(&c)
    if leader != 0usize || c.nodes[leader].term != 6u64 { os.exit(3i32) }

    // 4: membership change {0,1,2} -> {0..4} by joint consensus.
    build(nodes[..], logs[..], nexts[..], matches[..], 7u64)
    c = consensus.raft_cluster(nodes[..], 19u64, 150u64, 300u64, 50u64)
    var s2: Sim = zero
    s2.lcg = 23u64
    if run_ticks(&s2, &c, &net, 60usize, 0u64) != ok { os.exit(4i32) }
    leader = leader_of(&c)
    if leader != 1usize || c.nodes[leader].term != 1u64 { os.exit(4i32) }
    if consensus.membership_change(&c, 0usize, 31u64) != consensus.NotLeader { os.exit(4i32) }
    if consensus.membership_change(&c, leader, 31u64) != ok { os.exit(4i32) }
    if consensus.membership_change(&c, leader, 31u64) != consensus.Invalid { os.exit(4i32) }
    if run_ticks(&s2, &c, &net, 40usize, 0u64) != ok { os.exit(4i32) }
    i = 0usize
    while i < 5usize {
        if c.nodes[i].cfg_old != 31u64 || c.nodes[i].cfg_new != 31u64 { os.exit(4i32) }
        i += 1usize
    }
    leader = leader_of(&c)
    let (_, propose_error) = consensus.raft_propose(&c, leader, 1000i64)
    if propose_error != ok { os.exit(4i32) }
    if run_ticks(&s2, &c, &net, 40usize, 0u64) != ok { os.exit(4i32) }
    if !all_equal(&c, 1000i64, 4u64, 4usize) { os.exit(4i32) }
    if leader != 1usize || c.nodes[leader].term != 1u64 { os.exit(4i32) }

    // 5: single-decree Paxos under duelling proposers with 30% drops.
    var acceptors: [5]consensus.Acceptor = zero
    var proposers: [5]consensus.Proposer = zero
    var p = consensus.paxos(acceptors[..], proposers[..])
    var s3: Sim = zero
    s3.lcg = 5u64
    var rounds = 0usize
    var decided = 0usize
    while rounds < 20usize && decided < 5usize {
        rounds += 1usize
        if consensus.paxos_propose(&p, 0usize, 100i64, &net) != ok { os.exit(5i32) }
        if consensus.paxos_propose(&p, 1usize, 200i64, &net) != ok { os.exit(5i32) }
        if deliver_paxos(&s3, &p, &net, 3u64) != ok { os.exit(5i32) }
        decided = 0usize
        i = 0usize
        while i < 5usize {
            if p.proposers[i].decided { decided += 1usize }
            i += 1usize
        }
    }
    if rounds != 7usize || decided != 5usize { os.exit(5i32) }
    i = 0usize
    while i < 5usize {
        if p.proposers[i].decided_value != 200i64 { os.exit(5i32) }
        i += 1usize
    }

    // 6: Multi-Paxos: one Prepare, six Accepts.
    var slot_n: [80]u64 = zero
    var slot_value: [80]i64 = zero
    var proposed: [80]i64 = zero
    var accept_mask: [80]u64 = zero
    var decided_slots: [80]bool = zero
    var mp_nodes: [5]consensus.MpNode = zero
    i = 0usize
    while i < 5usize {
        let lo = i * 16usize
        mp_nodes[i] = consensus.mp_node(slot_n[lo..lo + 16usize], slot_value[lo..lo + 16usize], proposed[lo..lo + 16usize], accept_mask[lo..lo + 16usize], decided_slots[lo..lo + 16usize])
        i += 1usize
    }
    var mp = consensus.multi_paxos(mp_nodes[..])
    var s4: Sim = zero
    s4.lcg = 9u64
    let (_, early) = consensus.multi_paxos_propose(&mp, 0usize, 1i64, &net)
    if early != consensus.NotLeader { os.exit(6i32) }
    if consensus.multi_paxos_lead(&mp, 0usize, &net) != ok { os.exit(6i32) }
    if deliver_mp(&s4, &mp, &net) != ok { os.exit(6i32) }
    if !mp.nodes[0usize].leading || mp.nodes[0usize].ballot != 5u64 { os.exit(6i32) }
    v = 0i64
    while v < 6i64 {
        let (slot, slot_error) = consensus.multi_paxos_propose(&mp, 0usize, 11i64 * (v + 1i64), &net)
        if slot_error != ok || slot != u64(v) { os.exit(6i32) }
        v += 1i64
    }
    if deliver_mp(&s4, &mp, &net) != ok { os.exit(6i32) }
    var agree = 0usize
    i = 0usize
    while i < 5usize {
        var k = 0usize
        while k < 6usize {
            if i == 0usize && !mp.nodes[0usize].decided[k] { os.exit(6i32) }
            if mp.nodes[i].slot_n[k] == 5u64 && mp.nodes[i].slot_value[k] == 11i64 * i64(k + 1usize) { agree += 1usize }
            k += 1usize
        }
        i += 1usize
    }
    if agree != 30usize { os.exit(6i32) }
    if consensus.multi_paxos_lead(&mp, 1usize, &net) != ok { os.exit(6i32) }
    if deliver_mp(&s4, &mp, &net) != ok { os.exit(6i32) }
    if !mp.nodes[1usize].leading || mp.nodes[1usize].next_slot != 6u64 || mp.nodes[1usize].ballot != 6u64 { os.exit(6i32) }

    // 7: VR: three requests, the primary dies mid-request, a view change, one more.
    var vr_logs: [80]i64 = zero
    var vr_oks: [80]u64 = zero
    var vr_nodes: [5]consensus.VrNode = zero
    i = 0usize
    while i < 5usize {
        vr_nodes[i] = consensus.vr_node(u32(i), vr_logs[i * 16usize..i * 16usize + 16usize], vr_oks[i * 16usize..i * 16usize + 16usize])
        i += 1usize
    }
    var vr = consensus.viewstamped(vr_nodes[..])
    if consensus.vr_request(&vr, 1usize, 5i64, &net) != consensus.NotLeader { os.exit(7i32) }
    v = 5i64
    while v <= 7i64 {
        if consensus.vr_request(&vr, 0usize, v, &net) != ok { os.exit(7i32) }
        v += 1i64
    }
    if deliver_vr(&vr, &net, 0u64) != ok { os.exit(7i32) }
    i = 0usize
    while i < 5usize {
        if vr.nodes[i].commit != 3u64 || vr.nodes[i].state != 18i64 { os.exit(7i32) }
        i += 1usize
    }
    if consensus.vr_request(&vr, 0usize, 8i64, &net) != ok { os.exit(7i32) }
    var first = consensus.pool_pop(&net)
    if first.to != 1u32 { os.exit(7i32) }
    if consensus.vr_step(&vr, 1usize, &first, &net) != ok { os.exit(7i32) }
    net.len = 0usize
    i = 1usize
    while i < 5usize {
        if consensus.vr_primary_dead(&vr, i, &net) != ok { os.exit(7i32) }
        i += 1usize
    }
    if deliver_vr(&vr, &net, 1u64) != ok { os.exit(7i32) }
    if consensus.vr_primary(&vr, 1u64) != 1u32 { os.exit(7i32) }
    i = 1usize
    while i < 5usize {
        if vr.nodes[i].view != 1u64 || vr.nodes[i].status != .Normal { os.exit(7i32) }
        i += 1usize
    }
    if vr.nodes[1usize].op != 4u64 || vr.nodes[1usize].commit != 4u64 { os.exit(7i32) }
    if consensus.vr_request(&vr, 1usize, 9i64, &net) != ok { os.exit(7i32) }
    if deliver_vr(&vr, &net, 1u64) != ok { os.exit(7i32) }
    i = 1usize
    while i < 5usize {
        if vr.nodes[i].commit != 5u64 || vr.nodes[i].state != 35i64 { os.exit(7i32) }
        i += 1usize
    }
    if vr.nodes[0usize].state != 18i64 { os.exit(7i32) }

    try io.print("dist consensus ok\n")
    ret ok
}
