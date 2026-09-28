// Before q in module order: at `-j 1` its lowering reads q's front in place, since q
// is the same worker's and not yet given back (D1668).
use q

fn run(x: u8) -> i64 {
    var total = 0i64
    when q.flag() {
        total += 10i64
    } else {
        total += 1000i64
    }
    switch x {
    case q.code():
        total += 20i64
    default:
        total += 2000i64
    }
    ret total
}
