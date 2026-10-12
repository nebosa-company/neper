// Grouping and summaries over an `e.data.tableview` (docs/grid.md 5.4, steps 3 and 4).
//
// Grouping is a linear pass over the displayed rows, which are first sorted by the group
// levels (then by the caller's own keys): a group is a run of rows whose group-column
// cells are equal, found by comparing each row with the one before it, never by hashing
// strings. Groups are kept in one flat array in display (pre-)order, each with its level,
// first position, row count and parent, so a subtree is a contiguous run of that array
// and of the row order.
//
// An expansion is remembered by the group's *path*: a hash of the key values of the group
// and of its ancestors (text folded to ASCII upper case), not by its position, so it
// survives a re-sort, a re-filter and a change of data. The visible list is the flat
// sequence a grid scrolls over: a header per visible group, then the rows of an expanded
// bottom-level group.
//
// Summaries are typed accumulators per (group, column): row count, value count, sum, min,
// max (average is sum / values), over the footer (all displayed rows) and over every
// group; groups can be ordered by one of them.
//
// Text equality follows the group level's `fold`: ASCII upper-case folded (the grid's
// default) or exact bytes.
//
// ponytail: sums are f64 (exact to 2^53); a single thread.

use e.mem
use e.algo.sort
use e.data.table as table
use e.data.tableview as view

const MAX_LEVELS: usize = 4usize
const NO_GROUP: u32 = 4294967295u32
const HEADER_BIT: u32 = 2147483648u32
const MAX_TOGGLED: usize = 4096usize

type GroupLevel = struct { column: usize, descending: bool, fold: bool }

type Group = struct { level: u32, first: u32, count: u32, parent: u32, key_row: u32, path: u64, expanded: bool }

type SummaryKind = enum u8 { Rows, Values, Sum, Min, Max, Avg }

// What to accumulate: the cells of one column.
type SummarySpec = struct { column: usize }

type Summary = struct { rows: usize, values: usize, sum: f64, min: f64, max: f64 }

type Grouping = struct {
    v: *view.View,
    t: *table.Table,
    levels: [4]GroupLevel,
    level_count: usize,
    order: []u32,
    spare: []u32,
    total_rows: usize,
    groups: []Group,
    group_total: usize,
    visible: []u32,
    visible_total: usize,
    toggled: []u64,
    toggled_count: usize,
    default_expanded: bool,
    specs: []SummarySpec,
    sums: []Summary
}

error TooManyGroups
error TooManyToggles
error BadLevel

fn mix(x: u64) -> u64 {
    var h = x *% 6364136223846793005u64 +% 1442695040888963407u64
    h = h ^ (h >> 29u64)
    h = h *% 6364136223846793005u64
    ret h ^ (h >> 32u64)
}

// A grouping over `v`'s table with room for `group_capacity` groups (a group per distinct
// key combination of every level).
fn create(a: *mem.Arena, v: *view.View, group_capacity: usize) -> (Grouping, err) {
    var g: Grouping = zero
    g.v = v
    g.t = v.t
    let rows = table.capacity(v.t)
    if rows != 0usize {
        let (order, order_error) = mem.alloc[u32](a, rows)
        if order_error != ok { ret (g, order_error) }
        g.order = order
        let (spare, spare_error) = mem.alloc[u32](a, rows)
        if spare_error != ok { ret (g, spare_error) }
        g.spare = spare
    }
    if group_capacity != 0usize {
        let (groups, groups_error) = mem.alloc[Group](a, group_capacity)
        if groups_error != ok { ret (g, groups_error) }
        g.groups = groups
    }
    let (visible, visible_error) = mem.alloc[u32](a, rows + group_capacity)
    if visible_error != ok { ret (g, visible_error) }
    g.visible = visible
    let (toggled, toggled_error) = mem.alloc[u64](a, MAX_TOGGLED)
    if toggled_error != ok { ret (g, toggled_error) }
    g.toggled = toggled
    ret (g, ok)
}

// ---- keys ------------------------------------------------------------------------

type LevelKey = struct { column: usize, kind: table.Kind, fold: bool, ranks: []const u32 }

fn same_key(t: *const table.Table, k: *const LevelKey, x: usize, y: usize) -> bool {
    let xn = table.is_null(t, k.column, x)
    let yn = table.is_null(t, k.column, y)
    if xn || yn { ret xn && yn }
    if k.kind == table.Kind.I32 { ret table.get_i32(t, k.column, x) == table.get_i32(t, k.column, y) }
    if k.kind == table.Kind.I64 { ret table.get_i64(t, k.column, x) == table.get_i64(t, k.column, y) }
    if k.kind == table.Kind.F64 { ret table.get_f64(t, k.column, x) == table.get_f64(t, k.column, y) }
    if k.kind == table.Kind.Bool { ret table.get_bool(t, k.column, x) == table.get_bool(t, k.column, y) }
    if k.kind == table.Kind.Dict {
        let ix = usize(table.dict_id(t, k.column, x))
        let iy = usize(table.dict_id(t, k.column, y))
        if k.fold { ret k.ranks[ix] == k.ranks[iy] }
        ret ix == iy
    }
    let sx = table.get_str(t, k.column, x)
    let sy = table.get_str(t, k.column, y)
    if k.fold { ret table.compare_fold(sx, sy) == 0i32 }
    if sx.len != sy.len { ret false }
    var at = 0usize
    while at < sx.len {
        if sx[at] != sy[at] { ret false }
        at += 1usize
    }
    ret true
}

// A stable identity of the cell's value for a path: folded text, or the value bits.
fn key_hash(t: *const table.Table, k: *const LevelKey, row: usize) -> u64 {
    if table.is_null(t, k.column, row) { ret 7919u64 }
    if k.kind == table.Kind.I32 { ret mix(u64(mem.bitcast[u32](table.get_i32(t, k.column, row)))) }
    if k.kind == table.Kind.I64 { ret mix(mem.bitcast[u64](table.get_i64(t, k.column, row))) }
    if k.kind == table.Kind.F64 { ret mix(mem.bitcast[u64](table.get_f64(t, k.column, row))) }
    if k.kind == table.Kind.Bool {
        if table.get_bool(t, k.column, row) { ret 3u64 }
        ret 5u64
    }
    let s = table.get_str(t, k.column, row)
    var h = 14695981039346656037u64
    var at = 0usize
    while at < s.len {
        var b = s[at]
        if k.fold && b >= 97u8 && b <= 122u8 { b = b - 32u8 }
        h = (h ^ u64(b)) *% 1099511628211u64
        at += 1usize
    }
    ret h
}

// ---- expansion -------------------------------------------------------------------

// Position of `path` in the sorted toggled list, or where it would go.
fn toggled_find(g: *const Grouping, path: u64) -> (usize, bool) {
    var low = 0usize
    var high = g.toggled_count
    while low < high {
        let middle = (low + high) / 2usize
        if g.toggled[middle] < path {
            low = middle + 1usize
        } else {
            high = middle
        }
    }
    if low < g.toggled_count && g.toggled[low] == path { ret (low, true) }
    ret (low, false)
}

fn path_expanded(g: *const Grouping, path: u64) -> bool {
    let (_, found) = toggled_find(g, path)
    if found { ret !g.default_expanded }
    ret g.default_expanded
}

// Sets one group's expansion; the visible list is rebuilt.
fn set_expanded(g: *Grouping, group: usize, on: bool) -> err {
    let path = g.groups[group].path
    let (at, found) = toggled_find(g, path)
    let differs = on != g.default_expanded
    if differs && !found {
        if g.toggled_count >= g.toggled.len { ret TooManyToggles }
        var i = g.toggled_count
        while i > at {
            g.toggled[i] = g.toggled[i - 1usize]
            i -= 1usize
        }
        g.toggled[at] = path
        g.toggled_count += 1usize
    } else if !differs && found {
        var i = at
        while i + 1usize < g.toggled_count {
            g.toggled[i] = g.toggled[i + 1usize]
            i += 1usize
        }
        g.toggled_count -= 1usize
    }
    g.groups[group].expanded = on
    build_visible(g)
    ret ok
}

fn is_expanded(g: *const Grouping, group: usize) -> bool { ret g.groups[group].expanded }

// Every group expanded or collapsed, and the default for groups that appear later.
fn set_all_expanded(g: *Grouping, on: bool) {
    g.default_expanded = on
    g.toggled_count = 0usize
    var at = 0usize
    while at < g.group_total {
        g.groups[at].expanded = on
        at += 1usize
    }
    build_visible(g)
}

// ---- the visible list ------------------------------------------------------------

fn build_visible(g: *Grouping) {
    var out = 0usize
    if g.level_count == 0usize {
        var at = 0usize
        while at < g.total_rows {
            g.visible[out] = u32(at)
            out += 1usize
            at += 1usize
        }
        g.visible_total = out
        ret
    }
    var chain: [4]bool = zero
    var gi = 0usize
    while gi < g.group_total {
        let level = usize(g.groups[gi].level)
        var parent_open = true
        if level > 0usize { parent_open = chain[level - 1usize] }
        if parent_open {
            g.visible[out] = u32(gi) | HEADER_BIT
            out += 1usize
            chain[level] = g.groups[gi].expanded
        } else {
            chain[level] = false
        }
        if level + 1usize == g.level_count && chain[level] {
            var p = usize(g.groups[gi].first)
            let end = p + usize(g.groups[gi].count)
            while p < end {
                g.visible[out] = u32(p)
                out += 1usize
                p += 1usize
            }
        }
        gi += 1usize
    }
    g.visible_total = out
}

// Entries of the visible list: a group header or a data row.
fn visible_len(g: *const Grouping) -> usize { ret g.visible_total }

fn visible_is_group(g: *const Grouping, position: usize) -> bool { ret (g.visible[position] & HEADER_BIT) != 0u32 }

// The group index of a header entry.
fn visible_group(g: *const Grouping, position: usize) -> usize { ret usize(g.visible[position] & (HEADER_BIT - 1u32)) }

// The storage row of a data entry.
fn visible_row(g: *const Grouping, position: usize) -> usize { ret usize(g.order[usize(g.visible[position])]) }

fn group_len(g: *const Grouping) -> usize { ret g.group_total }

fn row_count(g: *const Grouping) -> usize { ret g.total_rows }

// The storage row at a position of the grouped order.
fn row_at(g: *const Grouping, position: usize) -> usize { ret usize(g.order[position]) }

// ---- grouping --------------------------------------------------------------------

fn group_error_level(levels: []const GroupLevel, columns: usize) -> bool {
    var at = 0usize
    while at < levels.len {
        if levels[at].column >= columns { ret true }
        at += 1usize
    }
    ret false
}

// Sorts the view by `levels` then `keys`, takes its displayed rows and groups them.
fn group_by(g: *Grouping, levels: []const GroupLevel, keys: []const view.Key, scratch: *mem.Arena) -> err {
    if levels.len > MAX_LEVELS || group_error_level(levels, table.column_count(g.t)) { ret BadLevel }
    let marker = mem.mark(scratch)
    let total_keys = levels.len + keys.len
    if total_keys != 0usize {
        let (all, all_error) = mem.alloc[view.Key](scratch, total_keys)
        if all_error != ok {
            mem.reset(scratch, marker)
            ret all_error
        }
        var at = 0usize
        while at < levels.len {
            all[at] = view.column_key(levels[at].column, levels[at].descending, levels[at].fold)
            at += 1usize
        }
        at = 0usize
        while at < keys.len {
            all[levels.len + at] = keys[at]
            at += 1usize
        }
        let sort_error = view.apply_sort(g.v, all, scratch)
        if sort_error != ok {
            mem.reset(scratch, marker)
            ret sort_error
        }
    }
    mem.reset(scratch, marker)
    g.level_count = levels.len
    var at = 0usize
    while at < levels.len {
        g.levels[at] = levels[at]
        at += 1usize
    }
    ret refresh(g, scratch)
}

// Takes the view's displayed rows again (after a filter or an edit) and regroups them in
// that order; the sort is not repeated.
fn refresh(g: *Grouping, scratch: *mem.Arena) -> err {
    let shown = view.rows(g.v)
    var at = 0usize
    while at < shown.len {
        g.order[at] = shown[at]
        at += 1usize
    }
    g.total_rows = shown.len
    ret regroup(g, scratch)
}

fn regroup(g: *Grouping, scratch: *mem.Arena) -> err {
    g.group_total = 0usize
    if g.level_count == 0usize {
        build_visible(g)
        ret ok
    }
    var keys: [4]LevelKey = zero
    var level = 0usize
    while level < g.level_count {
        let column = g.levels[level].column
        keys[level] = LevelKey { column: column, kind: table.column_kind(g.t, column), fold: g.levels[level].fold, ranks: zero }
        if keys[level].kind == table.Kind.Dict && keys[level].fold {
            let (rank_slice, rank_error) = table.ranks(g.t, column, scratch)
            if rank_error != ok { ret rank_error }
            keys[level].ranks = rank_slice
        }
        level += 1usize
    }
    var open: [4]u32 = zero
    var paths: [4]u64 = zero
    var i = 0usize
    while i < g.total_rows {
        let row = usize(g.order[i])
        var diff = 0usize
        if i > 0usize {
            diff = g.level_count
            let previous = usize(g.order[i - 1usize])
            level = 0usize
            while level < g.level_count {
                if !same_key(g.t, &keys[level], previous, row) {
                    diff = level
                    break
                }
                level += 1usize
            }
        }
        if diff < g.level_count {
            if i > 0usize {
                level = diff
                while level < g.level_count {
                    let closing = &g.groups[usize(open[level])]
                    closing.count = u32(i) - closing.first
                    level += 1usize
                }
            }
            level = diff
            while level < g.level_count {
                if g.group_total >= g.groups.len { ret TooManyGroups }
                var parent = NO_GROUP
                var base = 1469598103934665603u64
                if level > 0usize {
                    parent = open[level - 1usize]
                    base = paths[level - 1usize]
                }
                let path = mix(base ^ (key_hash(g.t, &keys[level], row) + u64(level) * 2654435761u64))
                paths[level] = path
                g.groups[g.group_total] = Group { level: u32(level), first: u32(i), count: 0u32, parent: parent, key_row: u32(row), path: path, expanded: path_expanded(g, path) }
                open[level] = u32(g.group_total)
                g.group_total += 1usize
                level += 1usize
            }
        }
        i += 1usize
    }
    if g.total_rows > 0usize {
        level = 0usize
        while level < g.level_count {
            let closing = &g.groups[usize(open[level])]
            closing.count = u32(g.total_rows) - closing.first
            level += 1usize
        }
    }
    build_visible(g)
    ret ok
}

// ---- group accessors -------------------------------------------------------------

fn group_level(g: *const Grouping, group: usize) -> usize { ret usize(g.groups[group].level) }
fn group_first(g: *const Grouping, group: usize) -> usize { ret usize(g.groups[group].first) }
fn group_count(g: *const Grouping, group: usize) -> usize { ret usize(g.groups[group].count) }

// The index of the parent group, or false at the top level.
fn group_parent(g: *const Grouping, group: usize) -> (usize, bool) {
    let p = g.groups[group].parent
    if p == NO_GROUP { ret (0usize, false) }
    ret (usize(p), true)
}

// A storage row whose cell in the group's column is the group's key (to read the key's text).
fn group_key_row(g: *const Grouping, group: usize) -> usize { ret usize(g.groups[group].key_row) }

// ---- summaries -------------------------------------------------------------------

fn cell_number(t: *const table.Table, column: usize, kind: table.Kind, row: usize) -> f64 {
    if kind == table.Kind.I32 { ret f64(table.get_i32(t, column, row)) }
    if kind == table.Kind.I64 { ret f64(table.get_i64(t, column, row)) }
    if kind == table.Kind.F64 { ret table.get_f64(t, column, row) }
    if kind == table.Kind.Bool {
        if table.get_bool(t, column, row) { ret 1.0f64 }
        ret 0.0f64
    }
    ret 0.0f64
}

fn accumulate(g: *const Grouping, column: usize, first: usize, count: usize) -> Summary {
    var s = Summary { rows: count, values: 0usize, sum: 0.0f64, min: 0.0f64, max: 0.0f64 }
    let kind = table.column_kind(g.t, column)
    let numeric = kind != table.Kind.Str && kind != table.Kind.Dict
    var p = first
    let end = first + count
    while p < end {
        let row = usize(g.order[p])
        if !table.is_null(g.t, column, row) {
            s.values += 1usize
            if numeric {
                let x = cell_number(g.t, column, kind, row)
                s.sum += x
                if s.values == 1usize || x < s.min { s.min = x }
                if s.values == 1usize || x > s.max { s.max = x }
            }
        }
        p += 1usize
    }
    ret s
}

fn fill_summaries(g: *Grouping) {
    let per = g.specs.len
    var gi = 0usize
    while gi < g.group_total {
        var si = 0usize
        while si < per {
            g.sums[gi * per + si] = accumulate(g, g.specs[si].column, usize(g.groups[gi].first), usize(g.groups[gi].count))
            si += 1usize
        }
        gi += 1usize
    }
    var si = 0usize
    while si < per {
        g.sums[g.group_total * per + si] = accumulate(g, g.specs[si].column, 0usize, g.total_rows)
        si += 1usize
    }
}

// Computes the summaries of every group and of the footer; the result storage comes from
// `store`, which the caller keeps until it applies summaries again.
fn apply_summaries(g: *Grouping, specs: []const SummarySpec, store: *mem.Arena) -> err {
    var at = 0usize
    while at < specs.len {
        if specs[at].column >= table.column_count(g.t) { ret BadLevel }
        at += 1usize
    }
    if specs.len == 0usize {
        g.specs = g.specs[0usize..0usize]
        g.sums = g.sums[0usize..0usize]
        ret ok
    }
    let (copied, copied_error) = mem.alloc[SummarySpec](store, specs.len)
    if copied_error != ok { ret copied_error }
    at = 0usize
    while at < specs.len {
        copied[at] = specs[at]
        at += 1usize
    }
    let (sums, sums_error) = mem.alloc[Summary](store, (g.group_total + 1usize) * specs.len)
    if sums_error != ok { ret sums_error }
    g.specs = copied
    g.sums = sums
    fill_summaries(g)
    ret ok
}

fn group_summary(g: *const Grouping, group: usize, spec: usize) -> Summary { ret g.sums[group * g.specs.len + spec] }

fn footer_summary(g: *const Grouping, spec: usize) -> Summary { ret g.sums[g.group_total * g.specs.len + spec] }

fn summary_value(s: Summary, kind: SummaryKind) -> f64 {
    if kind == SummaryKind.Rows { ret f64(s.rows) }
    if kind == SummaryKind.Values { ret f64(s.values) }
    if kind == SummaryKind.Sum { ret s.sum }
    if kind == SummaryKind.Min { ret s.min }
    if kind == SummaryKind.Max { ret s.max }
    if s.values == 0usize { ret 0.0f64 }
    ret s.sum / f64(s.values)
}

// ---- ordering groups by a summary ------------------------------------------------

type SiblingCtx = struct { g: *const Grouping, spec: usize, kind: SummaryKind, descending: bool }

fn compare_siblings(c: *SiblingCtx, x: u32, y: u32) -> i32 {
    let vx = summary_value(group_summary(c.g, usize(x), c.spec), c.kind)
    let vy = summary_value(group_summary(c.g, usize(y), c.spec), c.kind)
    var answer = 0i32
    if vx < vy { answer = -1i32 }
    if vx > vy { answer = 1i32 }
    if c.descending { ret 0i32 - answer }
    ret answer
}

// Reorders the groups of `level` (within each parent) by one of the applied summaries,
// ties keeping their order; the rows move with their groups. The summaries stay valid.
fn sort_groups_by_summary(g: *Grouping, level: usize, spec: usize, kind: SummaryKind, descending: bool, scratch: *mem.Arena) -> err {
    if level >= g.level_count || spec >= g.specs.len { ret BadLevel }
    let marker = mem.mark(scratch)
    // the groups of the level, in display order
    var found = 0usize
    var gi = 0usize
    while gi < g.group_total {
        if usize(g.groups[gi].level) == level { found += 1usize }
        gi += 1usize
    }
    if found < 2usize {
        mem.reset(scratch, marker)
        ret ok
    }
    let (list, list_error) = mem.alloc[u32](scratch, found)
    if list_error != ok {
        mem.reset(scratch, marker)
        ret list_error
    }
    var at = 0usize
    gi = 0usize
    while gi < g.group_total {
        if usize(g.groups[gi].level) == level {
            list[at] = u32(gi)
            at += 1usize
        }
        gi += 1usize
    }
    // rows start as they are; each run of siblings is rewritten in its new order
    var p = 0usize
    while p < g.total_rows {
        g.spare[p] = g.order[p]
        p += 1usize
    }
    var ctx = SiblingCtx { g: g, spec: spec, kind: kind, descending: descending }
    var start = 0usize
    while start < found {
        var stop = start + 1usize
        while stop < found && g.groups[usize(list[stop])].parent == g.groups[usize(list[start])].parent { stop += 1usize }
        let run_first = usize(g.groups[usize(list[start])].first)
        let run = list[start..stop]
        let sort_error = sort.stable_in_place_by[u32, SiblingCtx](scratch, run, &ctx, compare_siblings)
        if sort_error != ok {
            mem.reset(scratch, marker)
            ret sort_error
        }
        var dst = run_first
        var k = 0usize
        while k < run.len {
            let src_first = usize(g.groups[usize(run[k])].first)
            let src_count = usize(g.groups[usize(run[k])].count)
            var j = 0usize
            while j < src_count {
                g.spare[dst + j] = g.order[src_first + j]
                j += 1usize
            }
            dst += src_count
            k += 1usize
        }
        start = stop
    }
    mem.reset(scratch, marker)
    let held = g.order
    g.order = g.spare
    g.spare = held
    // the sums are indexed by the old group numbers: keep their values by key
    let old_total = g.group_total
    let per = g.specs.len
    let regroup_error = regroup_keep_sums(g, old_total, per, scratch)
    ret regroup_error
}

// Regroups after a block move and recomputes the summaries into the same storage.
fn regroup_keep_sums(g: *Grouping, old_total: usize, per: usize, scratch: *mem.Arena) -> err {
    try regroup(g, scratch)
    if per != 0usize && g.group_total == old_total { fill_summaries(g) }
    ret ok
}
