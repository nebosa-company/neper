// `e.dist.commit`: 2PC and 3PC over three participants commit, abort on a
// no vote, and differ when the coordinator dies (2PC participants block in
// Prepared, 3PC participants abort before PreCommit and commit after it);
// sagas complete or compensate in reverse by choreography and by
// orchestration; TCC confirms live reservations and cancels expired ones.
// A hash of every state after every tick (and of every saga message) is
// compared with the Python replica. Each check exits with its own code.

use e.dist.commit
use e.io
use e.mem
use e.os

type Sim = struct { now: u64, h: u64 }

fn coord_code(s: commit.CoordState) -> u64 {
    if s == .Init { ret 0u64 }
    if s == .Waiting { ret 1u64 }
    if s == .PreCommitting { ret 2u64 }
    if s == .Committed { ret 3u64 }
    ret 4u64
}

fn part_code(s: commit.PartState) -> u64 {
    if s == .Init { ret 0u64 }
    if s == .Prepared { ret 1u64 }
    if s == .PreCommitted { ret 2u64 }
    if s == .Committed { ret 3u64 }
    ret 4u64
}

fn kind_code(k: commit.Kind) -> u64 {
    if k == .Execute { ret 8u64 }
    if k == .StepDone { ret 9u64 }
    if k == .StepFailed { ret 10u64 }
    if k == .Compensate { ret 11u64 }
    ret 12u64
}

fn clear(xs: []u8) {
    var i = 0usize
    while i < xs.len {
        xs[i] = 0u8
        i += 1usize
    }
}

fn fold(s: *Sim, code: u64) { s.h = s.h *% 31u64 +% code }

fn snapshot(s: *Sim, t: *const commit.Commit) {
    fold(s, coord_code(t.state))
    var i = 0usize
    while i < t.parts.len {
        fold(s, part_code(t.parts[i].state))
        i += 1usize
    }
}

fn deliver(s: *Sim, t: *commit.Commit, net: *commit.Pool, cut: u64, count: usize) -> err {
    var n = 0usize
    while net.len > 0usize && n < count {
        var m = commit.pool_pop(net)
        n += 1usize
        if ((cut >> m.from) & 1u64) == 1u64 || ((cut >> m.to) & 1u64) == 1u64 { continue }
        try commit.commit_step(t, usize(m.to), s.now, &m, net)
    }
    ret ok
}

fn ticks(s: *Sim, t: *commit.Commit, net: *commit.Pool, count: usize, cut: u64) -> err {
    var none: commit.Message = zero
    var k = 0usize
    while k < count {
        s.now += 10u64
        var i = 0usize
        while i <= t.parts.len {
            if ((cut >> u32(i)) & 1u64) == 0u64 { try commit.commit_step(t, i, s.now, &none, net) }
            i += 1usize
        }
        try deliver(s, t, net, cut, 1000usize)
        snapshot(s, t)
        k += 1usize
    }
    ret ok
}

fn all_parts(t: *const commit.Commit, state: commit.PartState) -> bool {
    var i = 0usize
    while i < t.parts.len {
        if t.parts[i].state != state { ret false }
        i += 1usize
    }
    ret true
}

fn fresh(parts: []commit.Participant, no_vote: usize, three: bool, timeout: u64) -> commit.Commit {
    var i = 0usize
    while i < parts.len {
        parts[i] = commit.Participant { state: .Init, vote_yes: i != no_vote, deadline: 0u64 }
        i += 1usize
    }
    if three { ret commit.three_phase(parts, timeout) }
    ret commit.two_phase(parts, timeout)
}

fn run_saga(s: *commit.Saga, net: *commit.Pool) -> (u64, err) {
    var h = 0u64
    while net.len > 0usize {
        var m = commit.pool_pop(net)
        h = h *% 31u64 +% kind_code(m.kind)
        h = h *% 31u64 +% u64(m.to & 255u32)
        let step_error = commit.saga_step(s, usize(m.to), &m, net)
        if step_error != ok { ret (h, step_error) }
    }
    ret (h, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var items: [64]commit.Message = zero
    var net = commit.pool(items[..])
    var parts: [3]commit.Participant = zero

    // 1: 2PC commits, aborts on a no vote, and blocks under a dead coordinator.
    var s: Sim = zero
    var t = fresh(parts[..], 9usize, false, 100u64)
    if commit.commit_begin(&t, s.now, &net) != ok || commit.commit_begin(&t, s.now, &net) != commit.Invalid { os.exit(1i32) }
    if ticks(&s, &t, &net, 5usize, 0u64) != ok { os.exit(1i32) }
    if t.state != .Committed || !all_parts(&t, .Committed) || s.h != 77004613841013696u64 { os.exit(1i32) }
    s.now = 0u64
    s.h = 0u64
    t = fresh(parts[..], 1usize, false, 100u64)
    if commit.commit_begin(&t, s.now, &net) != ok { os.exit(1i32) }
    if ticks(&s, &t, &net, 5usize, 0u64) != ok { os.exit(1i32) }
    if t.state != .Aborted || !all_parts(&t, .Aborted) || s.h != 102672818454684928u64 { os.exit(1i32) }
    s.now = 0u64
    s.h = 0u64
    t = fresh(parts[..], 9usize, false, 100u64)
    if commit.commit_begin(&t, s.now, &net) != ok { os.exit(1i32) }
    if deliver(&s, &t, &net, 0u64, 3usize) != ok { os.exit(1i32) }
    if ticks(&s, &t, &net, 12usize, 8u64) != ok { os.exit(1i32) }
    if !all_parts(&t, .Prepared) || s.h != 4105145458233533184u64 { os.exit(1i32) }
    var i = 0usize
    while i < 3usize {
        if !commit.commit_blocked(&t, i, s.now) { os.exit(1i32) }
        i += 1usize
    }

    // 2: 3PC commits, aborts on a no vote, and recovers from a dead coordinator.
    s.now = 0u64
    s.h = 0u64
    t = fresh(parts[..], 9usize, true, 100u64)
    if commit.commit_begin(&t, s.now, &net) != ok { os.exit(2i32) }
    if ticks(&s, &t, &net, 5usize, 0u64) != ok { os.exit(2i32) }
    if t.state != .Committed || !all_parts(&t, .Committed) || s.h != 77004613841013696u64 { os.exit(2i32) }
    s.now = 0u64
    s.h = 0u64
    t = fresh(parts[..], 1usize, true, 100u64)
    if commit.commit_begin(&t, s.now, &net) != ok { os.exit(2i32) }
    if ticks(&s, &t, &net, 5usize, 0u64) != ok { os.exit(2i32) }
    if t.state != .Aborted || !all_parts(&t, .Aborted) || s.h != 102672818454684928u64 { os.exit(2i32) }
    // dead after Prepare: participants abort on their own
    s.now = 0u64
    s.h = 0u64
    t = fresh(parts[..], 9usize, true, 100u64)
    if commit.commit_begin(&t, s.now, &net) != ok { os.exit(2i32) }
    if deliver(&s, &t, &net, 0u64, 3usize) != ok { os.exit(2i32) }
    if ticks(&s, &t, &net, 12usize, 8u64) != ok { os.exit(2i32) }
    if !all_parts(&t, .Aborted) || s.h != 4107686223385241961u64 || commit.commit_blocked(&t, 0usize, s.now) { os.exit(2i32) }
    // dead after PreCommit: participants commit on their own
    s.now = 0u64
    s.h = 0u64
    t = fresh(parts[..], 9usize, true, 100u64)
    if commit.commit_begin(&t, s.now, &net) != ok { os.exit(2i32) }
    if deliver(&s, &t, &net, 0u64, 6usize) != ok || t.state != .PreCommitting { os.exit(2i32) }
    if deliver(&s, &t, &net, 0u64, 3usize) != ok || !all_parts(&t, .PreCommitted) { os.exit(2i32) }
    if ticks(&s, &t, &net, 12usize, 8u64) != ok { os.exit(2i32) }
    if !all_parts(&t, .Committed) || s.h != 8211137838184302627u64 { os.exit(2i32) }

    // 3: saga choreography: success, failure at step 2, failure at step 0.
    var done: [4]u8 = zero
    var saga = commit.saga_choreography(done[..], 4294967295u32)
    if commit.saga_start(&saga, &net) != ok { os.exit(3i32) }
    let (h_ok, ok_error) = run_saga(&saga, &net)
    if ok_error != ok || saga.state != .Completed || h_ok != 220359769091u64 { os.exit(3i32) }
    if done[0usize] != 1u8 || done[1usize] != 1u8 || done[2usize] != 1u8 || done[3usize] != 1u8 { os.exit(3i32) }
    clear(done[..])
    saga = commit.saga_choreography(done[..], 2u32)
    if commit.saga_start(&saga, &net) != ok { os.exit(3i32) }
    let (h_fail, fail_error) = run_saga(&saga, &net)
    if fail_error != ok || saga.state != .Aborted || h_fail != 211765738124692u64 { os.exit(3i32) }
    if done[0usize] != 2u8 || done[1usize] != 2u8 || done[2usize] != 3u8 || done[3usize] != 0u8 { os.exit(3i32) }
    clear(done[..])
    saga = commit.saga_choreography(done[..], 0u32)
    if commit.saga_start(&saga, &net) != ok { os.exit(3i32) }
    let (h_first, first_error) = run_saga(&saga, &net)
    if first_error != ok || saga.state != .Aborted || h_first != 248u64 || done[0usize] != 3u8 || done[1usize] != 0u8 { os.exit(3i32) }

    // 4: saga orchestration: the same three runs through a coordinator.
    clear(done[..])
    saga = commit.saga_orchestrate(done[..], 4294967295u32)
    if commit.saga_start(&saga, &net) != ok { os.exit(4i32) }
    let (o_ok, o_ok_error) = run_saga(&saga, &net)
    if o_ok_error != ok || saga.state != .Completed || o_ok != 9780208650494491602u64 { os.exit(4i32) }
    if done[0usize] != 1u8 || done[3usize] != 1u8 { os.exit(4i32) }
    clear(done[..])
    saga = commit.saga_orchestrate(done[..], 2u32)
    if commit.saga_start(&saga, &net) != ok { os.exit(4i32) }
    let (o_fail, o_fail_error) = run_saga(&saga, &net)
    if o_fail_error != ok || saga.state != .Aborted || o_fail != 1198376846415826806u64 { os.exit(4i32) }
    if done[0usize] != 2u8 || done[1usize] != 2u8 || done[2usize] != 3u8 || done[3usize] != 0u8 { os.exit(4i32) }
    clear(done[..])
    saga = commit.saga_orchestrate(done[..], 0u32)
    if commit.saga_start(&saga, &net) != ok { os.exit(4i32) }
    let (o_first, o_first_error) = run_saga(&saga, &net)
    if o_first_error != ok || saga.state != .Aborted || o_first != 238642u64 || done[0usize] != 3u8 { os.exit(4i32) }

    // 5: TCC: confirm within the ttl; expire and a late confirm cancels.
    var reservations: [3]commit.Reservation = zero
    var tcc = commit.tcc(reservations[..], 100u64)
    if commit.tcc_try(&tcc, 0usize, 0u64) != ok || commit.tcc_try(&tcc, 1usize, 10u64) != ok || commit.tcc_try(&tcc, 2usize, 20u64) != ok { os.exit(5i32) }
    if commit.tcc_try(&tcc, 0usize, 30u64) != commit.Invalid { os.exit(5i32) }
    if commit.tcc_confirm(&tcc, 50u64) != ok || tcc.state != .Completed { os.exit(5i32) }
    i = 0usize
    while i < 3usize {
        if reservations[i].state != .Confirmed { os.exit(5i32) }
        i += 1usize
    }
    if commit.tcc_confirm(&tcc, 60u64) != commit.Invalid { os.exit(5i32) }
    reservations[0usize].state = .Free
    reservations[1usize].state = .Free
    reservations[2usize].state = .Free
    tcc = commit.tcc(reservations[..], 100u64)
    if commit.tcc_try(&tcc, 0usize, 0u64) != ok || commit.tcc_try(&tcc, 1usize, 10u64) != ok { os.exit(5i32) }
    if commit.tcc_expire(&tcc, 100u64) != 1usize { os.exit(5i32) }
    if commit.tcc_confirm(&tcc, 100u64) != commit.Expired || tcc.state != .Aborted { os.exit(5i32) }
    if reservations[0usize].state != .Cancelled || reservations[1usize].state != .Cancelled || reservations[2usize].state != .Free { os.exit(5i32) }

    try io.print("dist commit ok\n")
    ret ok
}
