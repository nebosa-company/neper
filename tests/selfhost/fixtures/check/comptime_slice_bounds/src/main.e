// An index past a slice's end inside a comptime evaluation (D1569, C066): section
// 11's bounds check runs in the interpreter too, and the constant is refused naming
// what its call reached.
fn pick() -> u32 {
    var t: [2]u32 = zero
    let s = t[..]
    ret s[3usize]
}

const BAD = pick()

fn main() {}
