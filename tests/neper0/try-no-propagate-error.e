// `try` in a function with no err to propagate through.

use e.mem

fn fallible() -> err {
    ret ok
}

fn caller() -> usize {
    try fallible()
    ret 1usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    ret ok
}
