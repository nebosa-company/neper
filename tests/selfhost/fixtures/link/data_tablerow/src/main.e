// `e.data.tableview` single-row maintenance over a 150,000-row table: after one cell is
// edited, `reposition` puts the row where a full `apply_sort` would have (checked against that
// full sort, key set by key set: a nullable integer both ways, a float, a folded and an exact
// dictionary that grows, a heap string, three keys, a key function and a comparer), and
// `refilter_row` makes the row enter or leave a filtered view the way `apply_filter` would.
// Every check has its own exit code.
use e.os
use e.mem
use e.data.table as table
use e.data.tableview as view

const ROWS: usize = 150000usize
const C_CMC: usize = 0usize
const C_PRICE: usize = 1usize
const C_RARITY: usize = 2usize
const C_NAME: usize = 3usize

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
    let p = mix(u64(row) + 9u64) % 6u64
    if p == 0u64 { ret "Common" }
    if p == 1u64 { ret "common" }
    if p == 2u64 { ret "Uncommon" }
    if p == 3u64 { ret "Rare" }
    if p == 4u64 { ret "rare" }
    ret "Mythic"
}

fn build(a: *mem.Arena) -> table.Table {
    var spec: [4]table.Spec = zero
    spec[C_CMC] = table.Spec { name: "cmc", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_PRICE] = table.Spec { name: "price", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_RARITY] = table.Spec { name: "rarity", kind: table.Kind.Dict, heap_bytes: 1024usize, dict_cap: 64usize }
    spec[C_NAME] = table.Spec { name: "name", kind: table.Kind.Str, heap_bytes: 6000000usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { os.exit(1) }
    var t = made
    table.begin_load(&t)
    var buf: [64]u8 = zero
    var row = 0usize
    while row < ROWS {
        let (got, append_error) = table.append_row(&t)
        if append_error != ok || got != row { os.exit(2) }
        if row % 9usize != 0usize { table.set_i32(&t, C_CMC, row, i32(mix(u64(row) + 1u64) % 12u64)) }
        table.set_f64(&t, C_PRICE, row, f64(i64(mix(u64(row) + 2u64) % 4001u64) - 2000i64) / 8.0f64)
        if table.set_str(&t, C_RARITY, row, rarity_of(row)) != ok { os.exit(3) }
        buf[0usize] = 78u8
        if mix(u64(row) + 4u64) % 2u64 == 0u64 { buf[0usize] = 110u8 }
        let n = 1usize + digits(buf[1usize..], mix(u64(row) + 5u64) % 40000u64)
        if table.set_str(&t, C_NAME, row, buf[0usize..n]) != ok { os.exit(4) }
        row += 1usize
    }
    table.end_load(&t)
    ret t
}

fn copy_order(v: *const view.View, out: []u32) -> usize {
    var at = 0usize
    while at < view.len(v) {
        out[at] = u32(view.row_at(v, at))
        at += 1usize
    }
    ret at
}

fn same_order(v: *const view.View, saved: []const u32, n: usize) -> bool {
    if view.len(v) != n { ret false }
    var at = 0usize
    while at < n {
        if u32(view.row_at(v, at)) != saved[at] { ret false }
        at += 1usize
    }
    ret true
}

// The row was edited: reposition it, remember the order, sort fully, and compare.
fn check_row(v: *view.View, keys: []const view.Key, row: usize, saved: []u32, a: *mem.Arena, code: i32) {
    if view.reposition(v, keys, row, a) != ok { os.exit(code) }
    let n = copy_order(v, saved)
    if view.apply_sort(v, keys, a) != ok { os.exit(code + 1) }
    if !same_order(v, saved, n) { os.exit(code + 2) }
}

fn derived(ctx: *void, row: usize) -> u64 {
    let t = mem.cast[*table.Table](ctx)
    var c = 99u64
    if !table.is_null(t, C_CMC, row) { c = u64(table.get_i32(t, C_CMC, row)) }
    ret c * 8u64 + u64(row % 8usize)
}

fn by_price_then_row(ctx: *void, x: u32, y: u32) -> i32 {
    let t = mem.cast[*table.Table](ctx)
    let px = table.get_f64(t, C_PRICE, usize(x))
    let py = table.get_f64(t, C_PRICE, usize(y))
    if px < py { ret -1i32 }
    if px > py { ret 1i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var t = build(a)
    let (made, made_error) = view.create(a, &t)
    if made_error != ok { os.exit(10) }
    var v = made
    let (saved, saved_error) = mem.alloc[u32](a, ROWS)
    if saved_error != ok { os.exit(11) }
    var one: [1]view.Key = zero
    // a nullable integer, ascending: to a new value, to null, from null, to the same value
    one[0usize] = view.column_key(C_CMC, false, true)
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(12) }
    table.set_i32(&t, C_CMC, 40001usize, 11i32)
    check_row(&v, one[0..], 40001usize, saved, a, 20)
    table.set_null(&t, C_CMC, 40002usize)
    check_row(&v, one[0..], 40002usize, saved, a, 30)
    table.set_i32(&t, C_CMC, 9usize, 0i32)
    check_row(&v, one[0..], 9usize, saved, a, 40)
    check_row(&v, one[0..], 40001usize, saved, a, 50)
    // descending
    one[0usize] = view.column_key(C_CMC, true, true)
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(60) }
    table.set_i32(&t, C_CMC, 70000usize, 6i32)
    check_row(&v, one[0..], 70000usize, saved, a, 70)
    table.set_null(&t, C_CMC, 70001usize)
    check_row(&v, one[0..], 70001usize, saved, a, 80)
    // a float with negatives
    one[0usize] = view.column_key(C_PRICE, false, true)
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(90) }
    table.set_f64(&t, C_PRICE, 12345usize, -9999.0f64)
    check_row(&v, one[0..], 12345usize, saved, a, 100)
    table.set_f64(&t, C_PRICE, 12346usize, 9999.0f64)
    check_row(&v, one[0..], 12346usize, saved, a, 110)
    // a folded dictionary that grows (new entry: the ranks are rebuilt)
    one[0usize] = view.column_key(C_RARITY, false, true)
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(120) }
    if table.set_str(&t, C_RARITY, 5000usize, "aaa new") != ok { os.exit(121) }
    check_row(&v, one[0..], 5000usize, saved, a, 130)
    if table.set_str(&t, C_RARITY, 5001usize, "ZZZ last") != ok { os.exit(131) }
    check_row(&v, one[0..], 5001usize, saved, a, 140)
    if table.set_str(&t, C_RARITY, 5002usize, "RARE") != ok { os.exit(141) }
    check_row(&v, one[0..], 5002usize, saved, a, 150)
    // an exact dictionary
    one[0usize] = view.column_key(C_RARITY, true, false)
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(160) }
    if table.set_str(&t, C_RARITY, 5003usize, "Common") != ok { os.exit(161) }
    check_row(&v, one[0..], 5003usize, saved, a, 170)
    // a heap string, folded
    one[0usize] = view.column_key(C_NAME, false, true)
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(180) }
    if table.set_str(&t, C_NAME, 777usize, "n00000") != ok { os.exit(181) }
    check_row(&v, one[0..], 777usize, saved, a, 190)
    if table.set_str(&t, C_NAME, 778usize, "zzzz") != ok { os.exit(191) }
    check_row(&v, one[0..], 778usize, saved, a, 200)
    // three keys
    var three: [3]view.Key = zero
    three[0usize] = view.column_key(C_RARITY, true, true)
    three[1usize] = view.column_key(C_CMC, false, true)
    three[2usize] = view.column_key(C_NAME, false, true)
    if view.apply_sort(&v, three[0..], a) != ok { os.exit(210) }
    table.set_i32(&t, C_CMC, 100usize, 3i32)
    check_row(&v, three[0..], 100usize, saved, a, 220)
    if table.set_str(&t, C_RARITY, 101usize, "Uncommon") != ok { os.exit(221) }
    check_row(&v, three[0..], 101usize, saved, a, 230)
    // a key function and a comparer
    let ctx = mem.cast[*void](&t)
    var custom: [2]view.Key = zero
    custom[0usize] = view.fn_key(derived, ctx, false)
    custom[1usize] = view.compare_key(by_price_then_row, ctx, true)
    if view.apply_sort(&v, custom[0..], a) != ok { os.exit(240) }
    table.set_i32(&t, C_CMC, 300usize, 2i32)
    check_row(&v, custom[0..], 300usize, saved, a, 250)
    table.set_f64(&t, C_PRICE, 301usize, 123.0f64)
    check_row(&v, custom[0..], 301usize, saved, a, 260)
    // too many keys are refused
    var many: [9]view.Key = zero
    var k = 0usize
    while k < 9usize {
        many[k] = view.column_key(C_CMC, false, true)
        k += 1usize
    }
    if view.reposition(&v, many[0..], 5usize, a) != view.TooManyKeys { os.exit(270) }

    // a filtered view: the row leaves and enters as apply_filter would have it
    one[0usize] = view.column_key(C_PRICE, false, true)
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(280) }
    var nodes: [1]view.Node = zero
    nodes[0usize] = view.leaf_node(C_PRICE, view.Op.Gt, view.real_operand(100.0f64))
    if view.apply_filter(&v, nodes[0..], false, a) != ok { os.exit(281) }
    let before = view.len(&v)
    if before == 0usize { os.exit(282) }
    // a shown row drops below the threshold (and moves in the sort)
    let leaving = view.row_at(&v, before / 2usize)
    table.set_f64(&t, C_PRICE, leaving, -50.0f64)
    if view.reposition(&v, one[0..], leaving, a) != ok { os.exit(283) }
    if view.refilter_row(&v, nodes[0..], leaving, a) != ok { os.exit(284) }
    if view.len(&v) != before - 1usize || view.row_matches(&v, leaving) { os.exit(285) }
    let partial = copy_order(&v, saved)
    // against a full re-sort and a full re-filter
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(286) }
    if view.apply_filter(&v, nodes[0..], false, a) != ok { os.exit(287) }
    if !same_order(&v, saved, partial) { os.exit(288) }
    // a hidden row enters
    var outside = 0usize
    while view.row_matches(&v, outside) { outside += 1usize }
    table.set_f64(&t, C_PRICE, outside, 150.5f64)
    if view.reposition(&v, one[0..], outside, a) != ok { os.exit(289) }
    if view.refilter_row(&v, nodes[0..], outside, a) != ok { os.exit(290) }
    if view.len(&v) != before || !view.row_matches(&v, outside) { os.exit(291) }
    let entered = copy_order(&v, saved)
    if view.apply_sort(&v, one[0..], a) != ok { os.exit(292) }
    if view.apply_filter(&v, nodes[0..], false, a) != ok { os.exit(293) }
    if !same_order(&v, saved, entered) { os.exit(294) }
    os.exit(0)
    ret ok
}
