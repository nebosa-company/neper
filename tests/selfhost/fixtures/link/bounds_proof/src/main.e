// Bounds-check elimination under a proof (D356, H03): `sum` indexes `items[at]`
// under `while at < items.len` before `at` changes, and the check is left out;
// `shifted` reads `items[at]` after `at += 1` in the same body, `nested` writes `at`
// inside an inner loop, and `reslice` assigns `items` in the body -- each keeps its
// check, and `shifted` trips it: with a count that reaches the end, the read past
// it traps as section 11 says. Under `--stats` the build reports the elided ones.
use e.mem
use e.str

fn sum(items: []const u32) -> u32 {
    var total = 0u32
    var at = 0usize
    while at < items.len {
        total = total +% items[at]
        if at + 1usize < items.len { total = total +% items[at + 1usize] }
        at += 1usize
    }
    ret total
}

fn shifted(items: []const u32) -> u32 {
    var total = 0u32
    var at = 0usize
    while at < items.len {
        at += 1usize
        total = total +% items[at]
    }
    ret total
}

fn nested(items: []const u32) -> u32 {
    var total = 0u32
    var at = 0usize
    while at < items.len {
        var inner = 0usize
        while inner < 2usize {
            total = total +% items[at]
            at += 1usize
            inner += 1usize
        }
    }
    ret total
}

fn reslice(items: []const u32) -> u32 {
    var total = 0u32
    var view = items
    var at = 0usize
    while at < view.len {
        total = total +% view[at]
        view = view[1usize..]
        at += 1usize
    }
    ret total
}

// The guard form (D377): `if at < items.len` proves `items[at]` in its block the
// way the loop does; `guarded_shifted` writes `at` first and keeps its check.
fn guarded(items: []const u32, at: usize) -> u32 {
    var total = 0u32
    if at < items.len { total = items[at] }
    ret total
}

fn guarded_shifted(items: []const u32, start: usize) -> u32 {
    var total = 0u32
    var at = start
    if at < items.len {
        at += 1usize
        total = items[at]
    }
    ret total
}

// The conjunct form (D378): the leftmost `at < items.len` proves the accesses in
// the rest of the condition and in the block.
fn conjunct(items: []const u32, at: usize) -> u32 {
    var total = 0u32
    if at < items.len && items[at] != 0u32 { total = items[at] }
    ret total
}

// The early-exit form (D380): `if at >= items.len { ret }` proves `items[at]` for
// the rest of the block; `exit_shifted` writes `at` after the guard and keeps its
// check, which trips at the end.
fn exit_guard(items: []const u32, at: usize) -> u32 {
    if at >= items.len { ret 0u32 }
    ret items[at]
}

fn exit_shifted(items: []const u32, start: usize) -> u32 {
    var at = start
    if items.len <= at { ret 0u32 }
    at += 1usize
    ret items[at]
}

// The width form (D384): an index narrowed to `u8`, widened from a `u8`, masked by a
// literal or offset by one cannot reach a 256-entry table, so no check is emitted.
fn width(table: [256]u32, key: u8, hash: usize) -> u32 {
    let narrowed = table[usize(key)] + table[usize(u8(hash % 200usize))]
    ret narrowed + table[hash & 255usize] + table[128usize + (hash & 127usize)]
}

// The slack form (D385): `while at + 4usize <= items.len` proves `items[at + j]` for
// `j` below 4; `slack_shifted` reads `items[at + 4usize]` and keeps its check.
fn slack(items: []const u32) -> u32 {
    var total = 0u32
    var at = 0usize
    while at + 4usize <= items.len {
        total = total +% items[at] +% items[at + 1usize] +% items[at + 2usize] +% items[at + 3usize]
        at += 4usize
    }
    ret total
}

fn slack_shifted(items: []const u32) -> u32 {
    var total = 0u32
    var at = 0usize
    while at + 4usize <= items.len {
        total = total +% items[at + 4usize]
        at += 4usize
    }
    ret total
}

fn main(a: *mem.Arena, args: []str) -> err {
    var mode = ""
    if args.len > 1usize { mode = args[1usize] }
    var values: [5]u32 = zero
    var at = 0usize
    while at < values.len {
        values[at] = u32(at + 1usize)
        at += 1usize
    }
    if str.eq(mode, "shifted") {
        if shifted(values[..]) == 0u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "nested") {
        if nested(values[..4usize]) != 10u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "reslice") {
        if reslice(values[..]) != 9u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "guarded") {
        if guarded(values[..], args.len + 2usize) != 5u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "conjunct") {
        if conjunct(values[..], args.len + 2usize) != 5u32 { ret mem.Exhausted }
        if conjunct(values[..], args.len + 3usize) != 0u32 { ret mem.Exhausted }
        if conjunct(values[..], args.len + 1usize) != 4u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "exit_guard") {
        if exit_guard(values[..], args.len + 2usize) != 5u32 { ret mem.Exhausted }
        if exit_guard(values[..], args.len + 3usize) != 0u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "exit_shifted") {
        if exit_shifted(values[..], args.len + 2usize) == 0u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "width") {
        var table: [256]u32 = zero
        var fill = 0usize
        while fill < table.len {
            table[fill] = u32(fill)
            fill += 1usize
        }
        if width(table, u8(args.len + 250usize), args.len * 2654435761usize) == 0u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "slack") {
        var eight: [8]u32 = zero
        var fill = 0usize
        while fill < eight.len {
            eight[fill] = u32(fill + 1usize)
            fill += 1usize
        }
        if slack(eight[..]) != 36u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "slack_shifted") {
        var four: [4]u32 = zero
        if slack_shifted(four[..]) != 0u32 { ret mem.Exhausted }
        ret ok
    }
    if str.eq(mode, "guarded_shifted") {
        if guarded_shifted(values[..], args.len + 2usize) == 0u32 { ret mem.Exhausted }
        ret ok
    }
    if sum(values[..]) != 29u32 { ret mem.Exhausted }
    ret ok
}
