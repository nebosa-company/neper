// Exits 3 under the supplied `eq` and 4 once `edits/dep_declared.e` declares
// `colour_eq` answering false -- a kept `main` would still exit 3 (D494).
use dep
use e.os

fn same[T: type](a: T, b: T) -> bool {
    ret T.eq(a, b)
}

fn main() -> err {
    if same[dep.Colour](dep.pick(), dep.pick()) { os.exit(3i32) }
    os.exit(4i32)
    ret ok
}
