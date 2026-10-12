// `e.data.tableview` filter stage over a 150,000-row `e.data.table`: filter trees of every
// operator, checked against an independent brute-force evaluator that reads the cells
// directly (a different Like algorithm, no dictionary shortcut): text operators folded and
// exact, wildcards, numeric operators with nulls and real operands, booleans, In/NotIn,
// Between, Null/NotNull, groups And/Or/NotAnd/NotOr nested six deep, the sort order kept
// through a filter and through a re-sort, refining, clearing, refused operands and an edit.
// Every check has its own exit code.
use e.os
use e.mem
use e.data.table as table
use e.data.tableview as view

const ROWS: usize = 150000usize
const C_ID: usize = 0usize
const C_CMC: usize = 1usize
const C_PRICE: usize = 2usize
const C_TYPE: usize = 3usize
const C_NAME: usize = 4usize
const C_FLAG: usize = 5usize
const C_RARITY: usize = 6usize

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
    var spec: [7]table.Spec = zero
    spec[C_ID] = table.Spec { name: "id", kind: table.Kind.I64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_CMC] = table.Spec { name: "cmc", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_PRICE] = table.Spec { name: "price", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_TYPE] = table.Spec { name: "type", kind: table.Kind.Dict, heap_bytes: 1024usize, dict_cap: 32usize }
    spec[C_NAME] = table.Spec { name: "name", kind: table.Kind.Str, heap_bytes: 4000000usize, dict_cap: 0usize }
    spec[C_FLAG] = table.Spec { name: "flag", kind: table.Kind.Bool, heap_bytes: 0usize, dict_cap: 0usize }
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
        table.set_i64(&t, C_ID, row, i64(mix(u64(row)) % 2000u64) - 1000i64)
        if row % 9usize != 0usize { table.set_i32(&t, C_CMC, row, i32(mix(u64(row) + 1u64) % 12u64) - 2i32) }
        if row % 11usize != 0usize { table.set_f64(&t, C_PRICE, row, f64(i64(mix(u64(row) + 2u64) % 4001u64) - 2000i64) / 8.0f64) }
        if row % 17usize != 0usize {
            if table.set_str(&t, C_TYPE, row, type_of(row)) != ok { os.exit(3) }
        }
        var first = 110u8
        if mix(u64(row) + 4u64) % 2u64 == 1u64 { first = 78u8 }
        buf[0usize] = first
        buf[1usize] = 97u8 + u8(mix(u64(row) + 8u64) % 4u64)
        let n = 2usize + digits(buf[2usize..], mix(u64(row) + 5u64) % 30000u64)
        if table.set_str(&t, C_NAME, row, buf[0usize..n]) != ok { os.exit(4) }
        table.set_bool(&t, C_FLAG, row, mix(u64(row) + 6u64) % 3u64 == 0u64)
        if table.set_str(&t, C_RARITY, row, rarity_of(row)) != ok { os.exit(5) }
        row += 1usize
    }
    table.end_load(&t)
    ret t
}

// ---- independent evaluator --------------------------------------------------------

fn up(b: u8) -> u8 {
    if b >= 97u8 && b <= 122u8 { ret b - 32u8 }
    ret b
}

fn same(a: u8, b: u8, exact: bool) -> bool {
    if exact { ret a == b }
    ret up(a) == up(b)
}

// recursive glob: `*` any run, `?` one byte
fn glob(text: str, pat: str, i: usize, j: usize, exact: bool) -> bool {
    if j == pat.len { ret i == text.len }
    if pat[j] == 42u8 {
        var k = i
        while k <= text.len {
            if glob(text, pat, k, j + 1usize, exact) { ret true }
            k += 1usize
        }
        ret false
    }
    if i == text.len { ret false }
    if pat[j] == 63u8 || same(pat[j], text[i], exact) { ret glob(text, pat, i + 1usize, j + 1usize, exact) }
    ret false
}

fn order_text(x: str, y: str, exact: bool) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        var a = x[at]
        var b = y[at]
        if !exact {
            a = up(a)
            b = up(b)
        }
        if a < b { ret -1i32 }
        if a > b { ret 1i32 }
        at += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

fn find_in(hay: str, needle: str, exact: bool) -> i64 {
    // first index or -1, naive
    if needle.len > hay.len { ret -1i64 }
    var s = 0usize
    while s + needle.len <= hay.len {
        var k = 0usize
        var ok_here = true
        while k < needle.len {
            if !same(hay[s + k], needle[k], exact) { ok_here = false }
            k += 1usize
        }
        if ok_here { ret i64(s) }
        s += 1usize
    }
    ret -1i64
}

fn ref_text(op: view.Op, s: str, a: str, b: str, items: []const view.Operand, exact: bool) -> bool {
    if op == view.Op.Eq { ret order_text(s, a, exact) == 0i32 }
    if op == view.Op.Ne { ret order_text(s, a, exact) != 0i32 }
    if op == view.Op.Lt { ret order_text(s, a, exact) < 0i32 }
    if op == view.Op.Le { ret order_text(s, a, exact) <= 0i32 }
    if op == view.Op.Gt { ret order_text(s, a, exact) > 0i32 }
    if op == view.Op.Ge { ret order_text(s, a, exact) >= 0i32 }
    if op == view.Op.Like { ret glob(s, a, 0usize, 0usize, exact) }
    if op == view.Op.NotLike { ret !glob(s, a, 0usize, 0usize, exact) }
    if op == view.Op.Contains { ret find_in(s, a, exact) >= 0i64 }
    if op == view.Op.NotContains { ret find_in(s, a, exact) < 0i64 }
    if op == view.Op.Begins { ret s.len >= a.len && order_text(s[0usize..a.len], a, exact) == 0i32 }
    if op == view.Op.Ends { ret s.len >= a.len && order_text(s[s.len - a.len..], a, exact) == 0i32 }
    if op == view.Op.Between { ret order_text(s, a, exact) >= 0i32 && order_text(s, b, exact) <= 0i32 }
    if op == view.Op.NotBetween { ret !(order_text(s, a, exact) >= 0i32 && order_text(s, b, exact) <= 0i32) }
    var hit = false
    var at = 0usize
    while at < items.len {
        if order_text(s, items[at].text, exact) == 0i32 { hit = true }
        at += 1usize
    }
    if op == view.Op.In { ret hit }
    ret !hit
}

fn as_real(o: view.Operand) -> f64 {
    if o.kind == view.OperandKind.Int { ret f64(o.integer) }
    ret o.real
}

fn ref_number(op: view.Op, x: f64, a: view.Operand, b: view.Operand, items: []const view.Operand) -> bool {
    let ra = as_real(a)
    let rb = as_real(b)
    if op == view.Op.Eq { ret x == ra }
    if op == view.Op.Ne { ret x != ra }
    if op == view.Op.Lt { ret x < ra }
    if op == view.Op.Le { ret x <= ra }
    if op == view.Op.Gt { ret x > ra }
    if op == view.Op.Ge { ret x >= ra }
    if op == view.Op.Between { ret x >= ra && x <= rb }
    if op == view.Op.NotBetween { ret !(x >= ra && x <= rb) }
    var hit = false
    var at = 0usize
    while at < items.len {
        if x == as_real(items[at]) { hit = true }
        at += 1usize
    }
    if op == view.Op.In { ret hit }
    ret !hit
}

fn ref_leaf(t: *const table.Table, l: view.Leaf, row: usize) -> bool {
    let is_null = table.is_null(t, l.column, row)
    if l.op == view.Op.Null { ret is_null }
    if l.op == view.Op.NotNull { ret !is_null }
    if is_null {
        ret l.op == view.Op.Ne || l.op == view.Op.NotLike || l.op == view.Op.NotContains || l.op == view.Op.NotBetween || l.op == view.Op.NotIn
    }
    let kind = table.column_kind(t, l.column)
    if kind == table.Kind.Str || kind == table.Kind.Dict {
        ret ref_text(l.op, table.get_str(t, l.column, row), l.a.text, l.b.text, l.items, l.match_case)
    }
    var x = 0.0f64
    if kind == table.Kind.I32 { x = f64(table.get_i32(t, l.column, row)) }
    if kind == table.Kind.I64 { x = f64(table.get_i64(t, l.column, row)) }
    if kind == table.Kind.F64 { x = table.get_f64(t, l.column, row) }
    if kind == table.Kind.Bool && table.get_bool(t, l.column, row) { x = 1.0f64 }
    ret ref_number(l.op, x, l.a, l.b, l.items)
}

fn ref_node(t: *const table.Table, nodes: []const view.Node, index: usize, row: usize) -> bool {
    let n = nodes[index]
    if n.kind == view.NodeKind.Leaf { ret ref_leaf(t, n.leaf, row) }
    if n.count == 0usize { ret true }
    var all = true
    var any = false
    var at = 0usize
    while at < n.count {
        if ref_node(t, nodes, n.first + at, row) { any = true } else { all = false }
        at += 1usize
    }
    if n.kind == view.NodeKind.And { ret all }
    if n.kind == view.NodeKind.Or { ret any }
    if n.kind == view.NodeKind.NotAnd { ret !all }
    ret !any
}

// ---- verification ------------------------------------------------------------------

// The shown rows are exactly the rows of `before` (the unfiltered order) the reference
// passes, in that order. Returns the count.
fn verify(t: *const table.Table, v: *const view.View, before: []const u32, nodes: []const view.Node, code: i32) -> usize {
    var expected = 0usize
    var at = 0usize
    while at < before.len {
        let row = usize(before[at])
        if ref_node(t, nodes, 0usize, row) {
            if expected >= view.len(v) || view.row_at(v, expected) != row { os.exit(code) }
            expected += 1usize
        }
        at += 1usize
    }
    if expected != view.len(v) { os.exit(code + 1) }
    ret expected
}

fn snapshot(v: *const view.View, out: []u32) -> usize {
    var at = 0usize
    while at < view.len(v) {
        out[at] = u32(view.row_at(v, at))
        at += 1usize
    }
    ret at
}

fn run_one(t: *table.Table, v: *view.View, a: *mem.Arena, before: []const u32, nodes: []const view.Node, code: i32) -> usize {
    view.clear_filter(v)
    if view.apply_filter(v, nodes, false, a) != ok { os.exit(code + 2) }
    if !view.is_filtered(v) { os.exit(code + 3) }
    ret verify(t, v, before, nodes, code)
}

fn check_text(t: *table.Table, v: *view.View, a: *mem.Arena, before: []const u32) {
    var nodes: [1]view.Node = zero
    // `*creature*` folded: every case, in both dictionary and heap columns
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Like, view.text_operand("*creature*"))
    let folded = run_one(t, v, a, before, nodes[0..], 10)
    nodes[0usize] = view.match_case(view.leaf_node(C_TYPE, view.Op.Like, view.text_operand("*creature*")))
    let exact = run_one(t, v, a, before, nodes[0..], 20)
    if !(exact < folded) || exact == 0usize { os.exit(30) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Contains, view.text_operand("DRAGON"))
    if run_one(t, v, a, before, nodes[0..], 40) == 0usize { os.exit(50) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Begins, view.text_operand("legendary"))
    if run_one(t, v, a, before, nodes[0..], 60) == 0usize { os.exit(70) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Ends, view.text_operand("- goblin"))
    if run_one(t, v, a, before, nodes[0..], 80) == 0usize { os.exit(90) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Eq, view.text_operand("instant"))
    let instants = run_one(t, v, a, before, nodes[0..], 100)
    nodes[0usize] = view.match_case(view.leaf_node(C_TYPE, view.Op.Eq, view.text_operand("instant")))
    if run_one(t, v, a, before, nodes[0..], 110) != 0usize { os.exit(120) }
    if instants == 0usize { os.exit(121) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Ne, view.text_operand("Instant"))
    let not_instants = run_one(t, v, a, before, nodes[0..], 130)
    // null types (every 17th row) are in Ne, not in Eq
    if not_instants + instants > before.len { os.exit(140) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Like, view.text_operand("?and"))
    if run_one(t, v, a, before, nodes[0..], 150) == 0usize { os.exit(160) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.NotLike, view.text_operand("*a*"))
    let _ = run_one(t, v, a, before, nodes[0..], 170)
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.NotContains, view.text_operand("creature"))
    let _ = run_one(t, v, a, before, nodes[0..], 180)
    nodes[0usize] = view.between_node(C_TYPE, view.Op.Between, view.text_operand("e"), view.text_operand("m"))
    let _ = run_one(t, v, a, before, nodes[0..], 190)
    nodes[0usize] = view.between_node(C_TYPE, view.Op.NotBetween, view.text_operand("e"), view.text_operand("m"))
    let _ = run_one(t, v, a, before, nodes[0..], 200)
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Lt, view.text_operand("c"))
    let _ = run_one(t, v, a, before, nodes[0..], 210)
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Ge, view.text_operand("land"))
    let _ = run_one(t, v, a, before, nodes[0..], 220)
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Null, view.int_operand(0i64))
    let nulls = run_one(t, v, a, before, nodes[0..], 230)
    if nulls != (ROWS + 16usize) / 17usize { os.exit(240) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.NotNull, view.int_operand(0i64))
    if run_one(t, v, a, before, nodes[0..], 250) + nulls != ROWS { os.exit(260) }
    // a heap string column: wildcards and folding
    nodes[0usize] = view.leaf_node(C_NAME, view.Op.Like, view.text_operand("n?1*"))
    if run_one(t, v, a, before, nodes[0..], 270) == 0usize { os.exit(280) }
    nodes[0usize] = view.match_case(view.leaf_node(C_NAME, view.Op.Begins, view.text_operand("na")))
    let _ = run_one(t, v, a, before, nodes[0..], 290)
    nodes[0usize] = view.leaf_node(C_NAME, view.Op.Begins, view.text_operand("na"))
    let _ = run_one(t, v, a, before, nodes[0..], 300)
    // lists
    var items: [3]view.Operand = zero
    items[0usize] = view.text_operand("rare")
    items[1usize] = view.text_operand("MYTHIC")
    items[2usize] = view.text_operand("nothing")
    nodes[0usize] = view.list_node(C_RARITY, view.Op.In, items[0..])
    let listed = run_one(t, v, a, before, nodes[0..], 310)
    nodes[0usize] = view.list_node(C_RARITY, view.Op.NotIn, items[0..])
    if run_one(t, v, a, before, nodes[0..], 320) + listed != ROWS { os.exit(330) }
    nodes[0usize] = view.match_case(view.list_node(C_RARITY, view.Op.In, items[0..]))
    let _ = run_one(t, v, a, before, nodes[0..], 340)
}

fn check_numbers(t: *table.Table, v: *view.View, a: *mem.Arena, before: []const u32) {
    var nodes: [1]view.Node = zero
    nodes[0usize] = view.leaf_node(C_CMC, view.Op.Gt, view.int_operand(5i64))
    let big = run_one(t, v, a, before, nodes[0..], 400)
    if big == 0usize || big == ROWS { os.exit(410) }
    nodes[0usize] = view.leaf_node(C_CMC, view.Op.Le, view.real_operand(2.5f64))
    let _ = run_one(t, v, a, before, nodes[0..], 420)
    nodes[0usize] = view.leaf_node(C_CMC, view.Op.Ne, view.int_operand(3i64))
    let _ = run_one(t, v, a, before, nodes[0..], 430)
    nodes[0usize] = view.between_node(C_CMC, view.Op.Between, view.int_operand(2i64), view.int_operand(4i64))
    let _ = run_one(t, v, a, before, nodes[0..], 440)
    nodes[0usize] = view.between_node(C_CMC, view.Op.NotBetween, view.int_operand(2i64), view.int_operand(4i64))
    let _ = run_one(t, v, a, before, nodes[0..], 450)
    var items: [3]view.Operand = zero
    items[0usize] = view.int_operand(1i64)
    items[1usize] = view.real_operand(7.0f64)
    items[2usize] = view.int_operand(-2i64)
    nodes[0usize] = view.list_node(C_CMC, view.Op.In, items[0..])
    let _ = run_one(t, v, a, before, nodes[0..], 460)
    nodes[0usize] = view.list_node(C_ID, view.Op.NotIn, items[0..])
    let _ = run_one(t, v, a, before, nodes[0..], 465)
    nodes[0usize] = view.list_node(C_CMC, view.Op.NotIn, items[0..])
    let _ = run_one(t, v, a, before, nodes[0..], 470)
    nodes[0usize] = view.leaf_node(C_PRICE, view.Op.Lt, view.real_operand(-100.0f64))
    let _ = run_one(t, v, a, before, nodes[0..], 480)
    nodes[0usize] = view.between_node(C_PRICE, view.Op.Between, view.real_operand(-12.5f64), view.int_operand(12i64))
    let _ = run_one(t, v, a, before, nodes[0..], 490)
    nodes[0usize] = view.leaf_node(C_ID, view.Op.Eq, view.int_operand(-7i64))
    let _ = run_one(t, v, a, before, nodes[0..], 500)
    nodes[0usize] = view.leaf_node(C_FLAG, view.Op.Eq, view.int_operand(1i64))
    let flagged = run_one(t, v, a, before, nodes[0..], 510)
    nodes[0usize] = view.leaf_node(C_FLAG, view.Op.Ne, view.int_operand(1i64))
    if run_one(t, v, a, before, nodes[0..], 520) + flagged != ROWS { os.exit(530) }
    nodes[0usize] = view.leaf_node(C_CMC, view.Op.Null, view.int_operand(0i64))
    let nulls = run_one(t, v, a, before, nodes[0..], 540)
    if nulls != (ROWS + 8usize) / 9usize { os.exit(550) }
}

// (type like *creature* AND cmc > 2) OR NOT (rarity in (...) OR NotAnd(...)) nested six deep
fn check_groups(t: *table.Table, v: *view.View, a: *mem.Arena, before: []const u32) {
    var items: [2]view.Operand = zero
    items[0usize] = view.text_operand("Rare")
    items[1usize] = view.text_operand("Mythic")
    var n: [16]view.Node = zero
    // 0: Or(1, 2)
    n[0usize] = view.group_node(view.NodeKind.Or, 1usize, 2usize)
    // 1: And(3, 4)
    n[1usize] = view.group_node(view.NodeKind.And, 3usize, 2usize)
    // 2: NotOr(5, 6)
    n[2usize] = view.group_node(view.NodeKind.NotOr, 5usize, 2usize)
    n[3usize] = view.leaf_node(C_TYPE, view.Op.Like, view.text_operand("*creature*"))
    n[4usize] = view.leaf_node(C_CMC, view.Op.Gt, view.int_operand(2i64))
    n[5usize] = view.list_node(C_RARITY, view.Op.In, items[0..])
    // 6: NotAnd(7, 8)
    n[6usize] = view.group_node(view.NodeKind.NotAnd, 7usize, 2usize)
    n[7usize] = view.leaf_node(C_FLAG, view.Op.Eq, view.int_operand(1i64))
    // 8: Or(9, 10)  -- depth 4 .. 6 below
    n[8usize] = view.group_node(view.NodeKind.Or, 9usize, 2usize)
    n[9usize] = view.leaf_node(C_PRICE, view.Op.Gt, view.real_operand(100.0f64))
    // 10: And(11, 12)
    n[10usize] = view.group_node(view.NodeKind.And, 11usize, 2usize)
    n[11usize] = view.leaf_node(C_NAME, view.Op.Contains, view.text_operand("9"))
    // 12: Or(13, 14)
    n[12usize] = view.group_node(view.NodeKind.Or, 13usize, 2usize)
    n[13usize] = view.leaf_node(C_ID, view.Op.Lt, view.int_operand(0i64))
    n[14usize] = view.leaf_node(C_CMC, view.Op.Null, view.int_operand(0i64))
    let count = run_one(t, v, a, before, n[0..15], 600)
    if count == 0usize || count == ROWS { os.exit(610) }
    // an empty group passes everything, a group as the only node is itself
    var empty: [1]view.Node = zero
    empty[0usize] = view.group_node(view.NodeKind.And, 1usize, 0usize)
    if run_one(t, v, a, before, empty[0..], 620) != ROWS { os.exit(630) }
}

fn check_order(t: *table.Table, v: *view.View, a: *mem.Arena, before_all: []u32) {
    // sort by (rarity, cmc desc), filter, then re-sort: the filter stays and the order follows
    var keys: [2]view.Key = zero
    keys[0usize] = view.column_key(C_RARITY, false, true)
    keys[1usize] = view.column_key(C_CMC, true, true)
    view.clear_filter(v)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(700) }
    let n = snapshot(v, before_all)
    var nodes: [1]view.Node = zero
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Contains, view.text_operand("creature"))
    if view.apply_filter(v, nodes[0..], false, a) != ok { os.exit(701) }
    let _ = verify(t, v, before_all[0usize..n], nodes[0..], 710)
    let kept = view.len(v)
    // re-sort by price: the same rows, now in price order
    var keys2: [1]view.Key = zero
    keys2[0usize] = view.column_key(C_PRICE, false, true)
    if view.apply_sort(v, keys2[0..], a) != ok { os.exit(720) }
    if view.len(v) != kept { os.exit(721) }
    var at = 0usize
    while at + 1usize < view.len(v) {
        let x = view.row_at(v, at)
        let y = view.row_at(v, at + 1usize)
        if !ref_node(t, nodes[0..], 0usize, x) || !ref_node(t, nodes[0..], 0usize, y) { os.exit(722) }
        if !table.is_null(t, C_PRICE, y) && !table.is_null(t, C_PRICE, x) && table.get_f64(t, C_PRICE, x) > table.get_f64(t, C_PRICE, y) { os.exit(723) }
        at += 1usize
    }
    // refine: AND a second condition, evaluated over the previous matches only
    var both: [3]view.Node = zero
    both[0usize] = view.group_node(view.NodeKind.And, 1usize, 2usize)
    both[1usize] = nodes[0usize]
    both[2usize] = view.leaf_node(C_CMC, view.Op.Ge, view.int_operand(4i64))
    var before_refine: [1]u32 = zero
    let n2 = snapshot(v, before_all)
    if view.apply_filter(v, both[0..], true, a) != ok { os.exit(730) }
    let _ = verify(t, v, before_all[0usize..n2], both[0..], 740)
    // the unfiltered order is reachable again
    view.clear_filter(v)
    if view.is_filtered(v) || view.len(v) != table.live_count(t) { os.exit(750) }
    before_refine[0usize] = 0u32
}

fn check_refusals(t: *table.Table, v: *view.View, a: *mem.Arena) {
    var nodes: [1]view.Node = zero
    // a text operator on a number, a number operand on text, a column out of range
    nodes[0usize] = view.leaf_node(C_CMC, view.Op.Like, view.text_operand("1*"))
    if view.apply_filter(v, nodes[0..], false, a) != view.BadFilter { os.exit(800) }
    nodes[0usize] = view.leaf_node(C_TYPE, view.Op.Eq, view.int_operand(3i64))
    if view.apply_filter(v, nodes[0..], false, a) != view.BadFilter { os.exit(801) }
    nodes[0usize] = view.leaf_node(99usize, view.Op.Eq, view.int_operand(3i64))
    if view.apply_filter(v, nodes[0..], false, a) != view.BadFilter { os.exit(802) }
    // a group whose children are not after it
    nodes[0usize] = view.group_node(view.NodeKind.And, 0usize, 1usize)
    if view.apply_filter(v, nodes[0..], false, a) != view.BadFilter { os.exit(803) }
    if view.is_filtered(v) { os.exit(804) }
}

fn check_edit(t: *table.Table, v: *view.View, a: *mem.Arena, before: []const u32) {
    var nodes: [1]view.Node = zero
    nodes[0usize] = view.leaf_node(C_RARITY, view.Op.Eq, view.text_operand("Legendary"))
    if view.apply_filter(v, nodes[0..], false, a) != ok { os.exit(900) }
    if view.len(v) != 0usize { os.exit(901) }
    // a new dictionary entry appears; applying again sees it
    if table.set_str(t, C_RARITY, 123usize, "legendary") != ok { os.exit(902) }
    if view.apply_filter(v, nodes[0..], false, a) != ok { os.exit(903) }
    if view.len(v) != 1usize || view.row_at(v, 0usize) != 123usize { os.exit(904) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var t = build(a)
    let (made, made_error) = view.create(a, &t)
    if made_error != ok { os.exit(10) }
    var v = made
    // the unfiltered order every check compares with: a sort by id so it is not row order
    var key: [1]view.Key = zero
    key[0usize] = view.column_key(C_ID, false, true)
    if view.apply_sort(&v, key[0..], a) != ok { os.exit(11) }
    let (saved, saved_error) = mem.alloc[u32](a, ROWS)
    if saved_error != ok { os.exit(12) }
    let (spare, spare_error) = mem.alloc[u32](a, ROWS)
    if spare_error != ok { os.exit(13) }
    let n = snapshot(&v, saved)
    if n != ROWS { os.exit(14) }
    check_text(&t, &v, a, saved[0usize..n])
    check_numbers(&t, &v, a, saved[0usize..n])
    check_groups(&t, &v, a, saved[0usize..n])
    check_order(&t, &v, a, spare)
    check_refusals(&t, &v, a)
    // restore the id order for the edit check
    if view.apply_sort(&v, key[0..], a) != ok { os.exit(15) }
    check_edit(&t, &v, a, saved[0usize..n])
    os.exit(0)
    ret ok
}
