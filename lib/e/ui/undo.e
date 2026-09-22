// Undo/redo command stack over caller storage. A `Command` is a record the
// caller interprets (the module never sees the document): `undo` and `redo`
// hand back the command to invert or replay. Entries below `cursor` are
// undoable, entries from `cursor` to `len` are the redo tail; a push drops
// the tail, and a full stack forgets its oldest entry. `begin_group` /
// `end_group` stamp the pushes between them with one group id so
// `undo_group` / `redo_group` move them as a unit; `merge_last` lets the
// caller coalesce a new command into the latest entry (consecutive typing).
// `mark_saved` / `is_dirty` track whether the cursor sits at the saved point.

type Command = struct { kind: u32, a: i64, b: i64, group: u32 }
type Stack = struct { items: []Command, len: usize, cursor: usize, group_open: bool, group_id: u32, saved: usize, saved_valid: bool }
error Invalid
error TooSmall

// A clean, empty stack over `items`.
fn stack(items: []Command) -> Stack {
    ret Stack { items: items, len: 0usize, cursor: 0usize, group_open: false, group_id: 0u32, saved: 0usize, saved_valid: true }
}

fn stamp(s: *const Stack) -> u32 {
    if s.group_open { ret s.group_id }
    ret 0u32
}

// Record `c` after the cursor, dropping the redo tail; a full stack forgets
// its oldest entry. `TooSmall` only for zero storage.
fn push(s: *Stack, c: Command) -> err {
    if s.items.len == 0usize { ret TooSmall }
    if s.saved_valid && s.saved > s.cursor { s.saved_valid = false }
    s.len = s.cursor
    if s.len == s.items.len {
        // ponytail: O(n) shift when full; a ring buffer if capacity grows past a few thousand.
        var i = 1usize
        while i < s.len {
            s.items[i - 1usize] = s.items[i]
            i += 1usize
        }
        s.len -= 1usize
        s.cursor -= 1usize
        if s.saved_valid {
            if s.saved == 0usize { s.saved_valid = false } else { s.saved -= 1usize }
        }
    }
    var entry = c
    entry.group = stamp(s)
    s.items[s.len] = entry
    s.len += 1usize
    s.cursor = s.len
    ret ok
}

fn can_undo(s: *const Stack) -> bool { ret s.cursor > 0usize }
fn can_redo(s: *const Stack) -> bool { ret s.cursor < s.len }
fn len(s: *const Stack) -> usize { ret s.len }
fn undo_depth(s: *const Stack) -> usize { ret s.cursor }
fn redo_depth(s: *const Stack) -> usize { ret s.len - s.cursor }

// The latest undoable command, to invert; false when there is none.
fn undo(s: *Stack) -> (Command, bool) {
    if s.cursor == 0usize { ret (zero, false) }
    s.cursor -= 1usize
    ret (s.items[s.cursor], true)
}

// The next redoable command, to replay; false when there is none.
fn redo(s: *Stack) -> (Command, bool) {
    if s.cursor == s.len { ret (zero, false) }
    let c = s.items[s.cursor]
    s.cursor += 1usize
    ret (c, true)
}

// The latest undoable entry without moving the cursor.
fn last(s: *const Stack) -> (Command, bool) {
    if s.cursor == 0usize { ret (zero, false) }
    ret (s.items[s.cursor - 1usize], true)
}

// Start a transaction: every push until `end_group` shares one group id.
fn begin_group(s: *Stack) -> err {
    if s.group_open { ret Invalid }
    s.group_open = true
    s.group_id += 1u32
    ret ok
}

// Close the transaction; a group with no pushes leaves no entry.
fn end_group(s: *Stack) -> err {
    if !s.group_open { ret Invalid }
    s.group_open = false
    ret ok
}

// Undo the latest group (or one ungrouped entry) into `out`, latest first.
fn undo_group(s: *Stack, out: []Command) -> (usize, err) {
    if s.cursor == 0usize { ret (0usize, ok) }
    let g = s.items[s.cursor - 1usize].group
    var n = 1usize
    if g != 0u32 {
        while n < s.cursor && s.items[s.cursor - 1usize - n].group == g { n += 1usize }
    }
    if n > out.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        s.cursor -= 1usize
        out[i] = s.items[s.cursor]
        i += 1usize
    }
    ret (n, ok)
}

// Redo the next group (or one ungrouped entry) into `out`, in replay order.
fn redo_group(s: *Stack, out: []Command) -> (usize, err) {
    if s.cursor == s.len { ret (0usize, ok) }
    let g = s.items[s.cursor].group
    var n = 1usize
    if g != 0u32 {
        while s.cursor + n < s.len && s.items[s.cursor + n].group == g { n += 1usize }
    }
    if n > out.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        out[i] = s.items[s.cursor]
        s.cursor += 1usize
        i += 1usize
    }
    ret (n, ok)
}

// Coalesce `c` into the latest entry when there is no redo tail, the entry
// carries the current group stamp and `merge(prev, &c)` rewrites `prev` and
// answers true; otherwise push `c`. Answers whether it merged.
fn merge_last(s: *Stack, c: Command, merge: fn(*Command, *const Command) -> bool) -> (bool, err) {
    if s.cursor > 0usize && s.cursor == s.len && s.items[s.cursor - 1usize].group == stamp(s) {
        if merge(&s.items[s.cursor - 1usize], &c) {
            if s.saved_valid && s.saved == s.cursor { s.saved_valid = false }
            ret (true, ok)
        }
    }
    let e = push(s, c)
    ret (false, e)
}

// Forget every entry; the empty stack is clean.
fn clear(s: *Stack) {
    s.len = 0usize
    s.cursor = 0usize
    s.group_open = false
    s.saved = 0usize
    s.saved_valid = true
}

// The document at the cursor is what is on disk.
fn mark_saved(s: *Stack) {
    s.saved = s.cursor
    s.saved_valid = true
}

// Clean only when the cursor sits at the saved point and that point still exists.
fn is_dirty(s: *const Stack) -> bool {
    ret !s.saved_valid || s.saved != s.cursor
}
