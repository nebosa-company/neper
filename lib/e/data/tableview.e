// The "data controller" over an `e.data.table`: a display order of the table's live rows.
// This increment is the sort stage (docs/grid.md 5.4, step 2); filter, group, summary and
// search stages sit on the same `View`.
//
// Sorting is a stable LSD multi-key sort. The keys are applied last to first, each as one
// stable pass over the order array, so ties on every key are in row order, and a row order
// built from several keys costs the sum of its keys, not a comparer call per pair:
//   * a numeric, bool or dictionary column becomes an unsigned 64-bit key per row (the value
//     bits flipped for signed and float order, the rank of the dictionary entry for a
//     string) and is sorted with one counting pass per significant key byte;
//   * a text column that is not a dictionary is ranked once (cached until the column changes)
//     by a comparison sort of its rows, then handled as a rank;
//   * a key function `fn(ctx, row) -> u64` is a derived column for an order the table cannot
//     express (MTG's cost, symbol, colour: build once per row, then it is an integer sort);
//   * a comparer `fn(ctx, row_a, row_b) -> i32` is the slow path: a stable merge sort stage.
// Nulls sort first ascending and last descending (a descending key reverses the whole
// order, nulls included), and are one stable partition after the value stage.
//
// Text order is ASCII upper-case folded byte order (`fold: true`, the default of the grid) or
// plain byte order (`fold: false`).
//
// ponytail: one thread; chunked parallel passes are the next step if 150k rows are too slow.

use e.mem
use e.algo.sort
use e.data.table as table

type KeyMode = enum u8 { Column, KeyFn, Compare }

type Key = struct {
    mode: KeyMode,
    column: usize,
    descending: bool,
    fold: bool,
    key_fn: fn(*void, usize) -> u64,
    compare: fn(*void, u32, u32) -> i32,
    ctx: *void
}

// Rank cache of one column: the ranks of its strings under one text order, valid while the
// column, the row set and the order are the ones it was built for.
type Cache = struct {
    ranks: []u32,
    version: u64,
    structure: u64,
    fold: bool,
    size: usize,
    valid: bool
}

type View = struct {
    t: *table.Table,
    order_rows: []u32,
    spare: []u32,
    keys: []u64,
    caches: []Cache,
    total: usize
}

const SIGN64: u64 = 9223372036854775808u64
const SIGN32: u64 = 2147483648u64
const ALL64: u64 = 18446744073709551615u64

fn no_key(ctx: *void, row: usize) -> u64 { ret 0u64 }

fn no_compare(ctx: *void, x: u32, y: u32) -> i32 { ret 0i32 }

// Sort by a column of the table.
fn column_key(col: usize, descending: bool, fold: bool) -> Key {
    ret Key { mode: KeyMode.Column, column: col, descending: descending, fold: fold, key_fn: no_key, compare: no_compare, ctx: nil }
}

// Sort by a derived unsigned key per row (a custom order the table cannot express).
fn fn_key(f: fn(*void, usize) -> u64, ctx: *void, descending: bool) -> Key {
    ret Key { mode: KeyMode.KeyFn, column: 0usize, descending: descending, fold: true, key_fn: f, compare: no_compare, ctx: ctx }
}

// Sort by a row comparer: a negative answer puts the first row before the second.
fn compare_key(f: fn(*void, u32, u32) -> i32, ctx: *void, descending: bool) -> Key {
    ret Key { mode: KeyMode.Compare, column: 0usize, descending: descending, fold: true, key_fn: no_key, compare: f, ctx: ctx }
}

// A view over `t`, sized to the table's capacity; every row is in it until a stage narrows it.
fn create(a: *mem.Arena, t: *table.Table) -> (View, err) {
    var v: View = zero
    v.t = t
    let capacity_rows = table.capacity(t)
    if capacity_rows != 0usize {
        let (first, first_error) = mem.alloc[u32](a, capacity_rows)
        if first_error != ok { ret (v, first_error) }
        v.order_rows = first
        let (second, second_error) = mem.alloc[u32](a, capacity_rows)
        if second_error != ok { ret (v, second_error) }
        v.spare = second
        let (keys, keys_error) = mem.alloc[u64](a, capacity_rows)
        if keys_error != ok { ret (v, keys_error) }
        v.keys = keys
    }
    let columns = table.column_count(t)
    if columns != 0usize {
        let (caches, caches_error) = mem.alloc[Cache](a, columns)
        if caches_error != ok { ret (v, caches_error) }
        var col = 0usize
        while col < columns {
            var cache: Cache = zero
            let kind = table.column_kind(t, col)
            var size = 0usize
            if kind == table.Kind.Str { size = capacity_rows }
            if kind == table.Kind.Dict { size = table.dict_capacity(t, col) }
            if size != 0usize {
                let (ranks, ranks_error) = mem.alloc[u32](a, size)
                if ranks_error != ok { ret (v, ranks_error) }
                cache.ranks = ranks
            }
            caches[col] = cache
            col += 1usize
        }
        v.caches = caches
    }
    reset_order(&v)
    ret (v, ok)
}

// The live rows of the table in row order (no sort applied).
fn reset_order(v: *View) {
    var at = 0usize
    var row = 0usize
    let stored = table.row_count(v.t)
    while row < stored {
        if table.is_live(v.t, row) {
            v.order_rows[at] = u32(row)
            at += 1usize
        }
        row += 1usize
    }
    v.total = at
}

// Rows in display order.
fn rows(v: *const View) -> []const u32 { ret v.order_rows[0usize..v.total] }

fn len(v: *const View) -> usize { ret v.total }

fn row_at(v: *const View, position: usize) -> usize { ret usize(v.order_rows[position]) }

// ---- text ranks ------------------------------------------------------------------

type TextCtx = struct { t: *table.Table, col: usize, dict: bool, fold: bool }

fn text_at(c: *TextCtx, i: u32) -> str {
    if c.dict { ret table.dict_str(c.t, c.col, i) }
    ret table.get_str(c.t, c.col, usize(i))
}

fn compare_bytes(x: str, y: str) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        if x[at] != y[at] {
            if x[at] < y[at] { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

fn compare_text(c: *TextCtx, x: u32, y: u32) -> i32 {
    if c.fold { ret table.compare_fold(text_at(c, x), text_at(c, y)) }
    ret compare_bytes(text_at(c, x), text_at(c, y))
}

// Dense ranks of `n` strings (dictionary entries, or the rows of a Str column) into `out`.
fn rank_texts(c: *TextCtx, n: usize, out: []u32, scratch: *mem.Arena) -> err {
    if n == 0usize { ret ok }
    let marker = mem.mark(scratch)
    let (ids, ids_error) = mem.alloc[u32](scratch, n)
    if ids_error != ok { ret ids_error }
    var at = 0usize
    while at < n {
        ids[at] = u32(at)
        at += 1usize
    }
    let sort_error = sort.stable_in_place_by[u32, TextCtx](scratch, ids, c, compare_text)
    if sort_error != ok { ret sort_error }
    var rank = 0u32
    at = 0usize
    while at < n {
        if at > 0usize && compare_text(c, ids[at - 1usize], ids[at]) != 0i32 { rank += 1u32 }
        out[usize(ids[at])] = rank
        at += 1usize
    }
    mem.reset(scratch, marker)
    ret ok
}

// The cache of `col` holds the ranks of its strings under `fold`; build them when it does not.
fn ensure_text_ranks(v: *View, col: usize, fold: bool, scratch: *mem.Arena) -> err {
    let is_dict = table.column_kind(v.t, col) == table.Kind.Dict
    var n = table.row_count(v.t)
    if is_dict { n = table.dict_len(v.t, col) }
    let cache = &v.caches[col]
    let version = table.column_version(v.t, col)
    let structure = table.structure_version(v.t)
    if cache.valid && cache.version == version && cache.structure == structure && cache.fold == fold && cache.size == n { ret ok }
    var c = TextCtx { t: v.t, col: col, dict: is_dict, fold: fold }
    try rank_texts(&c, n, cache.ranks, scratch)
    cache.version = version
    cache.structure = structure
    cache.fold = fold
    cache.size = n
    cache.valid = true
    ret ok
}

// ---- key derivation --------------------------------------------------------------

// The maximum of the keys written and whether any live row is null.
type Derived = struct { max: u64, any_null: bool }

fn derive_column(v: *View, col: usize, fold: bool, scratch: *mem.Arena) -> (Derived, err) {
    var out = Derived { max: 0u64, any_null: false }
    let kind = table.column_kind(v.t, col)
    var cached = false
    var dict_ranks: []const u32 = v.order_rows[0usize..0usize]
    if kind == table.Kind.Str {
        let str_error = ensure_text_ranks(v, col, fold, scratch)
        if str_error != ok { ret (out, str_error) }
        cached = true
    }
    if kind == table.Kind.Dict {
        if fold {
            let (rank_slice, rank_error) = table.ranks(v.t, col, scratch)
            if rank_error != ok { ret (out, rank_error) }
            dict_ranks = rank_slice
        } else {
            let ensure_error = ensure_text_ranks(v, col, false, scratch)
            if ensure_error != ok { ret (out, ensure_error) }
            cached = true
        }
    }
    var at = 0usize
    while at < v.total {
        let row = usize(v.order_rows[at])
        var key = 0u64
        if table.is_null(v.t, col, row) {
            out.any_null = true
        } else if kind == table.Kind.I32 {
            key = u64(mem.bitcast[u32](table.get_i32(v.t, col, row))) ^ SIGN32
        } else if kind == table.Kind.I64 {
            key = mem.bitcast[u64](table.get_i64(v.t, col, row)) ^ SIGN64
        } else if kind == table.Kind.F64 {
            let bits = mem.bitcast[u64](table.get_f64(v.t, col, row))
            if (bits >> 63u64) == 1u64 { key = ALL64 ^ bits } else { key = bits ^ SIGN64 }
        } else if kind == table.Kind.Bool {
            if table.get_bool(v.t, col, row) { key = 1u64 }
        } else if kind == table.Kind.Dict {
            let id = usize(table.dict_id(v.t, col, row))
            if cached { key = u64(v.caches[col].ranks[id]) } else { key = u64(dict_ranks[id]) }
        } else {
            key = u64(v.caches[col].ranks[row])
        }
        v.keys[row] = key
        if key > out.max { out.max = key }
        at += 1usize
    }
    ret (out, ok)
}

fn derive_key_fn(v: *View, key: Key) -> Derived {
    var out = Derived { max: 0u64, any_null: false }
    var at = 0usize
    while at < v.total {
        let row = usize(v.order_rows[at])
        let k = key.key_fn(key.ctx, row)
        v.keys[row] = k
        if k > out.max { out.max = k }
        at += 1usize
    }
    ret out
}

// ---- stable passes ---------------------------------------------------------------

// Reverse the key order inside [0, max] so an ascending pass sorts descending.
fn flip_keys(v: *View, max: u64) {
    var at = 0usize
    while at < v.total {
        let row = usize(v.order_rows[at])
        v.keys[row] = max - v.keys[row]
        at += 1usize
    }
}

fn swap_order(v: *View) {
    let held = v.order_rows
    v.order_rows = v.spare
    v.spare = held
}

// One stable counting pass over key byte `shift / 8`.
fn counting_pass(v: *View, shift: u64) {
    var counts: [256]usize = zero
    var at = 0usize
    while at < v.total {
        let digit = (v.keys[usize(v.order_rows[at])] >> shift) & 255u64
        counts[usize(digit)] += 1usize
        at += 1usize
    }
    var running = 0usize
    var slot = 0usize
    while slot < 256usize {
        let held = counts[slot]
        counts[slot] = running
        running += held
        slot += 1usize
    }
    at = 0usize
    while at < v.total {
        let row = v.order_rows[at]
        let digit = usize((v.keys[usize(row)] >> shift) & 255u64)
        v.spare[counts[digit]] = row
        counts[digit] += 1usize
        at += 1usize
    }
    swap_order(v)
}

// Stable sort of the order by the keys of v.keys, one pass per significant byte.
fn radix(v: *View, max: u64) {
    var shift = 0u64
    while shift < 64u64 && (max >> shift) != 0u64 {
        counting_pass(v, shift)
        shift += 8u64
    }
}

// Stable partition: null rows of `col` first (or last).
fn partition_nulls(v: *View, col: usize, nulls_first: bool) {
    var null_count = 0usize
    var at = 0usize
    while at < v.total {
        if table.is_null(v.t, col, usize(v.order_rows[at])) { null_count += 1usize }
        at += 1usize
    }
    var next_null = 0usize
    var next_value = null_count
    if !nulls_first {
        next_null = v.total - null_count
        next_value = 0usize
    }
    at = 0usize
    while at < v.total {
        let row = v.order_rows[at]
        if table.is_null(v.t, col, usize(row)) {
            v.spare[next_null] = row
            next_null += 1usize
        } else {
            v.spare[next_value] = row
            next_value += 1usize
        }
        at += 1usize
    }
    swap_order(v)
}

type CompareCtx = struct { f: fn(*void, u32, u32) -> i32, ctx: *void, descending: bool }

fn call_compare(c: *CompareCtx, x: u32, y: u32) -> i32 {
    let answer = c.f(c.ctx, x, y)
    if c.descending { ret 0i32 - answer }
    ret answer
}

// Sorts the live rows by `keys` (the first key is the most significant). `scratch` supplies
// the working storage of rank building and merge stages; the caller may reset it afterwards.
fn apply_sort(v: *View, keys: []const Key, scratch: *mem.Arena) -> err {
    reset_order(v)
    var at = keys.len
    while at > 0usize {
        at -= 1usize
        let key = keys[at]
        if key.mode == KeyMode.Compare {
            var cc = CompareCtx { f: key.compare, ctx: key.ctx, descending: key.descending }
            try sort.stable_in_place_by[u32, CompareCtx](scratch, v.order_rows[0usize..v.total], &cc, call_compare)
        } else if key.mode == KeyMode.KeyFn {
            let derived = derive_key_fn(v, key)
            if key.descending { flip_keys(v, derived.max) }
            radix(v, derived.max)
        } else {
            let (derived, derive_error) = derive_column(v, key.column, key.fold, scratch)
            if derive_error != ok { ret derive_error }
            if key.descending { flip_keys(v, derived.max) }
            radix(v, derived.max)
            if derived.any_null { partition_nulls(v, key.column, !key.descending) }
        }
    }
    ret ok
}
