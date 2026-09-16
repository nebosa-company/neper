// Section 11's memory rows stay in a release build (D355, H03): built with
// `--release`, `bounds` indexes past a slice's end and traps, `null` reads through a
// nil pointer and traps, `tag` reads a payload under the wrong tag and traps -- each
// with the same record a debug build writes -- while `quiet` does the first inside
// `@nocheck`, at an index that happens to be in range, and exits 0. The values come
// from the argument count so nothing folds.
use e.mem
use e.str

type Node = union enum u8 { Nil, Lit: i32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let n = args.len + 5usize
    var mode = ""
    if args.len > 1usize { mode = args[1usize] }
    var buffer: [8]u8 = zero
    var gone: *i32 = nil
    var cell = 4i32
    if args.len > 100usize { gone = &cell }
    var node: Node = .Nil
    if str.eq(mode, "bounds") {
        buffer[n + 2usize] = 1u8
        ret ok
    }
    if str.eq(mode, "null") {
        cell = *gone
        if cell == 5i32 { ret ok }
        ret ok
    }
    if str.eq(mode, "tag") {
        let payload = node.Lit
        if payload == 5i32 { ret ok }
        ret ok
    }
    if str.eq(mode, "quiet") {
        @nocheck {
            buffer[n - 6usize] = 9u8
        }
        if buffer[1usize] != 9u8 { ret mem.Exhausted }
        ret ok
    }
    ret ok
}
