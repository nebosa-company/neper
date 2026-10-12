// A columnar record store: typed contiguous columns, a null bitmap per column,
// dictionary-encoded or heap strings, tombstoned rows, bulk load, and a per-column change
// version that a view reads to learn which of its stages a change reaches.
//
// Capacity is fixed and caller-funded (rows, string heap bytes and dictionary entries are
// declared at `create`): every column is one allocation, so 150,000 rows of 24 columns is
// 24 allocations and no per-cell object. A cell is read and written through typed
// accessors; there is no boxed value in the hot API.
//
// Strings. `Str` is an offset/length pair into a byte heap: appending is a copy, replacing
// a cell appends the new bytes and the old ones stay behind as `heap_wasted`. `Dict` stores
// each distinct string once and keeps one `u32` id per row; ids are never reused or freed.
// `ranks` gives every dictionary entry its dense position in ASCII upper-case-folded byte
// order (`CompareStr(UpperCase(a), UpperCase(b))` of the Delphi grid): two entries have the
// same rank exactly when they are equal ignoring ASCII case, so a case-insensitive
// equality or a sort over a column never touches a string per row.
//
// ponytail: single writer; row compaction and a boxed `Value` accessor are not here.

use e.mem
use e.algo.sort

type Kind = enum u8 { I32, I64, F64, Bool, Str, Dict }

// One column to create. `heap_bytes` funds a `Str` heap or the distinct strings of a
// `Dict`; `dict_cap` is the number of distinct strings a `Dict` may hold.
type Spec = struct { name: str, kind: Kind, heap_bytes: usize, dict_cap: usize }

type Column = struct {
    name: str,
    kind: Kind,
    nulls: []u64,
    i32s: []i32,
    i64s: []i64,
    f64s: []f64,
    bits: []u64,
    starts: []u32,
    lens: []u32,
    ids: []u32,
    heap: []u8,
    heap_len: usize,
    heap_wasted: usize,
    entry_starts: []u32,
    entry_lens: []u32,
    entry_count: usize,
    hashes: []u32,
    rank_of_entry: []u32,
    ranks_valid: bool,
    version: u64
}

// bytes taken from the arena so far, threaded through allocation
type Tally = struct { bytes: usize }

type Table = struct {
    columns: []Column,
    capacity_rows: usize,
    row_total: usize,
    live: []u64,
    deleted: usize,
    version: u64,
    structure: u64,
    loading: bool,
    bytes: usize
}

error Full
error BadKind

const ALL_BITS: u64 = 18446744073709551615u64

// ---- bit helpers -----------------------------------------------------------------

fn bit_get(words: []const u64, index: usize) -> bool {
    let word = words[index >> 6usize]
    let shift = u64(index & 63usize)
    ret ((word >> shift) & 1u64) != 0u64
}

fn bit_set(words: []u64, index: usize, on: bool) {
    let slot = index >> 6usize
    let bit = 1u64 << u64(index & 63usize)
    if on {
        words[slot] = words[slot] | bit
    } else {
        words[slot] = words[slot] & (ALL_BITS ^ bit)
    }
}

fn words_for(n: usize) -> usize { ret (n + 63usize) >> 6usize }

// ---- allocation ------------------------------------------------------------------

// A zero-filled array of n items; nothing is allocated for n == 0.
fn take[T: type](a: *mem.Arena, n: usize, tally: *Tally) -> ([]T, err) {
    var empty: []T = zero
    if n == 0usize { ret (empty, ok) }
    let (items, allocation_error) = mem.alloc[T](a, n)
    if allocation_error != ok { ret (empty, allocation_error) }
    var cleared: T = zero
    var at = 0usize
    while at < n {
        items[at] = cleared
        at += 1usize
    }
    tally.bytes += n * mem.size_of[T]()
    ret (items, ok)
}

fn next_power_of_two(n: usize) -> usize {
    var p = 16usize
    while p < n { p = p * 2usize }
    ret p
}

fn make_column(a: *mem.Arena, spec: Spec, rows: usize, tally: *Tally) -> (Column, err) {
    var c: Column = zero
    c.name = spec.name
    c.kind = spec.kind
    let (nulls, nulls_error) = take[u64](a, words_for(rows), tally)
    if nulls_error != ok { ret (c, nulls_error) }
    c.nulls = nulls
    if spec.kind == Kind.I32 {
        let (items, e) = take[i32](a, rows, tally)
        if e != ok { ret (c, e) }
        c.i32s = items
    } else if spec.kind == Kind.I64 {
        let (items, e) = take[i64](a, rows, tally)
        if e != ok { ret (c, e) }
        c.i64s = items
    } else if spec.kind == Kind.F64 {
        let (items, e) = take[f64](a, rows, tally)
        if e != ok { ret (c, e) }
        c.f64s = items
    } else if spec.kind == Kind.Bool {
        let (items, e) = take[u64](a, words_for(rows), tally)
        if e != ok { ret (c, e) }
        c.bits = items
    } else if spec.kind == Kind.Str {
        let (starts, e1) = take[u32](a, rows, tally)
        if e1 != ok { ret (c, e1) }
        c.starts = starts
        let (lens, e2) = take[u32](a, rows, tally)
        if e2 != ok { ret (c, e2) }
        c.lens = lens
        let (heap, e3) = take[u8](a, spec.heap_bytes, tally)
        if e3 != ok { ret (c, e3) }
        c.heap = heap
    } else {
        let (ids, e1) = take[u32](a, rows, tally)
        if e1 != ok { ret (c, e1) }
        c.ids = ids
        let (heap, e2) = take[u8](a, spec.heap_bytes, tally)
        if e2 != ok { ret (c, e2) }
        c.heap = heap
        let (entry_starts, e3) = take[u32](a, spec.dict_cap, tally)
        if e3 != ok { ret (c, e3) }
        c.entry_starts = entry_starts
        let (entry_lens, e4) = take[u32](a, spec.dict_cap, tally)
        if e4 != ok { ret (c, e4) }
        c.entry_lens = entry_lens
        let (hashes, e5) = take[u32](a, next_power_of_two(spec.dict_cap * 2usize), tally)
        if e5 != ok { ret (c, e5) }
        c.hashes = hashes
        let (rank_of_entry, e6) = take[u32](a, spec.dict_cap, tally)
        if e6 != ok { ret (c, e6) }
        c.rank_of_entry = rank_of_entry
    }
    ret (c, ok)
}

// A table of `row_capacity` rows over the given columns.
fn create(a: *mem.Arena, specs: []const Spec, row_capacity: usize) -> (Table, err) {
    var t: Table = zero
    var tally = Tally { bytes: 0usize }
    t.capacity_rows = row_capacity
    let (columns, columns_error) = take[Column](a, specs.len, &tally)
    if columns_error != ok { ret (t, columns_error) }
    t.columns = columns
    var at = 0usize
    while at < specs.len {
        let (made, made_error) = make_column(a, specs[at], row_capacity, &tally)
        if made_error != ok { ret (t, made_error) }
        t.columns[at] = made
        at += 1usize
    }
    let (live, live_error) = take[u64](a, words_for(row_capacity), &tally)
    if live_error != ok { ret (t, live_error) }
    t.live = live
    t.bytes = tally.bytes
    ret (t, ok)
}

// ---- shape -----------------------------------------------------------------------

fn column_count(t: *const Table) -> usize { ret t.columns.len }
fn row_count(t: *const Table) -> usize { ret t.row_total }
fn live_count(t: *const Table) -> usize { ret t.row_total - t.deleted }
fn capacity(t: *const Table) -> usize { ret t.capacity_rows }
fn memory_bytes(t: *const Table) -> usize { ret t.bytes }
fn column_name(t: *const Table, col: usize) -> str { ret t.columns[col].name }
fn column_kind(t: *const Table, col: usize) -> Kind { ret t.columns[col].kind }

fn find_column(t: *const Table, name: str) -> (usize, bool) {
    var at = 0usize
    while at < t.columns.len {
        if same_bytes(t.columns[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn same_bytes(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}

// ---- change journal --------------------------------------------------------------

// Bumped by every value write, load, delete and clear.
fn version(t: *const Table) -> u64 { ret t.version }
// The table version at which this column last changed (a value write, a load, a clear).
fn column_version(t: *const Table, col: usize) -> u64 { ret t.columns[col].version }
// Bumped when rows are added, deleted or the table is cleared: row positions may differ.
fn structure_version(t: *const Table) -> u64 { ret t.structure }
// True when the column changed after the caller last looked at `since`.
fn changed_since(t: *const Table, col: usize, since: u64) -> bool { ret t.columns[col].version > since }

fn touch(t: *Table, col: usize) {
    t.version += 1u64
    t.columns[col].version = t.version
}

// ---- rows, load ------------------------------------------------------------------

// Empties the table: no rows, empty dictionaries and heaps. Capacity is kept.
fn clear(t: *Table) {
    t.row_total = 0usize
    t.deleted = 0usize
    t.version += 1u64
    t.structure += 1u64
    var word = 0usize
    while word < t.live.len {
        t.live[word] = 0u64
        word += 1usize
    }
    var col = 0usize
    while col < t.columns.len {
        let c = &t.columns[col]
        c.heap_len = 0usize
        c.heap_wasted = 0usize
        c.entry_count = 0usize
        c.ranks_valid = false
        var slot = 0usize
        while slot < c.hashes.len {
            c.hashes[slot] = 0u32
            slot += 1usize
        }
        word = 0usize
        while word < c.nulls.len {
            c.nulls[word] = 0u64
            word += 1usize
        }
        word = 0usize
        while word < c.bits.len {
            c.bits[word] = 0u64
            word += 1usize
        }
        c.version = t.version
        col += 1usize
    }
}

// Starts a bulk load: the table is emptied. Rows are then added with `append_row` (and
// optionally given a column at a time with `fill_*`); `end_load` closes it.
fn begin_load(t: *Table) {
    clear(t)
    t.loading = true
}

fn end_load(t: *Table) {
    t.loading = false
    t.version += 1u64
    var col = 0usize
    while col < t.columns.len {
        t.columns[col].version = t.version
        col += 1usize
    }
}

// Adds a row, every cell null until written; `Full` when the capacity is reached.
fn append_row(t: *Table) -> (usize, err) {
    if t.row_total >= t.capacity_rows { ret (0usize, Full) }
    let row = t.row_total
    t.row_total += 1usize
    bit_set(t.live, row, true)
    var col = 0usize
    while col < t.columns.len {
        bit_set(t.columns[col].nulls, row, true)
        col += 1usize
    }
    t.structure += 1u64
    if !t.loading { t.version += 1u64 }
    ret (row, ok)
}

fn is_live(t: *const Table, row: usize) -> bool { ret bit_get(t.live, row) }

// Tombstones a row; its storage stays until `clear`/`begin_load`.
fn delete_row(t: *Table, row: usize) -> bool {
    if row >= t.row_total || !bit_get(t.live, row) { ret false }
    bit_set(t.live, row, false)
    t.deleted += 1usize
    t.structure += 1u64
    t.version += 1u64
    ret true
}

// ---- nulls and typed access ------------------------------------------------------

fn is_null(t: *const Table, col: usize, row: usize) -> bool { ret bit_get(t.columns[col].nulls, row) }

fn set_null(t: *Table, col: usize, row: usize) {
    bit_set(t.columns[col].nulls, row, true)
    touch(t, col)
}

fn get_i32(t: *const Table, col: usize, row: usize) -> i32 { ret t.columns[col].i32s[row] }
fn get_i64(t: *const Table, col: usize, row: usize) -> i64 { ret t.columns[col].i64s[row] }
fn get_f64(t: *const Table, col: usize, row: usize) -> f64 { ret t.columns[col].f64s[row] }
fn get_bool(t: *const Table, col: usize, row: usize) -> bool { ret bit_get(t.columns[col].bits, row) }

fn set_i32(t: *Table, col: usize, row: usize, value: i32) {
    t.columns[col].i32s[row] = value
    bit_set(t.columns[col].nulls, row, false)
    touch(t, col)
}

fn set_i64(t: *Table, col: usize, row: usize, value: i64) {
    t.columns[col].i64s[row] = value
    bit_set(t.columns[col].nulls, row, false)
    touch(t, col)
}

fn set_f64(t: *Table, col: usize, row: usize, value: f64) {
    t.columns[col].f64s[row] = value
    bit_set(t.columns[col].nulls, row, false)
    touch(t, col)
}

fn set_bool(t: *Table, col: usize, row: usize, value: bool) {
    bit_set(t.columns[col].bits, row, value)
    bit_set(t.columns[col].nulls, row, false)
    touch(t, col)
}

// Column-at-a-time fill of rows 0..values.len (those rows must exist): the fast path of a
// bulk load. One version bump for the whole column.
fn fill_i32(t: *Table, col: usize, values: []const i32) {
    var row = 0usize
    while row < values.len {
        t.columns[col].i32s[row] = values[row]
        bit_set(t.columns[col].nulls, row, false)
        row += 1usize
    }
    touch(t, col)
}

fn fill_i64(t: *Table, col: usize, values: []const i64) {
    var row = 0usize
    while row < values.len {
        t.columns[col].i64s[row] = values[row]
        bit_set(t.columns[col].nulls, row, false)
        row += 1usize
    }
    touch(t, col)
}

fn fill_f64(t: *Table, col: usize, values: []const f64) {
    var row = 0usize
    while row < values.len {
        t.columns[col].f64s[row] = values[row]
        bit_set(t.columns[col].nulls, row, false)
        row += 1usize
    }
    touch(t, col)
}

// ---- strings ---------------------------------------------------------------------

fn hash_bytes(s: str) -> u32 {
    var h = 2166136261u32
    var at = 0usize
    while at < s.len {
        h = (h ^ u32(s[at])) *% 16777619u32
        at += 1usize
    }
    ret h
}

// The cell's text (empty for a null cell).
fn get_str(t: *const Table, col: usize, row: usize) -> str {
    let c = &t.columns[col]
    if bit_get(c.nulls, row) { ret c.heap[0usize..0usize] }
    if c.kind == Kind.Str {
        let start = usize(c.starts[row])
        ret c.heap[start..start + usize(c.lens[row])]
    }
    ret entry_text(c, c.ids[row])
}

fn entry_text(c: *const Column, id: u32) -> str {
    let start = usize(c.entry_starts[usize(id)])
    ret c.heap[start..start + usize(c.entry_lens[usize(id)])]
}

fn set_str(t: *Table, col: usize, row: usize, s: str) -> err {
    let c = &t.columns[col]
    if c.kind == Kind.Str {
        if c.heap_len + s.len > c.heap.len { ret Full }
        var at = 0usize
        while at < s.len {
            c.heap[c.heap_len + at] = s[at]
            at += 1usize
        }
        if !bit_get(c.nulls, row) { c.heap_wasted += usize(c.lens[row]) }
        c.starts[row] = u32(c.heap_len)
        c.lens[row] = u32(s.len)
        c.heap_len += s.len
    } else {
        let (id, id_error) = intern(c, s)
        if id_error != ok { ret id_error }
        c.ids[row] = id
    }
    bit_set(c.nulls, row, false)
    touch(t, col)
    ret ok
}

// ---- dictionaries ----------------------------------------------------------------

fn find_entry(c: *const Column, s: str, hash: u32) -> (u32, bool) {
    let mask = c.hashes.len - 1usize
    var slot = usize(hash) & mask
    while c.hashes[slot] != 0u32 {
        let id = c.hashes[slot] - 1u32
        if same_bytes(entry_text(c, id), s) { ret (id, true) }
        slot = (slot + 1usize) & mask
    }
    ret (0u32, false)
}

fn intern(c: *Column, s: str) -> (u32, err) {
    let hash = hash_bytes(s)
    let (found, present) = find_entry(c, s, hash)
    if present { ret (found, ok) }
    if c.entry_count >= c.entry_starts.len || c.heap_len + s.len > c.heap.len { ret (0u32, Full) }
    var at = 0usize
    while at < s.len {
        c.heap[c.heap_len + at] = s[at]
        at += 1usize
    }
    let id = u32(c.entry_count)
    c.entry_starts[c.entry_count] = u32(c.heap_len)
    c.entry_lens[c.entry_count] = u32(s.len)
    c.heap_len += s.len
    c.entry_count += 1usize
    let mask = c.hashes.len - 1usize
    var slot = usize(hash) & mask
    while c.hashes[slot] != 0u32 { slot = (slot + 1usize) & mask }
    c.hashes[slot] = id + 1u32
    c.ranks_valid = false
    ret (id, ok)
}

fn dict_len(t: *const Table, col: usize) -> usize { ret t.columns[col].entry_count }
fn dict_capacity(t: *const Table, col: usize) -> usize { ret t.columns[col].entry_starts.len }
fn dict_str(t: *const Table, col: usize, id: u32) -> str { ret entry_text(&t.columns[col], id) }
// The dictionary id of a row's cell (meaningless for a null cell).
fn dict_id(t: *const Table, col: usize, row: usize) -> u32 { ret t.columns[col].ids[row] }

fn dict_find(t: *const Table, col: usize, s: str) -> (u32, bool) {
    let c = &t.columns[col]
    let (id, present) = find_entry(c, s, hash_bytes(s))
    ret (id, present)
}

fn heap_used(t: *const Table, col: usize) -> usize { ret t.columns[col].heap_len }
fn heap_wasted(t: *const Table, col: usize) -> usize { ret t.columns[col].heap_wasted }

// ASCII upper-case folding then byte order: the order of `CompareStr(UpperCase(x), UpperCase(y))`.
fn compare_fold(x: str, y: str) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        var xb = x[at]
        var yb = y[at]
        if xb >= 97u8 && xb <= 122u8 { xb -= 32u8 }
        if yb >= 97u8 && yb <= 122u8 { yb -= 32u8 }
        if xb != yb {
            if xb < yb { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

type RankCtx = struct { column: *const Column }

fn compare_entries(ctx: *RankCtx, x: u32, y: u32) -> i32 {
    ret compare_fold(entry_text(ctx.column, x), entry_text(ctx.column, y))
}

// Dense fold-order ranks of a Dict column's entries (index = dictionary id), built on first
// use after the dictionary grew. `scratch` supplies the sort's working storage; the caller
// may `mem.reset` it afterwards. Equal rank means equal ignoring ASCII case.
fn ranks(t: *Table, col: usize, scratch: *mem.Arena) -> ([]const u32, err) {
    let c = &t.columns[col]
    if c.kind != Kind.Dict { ret (c.rank_of_entry[0usize..0usize], BadKind) }
    let n = c.entry_count
    if c.ranks_valid { ret (c.rank_of_entry[0usize..n], ok) }
    let (order, order_error) = mem.alloc[u32](scratch, n)
    if order_error != ok { ret (c.rank_of_entry[0usize..0usize], order_error) }
    var at = 0usize
    while at < n {
        order[at] = u32(at)
        at += 1usize
    }
    var ctx = RankCtx { column: c }
    let sort_error = sort.stable_in_place_by[u32, RankCtx](scratch, order, &ctx, compare_entries)
    if sort_error != ok { ret (c.rank_of_entry[0usize..0usize], sort_error) }
    var rank = 0u32
    at = 0usize
    while at < n {
        if at > 0usize && compare_fold(entry_text(c, order[at - 1usize]), entry_text(c, order[at])) != 0i32 {
            rank += 1u32
        }
        c.rank_of_entry[usize(order[at])] = rank
        at += 1usize
    }
    c.ranks_valid = true
    ret (c.rank_of_entry[0usize..n], ok)
}

// The rank of a row's cell; `ranks` must have been called since the last dictionary growth.
fn rank_of(t: *const Table, col: usize, row: usize) -> u32 {
    let c = &t.columns[col]
    ret c.rank_of_entry[usize(c.ids[row])]
}
