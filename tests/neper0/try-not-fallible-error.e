// `try` on a call whose last result is not an err.

use e.mem

fn plain() -> usize {
    ret 1usize
}

fn caller() -> err {
    try plain()
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    ret ok
}
