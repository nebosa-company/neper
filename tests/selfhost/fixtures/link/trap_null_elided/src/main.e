// A null check already made is not made again (D923), and one made on some paths is.
// `twice` reads through `p` twice: a nil `p` traps at the first read, and the second
// read's check, dominated by the first, is gone. `branchy` reads `p` inside an `if`
// and again after it: with the `if` not taken, the later read's own check is the one
// that traps. `none` reads through a live pointer and exits 0.
use e.mem
use e.str

type Pair = struct { a: u64, b: u64 }

fn twice(p: *Pair) -> u64 {
    let first = p.a
    ret first + p.b
}

fn branchy(p: *Pair, taken: bool) -> u64 {
    var sum = 0u64
    if taken { sum = p.a }
    ret sum + p.b
}

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    var pair = Pair { a: 1u64, b: 2u64 }
    var gone: *Pair = nil
    if args.len > 100usize { gone = &pair }
    if str.eq(mode, "twice") {
        if twice(gone) == 7u64 { ret ok }
    }
    if str.eq(mode, "branchy") {
        if branchy(gone, args.len > 100usize) == 7u64 { ret ok }
    }
    if twice(&pair) + branchy(&pair, true) != 6u64 { ret mem.Exhausted }
    ret ok
}
