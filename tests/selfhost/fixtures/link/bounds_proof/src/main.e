// Bounds-check elimination under a proof (D356, H03): `sum` indexes `items[at]`
// under `while at < items.len` before `at` changes, and the check is left out;
// `shifted` reads `items[at]` after `at += 1` in the same body, `nested` writes `at`
// inside an inner loop, and `reslice` assigns `items` in the body -- each keeps its
// check, and `shifted` trips it: with a count that reaches the end, the read past
// it traps as section 11 says. Under `--stats` the build reports three elided.
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
    if sum(values[..]) != 29u32 { ret mem.Exhausted }
    ret ok
}
