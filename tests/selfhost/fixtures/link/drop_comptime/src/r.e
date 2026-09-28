// After q in module order: at `-j 1` q's front is gone when r is lowered, and the
// interpreter lexes and parses q again from its text (D1668).
use q

fn run(x: u8) -> i64 {
    var total = 0i64
    when q.flag() {
        total += 100i64
    } else {
        total += 10000i64
    }
    switch x {
    case q.code():
        total += 200i64
    default:
        total += 20000i64
    }
    ret total
}
