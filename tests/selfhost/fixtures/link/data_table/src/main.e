// `e.data.table`: the columnar store behind the data grid. A synthetic card pool of 150,000 rows
// by 24 columns (the MTG Studio shape: dictionary columns of few and many distinct values, long
// text heaps, numeric columns with nulls) is bulk loaded, read back cell by cell, ranked, edited,
// versioned, tombstoned and reloaded; the capacity errors and the memory budget are checked.
// Every check has its own exit code.
use e.os
use e.mem
use e.data.table as table

const ROWS: usize = 150000usize

// column positions
const C_ID: usize = 0usize
const C_FAVORITE: usize = 1usize
const C_NAME: usize = 2usize
const C_ABILITIES: usize = 3usize
const C_LEGALITY: usize = 4usize
const C_EDITION: usize = 5usize
const C_COLOR: usize = 6usize
const C_TYPE: usize = 7usize
const C_RARITY: usize = 8usize
const C_COST: usize = 9usize
const C_PT: usize = 10usize
const C_TEXT: usize = 11usize
const C_FLAVOR: usize = 12usize
const C_ARTIST: usize = 13usize
const C_EDITION_NAME: usize = 14usize
const C_COLLECTOR: usize = 15usize
const C_POWER: usize = 16usize
const C_TOUGHNESS: usize = 17usize
const C_CMC: usize = 18usize
const C_MTGO3: usize = 19usize
const C_MTGIE: usize = 20usize
const C_MTGO: usize = 21usize
const C_PRICE: usize = 22usize
const C_COUNT: usize = 23usize
const COLUMNS: usize = 24usize

fn mix(x: u64) -> u64 {
    var v = x *% 6364136223846793005u64 +% 1442695040888963407u64
    v = v ^ (v >> 29u64)
    v = v *% 6364136223846793005u64
    ret v ^ (v >> 32u64)
}

// Decimal digits of n into buf; the text is buf[..count].
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

// "<c>name<decimal>" with c the letter 'n' or 'N' by row parity: roughly 120,000 distinct
// strings, the upper/lower-case twins equal ignoring ASCII case.
fn name_of(buf: []u8, row: usize) -> usize {
    var first = 110u8
    if row % 2usize == 1usize { first = 78u8 }
    buf[0usize] = first
    ret 1usize + digits(buf[1usize..], mix(u64(row) % 120000u64) % 1000003u64)
}

// A text of 20..99 bytes derived from the row.
fn text_of(buf: []u8, row: usize) -> usize {
    let length = 20usize + usize(mix(u64(row) + 77u64) % 80u64)
    var at = 0usize
    while at < length {
        buf[at] = 97u8 + u8((u64(row) + u64(at) * 7u64) % 26u64)
        at += 1usize
    }
    ret length
}

fn small_of(buf: []u8, prefix: u8, bound: u64, seed: u64, row: usize) -> usize {
    buf[0usize] = prefix
    ret 1usize + digits(buf[1usize..], mix(u64(row) + seed) % bound)
}

fn cmc_of(row: usize) -> i32 { ret i32(mix(u64(row) + 5u64) % 16u64) }
fn price_of(row: usize) -> f64 { ret f64(mix(u64(row) + 11u64) % 100000u64) / 100.0f64 }

fn specs(out: []table.Spec) {
    out[C_ID] = table.Spec { name: "id", kind: table.Kind.I64, heap_bytes: 0usize, dict_cap: 0usize }
    out[C_FAVORITE] = table.Spec { name: "favorite", kind: table.Kind.Bool, heap_bytes: 0usize, dict_cap: 0usize }
    out[C_NAME] = table.Spec { name: "name", kind: table.Kind.Str, heap_bytes: 3000000usize, dict_cap: 0usize }
    out[C_ABILITIES] = table.Spec { name: "abilities", kind: table.Kind.Dict, heap_bytes: 40000usize, dict_cap: 3000usize }
    out[C_LEGALITY] = table.Spec { name: "legality", kind: table.Kind.Dict, heap_bytes: 2000usize, dict_cap: 64usize }
    out[C_EDITION] = table.Spec { name: "edition", kind: table.Kind.Dict, heap_bytes: 20000usize, dict_cap: 2048usize }
    out[C_COLOR] = table.Spec { name: "color", kind: table.Kind.Dict, heap_bytes: 1000usize, dict_cap: 32usize }
    out[C_TYPE] = table.Spec { name: "type", kind: table.Kind.Dict, heap_bytes: 100000usize, dict_cap: 8000usize }
    out[C_RARITY] = table.Spec { name: "rarity", kind: table.Kind.Dict, heap_bytes: 1000usize, dict_cap: 16usize }
    out[C_COST] = table.Spec { name: "cost", kind: table.Kind.Dict, heap_bytes: 20000usize, dict_cap: 2000usize }
    out[C_PT] = table.Spec { name: "pt", kind: table.Kind.Dict, heap_bytes: 4000usize, dict_cap: 512usize }
    out[C_TEXT] = table.Spec { name: "text", kind: table.Kind.Str, heap_bytes: 12000000usize, dict_cap: 0usize }
    out[C_FLAVOR] = table.Spec { name: "flavor", kind: table.Kind.Str, heap_bytes: 10000000usize, dict_cap: 0usize }
    out[C_ARTIST] = table.Spec { name: "artist", kind: table.Kind.Dict, heap_bytes: 60000usize, dict_cap: 4000usize }
    out[C_EDITION_NAME] = table.Spec { name: "edition_name", kind: table.Kind.Dict, heap_bytes: 40000usize, dict_cap: 2048usize }
    out[C_COLLECTOR] = table.Spec { name: "collector", kind: table.Kind.Dict, heap_bytes: 8000usize, dict_cap: 1024usize }
    out[C_POWER] = table.Spec { name: "power", kind: table.Kind.Dict, heap_bytes: 1000usize, dict_cap: 64usize }
    out[C_TOUGHNESS] = table.Spec { name: "toughness", kind: table.Kind.Dict, heap_bytes: 1000usize, dict_cap: 64usize }
    out[C_CMC] = table.Spec { name: "cmc", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    out[C_MTGO3] = table.Spec { name: "mtgo3", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    out[C_MTGIE] = table.Spec { name: "mtgie", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    out[C_MTGO] = table.Spec { name: "mtgo", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    out[C_PRICE] = table.Spec { name: "price", kind: table.Kind.F64, heap_bytes: 0usize, dict_cap: 0usize }
    out[C_COUNT] = table.Spec { name: "count", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
}

// Writes row `row`; `partial` true leaves the nullable cells (every seventh cmc, every
// thirteenth flavor) null.
fn write_row(t: *table.Table, row: usize) {
    var buf: [128]u8 = zero
    table.set_i64(t, C_ID, row, i64(row) * 3i64)
    table.set_bool(t, C_FAVORITE, row, row % 5usize == 0usize)
    var n = name_of(buf[0..], row)
    if table.set_str(t, C_NAME, row, buf[0usize..n]) != ok { os.exit(20) }
    n = small_of(buf[0..], 65u8, 2500u64, 1u64, row)
    if table.set_str(t, C_ABILITIES, row, buf[0usize..n]) != ok { os.exit(21) }
    n = small_of(buf[0..], 76u8, 8u64, 2u64, row)
    if table.set_str(t, C_LEGALITY, row, buf[0usize..n]) != ok { os.exit(22) }
    n = small_of(buf[0..], 69u8, 700u64, 3u64, row)
    if table.set_str(t, C_EDITION, row, buf[0usize..n]) != ok { os.exit(23) }
    n = small_of(buf[0..], 67u8, 7u64, 4u64, row)
    if table.set_str(t, C_COLOR, row, buf[0usize..n]) != ok { os.exit(24) }
    n = small_of(buf[0..], 84u8, 6000u64, 6u64, row)
    if table.set_str(t, C_TYPE, row, buf[0usize..n]) != ok { os.exit(25) }
    n = small_of(buf[0..], 82u8, 6u64, 7u64, row)
    if table.set_str(t, C_RARITY, row, buf[0usize..n]) != ok { os.exit(26) }
    n = small_of(buf[0..], 123u8, 1500u64, 8u64, row)
    if table.set_str(t, C_COST, row, buf[0usize..n]) != ok { os.exit(27) }
    n = small_of(buf[0..], 80u8, 300u64, 9u64, row)
    if table.set_str(t, C_PT, row, buf[0usize..n]) != ok { os.exit(28) }
    n = text_of(buf[0..], row)
    if table.set_str(t, C_TEXT, row, buf[0usize..n]) != ok { os.exit(29) }
    if row % 13usize != 0usize {
        n = text_of(buf[0..], row + 5usize)
        if table.set_str(t, C_FLAVOR, row, buf[0usize..n]) != ok { os.exit(30) }
    }
    n = small_of(buf[0..], 65u8, 3500u64, 12u64, row)
    if table.set_str(t, C_ARTIST, row, buf[0usize..n]) != ok { os.exit(31) }
    n = small_of(buf[0..], 83u8, 700u64, 3u64, row)
    if table.set_str(t, C_EDITION_NAME, row, buf[0usize..n]) != ok { os.exit(32) }
    n = small_of(buf[0..], 78u8, 900u64, 14u64, row)
    if table.set_str(t, C_COLLECTOR, row, buf[0usize..n]) != ok { os.exit(33) }
    n = small_of(buf[0..], 80u8, 12u64, 15u64, row)
    if table.set_str(t, C_POWER, row, buf[0usize..n]) != ok { os.exit(34) }
    n = small_of(buf[0..], 84u8, 12u64, 16u64, row)
    if table.set_str(t, C_TOUGHNESS, row, buf[0usize..n]) != ok { os.exit(35) }
    if row % 7usize != 0usize { table.set_i32(t, C_CMC, row, cmc_of(row)) }
    table.set_i32(t, C_MTGO3, row, i32(row))
    table.set_i32(t, C_MTGIE, row, i32(row) + 1i32)
    table.set_i32(t, C_MTGO, row, 0i32 - i32(row))
    table.set_f64(t, C_PRICE, row, price_of(row))
    table.set_i32(t, C_COUNT, row, i32(row % 4usize))
}

fn load(t: *table.Table) {
    table.begin_load(t)
    var row = 0usize
    while row < ROWS {
        let (made, made_error) = table.append_row(t)
        if made_error != ok || made != row { os.exit(40) }
        write_row(t, row)
        row += 1usize
    }
    table.end_load(t)
}

fn expect_text(t: *const table.Table, col: usize, row: usize, want: str, code: i32) {
    let got = table.get_str(t, col, row)
    if got.len != want.len { os.exit(code) }
    var at = 0usize
    while at < want.len {
        if got[at] != want[at] { os.exit(code) }
        at += 1usize
    }
}

fn read_back(t: *const table.Table) {
    var buf: [128]u8 = zero
    var row = 0usize
    while row < ROWS {
        if table.get_i64(t, C_ID, row) != i64(row) * 3i64 { os.exit(50) }
        if table.get_bool(t, C_FAVORITE, row) != (row % 5usize == 0usize) { os.exit(51) }
        var n = name_of(buf[0..], row)
        expect_text(t, C_NAME, row, buf[0usize..n], 52)
        n = small_of(buf[0..], 69u8, 700u64, 3u64, row)
        expect_text(t, C_EDITION, row, buf[0usize..n], 53)
        n = small_of(buf[0..], 82u8, 6u64, 7u64, row)
        expect_text(t, C_RARITY, row, buf[0usize..n], 54)
        n = text_of(buf[0..], row)
        expect_text(t, C_TEXT, row, buf[0usize..n], 55)
        if row % 13usize == 0usize {
            if !table.is_null(t, C_FLAVOR, row) || table.get_str(t, C_FLAVOR, row).len != 0usize { os.exit(56) }
        } else {
            n = text_of(buf[0..], row + 5usize)
            expect_text(t, C_FLAVOR, row, buf[0usize..n], 57)
        }
        if row % 7usize == 0usize {
            if !table.is_null(t, C_CMC, row) { os.exit(58) }
        } else {
            if table.is_null(t, C_CMC, row) || table.get_i32(t, C_CMC, row) != cmc_of(row) { os.exit(59) }
        }
        if table.get_i32(t, C_MTGO, row) != 0i32 - i32(row) { os.exit(60) }
        if table.get_f64(t, C_PRICE, row) != price_of(row) { os.exit(61) }
        if table.get_i32(t, C_COUNT, row) != i32(row % 4usize) { os.exit(62) }
        row += 1usize
    }
}

fn shape(t: *table.Table) {
    if table.column_count(t) != COLUMNS || table.row_count(t) != ROWS || table.live_count(t) != ROWS { os.exit(70) }
    if table.capacity(t) != ROWS { os.exit(71) }
    let (at_rarity, found) = table.find_column(t, "rarity")
    if !found || at_rarity != C_RARITY { os.exit(72) }
    let (_, missing) = table.find_column(t, "nope")
    if missing { os.exit(73) }
    if table.column_kind(t, C_NAME) != table.Kind.Str || table.column_kind(t, C_RARITY) != table.Kind.Dict { os.exit(74) }
    // a rarity column of six values has six dictionary entries; ids are consistent with the text
    if table.dict_len(t, C_RARITY) != 6usize { os.exit(75) }
    let (id, has) = table.dict_find(t, C_RARITY, "R0")
    if !has || table.dict_str(t, C_RARITY, id).len != 2usize { os.exit(76) }
    let (_, none) = table.dict_find(t, C_RARITY, "r0")
    if none { os.exit(77) }
    var row = 0usize
    while row < 2000usize {
        let found_id = table.dict_id(t, C_RARITY, row)
        let text = table.get_str(t, C_RARITY, row)
        let entry = table.dict_str(t, C_RARITY, found_id)
        if text.len != entry.len { os.exit(78) }
        row += 1usize
    }
}

fn memory(t: *const table.Table) {
    // 150k rows of 24 columns must stay within the design budget of about 45 MB
    if table.memory_bytes(t) > 45usize * 1024usize * 1024usize { os.exit(80) }
    if table.memory_bytes(t) < 1024usize * 1024usize { os.exit(81) }
}

fn ordering() {
    if table.compare_fold("abc", "ABC") != 0i32 { os.exit(90) }
    if table.compare_fold("Zebra", "apple") <= 0i32 { os.exit(91) }
    // upper-case folding: '_' (95) sorts after letters, '[' (91) too
    if table.compare_fold("_x", "Zed") <= 0i32 { os.exit(92) }
    if table.compare_fold("ab", "abc") >= 0i32 || table.compare_fold("abc", "ab") <= 0i32 { os.exit(93) }
    if table.compare_fold("", "a") >= 0i32 || table.compare_fold("", "") != 0i32 { os.exit(94) }
}

fn rank_checks(t: *table.Table, scratch: *mem.Arena) {
    let mark = mem.mark(scratch)
    let (rank_slice, rank_error) = table.ranks(t, C_ABILITIES, scratch)
    if rank_error != ok { os.exit(100) }
    let entries = table.dict_len(t, C_ABILITIES)
    if rank_slice.len != entries || entries < 100usize { os.exit(101) }
    // rank order is fold order; equal ranks are exactly the fold-equal pairs
    var x = 0usize
    while x < entries {
        var y = 0usize
        while y < entries {
            let c = table.compare_fold(table.dict_str(t, C_ABILITIES, u32(x)), table.dict_str(t, C_ABILITIES, u32(y)))
            let rx = rank_slice[x]
            let ry = rank_slice[y]
            if c < 0i32 && rx >= ry { os.exit(102) }
            if c > 0i32 && rx <= ry { os.exit(103) }
            if c == 0i32 && rx != ry { os.exit(104) }
            y += 97usize
        }
        x += 1usize
    }
    // the highest rank is one less than the number of fold-distinct strings: dense
    var top = 0u32
    x = 0usize
    while x < entries {
        if rank_slice[x] > top { top = rank_slice[x] }
        x += 1usize
    }
    if usize(top) >= entries { os.exit(105) }
    // rank_of reads the same
    if table.rank_of(t, C_ABILITIES, 123usize) != rank_slice[usize(table.dict_id(t, C_ABILITIES, 123usize))] { os.exit(106) }
    mem.reset(scratch, mark)
    // a non-Dict column answers BadKind
    let (_, kind_error) = table.ranks(t, C_NAME, scratch)
    if kind_error != table.BadKind { os.exit(107) }
}

// A small dictionary with case twins: "Apple" and "apple" share a rank, "_x" is after "Zed".
fn rank_cases(a: *mem.Arena, scratch: *mem.Arena) {
    var spec: [1]table.Spec = zero
    spec[0usize] = table.Spec { name: "w", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 8usize }
    let (made, made_error) = table.create(a, spec[0..], 8usize)
    if made_error != ok { os.exit(110) }
    var t = made
    var words: [6]str = zero
    words[0usize] = "pear"
    words[1usize] = "Apple"
    words[2usize] = "_x"
    words[3usize] = "apple"
    words[4usize] = "Zed"
    words[5usize] = "APPLE"
    var row = 0usize
    while row < 6usize {
        let (appended, append_error) = table.append_row(&t)
        if append_error != ok || appended != row { os.exit(111) }
        if table.set_str(&t, 0usize, row, words[row]) != ok { os.exit(112) }
        row += 1usize
    }
    if table.dict_len(&t, 0usize) != 6usize { os.exit(113) }
    let (rank_slice, rank_error) = table.ranks(&t, 0usize, scratch)
    if rank_error != ok { os.exit(114) }
    // Apple, apple, APPLE equal; then pear; then Zed; then _x
    if table.rank_of(&t, 0usize, 1usize) != table.rank_of(&t, 0usize, 3usize) { os.exit(115) }
    if table.rank_of(&t, 0usize, 1usize) != table.rank_of(&t, 0usize, 5usize) { os.exit(116) }
    if !(table.rank_of(&t, 0usize, 1usize) < table.rank_of(&t, 0usize, 0usize)) { os.exit(117) }
    if !(table.rank_of(&t, 0usize, 0usize) < table.rank_of(&t, 0usize, 4usize)) { os.exit(118) }
    if !(table.rank_of(&t, 0usize, 4usize) < table.rank_of(&t, 0usize, 2usize)) { os.exit(119) }
    if rank_slice.len != 6usize || table.rank_of(&t, 0usize, 2usize) != 3u32 { os.exit(120) }
    // growing the dictionary invalidates the ranks, and the next call rebuilds them
    let (more, more_error) = table.append_row(&t)
    if more_error != ok || table.set_str(&t, 0usize, more, "aardvark") != ok { os.exit(121) }
    let (rank_again, again_error) = table.ranks(&t, 0usize, scratch)
    if again_error != ok || rank_again.len != 7usize { os.exit(122) }
    if table.rank_of(&t, 0usize, more) != 0u32 || table.rank_of(&t, 0usize, 2usize) != 4u32 { os.exit(123) }
}

fn editing(t: *table.Table) {
    let before = table.version(t)
    let cmc_before = table.column_version(t, C_CMC)
    let name_before = table.column_version(t, C_NAME)
    let structure_before = table.structure_version(t)
    // overwrite a name, a count and a null cell; unrelated columns do not change
    if table.set_str(t, C_NAME, 10usize, "Replaced Name") != ok { os.exit(130) }
    expect_text(t, C_NAME, 10usize, "Replaced Name", 131)
    if table.heap_wasted(t, C_NAME) == 0usize { os.exit(132) }
    table.set_i32(t, C_COUNT, 10usize, 99i32)
    if table.get_i32(t, C_COUNT, 10usize) != 99i32 { os.exit(133) }
    if table.version(t) <= before { os.exit(134) }
    if !table.changed_since(t, C_NAME, name_before) || table.changed_since(t, C_CMC, cmc_before) { os.exit(135) }
    if table.structure_version(t) != structure_before { os.exit(136) }
    // row 0 has a null cmc (0 % 7 == 0): writing it clears the null, set_null restores it
    if !table.is_null(t, C_CMC, 0usize) { os.exit(137) }
    table.set_i32(t, C_CMC, 0usize, 4i32)
    if table.is_null(t, C_CMC, 0usize) || table.get_i32(t, C_CMC, 0usize) != 4i32 { os.exit(138) }
    table.set_null(t, C_CMC, 0usize)
    if !table.is_null(t, C_CMC, 0usize) { os.exit(139) }
    // a dictionary cell moves to another entry, and a new entry is interned
    if table.set_str(t, C_RARITY, 20usize, "R1") != ok { os.exit(140) }
    expect_text(t, C_RARITY, 20usize, "R1", 141)
    if table.set_str(t, C_RARITY, 20usize, "Mythic") != ok { os.exit(142) }
    expect_text(t, C_RARITY, 20usize, "Mythic", 143)
    if table.dict_len(t, C_RARITY) != 7usize { os.exit(144) }
    // column-wise fill, one version bump
    var fill: [16]i32 = zero
    var at = 0usize
    while at < 16usize {
        fill[at] = i32(at) * 11i32
        at += 1usize
    }
    let fill_before = table.version(t)
    table.fill_i32(t, C_MTGIE, fill[0..])
    if table.version(t) != fill_before + 1u64 || table.column_version(t, C_MTGIE) != table.version(t) { os.exit(145) }
    if table.get_i32(t, C_MTGIE, 15usize) != 165i32 || table.get_i32(t, C_MTGIE, 16usize) != 17i32 { os.exit(146) }
    // delete a row: tombstone, structure bump, counts
    let structure_mid = table.structure_version(t)
    if !table.delete_row(t, 5usize) { os.exit(147) }
    if table.delete_row(t, 5usize) { os.exit(148) }
    if table.is_live(t, 5usize) || !table.is_live(t, 6usize) { os.exit(149) }
    if table.live_count(t) != ROWS - 1usize || table.row_count(t) != ROWS { os.exit(150) }
    if table.structure_version(t) <= structure_mid { os.exit(151) }
}

fn limits(a: *mem.Arena) {
    var spec: [3]table.Spec = zero
    spec[0usize] = table.Spec { name: "s", kind: table.Kind.Str, heap_bytes: 8usize, dict_cap: 0usize }
    spec[1usize] = table.Spec { name: "d", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 2usize }
    spec[2usize] = table.Spec { name: "n", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], 2usize)
    if made_error != ok { os.exit(160) }
    var t = made
    let (r0, e0) = table.append_row(&t)
    let (r1, e1) = table.append_row(&t)
    if e0 != ok || e1 != ok || r0 != 0usize || r1 != 1usize { os.exit(161) }
    let (_, full) = table.append_row(&t)
    if full != table.Full { os.exit(162) }
    if !table.is_null(&t, 0usize, 0usize) || !table.is_null(&t, 2usize, 1usize) { os.exit(163) }
    // heap of 8 bytes: five fit, four more do not
    if table.set_str(&t, 0usize, 0usize, "hello") != ok { os.exit(164) }
    if table.set_str(&t, 0usize, 1usize, "toolong!") != table.Full { os.exit(165) }
    expect_text(&t, 0usize, 0usize, "hello", 166)
    // dictionary of 2 entries: a third distinct string is refused, a repeat is not
    if table.set_str(&t, 1usize, 0usize, "x") != ok || table.set_str(&t, 1usize, 1usize, "y") != ok { os.exit(167) }
    if table.set_str(&t, 1usize, 0usize, "z") != table.Full { os.exit(168) }
    if table.set_str(&t, 1usize, 0usize, "y") != ok || table.dict_len(&t, 1usize) != 2usize { os.exit(169) }
    // begin_load empties everything and keeps the capacity
    table.begin_load(&t)
    if table.row_count(&t) != 0usize || table.dict_len(&t, 1usize) != 0usize || table.heap_used(&t, 0usize) != 0usize { os.exit(170) }
    let (again, again_error) = table.append_row(&t)
    if again_error != ok || again != 0usize { os.exit(171) }
    table.end_load(&t)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var spec: [24]table.Spec = zero
    specs(spec[0..])
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { os.exit(1) }
    var t = made
    let scratch_mark = mem.mark(a)
    load(&t)
    shape(&t)
    read_back(&t)
    memory(&t)
    ordering()
    rank_checks(&t, a)
    rank_cases(a, a)
    editing(&t)
    mem.reset(a, scratch_mark)
    limits(a)
    os.exit(0)
    ret ok
}
