// Exits 8 with dep.LIMIT above 2, 4 otherwise: the fold reads the constant's value,
// and a warm build after `edits/dep_limit.e` must rebuild this module (D492).
use dep
use e.os

fn main() -> err {
    if dep.LIMIT > 2usize {
        os.exit(dep.answer() + 4i32)
    }
    os.exit(dep.answer())
    ret ok
}
