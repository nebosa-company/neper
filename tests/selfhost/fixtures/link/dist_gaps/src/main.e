// The planned entry points of `e.dist.*`, `e.concurrent.reclaim` and
// `e.net.{balance,reliable}` that existed under family names: vector
// clocks over an LCG exchange against a Python brute force, phi accrual over
// the failure-detector window, Redlock in one call, the wait-for graph of a
// lock table, gossip dissemination after k rounds, Ricart-Agrawala and
// Raymond over the mutex fixture schedules, a scripted Chandy-Lamport
// snapshot against a Python replica, the hazard-pointer constructor, Maglev,
// the two ARQ senders, and a Raft election plus replication through a
// partition. Each check exits with its own code.

use e.algo.rand
use e.atomic
use e.concurrent.reclaim
use e.dist.clock
use e.dist.consensus
use e.dist.deadlock as dl
use e.dist.failure_detector as fd
use e.dist.gossip
use e.dist.lock
use e.dist.mutex
use e.dist.snapshot as snap
use e.io
use e.mem
use e.net.balance
use e.net.reliable as rel
use e.os

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= 0.000000001f64 * want
}

fn kind_code(k: mutex.Kind) -> u64 {
    if k == .Request { ret 0u64 }
    if k == .Reply { ret 1u64 }
    ret 2u64
}

fn fold_sent(s: *const mutex.Sent) -> u64 {
    var h = 0u64
    var i = 0usize
    while i < s.count {
        h = h *% 1000003u64 +% (kind_code(s.out[i].kind) * 4096u64 + u64(s.out[i].from) * 64u64 + u64(s.out[i].to))
        i += 1usize
    }
    ret h
}

fn order_code(o: clock.Order) -> u64 {
    if o == .Before { ret 0u64 }
    if o == .After { ret 1u64 }
    if o == .Equal { ret 2u64 }
    ret 3u64
}

fn op(kind: snap.OpKind, from: usize, to: usize, amount: u64) -> snap.Op { ret snap.Op { kind: kind, from: u32(from), to: u32(to), amount: amount } }

fn raft_all(c: *const consensus.Cluster, state: i64, commit: u64, log_len: usize) -> bool {
    var i = 0usize
    while i < c.nodes.len {
        if c.nodes[i].state != state || c.nodes[i].commit != commit || c.nodes[i].log_len != log_len { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: vector clocks: three nodes over 30 LCG events, then every pair compared.
    var store: [9]u64 = zero
    var i = 0usize
    while i < 9usize {
        store[i] = 7u64
        i += 1usize
    }
    let v0 = clock.vector(store[0usize..3usize], 3usize)
    let v1 = clock.vector(store[3usize..6usize], 3usize)
    let v2 = clock.vector(store[6usize..9usize], 5usize)
    if v0.len != 3usize || v1.len != 3usize || v2.len != 3usize || store[0usize] != 0u64 || store[8usize] != 0u64 { os.exit(1i32) }
    var state = 5u64
    i = 0usize
    while i < 30usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r = state >> 33u32
        let node = usize(r % 3u64)
        let mine = store[node * 3usize..node * 3usize + 3usize]
        let _ = clock.vector_tick(mine, node)
        if (r >> 4u32) % 2u64 == 1u64 {
            let to = (node + 1usize + usize((r >> 8u32) % 2u64)) % 3usize
            var carried: [3]u64 = zero
            var k = 0usize
            while k < 3usize {
                carried[k] = mine[k]
                k += 1usize
            }
            let _ = clock.vector_receive(store[to * 3usize..to * 3usize + 3usize], carried[..], to)
        }
        i += 1usize
    }
    let want_vec = [9]u64 { 18u64, 15u64, 10u64, 16u64, 16u64, 10u64, 13u64, 12u64, 14u64 }
    i = 0usize
    while i < 9usize {
        if store[i] != want_vec[i] { os.exit(1i32) }
        i += 1usize
    }
    var cmp_fold = 0u64
    var p = 0usize
    while p < 3usize {
        var q = 0usize
        while q < 3usize {
            cmp_fold = cmp_fold *% 1000003u64 +% order_code(clock.vector_cmp(store[p * 3usize..p * 3usize + 3usize], store[q * 3usize..q * 3usize + 3usize]))
            q += 1usize
        }
        p += 1usize
    }
    if cmp_fold != 1257907689958915424u64 { os.exit(1i32) }

    // 2: phi accrual over the failure-detector window (seed 42, 24 heartbeats).
    var ring: [16]u64 = zero
    var d = fd.phi_accrual(ring[..], 1.0f64)
    state = 42u64
    var now = 0u64
    i = 0usize
    while i < 24usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += 900u64 + (state >> 33u32) % 201u64
        fd.heartbeat(&d, now)
        i += 1usize
    }
    if now != 24708u64 || d.count != 16usize || fd.phi(&d, now) != 0.0f64 { os.exit(2i32) }
    if !near(fd.phi(&d, now + 1300u64), 5.223349639665527f64) || !near(fd.phi(&d, now + 1378u64), 8.006471954824498f64) { os.exit(2i32) }
    if fd.suspect(&d, now + 1377u64, 8.0f64) || !fd.suspect(&d, now + 1378u64, 8.0f64) { os.exit(2i32) }

    // 3: Redlock in one call over the five skewed instances of the lock fixture.
    var insts: [5]lock.Instance = zero
    insts[0usize] = lock.instance(0i64, 1u64)
    insts[1usize] = lock.instance(3i64, 2u64)
    insts[2usize] = lock.instance(0i64 - 2i64, 1u64)
    insts[3usize] = lock.instance(0i64, 3u64)
    insts[4usize] = lock.instance(5i64, 2u64)
    let (held1, v1a) = lock.redlock(insts[..], 11u64, 0u64, 20u64, 1u64)
    if !held1 || v1a != 10u64 || lock.redlock_held(insts[..], 11u64, 2u64) != 5usize { os.exit(3i32) }
    let (held2, v2a) = lock.redlock(insts[..], 22u64, 2u64, 20u64, 1u64)
    if held2 || v2a != 0u64 { os.exit(3i32) }
    let (held3, v3a) = lock.redlock(insts[..], 22u64, 30u64, 20u64, 1u64)
    if !held3 || v3a != 10u64 || lock.redlock_held(insts[..], 22u64, 31u64) != 5usize { os.exit(3i32) }

    // 4: the wait-for graph of a lock table: p0 -> p1 -> p2 -> p0 is a cycle
    // of three, p3 waits on a free lock and p4 runs.
    let none = 4294967295u32
    var holder = [4]u32 { 0u32, 1u32, 2u32, 4294967295u32 }
    var waiting = [5]u32 { 1u32, 2u32, 0u32, 3u32, 4294967295u32 }
    var edges: [8]dl.Edge = zero
    var scratch: [10]usize = zero
    let (n1, cyc1, len1, e1) = dl.wait_for_graph(holder[..], waiting[..], edges[..], scratch[..])
    if e1 != ok || n1 != 3usize || !cyc1 || len1 != 3usize { os.exit(4i32) }
    if edges[0usize].from != 0u32 || edges[0usize].to != 1u32 || edges[2usize].from != 2u32 || edges[2usize].to != 0u32 { os.exit(4i32) }
    waiting[2usize] = none
    let (n2, cyc2, _, e2) = dl.wait_for_graph(holder[..], waiting[..], edges[..], scratch[..])
    if e2 != ok || n2 != 2usize || cyc2 { os.exit(4i32) }
    waiting[2usize] = 9u32
    let (_, _, _, e3) = dl.wait_for_graph(holder[..], waiting[..], edges[..], scratch[..])
    if e3 != dl.Invalid { os.exit(4i32) }
    waiting[2usize] = 0u32
    let (_, _, _, e4) = dl.wait_for_graph(holder[..], waiting[..], edges[..2usize], scratch[..])
    if e4 != dl.TooSmall { os.exit(4i32) }
    let (_, _, _, e5) = dl.wait_for_graph(holder[..], waiting[..], edges[..], scratch[..9usize])
    if e5 != dl.Invalid { os.exit(4i32) }

    // 5: gossip after k rounds (the gossip fixture streams).
    var nodes100: [100]u8 = zero
    var r = rand.pcg64(7u64, 3u64)
    if gossip.disseminate(nodes100[..], 1usize, 0usize, &r, 3usize) != 15usize { os.exit(5i32) }
    r = rand.pcg64(7u64, 3u64)
    if gossip.disseminate(nodes100[..], 1usize, 0usize, &r, 7usize) != 100usize { os.exit(5i32) }
    r = rand.pcg64(1u64, 9u64)
    if gossip.disseminate(nodes100[..64usize], 2usize, 0usize, &r, 4usize) != 64usize { os.exit(5i32) }
    if gossip.disseminate(nodes100[..64usize], 2usize, 3usize, &r, 0usize) != 1usize || nodes100[3usize] != 1u8 || nodes100[0usize] != 0u8 { os.exit(5i32) }

    // 6: Ricart-Agrawala over the mutex fixture schedule.
    var pool: [64]mutex.Message = zero
    var s = mutex.sent(pool[..])
    var ra_nodes: [4]mutex.RaNode = zero
    var deferred: [16]bool = zero
    var order: [8]u32 = zero
    let ra_schedule = [6]u32 { 0u32, 2u32, 4294967295u32, 1u32, 3u32, 0u32 }
    let (ra_entered, e6) = mutex.ricart_agrawala(ra_nodes[..], deferred[..], ra_schedule[..], &s, order[..])
    if e6 != ok || ra_entered != 5usize || s.count != 30usize || fold_sent(&s) != 3074633797412637136u64 { os.exit(6i32) }
    let want_ra = [5]u32 { 0u32, 2u32, 0u32, 1u32, 3u32 }
    i = 0usize
    while i < 5usize {
        if order[i] != want_ra[i] { os.exit(6i32) }
        i += 1usize
    }
    var tiny: [2]bool = zero
    let (_, e7) = mutex.ricart_agrawala(ra_nodes[..], tiny[..], ra_schedule[..], &s, order[..])
    if e7 != mutex.TooSmall { os.exit(6i32) }
    s = mutex.sent(pool[..])
    let (_, e8) = mutex.ricart_agrawala(ra_nodes[..], deferred[..], ra_schedule[..], &s, order[..4usize])
    if e8 != mutex.TooSmall { os.exit(6i32) }
    let bad_schedule = [1]u32 { 4u32 }
    s = mutex.sent(pool[..])
    let (_, e9) = mutex.ricart_agrawala(ra_nodes[..], deferred[..], bad_schedule[..], &s, order[..])
    if e9 != mutex.Invalid { os.exit(6i32) }

    // 7: Raymond over the binary tree of the mutex fixture.
    var rs = mutex.sent(pool[..])
    var ray_nodes: [7]mutex.RayNode = zero
    var queue: [49]u32 = zero
    let parent = [7]u32 { 0u32, 0u32, 0u32, 1u32, 1u32, 2u32, 2u32 }
    let ray_schedule = [6]u32 { 5u32, 3u32, 0u32, 4294967295u32, 4u32, 6u32 }
    let (ray_entered, e10) = mutex.raymond_tree(ray_nodes[..], queue[..], parent[..], 0usize, ray_schedule[..], &rs, order[..])
    if e10 != ok || ray_entered != 5usize || rs.count != 24usize || fold_sent(&rs) != 8047156026161654552u64 { os.exit(7i32) }
    let want_ray = [5]u32 { 0u32, 5u32, 3u32, 4u32, 6u32 }
    i = 0usize
    while i < 5usize {
        if order[i] != want_ray[i] { os.exit(7i32) }
        i += 1usize
    }
    let holders = [7]u32 { 2u32, 0u32, 6u32, 1u32, 1u32, 2u32, 6u32 }
    i = 0usize
    while i < 7usize {
        if ray_nodes[i].holder != holders[i] || ray_nodes[i].count != 0usize { os.exit(7i32) }
        i += 1usize
    }
    let (_, e11) = mutex.raymond_tree(ray_nodes[..], queue[..40usize], parent[..], 0usize, ray_schedule[..], &rs, order[..])
    if e11 != mutex.TooSmall { os.exit(7i32) }

    // 8: a scripted Chandy-Lamport snapshot against the Python replica.
    var msgs: [32]snap.Message = zero
    var out = snap.sent(msgs[..])
    var procs: [4]snap.Proc = zero
    var channels: [16]snap.Channel = zero
    let initial = [4]u64 { 100u64, 100u64, 100u64, 100u64 }
    var script: [21]snap.Op = zero
    script[0usize] = op(.Send, 0usize, 1usize, 30u64)
    script[1usize] = op(.Send, 1usize, 2usize, 20u64)
    script[2usize] = op(.Initiate, 1usize, 0usize, 0u64)
    script[3usize] = op(.Deliver, 0usize, 0usize, 0u64)
    script[4usize] = op(.Send, 2usize, 3usize, 50u64)
    script[5usize] = op(.Send, 0usize, 3usize, 10u64)
    i = 6usize
    while i < 21usize {
        script[i] = op(.Deliver, 0usize, 0usize, 0u64)
        i += 1usize
    }
    let (total1, complete1, e12) = snap.chandy_lamport(procs[..], channels[..], initial[..], script[..12usize], &out)
    if e12 != ok || total1 != 400u64 || complete1 || out.count != 16usize { os.exit(8i32) }
    let want_snap = [4]u64 { 60u64, 80u64, 70u64, 100u64 }
    let want_markers = [4]usize { 1usize, 0usize, 1usize, 1usize }
    i = 0usize
    while i < 4usize {
        if procs[i].snapshot != want_snap[i] || procs[i].markers != want_markers[i] { os.exit(8i32) }
        i += 1usize
    }
    if procs[1usize].state != 110u64 || procs[3usize].state != 160u64 { os.exit(8i32) }
    if channels[1usize].total != 30u64 || channels[3usize].total != 10u64 || channels[11usize].total != 50u64 || channels[11usize].count != 1usize { os.exit(8i32) }
    out = snap.sent(msgs[..])
    let (total2, complete2, e13) = snap.chandy_lamport(procs[..], channels[..], initial[..], script[..], &out)
    let view = snap.Snapshot { procs: procs[..], channels: channels[..] }
    if e13 != ok || total2 != 400u64 || !complete2 || out.count != 16usize || snap.snapshot_live(&view) != 400u64 { os.exit(8i32) }
    i = 0usize
    while i < 4usize {
        if procs[i].snapshot != want_snap[i] || procs[i].markers != 3usize { os.exit(8i32) }
        i += 1usize
    }
    out = snap.sent(msgs[..])
    script[20usize] = op(.Initiate, 1usize, 0usize, 0u64)
    let (_, _, e14) = snap.chandy_lamport(procs[..], channels[..], initial[..], script[..], &out)
    if e14 != snap.Invalid { os.exit(8i32) }
    out = snap.sent(msgs[..])
    let (_, _, e15) = snap.chandy_lamport(procs[..], channels[..], initial[..], script[..1usize], &out)
    if e15 != ok { os.exit(8i32) }
    out = snap.sent(msgs[..])
    script[0usize] = op(.Deliver, 0usize, 0usize, 0u64)
    let (_, _, e16) = snap.chandy_lamport(procs[..], channels[..], initial[..], script[..1usize], &out)
    if e16 != snap.Invalid { os.exit(8i32) }

    // 9: the hazard-pointer constructor (threads 2, k 2: H 4, R 8).
    var slots: [4]Atomic[u32] = zero
    var hretired: [20]u32 = zero
    var hcounts: [2]usize = zero
    var hfreed: [16]u32 = zero
    let (_, e17) = reclaim.hazard(slots[..], hretired[..], hcounts[..], hfreed[..], 2usize, 0usize)
    if e17 != reclaim.Invalid { os.exit(9i32) }
    let (h0, e18) = reclaim.hazard(slots[..], hretired[..], hcounts[..], hfreed[..], 2usize, 2usize)
    if e18 != ok || h0.threshold != 8usize || h0.retire_cap != 10usize { os.exit(9i32) }
    var h = h0
    reclaim.protect(&h, 0usize, 0usize, 5u32)
    if reclaim.retire_hazard(&h, 0usize, 5u32) != ok || reclaim.retire_hazard(&h, 0usize, 6u32) != ok { os.exit(9i32) }
    if reclaim.scan(&h, 0usize) != 1usize || hfreed[0usize] != 6u32 || !reclaim.is_protected(&h, 5u32) { os.exit(9i32) }

    // 10: Maglev over M = 503 with five backends: every backend gets 100 or 101 slots.
    var names: [5]str = zero
    names[0usize] = "alpha"
    names[1usize] = "bravo"
    names[2usize] = "charlie"
    names[3usize] = "delta"
    names[4usize] = "echo"
    var table: [503]u32 = zero
    var mscratch: [15]u32 = zero
    if balance.maglev(names[..], table[..], mscratch[..], 503usize) != ok { os.exit(10i32) }
    var counts: [5]usize = zero
    i = 0usize
    while i < 503usize {
        if table[i] >= 5u32 { os.exit(10i32) }
        counts[usize(table[i])] += 1usize
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        if counts[i] < 100usize || counts[i] > 101usize { os.exit(10i32) }
        i += 1usize
    }
    if balance.maglev(names[..], table[..], mscratch[..], 500usize) != balance.Invalid { os.exit(10i32) }
    if balance.maglev(names[..], table[..100usize], mscratch[..], 503usize) != balance.TooSmall { os.exit(10i32) }

    // 11: the two ARQ senders.
    var sent_at: [4]u64 = zero
    var gbn = rel.sliding_window(4usize, 100u64, sent_at[..], 8u32)
    i = 0usize
    while i < 4usize {
        let (seq, e19) = rel.sender_send(&gbn, 10u64)
        if e19 != ok || seq != u64(i) { os.exit(11i32) }
        i += 1usize
    }
    let (_, e20) = rel.sender_send(&gbn, 11u64)
    if e20 != rel.Full || !rel.sender_ack(&gbn, 2u64) || rel.sender_in_flight(&gbn) != 2usize { os.exit(11i32) }
    var sr_sent: [8]u64 = zero
    var sr_acked: [8]u8 = zero
    let (_, e21) = rel.selective_repeat(3usize, 1u64, sr_sent[..], sr_acked[..], 2u32)
    if e21 != rel.Invalid { os.exit(11i32) }
    let (_, e22) = rel.selective_repeat(4usize, 1u64, sr_sent[..3usize], sr_acked[..], 8u32)
    if e22 != rel.TooSmall { os.exit(11i32) }
    let (sr0, e23) = rel.selective_repeat(4usize, 3u64, sr_sent[..], sr_acked[..], 8u32)
    if e23 != ok { os.exit(11i32) }
    var sr = sr0
    let (seq0, e24) = rel.sr_send(&sr, 1u64)
    let (seq1, e25) = rel.sr_send(&sr, 2u64)
    if e24 != ok || e25 != ok || seq0 != 0u64 || seq1 != 1u64 || sr.next_seq != 2u64 { os.exit(11i32) }
    if rel.sr_ack(&sr, 1u64) || !rel.sr_ack(&sr, 0u64) || sr.base != 2u64 { os.exit(11i32) }

    // 12: Raft: node 2 is elected, replicates, loses a majority, heals; node 0
    // fails an election in a minority and wins one with everybody up.
    var items: [256]consensus.Message = zero
    var net = consensus.pool(items[..])
    var logs: [160]consensus.Entry = zero
    var nexts: [25]u64 = zero
    var matches: [25]u64 = zero
    var nodes: [5]consensus.Node = zero
    i = 0usize
    while i < 5usize {
        nodes[i] = consensus.raft_node(u32(i), logs[i * 32usize..i * 32usize + 32usize], nexts[i * 5usize..i * 5usize + 5usize], matches[i * 5usize..i * 5usize + 5usize], 31u64)
        i += 1usize
    }
    var c = consensus.raft_cluster(nodes[..], 7u64, 150u64, 300u64, 50u64)
    let (role1, term1, e26) = consensus.raft_election(&c, 2usize, 1000u64, 31u64, &net)
    if e26 != ok || role1 != .Leader || term1 != 1u64 || c.nodes[2usize].commit != 1u64 || net.len != 0usize { os.exit(12i32) }
    let (commit1, e27) = consensus.raft_replicate(&c, 2usize, 1000u64, 5i64, 31u64, &net)
    let (commit2, e28) = consensus.raft_replicate(&c, 2usize, 1000u64, 7i64, 31u64, &net)
    if e27 != ok || e28 != ok || commit1 != 2u64 || commit2 != 3u64 || !raft_all(&c, 12i64, 3u64, 3usize) { os.exit(12i32) }
    let (commit3, e29) = consensus.raft_replicate(&c, 2usize, 1000u64, 9i64, 12u64, &net)
    if e29 != ok || commit3 != 3u64 || c.nodes[3usize].log_len != 4usize || c.nodes[0usize].log_len != 3usize || c.nodes[2usize].state != 12i64 { os.exit(12i32) }
    let (commit4, e30) = consensus.raft_replicate(&c, 2usize, 1000u64, 11i64, 31u64, &net)
    if e30 != ok || commit4 != 5u64 || !raft_all(&c, 32i64, 5u64, 5usize) { os.exit(12i32) }
    let (role2, term2, e31) = consensus.raft_election(&c, 0usize, 1000u64, 3u64, &net)
    if e31 != ok || role2 != .Candidate || term2 != 2u64 || c.nodes[2usize].role != .Leader || c.nodes[1usize].term != 2u64 { os.exit(12i32) }
    let (role3, term3, e32) = consensus.raft_election(&c, 0usize, 1000u64, 31u64, &net)
    // The followers hold the no-op of term 3 but learn its commit with the next heartbeat.
    if e32 != ok || role3 != .Leader || term3 != 3u64 || c.nodes[2usize].role != .Follower || c.nodes[0usize].commit != 6u64 { os.exit(12i32) }
    i = 0usize
    while i < 5usize {
        if c.nodes[i].log_len != 6usize || c.nodes[i].state != 32i64 || c.nodes[i].term != 3u64 || (i != 0usize && c.nodes[i].commit != 5u64) { os.exit(12i32) }
        i += 1usize
    }
    let (role4, term4, e33) = consensus.raft_election(&c, 0usize, 1000u64, 31u64, &net)
    if e33 != ok || role4 != .Leader || term4 != 3u64 { os.exit(12i32) }
    let (_, e34) = consensus.raft_replicate(&c, 2usize, 1000u64, 1i64, 31u64, &net)
    if e34 != consensus.NotLeader { os.exit(12i32) }
    let (commit5, e35) = consensus.raft_replicate(&c, 0usize, 1000u64, 1i64, 31u64, &net)
    if e35 != ok || commit5 != 7u64 || !raft_all(&c, 33i64, 7u64, 7usize) { os.exit(12i32) }
    let (_, _, e36) = consensus.raft_election(&c, 5usize, 1000u64, 31u64, &net)
    if e36 != consensus.Invalid { os.exit(12i32) }

    try io.print("dist gaps ok\n")
    ret ok
}
