// `context-file` facts of a body (D486, H17): a resource consumed -- rebound into
// another local, then closed -- is a `move` fact at the site, and an `if` settled at
// compile time (D463) is a `phase` fact; both compiler-proved.
use e.mem
use e.meta
use e.os

fn width[T: type](v: T) -> usize {
    if meta.kind[T]() == .Int { ret 8usize } else { ret 0usize }
}

fn open_and_close(a: *mem.Arena) -> err {
    var flags: os.OpenFlags = zero
    flags.read = true
    let (file, open_error) = os.open(a, "context_moves.e", flags)
    if open_error != ok { ret open_error }
    let held = file
    ret os.close(held)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if width[i64](1i64) != 8usize { ret mem.Exhausted }
    ret open_and_close(a)
}
