// `e.algo.batch`: settled prepare slots are reclaimed, a partial commit keeps both
// histories inside their depth budget, undo/redo refuse to move an entry when the
// writes cannot be allocated, and a resumed chunk is sized by the ledger plus the
// chunk rather than the whole id list. Each check has its own exit code.
use e.algo.batch as b
use e.algo.formula as f
use e.mem
use e.os

fn ok_apply(state: *void, id: f.Value) -> b.Outcome {
    ret b.success()
}

fn text_change(a: *mem.Arena, field: str) -> []const b.Change {
    var none: []const b.Change = zero
    let (ch, e) = mem.alloc[b.Change](a, 1usize)
    if e != ok { ret none }
    ch[0] = b.Change { record_id: f.text("r1"), field: field, before: f.text("a"), after: f.text("b") }
    ret ch[0usize..1usize]
}

fn ack_of(a: *mem.Arena, field: str) -> []const b.Ack {
    var none: []const b.Ack = zero
    let (acks, e) = mem.alloc[b.Ack](a, 1usize)
    if e != ok { ret none }
    acks[0] = b.Ack { record_id: f.text("r1"), field: field }
    ret acks[0usize..1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: more prepare/commit pairs than max_pending are still served.
    var store = b.new_undo_store(a, 4usize, 4usize, 2usize)
    var round = 0usize
    while round < 10usize {
        let pushed = b.undo_push(&store, "ed", "tbl", text_change(a, "f"), "edit", true)
        if pushed == 0usize { os.exit(1i32) }
        let step = b.prepare(&store, "ed", "tbl", false)
        if !step.valid || !step.has_token { os.exit(1i32) }
        let moved = b.commit(&store, step.token, ack_of(a, "f"))
        if moved != 1usize { os.exit(1i32) }
        round += 1usize
    }

    // 2: partial commits cannot push either history past depth cells.
    var store2 = b.new_undo_store(a, 3usize, 4usize, 64usize)
    let names: [3]str = [3]str{ "f0", "f1", "f2" }
    var round2 = 0usize
    while round2 < 3usize {
        let (ch, ce) = mem.alloc[b.Change](a, 4usize)
        if ce != ok { os.exit(2i32) }
        ch[0usize] = b.Change { record_id: f.text("r1"), field: "f0", before: f.text("a"), after: f.text("b") }
        ch[1usize] = b.Change { record_id: f.text("r1"), field: "f1", before: f.text("a"), after: f.text("b") }
        ch[2usize] = b.Change { record_id: f.text("r1"), field: "f2", before: f.text("a"), after: f.text("b") }
        ch[3usize] = b.Change { record_id: f.text("r1"), field: "f3", before: f.text("a"), after: f.text("b") }
        let pushed = b.undo_push(&store2, "ed", "tbl", ch[0usize..4usize], "range", true)
        if pushed != round2 + 1usize { os.exit(2i32) }
        round2 += 1usize
    }
    var partial = 0usize
    while partial < 3usize {
        let step = b.prepare(&store2, "ed", "tbl", false)
        if !step.valid { os.exit(2i32) }
        let moved = b.commit(&store2, step.token, ack_of(a, names[partial]))
        if moved != 1usize { os.exit(2i32) }
        partial += 1usize
    }
    var back = 0usize
    while back < 3usize {
        let step = b.undo(&store2, "ed", "tbl")
        if !step.valid || step.writes.len == 0usize { os.exit(2i32) }
        back += 1usize
    }
    var forward = 0usize
    while forward < 3usize {
        let step = b.redo(&store2, "ed", "tbl")
        if !step.valid || step.writes.len == 0usize { os.exit(2i32) }
        forward += 1usize
    }

    // 3: a full arena makes undo answer invalid and leaves the entry in place.
    let (pool, pool_error) = mem.alloc[u8](a, 16384usize)
    if pool_error != ok { os.exit(3i32) }
    var limited = mem.arena_from(pool)
    var store3 = b.new_undo_store(&limited, 4usize, 4usize, 8usize)
    let one = text_change(a, "f")
    if one.len != 1usize { os.exit(3i32) }
    let pushed3 = b.undo_push(&store3, "ed", "tbl", one, "edit", true)
    if pushed3 != 1usize { os.exit(3i32) }
    let saved = limited.off
    limited.off = limited.cap - 64usize
    let refused = b.undo(&store3, "ed", "tbl")
    if refused.valid { os.exit(3i32) }
    let state = b.undo_state(&store3, "ed", "tbl")
    if !state.can_undo || state.undo_depth != 1usize { os.exit(3i32) }
    limited.off = limited.cap - 64usize
    let refused_prepare = b.prepare(&store3, "ed", "tbl", false)
    if refused_prepare.valid { os.exit(4i32) }
    limited.off = saved
    let ready = b.prepare(&store3, "ed", "tbl", false)
    if !ready.valid || !ready.has_token { os.exit(4i32) }

    // 4: a resumed chunk allocates the ledger plus the chunk, not the whole id list.
    let (ids, ids_error) = mem.alloc[f.Value](a, 1000usize)
    if ids_error != ok { os.exit(5i32) }
    var i = 0usize
    while i < 1000usize {
        ids[i] = f.text("id")
        i += 1usize
    }
    var no_values: []const f.Value = zero
    var no_failed: []const b.Failed = zero
    let empty = b.Ledger { succeeded: no_values, failed: no_failed }
    let state_ptr = mem.cast[*void](a)
    let first = b.run_batch(a, ids[0usize..1000usize], ok_apply, state_ptr, 5usize, 0usize, empty)
    if first.succeeded != 5usize || first.done { os.exit(5i32) }
    let before = a.off
    let second = b.run_batch(a, ids[0usize..1000usize], ok_apply, state_ptr, 5usize, 5usize, first.ledger)
    let grew = a.off - before
    if second.succeeded != 10usize { os.exit(5i32) }
    if grew > 16384usize { os.exit(5i32) }

    // 5: a resume index past the end is clamped, not wrapped.
    let (three, three_error) = mem.alloc[f.Value](a, 3usize)
    if three_error != ok { os.exit(6i32) }
    var k = 0usize
    while k < 3usize {
        three[k] = f.text("id")
        k += 1usize
    }
    let clamped = b.run_batch(a, three[0usize..3usize], ok_apply, state_ptr, 500usize, 18446744073709551615usize, empty)
    if !clamped.done || clamped.processed != 0usize { os.exit(6i32) }
    ret ok
}
