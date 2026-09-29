// Comptime parameters are symbols (T009): `T` and `N` are `parameter`s of `pick` whose
// signatures say they are comptime, and `[N]T` names them -- `N` read, `T` a type.
fn pick[T: type, N: usize](xs: [N]T, at: usize) -> T {
    var copy: [N]T = xs
    ret copy[at]
}

fn main() {
    let xs: [2]u8 = zero
    let y = pick[u8, 2usize](xs, 1usize)
}
