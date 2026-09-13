// `@nocheck { ... }` (section 11) leaves the debug-only rows out of a block: `quiet`
// runs an overflowing `+`, a narrowing cast, an over-wide shift and a payload read
// under the wrong tag inside one, and exits 0; `divide` shows a row that traps in
// release too is not disabled by it; `loud` runs the same `+` outside a block and
// traps. Anything else stores through a bounds-elided index that happens to be in
// range and exits 0. The values come from the argument count so nothing folds.
use e.mem
use e.str

type Node = union enum u8 { Nil, Lit: i32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    let n = args.len + 5usize
    var buffer: [4]u8 = zero
    var total = 0u8
    var node: Node = .Nil
    var gone: *i32 = nil
    var cell = 4i32
    if args.len > 100usize { gone = &cell }
    if str.eq(mode, "quiet") {
        @nocheck {
            // Every debug-only row, elided: the index wraps to whatever the frame holds,
            // the sum wraps, the cast truncates, the count is masked, the tag is not
            // looked at.
            let wrapped = 250u8 + u8(n)
            let cut = u8(n + 300usize)
            let shifted = 1u32 << u32(n + 30usize)
            let payload = node.Lit
            total = wrapped +% cut +% u8.trunc(shifted) +% u8.trunc(payload)
        }
        if total == 3u8 { ret ok }
    }
    if str.eq(mode, "divide") {
        @nocheck {
            let q = 7usize / (n - 7usize)
            if q == 3usize { ret ok }
        }
    }
    if str.eq(mode, "loud") {
        let wrapped = 250u8 + u8(n)
        if wrapped == 3u8 { ret ok }
    }
    @nocheck {
        buffer[n - 6usize] = 9u8
    }
    if buffer[1usize] != 9u8 { ret ok }
    ret ok
}
