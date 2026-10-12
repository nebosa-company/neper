// `e.data.tablesearch` over a 150,000-row table and view: the incremental search (begins
// with and within, folded and exact, forward and backward, with and without wrap, over a
// sorted and filtered order) enumerated against a brute-force scan, and the distinct-value
// list (counts, fold order, merged case variants, nulls, only the filtered rows) against a
// per-entry count. Every check has its own exit code.
use e.os
use e.mem
use e.data.table as table
use e.data.tableview as view
use e.data.tablesearch as srch

const ROWS: usize = 150000usize
const C_ID: usize = 0usize
const C_TYPE: usize = 1usize
const C_NAME: usize = 2usize
const C_RARITY: usize = 3usize

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

fn type_of(row: usize) -> str {
    let p = mix(u64(row) + 3u64) % 12u64
    if p == 0u64 { ret "Creature - Dragon" }
    if p == 1u64 { ret "creature - elf" }
    if p == 2u64 { ret "Legendary Creature - Human Wizard" }
    if p == 3u64 { ret "Instant" }
    if p == 4u64 { ret "INSTANT" }
    if p == 5u64 { ret "Sorcery" }
    if p == 6u64 { ret "Artifact Creature - Golem" }
    if p == 7u64 { ret "Enchantment" }
    if p == 8u64 { ret "Land" }
    if p == 9u64 { ret "Artifact" }
    if p == 10u64 { ret "Tribal Instant - Goblin" }
    ret "Dragon Egg"
}

fn rarity_of(row: usize) -> str {
    let p = mix(u64(row) + 9u64) % 5u64
    if p == 0u64 { ret "Common" }
    if p == 1u64 { ret "Uncommon" }
    if p == 2u64 { ret "Rare" }
    if p == 3u64 { ret "rare" }
    ret "Mythic"
}

fn build(a: *mem.Arena) -> table.Table {
    var spec: [4]table.Spec = zero
    spec[C_ID] = table.Spec { name: "id", kind: table.Kind.I64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_TYPE] = table.Spec { name: "type", kind: table.Kind.Dict, heap_bytes: 1024usize, dict_cap: 32usize }
    spec[C_NAME] = table.Spec { name: "name", kind: table.Kind.Str, heap_bytes: 4000000usize, dict_cap: 0usize }
    spec[C_RARITY] = table.Spec { name: "rarity", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 16usize }
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
        if row % 17usize != 0usize {
            if table.set_str(&t, C_TYPE, row, type_of(row)) != ok { os.exit(3) }
        }
        var first = 110u8
        if mix(u64(row) + 4u64) % 2u64 == 1u64 { first = 78u8 }
        buf[0usize] = first
        let n = 1usize + digits(buf[1usize..], mix(u64(row) + 5u64) % 30000u64)
        if row % 19usize != 0usize {
            if table.set_str(&t, C_NAME, row, buf[0usize..n]) != ok { os.exit(4) }
        }
        if table.set_str(&t, C_RARITY, row, rarity_of(row)) != ok { os.exit(5) }
        row += 1usize
    }
    table.end_load(&t)
    ret t
}

// ---- reference -----------------------------------------------------------------------

fn up(b: u8) -> u8 {
    if b >= 97u8 && b <= 122u8 { ret b - 32u8 }
    ret b
}

fn eq_byte(a: u8, b: u8, fold: bool) -> bool {
    if fold { ret up(a) == up(b) }
    ret a == b
}

// begins with / contains, by a plain double loop
fn ref_text(s: str, text: str, begins: bool, fold: bool) -> bool {
    if text.len > s.len { ret false }
    var start = 0usize
    while start + text.len <= s.len {
        var all = true
        var k = 0usize
        while k < text.len {
            if !eq_byte(s[start + k], text[k], fold) { all = false }
            k += 1usize
        }
        if all { ret true }
        if begins { ret false }
        start += 1usize
    }
    ret false
}

fn ref_row(t: *const table.Table, column: usize, row: usize, text: str, begins: bool, fold: bool) -> bool {
    if table.is_null(t, column, row) { ret false }
    ret ref_text(table.get_str(t, column, row), text, begins, fold)
}

// All matching positions of `rows`, in order; returns the count (positions stored up to out.len).
fn ref_positions(t: *const table.Table, rows: []const u32, column: usize, text: str, begins: bool, fold: bool, out: []usize) -> usize {
    var n = 0usize
    var at = 0usize
    while at < rows.len {
        if ref_row(t, column, usize(rows[at]), text, begins, fold) {
            if n < out.len { out[n] = at }
            n += 1usize
        }
        at += 1usize
    }
    ret n
}

fn mode_of(begins: bool) -> srch.Mode {
    if begins { ret srch.Mode.Begins }
    ret srch.Mode.Within
}

// Forward enumeration with find equals the reference list; backward equals its reverse; and
// wrapping behaves.
fn check_query(t: *table.Table, v: *view.View, rows: []const u32, column: usize, text: str, begins: bool, fold: bool, positions: []usize, a: *mem.Arena, code: i32) -> usize {
    let n = ref_positions(t, rows, column, text, begins, fold, positions)
    if n > positions.len { os.exit(code) }
    // forward, no wrap, from 0
    var next = 0usize
    var seen = 0usize
    var more = true
    while more {
        let (at, found, e) = srch.find(v, rows, column, text, mode_of(begins), fold, next, true, false, a)
        if e != ok { os.exit(code + 1) }
        if !found {
            more = false
        } else {
            if seen >= n || at != positions[seen] { os.exit(code + 2) }
            seen += 1usize
            next = at + 1usize
            if next >= rows.len { more = false }
        }
    }
    if seen != n { os.exit(code + 3) }
    // backward, no wrap, from the end
    var prev = rows.len - 1usize
    seen = 0usize
    more = true
    while more {
        let (at, found, e) = srch.find(v, rows, column, text, mode_of(begins), fold, prev, false, false, a)
        if e != ok { os.exit(code + 4) }
        if !found {
            more = false
        } else {
            if seen >= n || at != positions[n - 1usize - seen] { os.exit(code + 5) }
            seen += 1usize
            if at == 0usize { more = false } else { prev = at - 1usize }
        }
    }
    if seen != n { os.exit(code + 6) }
    if n > 0usize {
        // wrap: past the last match, forward, finds the first; backward from before the first finds the last
        let last = positions[n - 1usize]
        let first = positions[0usize]
        let (w1, f1, e1) = srch.find(v, rows, column, text, mode_of(begins), fold, last + 1usize, true, true, a)
        if e1 != ok || !f1 || w1 != first { os.exit(code + 7) }
        let (_, g1, e2) = srch.find(v, rows, column, text, mode_of(begins), fold, last + 1usize, true, false, a)
        if e2 != ok || g1 { os.exit(code + 8) }
        var back_from = 0usize
        if first > 0usize { back_from = first - 1usize }
        if first > 0usize {
            let (w2, f2, e3) = srch.find(v, rows, column, text, mode_of(begins), fold, back_from, false, true, a)
            if e3 != ok || !f2 || w2 != last { os.exit(code + 9) }
        }
    }
    ret n
}

fn check_dict(t: *table.Table, v: *view.View, rows: []const u32, positions: []usize, a: *mem.Arena, base: i32) {
    let folded = check_query(t, v, rows, C_TYPE, "creature", true, true, positions, a, base)
    let exact = check_query(t, v, rows, C_TYPE, "creature", true, false, positions, a, base + 20)
    if folded == 0usize || exact >= folded || exact == 0usize { os.exit(base + 40) }
    let within = check_query(t, v, rows, C_TYPE, "dragon", false, true, positions, a, base + 50)
    if within == 0usize { os.exit(base + 70) }
    let _ = check_query(t, v, rows, C_TYPE, "- goblin", false, true, positions, a, base + 80)
    let _ = check_query(t, v, rows, C_TYPE, "ARTIFACT", true, true, positions, a, base + 100)
    let _ = check_query(t, v, rows, C_TYPE, "zzz", false, true, positions, a, base + 120)
    // the empty text matches every non-null cell
    let all = check_query(t, v, rows, C_TYPE, "", true, true, positions, a, base + 140)
    var non_null = 0usize
    var at = 0usize
    while at < rows.len {
        if !table.is_null(t, C_TYPE, usize(rows[at])) { non_null += 1usize }
        at += 1usize
    }
    if all != non_null { os.exit(base + 160) }
}

fn check_str(t: *table.Table, v: *view.View, rows: []const u32, positions: []usize, a: *mem.Arena, base: i32) {
    let folded = check_query(t, v, rows, C_NAME, "n1", true, true, positions, a, base)
    let exact = check_query(t, v, rows, C_NAME, "n1", true, false, positions, a, base + 20)
    if folded == 0usize || exact >= folded { os.exit(base + 40) }
    let _ = check_query(t, v, rows, C_NAME, "99", false, true, positions, a, base + 50)
    let _ = check_query(t, v, rows, C_NAME, "N29", true, false, positions, a, base + 80)
}

fn check_refusals(t: *table.Table, v: *view.View, rows: []const u32, a: *mem.Arena) {
    let (_, f1, e1) = srch.find(v, rows, C_ID, "1", srch.Mode.Begins, true, 0usize, true, false, a)
    if e1 != srch.BadColumn || f1 { os.exit(500) }
    let (_, f2, e2) = srch.find(v, rows, 99usize, "1", srch.Mode.Begins, true, 0usize, true, false, a)
    if e2 != srch.BadColumn || f2 { os.exit(501) }
    var out: [4]srch.Value = zero
    let (_, _, e3) = srch.value_list(v, C_NAME, rows, true, out[0..], a)
    if e3 != srch.BadColumn { os.exit(502) }
    // out of range start without wrap is not found; with wrap it searches
    let (_, f4, e4) = srch.find(v, rows, C_TYPE, "land", srch.Mode.Begins, true, rows.len + 5usize, true, false, a)
    if e4 != ok || f4 { os.exit(503) }
    let (_, f5, e5) = srch.find(v, rows, C_TYPE, "land", srch.Mode.Begins, true, rows.len + 5usize, true, true, a)
    if e5 != ok || !f5 { os.exit(504) }
}

// ---- value lists ---------------------------------------------------------------------

fn bytes_same(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}

fn check_values(t: *table.Table, v: *view.View, rows: []const u32, column: usize, a: *mem.Arena, base: i32) -> usize {
    var out: [64]srch.Value = zero
    let (count, nulls, e) = srch.value_list(v, column, rows, false, out[0..], a)
    if e != ok { os.exit(base) }
    // reference: nulls, and for each listed value the exact count by comparing strings
    var ref_nulls = 0usize
    var at = 0usize
    while at < rows.len {
        if table.is_null(t, column, usize(rows[at])) { ref_nulls += 1usize }
        at += 1usize
    }
    if nulls != ref_nulls { os.exit(base + 1) }
    var total = 0usize
    var i = 0usize
    while i < count {
        let name = table.dict_str(t, column, out[i].id)
        var n = 0usize
        at = 0usize
        while at < rows.len {
            let row = usize(rows[at])
            if !table.is_null(t, column, row) && bytes_same(table.get_str(t, column, row), name) { n += 1usize }
            at += 1usize
        }
        if n != usize(out[i].count) || n == 0usize { os.exit(base + 2) }
        total += n
        // fold order: each value is not after the next
        if i + 1usize < count && table.compare_fold(name, table.dict_str(t, column, out[i + 1usize].id)) > 0i32 { os.exit(base + 3) }
        i += 1usize
    }
    if total + nulls != rows.len { os.exit(base + 4) }
    // merged case variants: fewer entries, the same total, fold-distinct neighbours
    var merged: [64]srch.Value = zero
    let (mcount, mnulls, me) = srch.value_list(v, column, rows, true, merged[0..], a)
    if me != ok || mnulls != nulls { os.exit(base + 5) }
    var mtotal = 0usize
    i = 0usize
    while i < mcount {
        mtotal += usize(merged[i].count)
        if i + 1usize < mcount && table.compare_fold(table.dict_str(t, column, merged[i].id), table.dict_str(t, column, merged[i + 1usize].id)) == 0i32 { os.exit(base + 6) }
        i += 1usize
    }
    if mtotal != total || mcount > count { os.exit(base + 7) }
    // too small an output
    var tiny: [1]srch.Value = zero
    if count > 1usize {
        let (_, _, te) = srch.value_list(v, column, rows, false, tiny[0..], a)
        if te != srch.TooSmall { os.exit(base + 8) }
    }
    ret count
}

fn main(a: *mem.Arena, args: []str) -> err {
    var t = build(a)
    let (made, made_error) = view.create(a, &t)
    if made_error != ok { os.exit(10) }
    var v = made
    let (positions, positions_error) = mem.alloc[usize](a, ROWS)
    if positions_error != ok { os.exit(11) }
    // sorted by type (rows in a non-row order), unfiltered
    var key: [1]view.Key = zero
    key[0usize] = view.column_key(C_TYPE, false, true)
    if view.apply_sort(&v, key[0..], a) != ok { os.exit(12) }
    check_dict(&t, &v, view.rows(&v), positions, a, 100)
    check_str(&t, &v, view.rows(&v), positions, a, 400)
    check_refusals(&t, &v, view.rows(&v), a)
    let full = check_values(&t, &v, view.rows(&v), C_TYPE, a, 600)
    let rarities = check_values(&t, &v, view.rows(&v), C_RARITY, a, 620)
    if rarities != 5usize || full < 10usize { os.exit(640) }
    // filtered: rarity Rare (folded: Rare and rare), then search and list the shown rows only
    var nodes: [1]view.Node = zero
    nodes[0usize] = view.leaf_node(C_RARITY, view.Op.Eq, view.text_operand("rare"))
    if view.apply_filter(&v, nodes[0..], false, a) != ok { os.exit(13) }
    check_dict(&t, &v, view.rows(&v), positions, a, 700)
    let narrowed = check_values(&t, &v, view.rows(&v), C_RARITY, a, 900)
    if narrowed != 2usize { os.exit(920) }
    let narrowed_merged = check_values(&t, &v, view.rows(&v), C_TYPE, a, 930)
    if narrowed_merged == 0usize { os.exit(950) }
    os.exit(0)
    ret ok
}
