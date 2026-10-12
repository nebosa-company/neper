// `e.data.tableview` sort stage over a 150,000-row `e.data.table`: a stable multi-key LSD
// sort whose result is checked against an independent reference ordering (every adjacent
// pair of the result compares strictly less under the reference, which with a permutation
// check pins the order exactly): dictionary ranks with case folding and without, an integer
// column with nulls (first ascending, last descending), floats and 64-bit integers with
// negative values, a heap string column, three keys at once, a key function, a comparer,
// deleted rows, and the rank caches after an edit. Every check has its own exit code.
use e.os
use e.mem
use e.data.table as table
use e.data.tableview as view

const ROWS: usize = 150000usize
const C_ID: usize = 0usize
const C_CMC: usize = 1usize
const C_PRICE: usize = 2usize
const C_RARITY: usize = 3usize
const C_NAME: usize = 4usize
const C_FLAG: usize = 5usize
const C_NO: usize = 6usize

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
    let pick = mix(u64(row) + 3u64) % 9u64
    if pick == 0u64 { ret "Common" }
    if pick == 1u64 { ret "common" }
    if pick == 2u64 { ret "Uncommon" }
    if pick == 3u64 { ret "Rare" }
    if pick == 4u64 { ret "rare" }
    if pick == 5u64 { ret "Mythic" }
    if pick == 6u64 { ret "MYTHIC" }
    if pick == 7u64 { ret "_special" }
    ret "Zed"
}

fn build(a: *mem.Arena) -> table.Table {
    var spec: [7]table.Spec = zero
    spec[C_ID] = table.Spec { name: "id", kind: table.Kind.I64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_CMC] = table.Spec { name: "cmc", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_PRICE] = table.Spec { name: "price", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_RARITY] = table.Spec { name: "rarity", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 16usize }
    spec[C_NAME] = table.Spec { name: "name", kind: table.Kind.Str, heap_bytes: 3000000usize, dict_cap: 0usize }
    spec[C_FLAG] = table.Spec { name: "flag", kind: table.Kind.Bool, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_NO] = table.Spec { name: "no", kind: table.Kind.Dict, heap_bytes: 200000usize, dict_cap: 40000usize }
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { os.exit(1) }
    var t = made
    table.begin_load(&t)
    var buf: [64]u8 = zero
    var row = 0usize
    while row < ROWS {
        let (got, append_error) = table.append_row(&t)
        if append_error != ok || got != row { os.exit(2) }
        // ids: negative and positive, many equal in absolute value
        table.set_i64(&t, C_ID, row, i64(mix(u64(row)) % 2000u64) - 1000i64)
        if row % 9usize != 0usize { table.set_i32(&t, C_CMC, row, i32(mix(u64(row) + 1u64) % 12u64) - 2i32) }
        table.set_f64(&t, C_PRICE, row, f64(i64(mix(u64(row) + 2u64) % 4001u64) - 2000i64) / 8.0f64)
        if table.set_str(&t, C_RARITY, row, rarity_of(row)) != ok { os.exit(3) }
        var first = 110u8
        if mix(u64(row) + 4u64) % 2u64 == 1u64 { first = 78u8 }
        buf[0usize] = first
        let n = 1usize + digits(buf[1usize..], mix(u64(row) + 5u64) % 30000u64)
        if table.set_str(&t, C_NAME, row, buf[0usize..n]) != ok { os.exit(4) }
        table.set_bool(&t, C_FLAG, row, mix(u64(row) + 6u64) % 3u64 == 0u64)
        let m = digits(buf[0..], mix(u64(row) + 7u64) % 35000u64)
        if table.set_str(&t, C_NO, row, buf[0usize..m]) != ok { os.exit(5) }
        row += 1usize
    }
    table.end_load(&t)
    ret t
}

// ---- reference ordering ----------------------------------------------------------

fn exact(x: str, y: str) -> i32 {
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

fn three_way_i64(x: i64, y: i64) -> i32 {
    if x < y { ret -1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn three_way_f64(x: f64, y: f64) -> i32 {
    if x < y { ret -1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn ref_one(t: *const table.Table, k: view.Key, x: usize, y: usize) -> i32 {
    let xn = table.is_null(t, k.column, x)
    let yn = table.is_null(t, k.column, y)
    var c = 0i32
    if xn && yn {
        c = 0i32
    } else if xn {
        c = -1i32
    } else if yn {
        c = 1i32
    } else {
        let kind = table.column_kind(t, k.column)
        if kind == table.Kind.I32 {
            c = three_way_i64(i64(table.get_i32(t, k.column, x)), i64(table.get_i32(t, k.column, y)))
        } else if kind == table.Kind.I64 {
            c = three_way_i64(table.get_i64(t, k.column, x), table.get_i64(t, k.column, y))
        } else if kind == table.Kind.F64 {
            c = three_way_f64(table.get_f64(t, k.column, x), table.get_f64(t, k.column, y))
        } else if kind == table.Kind.Bool {
            var bx = 0i64
            var by = 0i64
            if table.get_bool(t, k.column, x) { bx = 1i64 }
            if table.get_bool(t, k.column, y) { by = 1i64 }
            c = three_way_i64(bx, by)
        } else {
            let sx = table.get_str(t, k.column, x)
            let sy = table.get_str(t, k.column, y)
            if k.fold { c = table.compare_fold(sx, sy) } else { c = exact(sx, sy) }
        }
    }
    if k.descending { ret 0i32 - c }
    ret c
}

fn ref_all(t: *const table.Table, keys: []const view.Key, x: usize, y: usize) -> i32 {
    var at = 0usize
    while at < keys.len {
        let c = ref_one(t, keys[at], x, y)
        if c != 0i32 { ret c }
        at += 1usize
    }
    if x < y { ret -1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// The view is a permutation of the live rows and every adjacent pair is strictly increasing.
fn verify(t: *const table.Table, v: *const view.View, keys: []const view.Key, a: *mem.Arena, code: i32) {
    let n = view.len(v)
    if n != table.live_count(t) { os.exit(code) }
    let marker = mem.mark(a)
    let (seen, seen_error) = mem.alloc[bool](a, table.row_count(t))
    if seen_error != ok { os.exit(code + 1) }
    var at = 0usize
    while at < seen.len {
        seen[at] = false
        at += 1usize
    }
    at = 0usize
    while at < n {
        let row = view.row_at(v, at)
        if !table.is_live(t, row) || seen[row] { os.exit(code + 2) }
        seen[row] = true
        if at + 1usize < n && ref_all(t, keys, row, view.row_at(v, at + 1usize)) >= 0i32 { os.exit(code + 3) }
        at += 1usize
    }
    mem.reset(a, marker)
}

// ---- custom keys -----------------------------------------------------------------

fn derived(ctx: *void, row: usize) -> u64 {
    let t = mem.cast[*table.Table](ctx)
    var c = 99u64
    if !table.is_null(t, C_CMC, row) { c = u64(table.get_i32(t, C_CMC, row) + 2i32) }
    ret c * 7u64 + u64(row % 7usize)
}

fn by_id_mod(ctx: *void, x: u32, y: u32) -> i32 {
    let t = mem.cast[*table.Table](ctx)
    let mx = table.get_i64(t, C_ID, usize(x)) % 37i64
    let my = table.get_i64(t, C_ID, usize(y)) % 37i64
    ret three_way_i64(mx, my)
}

fn check_custom(t: *table.Table, v: *view.View, a: *mem.Arena) {
    let ctx = mem.cast[*void](t)
    // key function ascending: (derived key, row)
    var keys: [1]view.Key = zero
    keys[0usize] = view.fn_key(derived, ctx, false)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(100) }
    var at = 0usize
    while at + 1usize < view.len(v) {
        let x = view.row_at(v, at)
        let y = view.row_at(v, at + 1usize)
        let kx = derived(ctx, x)
        let ky = derived(ctx, y)
        if kx > ky || (kx == ky && x >= y) { os.exit(101) }
        at += 1usize
    }
    // key function descending, then ties by row ascending
    keys[0usize] = view.fn_key(derived, ctx, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(102) }
    at = 0usize
    while at + 1usize < view.len(v) {
        let x = view.row_at(v, at)
        let y = view.row_at(v, at + 1usize)
        let kx = derived(ctx, x)
        let ky = derived(ctx, y)
        if kx < ky || (kx == ky && x >= y) { os.exit(103) }
        at += 1usize
    }
    // comparer slow path, as the second key of a pair: rarity then id % 37 descending
    var two: [2]view.Key = zero
    two[0usize] = view.column_key(C_RARITY, false, true)
    two[1usize] = view.compare_key(by_id_mod, ctx, true)
    if view.apply_sort(v, two[0..], a) != ok { os.exit(104) }
    at = 0usize
    while at + 1usize < view.len(v) {
        let x = view.row_at(v, at)
        let y = view.row_at(v, at + 1usize)
        var c = table.compare_fold(table.get_str(t, C_RARITY, x), table.get_str(t, C_RARITY, y))
        if c == 0i32 { c = three_way_i64(table.get_i64(t, C_ID, y) % 37i64, table.get_i64(t, C_ID, x) % 37i64) }
        if c == 0i32 && x < y { c = -1i32 }
        if c >= 0i32 { os.exit(105) }
        at += 1usize
    }
}

// ---- checks ----------------------------------------------------------------------

fn check_single(t: *table.Table, v: *view.View, a: *mem.Arena) {
    var keys: [1]view.Key = zero
    // dictionary, folded: "Common" and "common" tie and keep row order
    keys[0usize] = view.column_key(C_RARITY, false, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(110) }
    verify(t, v, keys[0..], a, 120)
    // dictionary, byte order: upper case before lower case
    keys[0usize] = view.column_key(C_RARITY, false, false)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(111) }
    verify(t, v, keys[0..], a, 130)
    // integer with nulls: first ascending, last descending
    keys[0usize] = view.column_key(C_CMC, false, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(112) }
    verify(t, v, keys[0..], a, 140)
    if !table.is_null(t, C_CMC, view.row_at(v, 0usize)) { os.exit(113) }
    keys[0usize] = view.column_key(C_CMC, true, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(114) }
    verify(t, v, keys[0..], a, 150)
    if !table.is_null(t, C_CMC, view.row_at(v, view.len(v) - 1usize)) { os.exit(115) }
    // 64-bit integers and floats with negative values
    keys[0usize] = view.column_key(C_ID, false, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(116) }
    verify(t, v, keys[0..], a, 160)
    keys[0usize] = view.column_key(C_PRICE, true, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(117) }
    verify(t, v, keys[0..], a, 170)
    // booleans
    keys[0usize] = view.column_key(C_FLAG, false, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(118) }
    verify(t, v, keys[0..], a, 180)
    // heap strings, folded and exact (names have n/N twins)
    keys[0usize] = view.column_key(C_NAME, false, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(119) }
    verify(t, v, keys[0..], a, 190)
    keys[0usize] = view.column_key(C_NAME, true, false)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(121) }
    verify(t, v, keys[0..], a, 200)
    // a dictionary of many entries, exact order
    keys[0usize] = view.column_key(C_NO, false, false)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(122) }
    verify(t, v, keys[0..], a, 210)
}

fn check_multi(t: *table.Table, v: *view.View, a: *mem.Arena) {
    var keys: [3]view.Key = zero
    keys[0usize] = view.column_key(C_RARITY, true, true)
    keys[1usize] = view.column_key(C_CMC, false, true)
    keys[2usize] = view.column_key(C_NAME, false, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(220) }
    verify(t, v, keys[0..], a, 230)
    keys[0usize] = view.column_key(C_FLAG, true, true)
    keys[1usize] = view.column_key(C_PRICE, false, true)
    keys[2usize] = view.column_key(C_ID, true, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(240) }
    verify(t, v, keys[0..], a, 250)
}

fn check_edit(t: *table.Table, v: *view.View, a: *mem.Arena) {
    var keys: [1]view.Key = zero
    keys[0usize] = view.column_key(C_NAME, false, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(260) }
    // an edit to the name column invalidates its rank cache; the next sort is still exact
    if table.set_str(t, C_NAME, 77usize, "!first") != ok { os.exit(261) }
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(262) }
    verify(t, v, keys[0..], a, 270)
    if view.row_at(v, 0usize) != 77usize { os.exit(274) }
    // deleted rows are not in the order
    if !table.delete_row(t, 77usize) || !table.delete_row(t, 5usize) || !table.delete_row(t, 100000usize) { os.exit(275) }
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(276) }
    verify(t, v, keys[0..], a, 280)
    if view.len(v) != ROWS - 3usize { os.exit(284) }
    // a new dictionary entry: the rarity ranks are rebuilt
    keys[0usize] = view.column_key(C_RARITY, false, true)
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(285) }
    if table.set_str(t, C_RARITY, 9usize, "Aaa") != ok { os.exit(286) }
    if view.apply_sort(v, keys[0..], a) != ok { os.exit(287) }
    verify(t, v, keys[0..], a, 290)
    if view.row_at(v, 0usize) != 9usize { os.exit(294) }
}

fn check_empty(a: *mem.Arena) {
    var spec: [1]table.Spec = zero
    spec[0usize] = table.Spec { name: "n", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], 4usize)
    if made_error != ok { os.exit(300) }
    var t = made
    let (made_view, view_error) = view.create(a, &t)
    if view_error != ok { os.exit(301) }
    var v = made_view
    var keys: [1]view.Key = zero
    keys[0usize] = view.column_key(0usize, false, true)
    if view.apply_sort(&v, keys[0..], a) != ok || view.len(&v) != 0usize { os.exit(302) }
    let (r, append_error) = table.append_row(&t)
    if append_error != ok { os.exit(303) }
    if view.apply_sort(&v, keys[0..], a) != ok || view.len(&v) != 1usize || view.row_at(&v, 0usize) != r { os.exit(304) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var t = build(a)
    let (made, made_error) = view.create(a, &t)
    if made_error != ok { os.exit(10) }
    var v = made
    if view.len(&v) != ROWS { os.exit(11) }
    check_single(&t, &v, a)
    check_multi(&t, &v, a)
    check_custom(&t, &v, a)
    check_edit(&t, &v, a)
    check_empty(a)
    os.exit(0)
    ret ok
}
