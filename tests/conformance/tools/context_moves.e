// `context-file` facts of a body (D486, H17): a resource consumed -- rebound into
// another local, then closed -- is a `move` fact at the site, and an `if` settled at
// compile time (D463) is a `phase` fact; a local bound to a view of another (D487)
// -- `&items`, `items[..]` -- is a `borrow` fact naming both; all compiler-proved.
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

fn views() -> usize {
    var items: [4]u8 = zero
    let first = &items[0usize]
    let part = items[1usize..3usize]
    ret usize(*first) + part.len + 4usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    if views() != 6usize { ret mem.Exhausted }
    if width[i64](1i64) != 8usize { ret mem.Exhausted }
    ret open_and_close(a)
}
