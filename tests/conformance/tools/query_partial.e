// A partial answer (D1554, H08): `main`'s body does not check, and the functions
// declared after it do. `context-file --symbol query_partial.later` answers with
// later's page -- the diagnostic after the subject, its call to `twice` among the
// facts, a result of exit 1 marked partial -- since the checker goes on past the
// body that fails.
use e.os

fn main() -> err {
    let x: i32 = true
    os.exit(i32(later(2usize)))
    ret ok
}

fn later(n: usize) -> usize {
    ret twice(n) + 1usize
}

fn twice(n: usize) -> usize {
    ret n * 2usize
}
