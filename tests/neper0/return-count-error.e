// `ret` gives fewer values than the signature declares.

use e.mem

fn pair() -> (i64, bool) {
    ret 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    ret ok
}
