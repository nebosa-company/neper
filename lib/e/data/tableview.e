// The "data controller" over an `e.data.table`: a display order of the table's live rows.
// Sort and filter stages (docs/grid.md 5.4, steps 1-2); group, summary and search stages
// sit on the same `View`.
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
    total: usize,
    matched: []u64,
    next_matched: []u64,
    shown: []u32,
    shown_total: usize,
    filtered: bool
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
        let (shown, shown_error) = mem.alloc[u32](a, capacity_rows)
        if shown_error != ok { ret (v, shown_error) }
        v.shown = shown
        let words = (capacity_rows + 63usize) >> 6usize
        let (matched, matched_error) = mem.alloc[u64](a, words)
        if matched_error != ok { ret (v, matched_error) }
        v.matched = matched
        let (next_matched, next_error) = mem.alloc[u64](a, words)
        if next_error != ok { ret (v, next_error) }
        v.next_matched = next_matched
        var word = 0usize
        while word < words {
            v.matched[word] = 0u64
            v.next_matched[word] = 0u64
            word += 1usize
        }
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
fn rows(v: *const View) -> []const u32 {
    if v.filtered { ret v.shown[0usize..v.shown_total] }
    ret v.order_rows[0usize..v.total]
}

fn len(v: *const View) -> usize {
    if v.filtered { ret v.shown_total }
    ret v.total
}

fn row_at(v: *const View, position: usize) -> usize {
    if v.filtered { ret usize(v.shown[position]) }
    ret usize(v.order_rows[position])
}

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
    if v.filtered { rebuild_shown(v) }
    ret ok
}

// ---- filter ----------------------------------------------------------------------
//
// A filter is a tree of nodes in one flat array: a group node names its children as a
// contiguous run `first .. first + count`, a leaf compares one column with constants.
// `apply_filter` evaluates it over the sorted order and keeps the order: the rows that
// pass are the same rows in the same positions, so changing a filter never re-sorts
// (and a sort keeps the filter, through the `matched` bitset).
//
// Per column kind the evaluation is specialised: a dictionary column evaluates the
// operator once per distinct entry and a row costs one array read; a numeric column is a
// typed compare; a heap string column evaluates the text operator per row.
//
// Text operators are case-insensitive unless the leaf says `match_case` (ASCII folding,
// the order of `compare_fold`). `Like` has two wildcards: `*` any run of bytes (also
// none) and `?` exactly one byte. A null cell matches only `Null` and the negative
// operators (`Ne`, `NotLike`, `NotContains`, `NotBetween`, `NotIn`, `NotNull`).

type Op = enum u8 { Eq, Ne, Lt, Le, Gt, Ge, Like, NotLike, Contains, NotContains, Begins, Ends, Between, NotBetween, In, NotIn, Null, NotNull }

type OperandKind = enum u8 { Int, Real, Text }

type Operand = struct { kind: OperandKind, integer: i64, real: f64, text: str }

type Leaf = struct { column: usize, op: Op, a: Operand, b: Operand, items: []const Operand, match_case: bool }

type NodeKind = enum u8 { Leaf, And, Or, NotAnd, NotOr }

type Node = struct { kind: NodeKind, leaf: Leaf, first: usize, count: usize }

error BadFilter

// Per node: for a leaf over a dictionary column, the verdict of each dictionary entry.
type Accept = struct { entries: []bool }

type Compiled = struct { nodes: []const Node, accept: []Accept }

fn int_operand(value: i64) -> Operand {
    ret Operand { kind: OperandKind.Int, integer: value, real: 0.0f64, text: "" }
}

fn real_operand(value: f64) -> Operand {
    ret Operand { kind: OperandKind.Real, integer: 0i64, real: value, text: "" }
}

fn text_operand(value: str) -> Operand {
    ret Operand { kind: OperandKind.Text, integer: 0i64, real: 0.0f64, text: value }
}

// A leaf comparing `column` with one constant (or none for Null/NotNull).
fn leaf_node(column: usize, op: Op, a: Operand) -> Node {
    ret Node { kind: NodeKind.Leaf, leaf: Leaf { column: column, op: op, a: a, b: a, items: zero, match_case: false }, first: 0usize, count: 0usize }
}

// A leaf with two constants (Between, NotBetween).
fn between_node(column: usize, op: Op, low: Operand, high: Operand) -> Node {
    ret Node { kind: NodeKind.Leaf, leaf: Leaf { column: column, op: op, a: low, b: high, items: zero, match_case: false }, first: 0usize, count: 0usize }
}

// A leaf comparing `column` with a list of constants (In, NotIn).
fn list_node(column: usize, op: Op, items: []const Operand) -> Node {
    let none = int_operand(0i64)
    ret Node { kind: NodeKind.Leaf, leaf: Leaf { column: column, op: op, a: none, b: none, items: items, match_case: false }, first: 0usize, count: 0usize }
}

// The same leaf, exact case.
fn match_case(n: Node) -> Node {
    var copy = n
    copy.leaf.match_case = true
    ret copy
}

// A group whose children are nodes[first .. first + count] of the same array.
fn group_node(kind: NodeKind, first: usize, count: usize) -> Node {
    let none = int_operand(0i64)
    ret Node { kind: kind, leaf: Leaf { column: 0usize, op: Op.Eq, a: none, b: none, items: zero, match_case: false }, first: first, count: count }
}

// ---- text operators --------------------------------------------------------------

fn fold_byte(b: u8) -> u8 {
    if b >= 97u8 && b <= 122u8 { ret b - 32u8 }
    ret b
}

fn bytes_equal(x: str, y: str, exact_case: bool) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        var xb = x[at]
        var yb = y[at]
        if !exact_case {
            xb = fold_byte(xb)
            yb = fold_byte(yb)
        }
        if xb != yb { ret false }
        at += 1usize
    }
    ret true
}

fn compare_text_op(x: str, y: str, exact_case: bool) -> i32 {
    if exact_case { ret compare_bytes(x, y) }
    ret table.compare_fold(x, y)
}

// `needle` occurs in `hay` (anywhere, at the start or at the end).
fn contains_text(hay: str, needle: str, exact_case: bool, at_start: bool, at_end: bool) -> bool {
    if needle.len > hay.len { ret false }
    if needle.len == 0usize { ret true }
    var start = 0usize
    var last = hay.len - needle.len
    if at_start { last = 0usize }
    if at_end { start = hay.len - needle.len }
    while start <= last {
        var same = true
        var k = 0usize
        while k < needle.len {
            var hb = hay[start + k]
            var nb = needle[k]
            if !exact_case {
                hb = fold_byte(hb)
                nb = fold_byte(nb)
            }
            if hb != nb {
                same = false
                break
            }
            k += 1usize
        }
        if same { ret true }
        start += 1usize
    }
    ret false
}

// `*` matches any run of bytes, `?` exactly one: the classic two-pointer match with one
// backtrack point, linear in practice.
fn like_text(text: str, pattern: str, exact_case: bool) -> bool {
    var t = 0usize
    var p = 0usize
    var star = pattern.len
    var mark = 0usize
    var have_star = false
    while t < text.len {
        if p < pattern.len && pattern[p] == 42u8 {
            have_star = true
            star = p
            mark = t
            p += 1usize
        } else if p < pattern.len && (pattern[p] == 63u8 || (exact_case && pattern[p] == text[t]) || (!exact_case && fold_byte(pattern[p]) == fold_byte(text[t]))) {
            p += 1usize
            t += 1usize
        } else if have_star {
            mark += 1usize
            t = mark
            p = star + 1usize
        } else {
            ret false
        }
    }
    while p < pattern.len && pattern[p] == 42u8 { p += 1usize }
    ret p == pattern.len
}

// The verdict of a text operator on a non-null string.
fn text_verdict(l: *const Leaf, s: str) -> bool {
    let exact_case = l.match_case
    if l.op == Op.Eq { ret bytes_equal(s, l.a.text, exact_case) }
    if l.op == Op.Ne { ret !bytes_equal(s, l.a.text, exact_case) }
    if l.op == Op.Lt { ret compare_text_op(s, l.a.text, exact_case) < 0i32 }
    if l.op == Op.Le { ret compare_text_op(s, l.a.text, exact_case) <= 0i32 }
    if l.op == Op.Gt { ret compare_text_op(s, l.a.text, exact_case) > 0i32 }
    if l.op == Op.Ge { ret compare_text_op(s, l.a.text, exact_case) >= 0i32 }
    if l.op == Op.Like { ret like_text(s, l.a.text, exact_case) }
    if l.op == Op.NotLike { ret !like_text(s, l.a.text, exact_case) }
    if l.op == Op.Contains { ret contains_text(s, l.a.text, exact_case, false, false) }
    if l.op == Op.NotContains { ret !contains_text(s, l.a.text, exact_case, false, false) }
    if l.op == Op.Begins { ret contains_text(s, l.a.text, exact_case, true, false) }
    if l.op == Op.Ends { ret contains_text(s, l.a.text, exact_case, false, true) }
    if l.op == Op.Between || l.op == Op.NotBetween {
        let inside = compare_text_op(s, l.a.text, exact_case) >= 0i32 && compare_text_op(s, l.b.text, exact_case) <= 0i32
        if l.op == Op.Between { ret inside }
        ret !inside
    }
    // In, NotIn
    var found = false
    var at = 0usize
    while at < l.items.len && !found {
        if bytes_equal(s, l.items[at].text, exact_case) { found = true }
        at += 1usize
    }
    if l.op == Op.In { ret found }
    ret !found
}

// ---- numeric operators -----------------------------------------------------------

fn apply_comparison(op: Op, c: i32) -> bool {
    if op == Op.Eq { ret c == 0i32 }
    if op == Op.Ne { ret c != 0i32 }
    if op == Op.Lt { ret c < 0i32 }
    if op == Op.Le { ret c <= 0i32 }
    if op == Op.Gt { ret c > 0i32 }
    ret c >= 0i32
}

fn three_way_int(x: i64, y: i64) -> i32 {
    if x < y { ret -1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn three_way_real(x: f64, y: f64) -> i32 {
    if x < y { ret -1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// Compares a numeric cell with one operand: as integers when both are, else as reals.
fn compare_number(integer_cell: bool, cell_int: i64, cell_real: f64, o: Operand) -> i32 {
    if integer_cell && o.kind == OperandKind.Int { ret three_way_int(cell_int, o.integer) }
    var cell = cell_real
    if integer_cell { cell = f64(cell_int) }
    var other = o.real
    if o.kind == OperandKind.Int { other = f64(o.integer) }
    ret three_way_real(cell, other)
}

fn number_verdict(l: *const Leaf, integer_cell: bool, cell_int: i64, cell_real: f64) -> bool {
    if l.op == Op.Between || l.op == Op.NotBetween {
        let low = compare_number(integer_cell, cell_int, cell_real, l.a)
        let high = compare_number(integer_cell, cell_int, cell_real, l.b)
        let inside = low >= 0i32 && high <= 0i32
        if l.op == Op.Between { ret inside }
        ret !inside
    }
    if l.op == Op.In || l.op == Op.NotIn {
        var found = false
        var at = 0usize
        while at < l.items.len && !found {
            if compare_number(integer_cell, cell_int, cell_real, l.items[at]) == 0i32 { found = true }
            at += 1usize
        }
        if l.op == Op.In { ret found }
        ret !found
    }
    ret apply_comparison(l.op, compare_number(integer_cell, cell_int, cell_real, l.a))
}

fn negative_op(op: Op) -> bool {
    ret op == Op.Ne || op == Op.NotLike || op == Op.NotContains || op == Op.NotBetween || op == Op.NotIn || op == Op.NotNull
}

fn text_op(op: Op) -> bool {
    ret op == Op.Like || op == Op.NotLike || op == Op.Contains || op == Op.NotContains || op == Op.Begins || op == Op.Ends
}

// ---- compile and evaluate --------------------------------------------------------

// Checks the operands against the column kind and, for a dictionary column, evaluates the
// operator once per entry.
fn compile_leaf(v: *const View, l: *const Leaf, out: *Accept, scratch: *mem.Arena) -> err {
    if l.column >= table.column_count(v.t) { ret BadFilter }
    let kind = table.column_kind(v.t, l.column)
    let textual = kind == table.Kind.Str || kind == table.Kind.Dict
    if l.op == Op.Null || l.op == Op.NotNull { ret ok }
    if textual {
        if l.op == Op.In || l.op == Op.NotIn {
            var at = 0usize
            while at < l.items.len {
                if l.items[at].kind != OperandKind.Text { ret BadFilter }
                at += 1usize
            }
        } else {
            if l.a.kind != OperandKind.Text { ret BadFilter }
            if (l.op == Op.Between || l.op == Op.NotBetween) && l.b.kind != OperandKind.Text { ret BadFilter }
        }
    } else {
        if text_op(l.op) { ret BadFilter }
        if l.op == Op.In || l.op == Op.NotIn {
            var at = 0usize
            while at < l.items.len {
                if l.items[at].kind == OperandKind.Text { ret BadFilter }
                at += 1usize
            }
        } else {
            if l.a.kind == OperandKind.Text { ret BadFilter }
            if (l.op == Op.Between || l.op == Op.NotBetween) && l.b.kind == OperandKind.Text { ret BadFilter }
        }
    }
    if kind == table.Kind.Dict {
        let n = table.dict_len(v.t, l.column)
        if n != 0usize {
            let (entries, entries_error) = mem.alloc[bool](scratch, n)
            if entries_error != ok { ret entries_error }
            var id = 0usize
            while id < n {
                entries[id] = text_verdict(l, table.dict_str(v.t, l.column, u32(id)))
                id += 1usize
            }
            out.entries = entries
        }
    }
    ret ok
}

fn compile(v: *const View, nodes: []const Node, scratch: *mem.Arena) -> (Compiled, err) {
    var c = Compiled { nodes: nodes, accept: zero }
    if nodes.len == 0usize { ret (c, ok) }
    let (accept, accept_error) = mem.alloc[Accept](scratch, nodes.len)
    if accept_error != ok { ret (c, accept_error) }
    var at = 0usize
    while at < nodes.len {
        accept[at] = Accept { entries: zero }
        at += 1usize
    }
    at = 0usize
    while at < nodes.len {
        if nodes[at].kind == NodeKind.Leaf {
            let leaf_error = compile_leaf(v, &nodes[at].leaf, &accept[at], scratch)
            if leaf_error != ok { ret (c, leaf_error) }
        } else if nodes[at].first + nodes[at].count > nodes.len || nodes[at].first <= at {
            // children come after their group: a cycle or an out-of-range run is refused
            ret (c, BadFilter)
        }
        at += 1usize
    }
    c.accept = accept
    ret (c, ok)
}

fn eval_leaf(v: *const View, c: *const Compiled, index: usize, row: usize) -> bool {
    let l = &c.nodes[index].leaf
    let cell_null = table.is_null(v.t, l.column, row)
    if l.op == Op.Null { ret cell_null }
    if l.op == Op.NotNull { ret !cell_null }
    if cell_null { ret negative_op(l.op) }
    let kind = table.column_kind(v.t, l.column)
    if kind == table.Kind.Dict { ret c.accept[index].entries[usize(table.dict_id(v.t, l.column, row))] }
    if kind == table.Kind.Str { ret text_verdict(l, table.get_str(v.t, l.column, row)) }
    if kind == table.Kind.I32 { ret number_verdict(l, true, i64(table.get_i32(v.t, l.column, row)), 0.0f64) }
    if kind == table.Kind.I64 { ret number_verdict(l, true, table.get_i64(v.t, l.column, row), 0.0f64) }
    if kind == table.Kind.Bool {
        var as_int = 0i64
        if table.get_bool(v.t, l.column, row) { as_int = 1i64 }
        ret number_verdict(l, true, as_int, 0.0f64)
    }
    ret number_verdict(l, false, 0i64, table.get_f64(v.t, l.column, row))
}

fn eval_node(v: *const View, c: *const Compiled, index: usize, row: usize) -> bool {
    let node = &c.nodes[index]
    if node.kind == NodeKind.Leaf { ret eval_leaf(v, c, index, row) }
    var any_pass = false
    var all_pass = true
    var at = 0usize
    while at < node.count {
        let pass = eval_node(v, c, node.first + at, row)
        if pass { any_pass = true } else { all_pass = false }
        // short circuit: an And stops at the first false, an Or at the first true
        if (node.kind == NodeKind.And || node.kind == NodeKind.NotAnd) && !pass { break }
        if (node.kind == NodeKind.Or || node.kind == NodeKind.NotOr) && pass { break }
        at += 1usize
    }
    if node.count == 0usize { ret true }
    if node.kind == NodeKind.And { ret all_pass }
    if node.kind == NodeKind.Or { ret any_pass }
    if node.kind == NodeKind.NotAnd { ret !all_pass }
    ret !any_pass
}

// Rebuilds the shown rows from the matched set, in the current sort order.
fn rebuild_shown(v: *View) {
    var count_shown = 0usize
    var at = 0usize
    while at < v.total {
        let row = v.order_rows[at]
        if bit_is_set(v.matched, usize(row)) {
            v.shown[count_shown] = row
            count_shown += 1usize
        }
        at += 1usize
    }
    v.shown_total = count_shown
}

fn bit_is_set(words: []const u64, index: usize) -> bool {
    ret ((words[index >> 6usize] >> u64(index & 63usize)) & 1u64) != 0u64
}

fn bit_put(words: []u64, index: usize) {
    words[index >> 6usize] = words[index >> 6usize] | (1u64 << u64(index & 63usize))
}

// Filters the display order by the tree rooted at nodes[0]. The rows that pass keep their
// sort positions. With `refine` the new filter is taken to pass only rows the current one
// passes (typing on in a filter box, AND-ing a condition): only those rows are evaluated.
// An empty `nodes` clears the filter.
fn apply_filter(v: *View, nodes: []const Node, refine: bool, scratch: *mem.Arena) -> err {
    if nodes.len == 0usize {
        clear_filter(v)
        ret ok
    }
    let marker = mem.mark(scratch)
    let (compiled, compile_error) = compile(v, nodes, scratch)
    if compile_error != ok {
        mem.reset(scratch, marker)
        ret compile_error
    }
    let narrowing = refine && v.filtered
    var count_shown = 0usize
    var at = 0usize
    // the previous matches are consulted while the new ones are written: build into `next`
    var word = 0usize
    while word < v.next_matched.len {
        v.next_matched[word] = 0u64
        word += 1usize
    }
    while at < v.total {
        let row = v.order_rows[at]
        var pass = false
        if !narrowing || bit_is_set(v.matched, usize(row)) { pass = eval_node(v, &compiled, 0usize, usize(row)) }
        if pass {
            bit_put(v.next_matched, usize(row))
            v.shown[count_shown] = row
            count_shown += 1usize
        }
        at += 1usize
    }
    mem.reset(scratch, marker)
    let held = v.matched
    v.matched = v.next_matched
    v.next_matched = held
    v.shown_total = count_shown
    v.filtered = true
    ret ok
}

fn clear_filter(v: *View) {
    v.filtered = false
    v.shown_total = 0usize
}

fn is_filtered(v: *const View) -> bool { ret v.filtered }
