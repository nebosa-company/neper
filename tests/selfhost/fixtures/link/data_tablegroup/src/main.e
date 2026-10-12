// `e.data.tablegroup`: grouping and summaries over a 150,000-row `e.data.tableview`, each
// result checked against an independent reference: group boundaries recomputed by comparing
// neighbouring rows with plain cell equality (folded text, no ranks), summaries by looping the
// reference ranges, the visible list by walking the reference groups. One, two and three
// levels, folded and exact text, null keys, expansion by path surviving a re-sort and a
// re-filter, expand all, summaries (rows, values, sum, min, max, avg) with nulls, groups
// ordered by a summary at two levels, refusals. Every check has its own exit code.
use e.os
use e.mem
use e.data.table as table
use e.data.tableview as view
use e.data.tablegroup as grp

const ROWS: usize = 150000usize
const C_ID: usize = 0usize
const C_CMC: usize = 1usize
const C_PRICE: usize = 2usize
const C_RARITY: usize = 3usize
const C_EDITION: usize = 4usize
const C_NAME: usize = 5usize
const C_FLAG: usize = 6usize

fn mix(x: u64) -> u64 {
    var v = x *% 6364136223846793005u64 +% 1442695040888963407u64
    v = v ^ (v >> 29u64)
    v = v *% 6364136223846793005u64
    ret v ^ (v >> 32u64)
}

fn digits(buf: []u8, n: u64) -> usize {
    var tmp: [20]u8 = zero
    var count = 0usize
    var v = n
    if v == 0u64 {
        buf[0usize] = 48u8
        ret 1usize
    }
    while v > 0u64 {
        tmp[count] = 48u8 + u8(v % 10u64)
        v = v / 10u64
        count += 1usize
    }
    var at = 0usize
    while at < count {
        buf[at] = tmp[count - 1usize - at]
        at += 1usize
    }
    ret count
}

fn rarity_of(row: usize) -> str {
    let p = mix(u64(row) + 9u64) % 7u64
    if p == 0u64 { ret "Common" }
    if p == 1u64 { ret "common" }
    if p == 2u64 { ret "Uncommon" }
    if p == 3u64 { ret "Rare" }
    if p == 4u64 { ret "rare" }
    if p == 5u64 { ret "Mythic" }
    ret "COMMON"
}

fn build(a: *mem.Arena) -> table.Table {
    var spec: [7]table.Spec = zero
    spec[C_ID] = table.Spec { name: "id", kind: table.Kind.I64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_CMC] = table.Spec { name: "cmc", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_PRICE] = table.Spec { name: "price", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_RARITY] = table.Spec { name: "rarity", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 16usize }
    spec[C_EDITION] = table.Spec { name: "edition", kind: table.Kind.Dict, heap_bytes: 4096usize, dict_cap: 64usize }
    spec[C_NAME] = table.Spec { name: "name", kind: table.Kind.Str, heap_bytes: 4000000usize, dict_cap: 0usize }
    spec[C_FLAG] = table.Spec { name: "flag", kind: table.Kind.Bool, heap_bytes: 0usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { os.exit(1) }
    var t = made
    table.begin_load(&t)
    var buf: [64]u8 = zero
    var row = 0usize
    while row < ROWS {
        let (got, append_error) = table.append_row(&t)
        if append_error != ok || got != row { os.exit(2) }
        table.set_i64(&t, C_ID, row, i64(row))
        if row % 9usize != 0usize { table.set_i32(&t, C_CMC, row, i32(mix(u64(row) + 1u64) % 8u64)) }
        if row % 11usize != 0usize { table.set_f64(&t, C_PRICE, row, f64(mix(u64(row) + 2u64) % 5001u64) / 4.0f64 - 250.0f64) }
        if row % 13usize != 0usize {
            if table.set_str(&t, C_RARITY, row, rarity_of(row)) != ok { os.exit(3) }
        }
        buf[0usize] = 69u8
        buf[1usize] = 48u8 + u8(mix(u64(row) + 3u64) % 10u64)
        buf[2usize] = 48u8 + u8(mix(u64(row) + 33u64) % 3u64)
        if table.set_str(&t, C_EDITION, row, buf[0usize..3usize]) != ok { os.exit(4) }
        var first = 110u8
        if mix(u64(row) + 4u64) % 2u64 == 1u64 { first = 78u8 }
        buf[0usize] = first
        let n = 1usize + digits(buf[1usize..], mix(u64(row) + 5u64) % 3000u64)
        if table.set_str(&t, C_NAME, row, buf[0usize..n]) != ok { os.exit(5) }
        table.set_bool(&t, C_FLAG, row, mix(u64(row) + 6u64) % 3u64 == 0u64)
        row += 1usize
    }
    table.end_load(&t)
    ret t
}

// ---- independent reference -----------------------------------------------------------

fn up(b: u8) -> u8 {
    if b >= 97u8 && b <= 122u8 { ret b - 32u8 }
    ret b
}

fn text_equal(x: str, y: str, fold: bool) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        var p = x[at]
        var q = y[at]
        if fold {
            p = up(p)
            q = up(q)
        }
        if p != q { ret false }
        at += 1usize
    }
    ret true
}

fn cell_equal(t: *const table.Table, col: usize, a: usize, b: usize, fold: bool) -> bool {
    let an = table.is_null(t, col, a)
    let bn = table.is_null(t, col, b)
    if an || bn { ret an && bn }
    let kind = table.column_kind(t, col)
    if kind == table.Kind.I32 { ret table.get_i32(t, col, a) == table.get_i32(t, col, b) }
    if kind == table.Kind.I64 { ret table.get_i64(t, col, a) == table.get_i64(t, col, b) }
    if kind == table.Kind.F64 { ret table.get_f64(t, col, a) == table.get_f64(t, col, b) }
    if kind == table.Kind.Bool { ret table.get_bool(t, col, a) == table.get_bool(t, col, b) }
    ret text_equal(table.get_str(t, col, a), table.get_str(t, col, b), fold)
}

// The reference groups of the grouped order of `g`.
type RefGroup = struct { level: usize, first: usize, count: usize }

fn reference_groups(t: *const table.Table, g: *const grp.Grouping, levels: []const grp.GroupLevel, out: []RefGroup) -> usize {
    var count_groups = 0usize
    let n = grp.row_count(g)
    var level = 0usize
    var open: [4]usize = zero
    var i = 0usize
    while i < n {
        let row = grp.row_at(g, i)
        var diff = 0usize
        if i > 0usize {
            diff = levels.len
            level = 0usize
            while level < levels.len {
                if !cell_equal(t, levels[level].column, grp.row_at(g, i - 1usize), row, levels[level].fold) {
                    diff = level
                    break
                }
                level += 1usize
            }
        }
        level = diff
        while level < levels.len {
            if i > 0usize && level >= diff && level < levels.len {
                // close the open group of this level
                if open[level] < count_groups { out[open[level]].count = i - out[open[level]].first }
            }
            level += 1usize
        }
        level = diff
        while level < levels.len {
            out[count_groups] = RefGroup { level: level, first: i, count: 0usize }
            open[level] = count_groups
            count_groups += 1usize
            level += 1usize
        }
        i += 1usize
    }
    level = 0usize
    while n > 0usize && level < levels.len {
        out[open[level]].count = n - out[open[level]].first
        level += 1usize
    }
    ret count_groups
}

// The grouped order is sorted by the levels, the groups are the reference groups, and the
// key row of every group has the key of its rows.
fn verify_groups(t: *const table.Table, g: *const grp.Grouping, levels: []const grp.GroupLevel, expected_rows: usize, scratch: []RefGroup, code: i32) -> usize {
    if grp.row_count(g) != expected_rows { os.exit(code) }
    let count_groups = reference_groups(t, g, levels, scratch)
    if grp.group_len(g) != count_groups { os.exit(code + 1) }
    var gi = 0usize
    while gi < count_groups {
        if grp.group_level(g, gi) != scratch[gi].level || grp.group_first(g, gi) != scratch[gi].first || grp.group_count(g, gi) != scratch[gi].count { os.exit(code + 2) }
        let (parent, has_parent) = grp.group_parent(g, gi)
        if scratch[gi].level == 0usize {
            if has_parent { os.exit(code + 3) }
        } else {
            if !has_parent || grp.group_level(g, parent) + 1usize != scratch[gi].level { os.exit(code + 3) }
            // a child lies inside its parent
            if grp.group_first(g, gi) < grp.group_first(g, parent) || grp.group_first(g, gi) + grp.group_count(g, gi) > grp.group_first(g, parent) + grp.group_count(g, parent) { os.exit(code + 4) }
        }
        // every row of the group has the group's key at its level and above
        var p = grp.group_first(g, gi)
        let end = p + grp.group_count(g, gi)
        let key_row = grp.group_key_row(g, gi)
        while p < end {
            var l = 0usize
            while l <= scratch[gi].level {
                if !cell_equal(t, levels[l].column, key_row, grp.row_at(g, p), levels[l].fold) { os.exit(code + 5) }
                l += 1usize
            }
            p += 1usize
        }
        gi += 1usize
    }
    // the groups of the top level cover all the rows
    var covered = 0usize
    gi = 0usize
    while gi < count_groups {
        if scratch[gi].level == 0usize { covered += scratch[gi].count }
        gi += 1usize
    }
    if levels.len != 0usize && covered != expected_rows { os.exit(code + 6) }
    // adjacent groups of one level differ in key (the grouping is maximal)
    gi = 0usize
    while gi + 1usize < count_groups {
        let x = gi
        var y = gi + 1usize
        while y < count_groups && scratch[y].level > scratch[x].level { y += 1usize }
        if y < count_groups && scratch[y].level == scratch[x].level {
            var same_above = true
            var l = 0usize
            while l + 1usize < scratch[x].level + 1usize && l < scratch[x].level {
                if !cell_equal(t, levels[l].column, grp.group_key_row(g, x), grp.group_key_row(g, y), levels[l].fold) { same_above = false }
                l += 1usize
            }
            if same_above && cell_equal(t, levels[scratch[x].level].column, grp.group_key_row(g, x), grp.group_key_row(g, y), levels[scratch[x].level].fold) { os.exit(code + 7) }
        }
        gi += 1usize
    }
    ret count_groups
}

// Ordering of the grouped rows: sorted by the levels (reference compare, nulls first).
fn level_order(t: *const table.Table, level: grp.GroupLevel, x: usize, y: usize) -> i32 {
    let xn = table.is_null(t, level.column, x)
    let yn = table.is_null(t, level.column, y)
    var c = 0i32
    if xn && yn {
        c = 0i32
    } else if xn {
        c = -1i32
    } else if yn {
        c = 1i32
    } else {
        let kind = table.column_kind(t, level.column)
        if kind == table.Kind.I32 {
            let p = table.get_i32(t, level.column, x)
            let q = table.get_i32(t, level.column, y)
            if p < q { c = -1i32 }
            if p > q { c = 1i32 }
        } else if kind == table.Kind.Bool {
            let p = table.get_bool(t, level.column, x)
            let q = table.get_bool(t, level.column, y)
            if !p && q { c = -1i32 }
            if p && !q { c = 1i32 }
        } else {
            let sx = table.get_str(t, level.column, x)
            let sy = table.get_str(t, level.column, y)
            var at = 0usize
            while at < sx.len && at < sy.len && c == 0i32 {
                var p = sx[at]
                var q = sy[at]
                if level.fold {
                    p = up(p)
                    q = up(q)
                }
                if p < q { c = -1i32 }
                if p > q { c = 1i32 }
                at += 1usize
            }
            if c == 0i32 && sx.len < sy.len { c = -1i32 }
            if c == 0i32 && sx.len > sy.len { c = 1i32 }
        }
    }
    if level.descending { ret 0i32 - c }
    ret c
}

fn verify_sorted(t: *const table.Table, g: *const grp.Grouping, levels: []const grp.GroupLevel, code: i32) {
    var i = 0usize
    while i + 1usize < grp.row_count(g) {
        var l = 0usize
        var c = 0i32
        while l < levels.len && c == 0i32 {
            c = level_order(t, levels[l], grp.row_at(g, i), grp.row_at(g, i + 1usize))
            l += 1usize
        }
        if c > 0i32 { os.exit(code) }
        i += 1usize
    }
}

// ---- checks ---------------------------------------------------------------------------

fn lvl(column: usize, descending: bool, fold: bool) -> grp.GroupLevel {
    ret grp.GroupLevel { column: column, descending: descending, fold: fold }
}

fn check_levels(t: *table.Table, v: *view.View, g: *grp.Grouping, a: *mem.Arena, refs: []RefGroup) {
    var lv: [3]grp.GroupLevel = zero
    var none: [1]view.Key = zero
    // one level, folded: Common/common/COMMON are one group, nulls are their own
    lv[0usize] = lvl(C_RARITY, false, true)
    if grp.group_by(g, lv[0usize..1usize], none[0usize..0usize], a) != ok { os.exit(10) }
    verify_sorted(t, g, lv[0usize..1usize], 11)
    let folded = verify_groups(t, g, lv[0usize..1usize], ROWS, refs, 20)
    // Common, Uncommon, Rare, Mythic and the nulls
    if folded != 5usize { os.exit(30) }
    // exact: Common, common, COMMON, Rare, rare, ... are separate
    lv[0usize] = lvl(C_RARITY, false, false)
    if grp.group_by(g, lv[0usize..1usize], none[0usize..0usize], a) != ok { os.exit(31) }
    let exact = verify_groups(t, g, lv[0usize..1usize], ROWS, refs, 40)
    if exact != 8usize { os.exit(50) }
    // two levels: rarity then edition
    lv[0usize] = lvl(C_RARITY, false, true)
    lv[1usize] = lvl(C_EDITION, false, true)
    if grp.group_by(g, lv[0usize..2usize], none[0usize..0usize], a) != ok { os.exit(51) }
    verify_sorted(t, g, lv[0usize..2usize], 52)
    let two = verify_groups(t, g, lv[0usize..2usize], ROWS, refs, 60)
    if two <= folded { os.exit(70) }
    // three levels with a descending integer (nulls last) and a boolean
    lv[0usize] = lvl(C_RARITY, true, true)
    lv[1usize] = lvl(C_CMC, true, true)
    lv[2usize] = lvl(C_FLAG, false, true)
    if grp.group_by(g, lv[0usize..3usize], none[0usize..0usize], a) != ok { os.exit(71) }
    verify_sorted(t, g, lv[0usize..3usize], 72)
    let three = verify_groups(t, g, lv[0usize..3usize], ROWS, refs, 80)
    if three < 5usize * 2usize { os.exit(90) }
    // a heap string column as the key, folded: n12 and N12 group together
    lv[0usize] = lvl(C_NAME, false, true)
    if grp.group_by(g, lv[0usize..1usize], none[0usize..0usize], a) != ok { os.exit(91) }
    verify_sorted(t, g, lv[0usize..1usize], 92)
    let names = verify_groups(t, g, lv[0usize..1usize], ROWS, refs, 100)
    if names > 3000usize || names < 2000usize { os.exit(110) }
    // no levels: the visible list is the rows
    if grp.group_by(g, lv[0usize..0usize], none[0usize..0usize], a) != ok { os.exit(111) }
    if grp.group_len(g) != 0usize || grp.visible_len(g) != ROWS { os.exit(112) }
}

fn check_visible(t: *table.Table, v: *view.View, g: *grp.Grouping, a: *mem.Arena, refs: []RefGroup) {
    var lv: [2]grp.GroupLevel = zero
    var none: [1]view.Key = zero
    lv[0usize] = lvl(C_RARITY, false, true)
    lv[1usize] = lvl(C_EDITION, false, true)
    if grp.group_by(g, lv[0usize..2usize], none[0usize..0usize], a) != ok { os.exit(120) }
    let total = verify_groups(t, g, lv[0usize..2usize], ROWS, refs, 130)
    // collapsed: only the top-level headers
    var tops = 0usize
    var gi = 0usize
    while gi < total {
        if refs[gi].level == 0usize { tops += 1usize }
        gi += 1usize
    }
    if grp.visible_len(g) != tops { os.exit(140) }
    var i = 0usize
    while i < grp.visible_len(g) {
        if !grp.visible_is_group(g, i) || grp.group_level(g, grp.visible_group(g, i)) != 0usize { os.exit(141) }
        i += 1usize
    }
    // expand the second top group: its edition headers appear, still no rows
    var second = 0usize
    gi = 0usize
    var seen = 0usize
    while gi < total {
        if refs[gi].level == 0usize {
            seen += 1usize
            if seen == 2usize { second = gi }
        }
        gi += 1usize
    }
    var children = 0usize
    gi = 0usize
    while gi < total {
        let (p, has) = grp.group_parent(g, gi)
        if has && p == second { children += 1usize }
        gi += 1usize
    }
    if grp.set_expanded(g, second, true) != ok { os.exit(142) }
    if grp.visible_len(g) != tops + children { os.exit(143) }
    // expand one of its editions: its rows appear after its header
    var child = 0usize
    gi = 0usize
    while gi < total {
        let (p, has) = grp.group_parent(g, gi)
        if has && p == second {
            child = gi
            break
        }
        gi += 1usize
    }
    if grp.set_expanded(g, child, true) != ok { os.exit(144) }
    if grp.visible_len(g) != tops + children + grp.group_count(g, child) { os.exit(145) }
    // find the header of the child and check the rows after it
    var at = 0usize
    while at < grp.visible_len(g) {
        if grp.visible_is_group(g, at) && grp.visible_group(g, at) == child { break }
        at += 1usize
    }
    var k = 0usize
    while k < grp.group_count(g, child) {
        if grp.visible_is_group(g, at + 1usize + k) { os.exit(146) }
        if grp.visible_row(g, at + 1usize + k) != grp.row_at(g, grp.group_first(g, child) + k) { os.exit(147) }
        k += 1usize
    }
    // collapse the parent: the child's rows disappear with it
    if grp.set_expanded(g, second, false) != ok { os.exit(148) }
    if grp.visible_len(g) != tops { os.exit(149) }
    if grp.set_expanded(g, second, true) != ok { os.exit(150) }
    // expand all: every header and every row
    grp.set_all_expanded(g, true)
    if grp.visible_len(g) != total + ROWS { os.exit(151) }
    grp.set_all_expanded(g, false)
    if grp.visible_len(g) != tops { os.exit(152) }
}

// An expanded group stays expanded, by key, through a re-sort and a re-filter.
fn check_persistence(t: *table.Table, v: *view.View, g: *grp.Grouping, a: *mem.Arena, refs: []RefGroup) {
    var lv: [1]grp.GroupLevel = zero
    var none: [1]view.Key = zero
    lv[0usize] = lvl(C_RARITY, false, true)
    if grp.group_by(g, lv[0usize..1usize], none[0usize..0usize], a) != ok { os.exit(160) }
    grp.set_all_expanded(g, false)
    // expand the "Mythic" group
    var mythic = 0usize
    var found = false
    var gi = 0usize
    while gi < grp.group_len(g) {
        let key = table.get_str(t, C_RARITY, grp.group_key_row(g, gi))
        if text_equal(key, "mythic", true) {
            mythic = gi
            found = true
        }
        gi += 1usize
    }
    if !found { os.exit(161) }
    if grp.set_expanded(g, mythic, true) != ok { os.exit(162) }
    // re-sort by price inside the groups
    var keys: [1]view.Key = zero
    keys[0usize] = view.column_key(C_PRICE, true, true)
    if grp.group_by(g, lv[0usize..1usize], keys[0usize..1usize], a) != ok { os.exit(163) }
    var expanded_count = 0usize
    gi = 0usize
    while gi < grp.group_len(g) {
        if grp.is_expanded(g, gi) {
            expanded_count += 1usize
            if !text_equal(table.get_str(t, C_RARITY, grp.group_key_row(g, gi)), "mythic", true) { os.exit(164) }
        }
        gi += 1usize
    }
    if expanded_count != 1usize { os.exit(165) }
    // inside the group, prices descend with nulls last (a descending key reverses everything)
    gi = 0usize
    while gi < grp.group_len(g) {
        var p = grp.group_first(g, gi)
        let end = p + grp.group_count(g, gi)
        while p + 1usize < end {
            let x = grp.row_at(g, p)
            let y = grp.row_at(g, p + 1usize)
            if !table.is_null(t, C_PRICE, x) && !table.is_null(t, C_PRICE, y) && table.get_f64(t, C_PRICE, x) < table.get_f64(t, C_PRICE, y) { os.exit(166) }
            if table.is_null(t, C_PRICE, x) && !table.is_null(t, C_PRICE, y) { os.exit(167) }
            p += 1usize
        }
        gi += 1usize
    }
    // filter to one edition, refresh: the Mythic group is still expanded
    var nodes: [1]view.Node = zero
    nodes[0usize] = view.leaf_node(C_EDITION, view.Op.Begins, view.text_operand("E1"))
    if view.apply_filter(v, nodes[0..], false, a) != ok { os.exit(168) }
    if grp.refresh(g, a) != ok { os.exit(169) }
    let filtered = verify_groups(t, g, lv[0usize..1usize], view.len(v), refs, 170)
    if filtered == 0usize { os.exit(180) }
    expanded_count = 0usize
    gi = 0usize
    while gi < grp.group_len(g) {
        if grp.is_expanded(g, gi) { expanded_count += 1usize }
        gi += 1usize
    }
    if expanded_count != 1usize { os.exit(181) }
    view.clear_filter(v)
    if grp.refresh(g, a) != ok { os.exit(182) }
}

fn close_to(x: f64, y: f64) -> bool {
    var d = x - y
    if d < 0.0f64 { d = 0.0f64 - d }
    var m = y
    if m < 0.0f64 { m = 0.0f64 - m }
    ret d <= 0.000001f64 * (1.0f64 + m)
}

fn check_summaries(t: *table.Table, v: *view.View, g: *grp.Grouping, a: *mem.Arena, store: *mem.Arena, refs: []RefGroup) {
    var lv: [2]grp.GroupLevel = zero
    var none: [1]view.Key = zero
    lv[0usize] = lvl(C_RARITY, false, true)
    lv[1usize] = lvl(C_FLAG, false, true)
    if grp.group_by(g, lv[0usize..2usize], none[0usize..0usize], a) != ok { os.exit(200) }
    let total = verify_groups(t, g, lv[0usize..2usize], ROWS, refs, 210)
    var specs: [3]grp.SummarySpec = zero
    specs[0usize] = grp.SummarySpec { column: C_CMC }
    specs[1usize] = grp.SummarySpec { column: C_PRICE }
    specs[2usize] = grp.SummarySpec { column: C_RARITY }
    let mark = mem.mark(store)
    if grp.apply_summaries(g, specs[0..], store) != ok { os.exit(220) }
    // every group against a loop over its reference range
    var gi = 0usize
    while gi < total {
        var s = 0usize
        while s < 3usize {
            let want = reference_sum(t, g, specs[s].column, refs[gi].first, refs[gi].count)
            let got = grp.group_summary(g, gi, s)
            if got.rows != want.rows || got.values != want.values { os.exit(221) }
            if !close_to(got.sum, want.sum) || !close_to(got.min, want.min) || !close_to(got.max, want.max) { os.exit(222) }
            s += 1usize
        }
        gi += 1usize
    }
    let footer_cmc = grp.footer_summary(g, 0usize)
    let want_footer = reference_sum(t, g, C_CMC, 0usize, ROWS)
    if footer_cmc.rows != ROWS || footer_cmc.values != want_footer.values || !close_to(footer_cmc.sum, want_footer.sum) { os.exit(223) }
    // text columns count rows and values only
    let text_footer = grp.footer_summary(g, 2usize)
    if text_footer.rows != ROWS || text_footer.values != ROWS - (ROWS + 12usize) / 13usize { os.exit(224) }
    if !close_to(grp.summary_value(footer_cmc, grp.SummaryKind.Avg), footer_cmc.sum / f64(footer_cmc.values)) { os.exit(225) }
    // groups ordered by a summary: level 0 by price sum, descending
    var before: [16]usize = zero
    let tops = top_level_groups(g, before[0..])
    if grp.sort_groups_by_summary(g, 0usize, 1usize, grp.SummaryKind.Sum, true, a) != ok { os.exit(230) }
    if grp.group_len(g) != total { os.exit(231) }
    var last = 0.0f64
    var have_last = false
    gi = 0usize
    var seen = 0usize
    while gi < grp.group_len(g) {
        if grp.group_level(g, gi) == 0usize {
            let sum = grp.group_summary(g, gi, 1usize).sum
            if have_last && sum > last + 0.000001f64 { os.exit(232) }
            last = sum
            have_last = true
            seen += 1usize
        }
        gi += 1usize
    }
    if seen != tops { os.exit(233) }
    // the groups are still the reference groups of the (moved) rows, and still summed right
    let after_total = verify_groups(t, g, lv[0usize..2usize], ROWS, refs, 240)
    if after_total != total { os.exit(250) }
    gi = 0usize
    while gi < after_total {
        let want = reference_sum(t, g, C_PRICE, refs[gi].first, refs[gi].count)
        let got = grp.group_summary(g, gi, 1usize)
        if got.rows != want.rows || !close_to(got.sum, want.sum) { os.exit(251) }
        gi += 1usize
    }
    // level 1 by row count ascending, within each parent
    if grp.sort_groups_by_summary(g, 1usize, 0usize, grp.SummaryKind.Rows, false, a) != ok { os.exit(252) }
    gi = 0usize
    while gi + 1usize < grp.group_len(g) {
        let (px, hx) = grp.group_parent(g, gi)
        let (py, hy) = grp.group_parent(g, gi + 1usize)
        if grp.group_level(g, gi) == 1usize && grp.group_level(g, gi + 1usize) == 1usize && hx && hy && px == py {
            if grp.group_summary(g, gi, 0usize).rows > grp.group_summary(g, gi + 1usize, 0usize).rows { os.exit(253) }
        }
        gi += 1usize
    }
    let final_total = verify_groups(t, g, lv[0usize..2usize], ROWS, refs, 260)
    if final_total != total { os.exit(270) }
    mem.reset(store, mark)
}

fn top_level_groups(g: *const grp.Grouping, out: []usize) -> usize {
    var n = 0usize
    var gi = 0usize
    while gi < grp.group_len(g) {
        if grp.group_level(g, gi) == 0usize {
            if n < out.len { out[n] = gi }
            n += 1usize
        }
        gi += 1usize
    }
    ret n
}

fn reference_sum(t: *const table.Table, g: *const grp.Grouping, col: usize, first: usize, count: usize) -> grp.Summary {
    var s = grp.Summary { rows: count, values: 0usize, sum: 0.0f64, min: 0.0f64, max: 0.0f64 }
    let kind = table.column_kind(t, col)
    var p = first
    while p < first + count {
        let row = grp.row_at(g, p)
        if !table.is_null(t, col, row) {
            s.values += 1usize
            var x = 0.0f64
            if kind == table.Kind.I32 { x = f64(table.get_i32(t, col, row)) }
            if kind == table.Kind.F64 { x = table.get_f64(t, col, row) }
            s.sum += x
            if s.values == 1usize || x < s.min { s.min = x }
            if s.values == 1usize || x > s.max { s.max = x }
        }
        p += 1usize
    }
    ret s
}

fn check_refusals(t: *table.Table, v: *view.View, a: *mem.Arena, scratch: *mem.Arena) {
    var lv: [5]grp.GroupLevel = zero
    var none: [1]view.Key = zero
    var k = 0usize
    while k < 5usize {
        lv[k] = lvl(C_FLAG, false, true)
        k += 1usize
    }
    let (made, made_error) = grp.create(a, v, 3usize)
    if made_error != ok { os.exit(300) }
    var small = made
    // five levels: refused; a column out of range: refused
    if grp.group_by(&small, lv[0..5], none[0usize..0usize], scratch) != grp.BadLevel { os.exit(301) }
    lv[0usize] = lvl(99usize, false, true)
    if grp.group_by(&small, lv[0usize..1usize], none[0usize..0usize], scratch) != grp.BadLevel { os.exit(302) }
    // a group capacity of 3 cannot hold the rarity groups of the heap name column
    lv[0usize] = lvl(C_NAME, false, true)
    if grp.group_by(&small, lv[0usize..1usize], none[0usize..0usize], scratch) != grp.TooManyGroups { os.exit(303) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var t = build(a)
    let (made_view, view_error) = view.create(a, &t)
    if view_error != ok { os.exit(10) }
    var v = made_view
    let (made_group, group_error) = grp.create(a, &v, 160000usize)
    if group_error != ok { os.exit(11) }
    var g = made_group
    let (refs, refs_error) = mem.alloc[RefGroup](a, 160000usize)
    if refs_error != ok { os.exit(12) }
    let (store_bytes, store_error) = mem.alloc[u8](a, 33554432usize)
    if store_error != ok { os.exit(13) }
    var store = mem.arena_from(store_bytes)
    check_levels(&t, &v, &g, a, refs)
    check_visible(&t, &v, &g, a, refs)
    check_persistence(&t, &v, &g, a, refs)
    check_summaries(&t, &v, &g, a, &store, refs)
    check_refusals(&t, &v, a, a)
    os.exit(0)
    ret ok
}
