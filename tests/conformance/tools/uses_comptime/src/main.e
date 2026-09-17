// A function only a constant reaches (D510, H17): `twice` is called in the
// initializer of `WIDTH` and nowhere else, so its one use is that call, evaluated
// at compile time; a rename plan rewrites it with the declaration, and the renamed
// program builds and exits the same.
use e.os

const WIDTH: usize = twice(4usize)

fn twice(n: usize) -> usize {
    ret n + n
}

fn main() -> err {
    var bytes: [WIDTH]u8 = zero
    os.exit(i32(bytes.len))
    ret ok
}
