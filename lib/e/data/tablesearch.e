// Search and value lists over an `e.data.table` (docs/grid.md 5.4, steps 5 and 6).
//
// `find` is the incremental search of the grid (`Locate` / `LocateNext` / previous): over a
// display order (the rows of a view, or of a grouping) it answers the first position, from a
// start and in a direction, whose cell begins with or contains the text, optionally
// wrapping round. A dictionary column evaluates the match once per distinct entry, so a
// row costs one array read and a search costs O(entries + distance); a heap string column
// tests each row. Text is ASCII upper-case folded unless `fold` is false.
//
// `value_list` is the distinct-value list of a column's filter popup: the dictionary
// entries in use among the given rows with their row counts, in fold order, plus the count
// of null cells, without a scan of strings per row.

use e.mem
use e.algo.sort
use e.data.table as table
use e.data.tableview as view

type Mode = enum u8 { Begins, Within }

// One distinct value of a column: its dictionary id and how many of the rows have it.
type Value = struct { id: u32, count: u32 }

error BadColumn
error TooSmall

fn row_matches(t: *const table.Table, column: usize, kind: table.Kind, accepted: []const bool, text: str, mode: Mode, fold: bool, row: usize) -> bool {
    if table.is_null(t, column, row) { ret false }
    if kind == table.Kind.Dict { ret accepted[usize(table.dict_id(t, column, row))] }
    ret view.contains_text(table.get_str(t, column, row), text, !fold, mode == Mode.Begins, false)
}

// The first position of `rows`, examined from `start` (inclusive) forward or backward and
// wrapping round when `wrap`, whose cell in `column` begins with or contains `text`. The
// empty text matches every non-null cell.
fn find(v: *const view.View, rows: []const u32, column: usize, text: str, mode: Mode, fold: bool, start: usize, forward: bool, wrap: bool, scratch: *mem.Arena) -> (usize, bool, err) {
    let t = v.t
    if column >= table.column_count(t) { ret (0usize, false, BadColumn) }
    let kind = table.column_kind(t, column)
    if kind != table.Kind.Str && kind != table.Kind.Dict { ret (0usize, false, BadColumn) }
    if rows.len == 0usize { ret (0usize, false, ok) }
    let marker = mem.mark(scratch)
    var accepted: []bool = zero
    if kind == table.Kind.Dict {
        let n = table.dict_len(t, column)
        if n != 0usize {
            let (flags, flags_error) = mem.alloc[bool](scratch, n)
            if flags_error != ok { ret (0usize, false, flags_error) }
            var id = 0usize
            while id < n {
                flags[id] = view.contains_text(table.dict_str(t, column, u32(id)), text, !fold, mode == Mode.Begins, false)
                id += 1usize
            }
            accepted = flags
        }
    }
    var at = start
    if at >= rows.len {
        if !wrap {
            mem.reset(scratch, marker)
            ret (0usize, false, ok)
        }
        if forward { at = 0usize } else { at = rows.len - 1usize }
    }
    var examined = 0usize
    var limit = rows.len
    if !wrap {
        if forward { limit = rows.len - at } else { limit = at + 1usize }
    }
    while examined < limit {
        if row_matches(t, column, kind, accepted, text, mode, fold, usize(rows[at])) {
            mem.reset(scratch, marker)
            ret (at, true, ok)
        }
        examined += 1usize
        if forward {
            at += 1usize
            if at == rows.len { at = 0usize }
        } else {
            if at == 0usize { at = rows.len - 1usize } else { at -= 1usize }
        }
    }
    mem.reset(scratch, marker)
    ret (0usize, false, ok)
}

type RankCtx = struct { ranks: []const u32 }

fn by_rank(c: *RankCtx, x: u32, y: u32) -> i32 {
    let rx = c.ranks[usize(x)]
    let ry = c.ranks[usize(y)]
    if rx < ry { ret -1i32 }
    if rx > ry { ret 1i32 }
    ret 0i32
}

// The distinct values of a dictionary column among `rows`, in fold order: `out` receives up
// to `out.len` values (`TooSmall` when there are more) and the answer is how many, then the
// number of null cells. With `merge_fold` the entries that differ only in ASCII case are
// one value (its id is the first by dictionary order; its count is the sum).
fn value_list(v: *view.View, column: usize, rows: []const u32, merge_fold: bool, out: []Value, scratch: *mem.Arena) -> (usize, usize, err) {
    let t = v.t
    if column >= table.column_count(t) || table.column_kind(t, column) != table.Kind.Dict { ret (0usize, 0usize, BadColumn) }
    let marker = mem.mark(scratch)
    let n = table.dict_len(t, column)
    var nulls = 0usize
    if n == 0usize {
        var at = 0usize
        while at < rows.len {
            nulls += 1usize
            at += 1usize
        }
        mem.reset(scratch, marker)
        ret (0usize, nulls, ok)
    }
    let (counts, counts_error) = mem.alloc[u32](scratch, n)
    if counts_error != ok { ret (0usize, 0usize, counts_error) }
    var id = 0usize
    while id < n {
        counts[id] = 0u32
        id += 1usize
    }
    var at = 0usize
    while at < rows.len {
        let row = usize(rows[at])
        if table.is_null(t, column, row) {
            nulls += 1usize
        } else {
            counts[usize(table.dict_id(t, column, row))] += 1u32
        }
        at += 1usize
    }
    let (used, used_error) = mem.alloc[u32](scratch, n)
    if used_error != ok {
        mem.reset(scratch, marker)
        ret (0usize, 0usize, used_error)
    }
    var used_count = 0usize
    id = 0usize
    while id < n {
        if counts[id] != 0u32 {
            used[used_count] = u32(id)
            used_count += 1usize
        }
        id += 1usize
    }
    let (rank_slice, rank_error) = table.ranks(v.t, column, scratch)
    if rank_error != ok {
        mem.reset(scratch, marker)
        ret (0usize, 0usize, rank_error)
    }
    var ctx = RankCtx { ranks: rank_slice }
    let sort_error = sort.stable_in_place_by[u32, RankCtx](scratch, used[0usize..used_count], &ctx, by_rank)
    if sort_error != ok {
        mem.reset(scratch, marker)
        ret (0usize, 0usize, sort_error)
    }
    var written = 0usize
    at = 0usize
    while at < used_count {
        let entry = used[at]
        if merge_fold && written > 0usize && rank_slice[usize(out[written - 1usize].id)] == rank_slice[usize(entry)] {
            out[written - 1usize].count += counts[usize(entry)]
        } else {
            if written >= out.len {
                mem.reset(scratch, marker)
                ret (written, nulls, TooSmall)
            }
            out[written] = Value { id: entry, count: counts[usize(entry)] }
            written += 1usize
        }
        at += 1usize
    }
    mem.reset(scratch, marker)
    ret (written, nulls, ok)
}
