// `e.ui.undo`: linear push/undo/redo, a push after undo drops the redo tail,
// a full stack forgets its oldest entry, groups undo as one, merge_last
// coalesces adjacent inserts, the dirty flag follows the save point, and a
// 200-step LCG script over an integer-array document matches the Python
// replica's hash and depths. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.ui.undo

type Doc = struct { cells: [128]i64, n: usize }

fn insert_at(d: *Doc, pos: usize, v: i64) {
    var j = d.n
    while j > pos {
        d.cells[j] = d.cells[j - 1usize]
        j -= 1usize
    }
    d.cells[pos] = v
    d.n += 1usize
}

fn delete_at(d: *Doc, pos: usize) {
    var j = pos
    while j + 1usize < d.n {
        d.cells[j] = d.cells[j + 1usize]
        j += 1usize
    }
    d.n -= 1usize
}

// kind 1 insert(a=pos, b=value); 2 delete(a=pos, b=old); 3 replace(a=pos, b=old*65536+new); 4 run of zeros(a=pos, b=count).
fn apply(d: *Doc, c: undo.Command, invert: bool) {
    let pos = usize(c.a)
    if c.kind == 1u32 {
        if invert { delete_at(d, pos) } else { insert_at(d, pos, c.b) }
    } else if c.kind == 2u32 {
        if invert { insert_at(d, pos, c.b) } else { delete_at(d, pos) }
    } else if c.kind == 3u32 {
        if invert { d.cells[pos] = c.b / 65536i64 } else { d.cells[pos] = c.b % 65536i64 }
    } else if c.kind == 4u32 {
        var k = 0usize
        while k < usize(c.b) {
            if invert { delete_at(d, pos) } else { insert_at(d, pos, 0i64) }
            k += 1usize
        }
    }
}

fn merge_inserts(prev: *undo.Command, c: *const undo.Command) -> bool {
    if c.kind != 1u32 { ret false }
    if prev.kind == 1u32 && c.a == prev.a + 1i64 {
        prev.kind = 4u32
        prev.b = 2i64
        ret true
    }
    if prev.kind == 4u32 && c.a == prev.a + prev.b {
        prev.b += 1i64
        ret true
    }
    ret false
}

fn cmd(kind: u32, a: i64, b: i64) -> undo.Command { ret undo.Command { kind: kind, a: a, b: b, group: 0u32 } }

fn next_lcg(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var items: [8]undo.Command = zero
    var s = undo.stack(items[..])

    // 1: linear order.
    try undo.push(&s, cmd(1u32, 10i64, 0i64))
    try undo.push(&s, cmd(1u32, 11i64, 0i64))
    try undo.push(&s, cmd(1u32, 12i64, 0i64))
    if undo.len(&s) != 3usize || undo.undo_depth(&s) != 3usize || undo.redo_depth(&s) != 0usize || undo.can_redo(&s) { os.exit(1i32) }
    let (u1, ok1) = undo.undo(&s)
    if !ok1 || u1.a != 12i64 { os.exit(1i32) }
    let (u2, ok2) = undo.undo(&s)
    if !ok2 || u2.a != 11i64 || undo.redo_depth(&s) != 2usize { os.exit(1i32) }
    let (ra, rok1) = undo.redo(&s)
    if !rok1 || ra.a != 11i64 { os.exit(1i32) }
    let (rb, rok2) = undo.redo(&s)
    if !rok2 || rb.a != 12i64 || undo.can_redo(&s) { os.exit(1i32) }
    let (_, rok3) = undo.redo(&s)
    if rok3 { os.exit(1i32) }

    // 2: a push after undo drops the redo tail.
    let (_, _) = undo.undo(&s)
    let (_, _) = undo.undo(&s)
    try undo.push(&s, cmd(1u32, 20i64, 0i64))
    if undo.len(&s) != 2usize || undo.can_redo(&s) { os.exit(2i32) }
    let (u3, _) = undo.undo(&s)
    if u3.a != 20i64 { os.exit(2i32) }
    let (u4, _) = undo.undo(&s)
    if u4.a != 10i64 || undo.can_undo(&s) { os.exit(2i32) }

    // 3: capacity 8 with 12 pushes keeps the last 8.
    undo.clear(&s)
    var i = 0usize
    while i < 12usize {
        try undo.push(&s, cmd(1u32, i64(i), 0i64))
        i += 1usize
    }
    if undo.len(&s) != 8usize || undo.undo_depth(&s) != 8usize { os.exit(3i32) }
    var expect = 11i64
    var popped = 0usize
    var more = true
    while more {
        let (c, got) = undo.undo(&s)
        more = got
        if got {
            if c.a != expect { os.exit(3i32) }
            expect -= 1i64
            popped += 1usize
        }
    }
    if popped != 8usize || expect != 3i64 { os.exit(3i32) }
    var empty = undo.stack(items[..0usize])
    if undo.push(&empty, cmd(1u32, 0i64, 0i64)) != undo.TooSmall { os.exit(3i32) }

    // 4: groups.
    undo.clear(&s)
    try undo.push(&s, cmd(1u32, 1i64, 0i64))
    try undo.begin_group(&s)
    if undo.begin_group(&s) != undo.Invalid { os.exit(4i32) }
    try undo.push(&s, cmd(1u32, 2i64, 0i64))
    try undo.push(&s, cmd(1u32, 3i64, 0i64))
    try undo.push(&s, cmd(1u32, 4i64, 0i64))
    try undo.end_group(&s)
    if undo.end_group(&s) != undo.Invalid { os.exit(4i32) }
    try undo.begin_group(&s)
    try undo.end_group(&s)
    if undo.len(&s) != 4usize { os.exit(4i32) }
    var out: [8]undo.Command = zero
    let (g1, ge1) = undo.undo_group(&s, out[..])
    if ge1 != ok || g1 != 3usize || out[0usize].a != 4i64 || out[2usize].a != 2i64 || undo.undo_depth(&s) != 1usize { os.exit(4i32) }
    let (g2, ge2) = undo.redo_group(&s, out[..])
    if ge2 != ok || g2 != 3usize || out[0usize].a != 2i64 || out[2usize].a != 4i64 || undo.undo_depth(&s) != 4usize { os.exit(4i32) }
    let (_, ge3) = undo.undo_group(&s, out[..2usize])
    if ge3 != undo.TooSmall || undo.undo_depth(&s) != 4usize { os.exit(4i32) }
    let (_, _) = undo.undo_group(&s, out[..])
    let (g4, _) = undo.undo_group(&s, out[..])
    if g4 != 1usize || out[0usize].a != 1i64 || undo.can_undo(&s) { os.exit(4i32) }

    // 5: merge_last coalesces adjacent inserts.
    undo.clear(&s)
    var d: Doc = zero
    let c5a = cmd(1u32, 0i64, 7i64)
    apply(&d, c5a, false)
    try undo.push(&s, c5a)
    let c5b = cmd(1u32, 1i64, 8i64)
    apply(&d, c5b, false)
    let (m1, me1) = undo.merge_last(&s, c5b, merge_inserts)
    if me1 != ok || !m1 || undo.len(&s) != 1usize { os.exit(5i32) }
    let c5c = cmd(1u32, 2i64, 9i64)
    apply(&d, c5c, false)
    let (m2, _) = undo.merge_last(&s, c5c, merge_inserts)
    if !m2 || undo.len(&s) != 1usize { os.exit(5i32) }
    let c5d = cmd(1u32, 0i64, 1i64)
    apply(&d, c5d, false)
    let (m3, _) = undo.merge_last(&s, c5d, merge_inserts)
    if m3 || undo.len(&s) != 2usize || d.n != 4usize { os.exit(5i32) }
    let (u5, _) = undo.undo(&s)
    apply(&d, u5, true)
    let (u6, _) = undo.undo(&s)
    if u6.kind != 4u32 || u6.b != 3i64 { os.exit(5i32) }
    apply(&d, u6, true)
    if d.n != 0usize { os.exit(5i32) }

    // 6: dirty flag across save/undo/redo.
    undo.clear(&s)
    if undo.is_dirty(&s) { os.exit(6i32) }
    try undo.push(&s, cmd(1u32, 0i64, 0i64))
    if !undo.is_dirty(&s) { os.exit(6i32) }
    try undo.push(&s, cmd(1u32, 1i64, 0i64))
    undo.mark_saved(&s)
    if undo.is_dirty(&s) { os.exit(6i32) }
    let (_, _) = undo.undo(&s)
    if !undo.is_dirty(&s) { os.exit(6i32) }
    let (_, _) = undo.redo(&s)
    if undo.is_dirty(&s) { os.exit(6i32) }
    let (_, _) = undo.undo(&s)
    try undo.push(&s, cmd(1u32, 2i64, 0i64))
    if !undo.is_dirty(&s) { os.exit(6i32) }
    let (_, _) = undo.undo(&s)
    if !undo.is_dirty(&s) { os.exit(6i32) }
    undo.mark_saved(&s)
    if undo.is_dirty(&s) { os.exit(6i32) }
    let (_, _) = undo.redo(&s)
    if !undo.is_dirty(&s) { os.exit(6i32) }

    // 7: the scripted run against the replica.
    var big: [32]undo.Command = zero
    var t = undo.stack(big[..])
    var doc: Doc = zero
    var state = 2125u64
    var step = 0usize
    while step < 200usize {
        let op = next_lcg(&state) % 10u64
        let r2 = next_lcg(&state)
        let r3 = next_lcg(&state)
        let n = doc.n
        if op <= 2u64 {
            if n < 100usize {
                let c = cmd(1u32, i64(r2 % u64(n + 1usize)), i64(r3 % 1000u64))
                apply(&doc, c, false)
                try undo.push(&t, c)
            }
        } else if op == 3u64 {
            if n > 0usize {
                let pos = usize(r2 % u64(n))
                let c = cmd(2u32, i64(pos), doc.cells[pos])
                apply(&doc, c, false)
                try undo.push(&t, c)
            }
        } else if op == 4u64 {
            if n > 0usize {
                let pos = usize(r2 % u64(n))
                let c = cmd(3u32, i64(pos), doc.cells[pos] * 65536i64 + i64(r3 % 1000u64))
                apply(&doc, c, false)
                try undo.push(&t, c)
            }
        } else if op == 5u64 || op == 6u64 {
            if (r2 & 1u64) == 1u64 {
                let (count, e) = undo.undo_group(&t, out[..])
                if e != ok { os.exit(7i32) }
                var k = 0usize
                while k < count {
                    apply(&doc, out[k], true)
                    k += 1usize
                }
            } else {
                let (c, got) = undo.undo(&t)
                if got { apply(&doc, c, true) }
            }
        } else if op == 7u64 {
            if (r2 & 1u64) == 1u64 {
                let (count, e) = undo.redo_group(&t, out[..])
                if e != ok { os.exit(7i32) }
                var k = 0usize
                while k < count {
                    apply(&doc, out[k], false)
                    k += 1usize
                }
            } else {
                let (c, got) = undo.redo(&t)
                if got { apply(&doc, c, false) }
            }
        } else if op == 8u64 {
            if n < 100usize {
                try undo.begin_group(&t)
                let c1 = cmd(1u32, i64(r2 % u64(n + 1usize)), i64(r3 % 1000u64))
                apply(&doc, c1, false)
                try undo.push(&t, c1)
                let c2 = cmd(1u32, i64(r3 % u64(n + 2usize)), i64(r2 % 1000u64))
                apply(&doc, c2, false)
                try undo.push(&t, c2)
                try undo.end_group(&t)
            }
        } else {
            var merged = false
            let (prev, has_prev) = undo.last(&t)
            if has_prev && n < 100usize && (prev.kind == 1u32 || prev.kind == 4u32) {
                var pos = prev.a + 1i64
                if prev.kind == 4u32 { pos = prev.a + prev.b }
                if usize(pos) <= n {
                    let c = cmd(1u32, pos, i64(r2 % 1000u64))
                    apply(&doc, c, false)
                    let (_, e) = undo.merge_last(&t, c, merge_inserts)
                    if e != ok { os.exit(7i32) }
                    merged = true
                }
            }
            if !merged { undo.mark_saved(&t) }
        }
        step += 1usize
    }
    var h = 1469598103934665603u64
    i = 0usize
    while i < doc.n {
        h = (h *% 1099511628211u64) ^ u64(doc.cells[i])
        i += 1usize
    }
    if h != 14857964988730633811u64 || doc.n != 60usize { os.exit(7i32) }
    if undo.len(&t) != 32usize || undo.undo_depth(&t) != 32usize || undo.redo_depth(&t) != 0usize || !undo.is_dirty(&t) { os.exit(7i32) }

    try io.print("ui undo ok\n")
    ret ok
}
