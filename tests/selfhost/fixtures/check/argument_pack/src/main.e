// A `...` parameter outside the three intrinsic packs and `extern` (D787): refused
// at the parameter, naming the function.

use e.mem

fn total(args: ...) -> err {
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    ret total(1i32, 2i32)
}
