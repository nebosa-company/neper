// Section 13's failure line: `main` returning anything but `ok` writes one line,
// `error: <qualified name>`, to stderr from the merged error table and exits 1. `own`
// returns this module's error and `os` one of `e.os`'s, whose name comes from another
// module's table; anything else returns `ok` and writes nothing.
use e.mem
use e.str
use e.os

error Boom

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    if str.eq(mode, "own") { ret Boom }
    if str.eq(mode, "os") { ret os.NotFound }
    ret ok
}
