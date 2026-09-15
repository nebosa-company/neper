// Section 13's failure line: `main` returning anything but `ok` writes one line,
// `error: <qualified name>`, to stderr from the merged error table and exits 1. `own`
// returns this module's error and `os` one of `e.os`'s, whose name comes from another
// module's table; `try` is a failing `try` (D312), which is `main` returning an error
// too; anything else returns `ok` and writes nothing.
use e.mem
use e.str
use e.os

error Boom
error Tried

fn fails() -> err { ret Tried }

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    if str.eq(mode, "own") { ret Boom }
    if str.eq(mode, "os") { ret os.NotFound }
    if str.eq(mode, "try") { try fails() }
    ret ok
}
