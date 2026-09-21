// `e.dist.gossip`: push/pull rumour spreading over the same PCG64 stream
// informs exactly the nodes per round that a Python replica computes for
// three seeds, rounds-until-all stops at saturation and honours its limit,
// and the SWIM membership table applies the incarnation precedence rules on a
// table of cases, with suspect/confirm/refute/sweep moving members as the
// protocol says. Each check exits with its own code.

use e.algo.rand
use e.dist.gossip
use e.io
use e.mem
use e.os

fn spread(seed: u64, want: []const usize) -> bool {
    var state: [64]u8 = zero
    var r = rand.pcg64(seed, 9u64)
    var g = gossip.gossip(state[..], 1usize, 0usize)
    var i = 0usize
    while i < want.len {
        if gossip.gossip_round(&g, &r) != want[i] { ret false }
        i += 1usize
    }
    if g.informed != 64usize { ret false }
    if gossip.gossip_round(&g, &r) != 0usize { ret false }
    ret true
}

fn member(id: u32, incarnation: u32, status: gossip.Status, heartbeat: u64) -> gossip.Member {
    ret gossip.Member { id: id, incarnation: incarnation, status: status, heartbeat: heartbeat }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: newly informed per round for three seeds (64 nodes, fanout 1).
    let w1 = [7]usize { 1usize, 3usize, 6usize, 18usize, 25usize, 9usize, 1usize }
    let w2 = [6]usize { 3usize, 7usize, 15usize, 24usize, 12usize, 2usize }
    let w3 = [6]usize { 2usize, 4usize, 9usize, 24usize, 17usize, 7usize }
    if !spread(1u64, w1[..]) || !spread(2u64, w2[..]) || !spread(3u64, w3[..]) { os.exit(1i32) }

    // 2: rounds until all: 100 nodes, fanout 1, seed 7 stream 3 takes 7 rounds;
    // a limit stops early; fanout 2 over 64 nodes seed 1 stream 9 takes 4.
    var state: [100]u8 = zero
    var r = rand.pcg64(7u64, 3u64)
    var g = gossip.gossip(state[..], 1usize, 0usize)
    if gossip.gossip_rounds_until_all(&g, &r, 0usize) != 7usize || g.informed != 100usize { os.exit(2i32) }
    var i = 0usize
    while i < 100usize {
        if !gossip.informed(&g, i) { os.exit(2i32) }
        i += 1usize
    }
    r = rand.pcg64(7u64, 3u64)
    g = gossip.gossip(state[..], 1usize, 0usize)
    if gossip.gossip_rounds_until_all(&g, &r, 3usize) != 3usize || g.informed != 15usize { os.exit(2i32) }
    r = rand.pcg64(1u64, 9u64)
    g = gossip.gossip(state[..64usize], 2usize, 0usize)
    if gossip.gossip_rounds_until_all(&g, &r, 0usize) != 4usize { os.exit(2i32) }

    // 3: membership precedence over a table of cases.
    var slots: [8]gossip.Member = zero
    var t = gossip.membership(slots[..])
    var cases: [10]gossip.Member = zero
    cases[0usize] = member(1u32, 0u32, .Alive, 10u64)
    cases[1usize] = member(2u32, 0u32, .Alive, 10u64)
    cases[2usize] = member(3u32, 1u32, .Suspect, 10u64)
    cases[3usize] = member(1u32, 0u32, .Suspect, 11u64)
    cases[4usize] = member(1u32, 0u32, .Alive, 12u64)
    cases[5usize] = member(2u32, 1u32, .Alive, 12u64)
    cases[6usize] = member(2u32, 0u32, .Dead, 13u64)
    cases[7usize] = member(3u32, 1u32, .Dead, 14u64)
    cases[8usize] = member(3u32, 2u32, .Alive, 15u64)
    cases[9usize] = member(4u32, 0u32, .Dead, 15u64)
    let accepted = [10]bool { true, true, true, true, false, true, false, true, true, true }
    i = 0usize
    while i < 10usize {
        let (did, e) = gossip.membership_apply(&t, cases[i])
        if e != ok || did != accepted[i] { os.exit(3i32) }
        i += 1usize
    }
    if t.count != 4usize { os.exit(3i32) }
    if t.members[0usize].incarnation != 0u32 || t.members[0usize].status != .Suspect || t.members[0usize].heartbeat != 11u64 { os.exit(3i32) }
    if t.members[1usize].incarnation != 1u32 || t.members[1usize].status != .Alive || t.members[1usize].heartbeat != 12u64 { os.exit(3i32) }
    if t.members[2usize].incarnation != 2u32 || t.members[2usize].status != .Alive || t.members[2usize].heartbeat != 15u64 { os.exit(3i32) }
    if t.members[3usize].id != 4u32 || t.members[3usize].status != .Dead { os.exit(3i32) }

    // 4: merging a peer's table.
    var batch: [4]gossip.Member = zero
    batch[0usize] = member(1u32, 1u32, .Alive, 20u64)
    batch[1usize] = member(2u32, 1u32, .Dead, 20u64)
    batch[2usize] = member(3u32, 2u32, .Suspect, 20u64)
    batch[3usize] = member(5u32, 0u32, .Alive, 20u64)
    let (changed, merge_error) = gossip.membership_merge(&t, batch[..])
    if merge_error != ok || changed != 4usize || t.count != 5usize { os.exit(4i32) }
    if t.members[0usize].incarnation != 1u32 || t.members[0usize].status != .Alive { os.exit(4i32) }
    if t.members[1usize].status != .Dead || t.members[2usize].status != .Suspect || t.members[3usize].heartbeat != 15u64 || t.members[4usize].id != 5u32 { os.exit(4i32) }
    let (again, _) = gossip.membership_merge(&t, batch[..])
    if again != 0usize { os.exit(4i32) }
    var tiny = gossip.membership(slots[..2usize])
    let (_, full) = gossip.membership_merge(&tiny, batch[..])
    if full != gossip.TooSmall || tiny.count != 2usize { os.exit(4i32) }

    // 5: suspect, confirm, refute, sweep.
    if !gossip.membership_suspect(&t, 1u32, 30u64) || gossip.membership_suspect(&t, 1u32, 31u64) || gossip.membership_suspect(&t, 9u32, 31u64) { os.exit(5i32) }
    if t.members[0usize].status != .Suspect || t.members[0usize].heartbeat != 30u64 { os.exit(5i32) }
    if gossip.membership_refute(&t, 1u32, 32u64) != 2u32 || t.members[0usize].status != .Alive { os.exit(5i32) }
    if gossip.membership_refute(&t, 2u32, 32u64) != 0u32 || gossip.membership_refute(&t, 9u32, 32u64) != 0u32 { os.exit(5i32) }
    if gossip.membership_confirm(&t, 1u32, 33u64) || !gossip.membership_confirm(&t, 3u32, 33u64) || t.members[2usize].status != .Dead { os.exit(5i32) }
    // Alive members: 1 (heartbeat 32) and 5 (heartbeat 20); at 40 with timeout 10 only 5 is stale.
    if gossip.membership_sweep(&t, 40u64, 10u64) != 1usize || t.members[4usize].status != .Suspect || t.members[0usize].status != .Alive { os.exit(5i32) }
    if gossip.membership_sweep(&t, 40u64, 10u64) != 0usize { os.exit(5i32) }

    try io.print("dist gossip ok\n")
    ret ok
}
