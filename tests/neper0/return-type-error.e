// The returned value does not have the declared type. Both front ends have to say so
// in the same words: `check.e` used to report this as "ret is not legal inside defer".

use e.mem

fn width() -> usize {
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    ret ok
}
