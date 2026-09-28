// The functions p and r evaluate at compile time, and a `when` over one of them in q's
// own body: q's lowering reads its tokens and tree too, and gives them back after its
// artifact is written (D1668).
fn flag() -> bool {
    ret code() > 2u8
}

fn code() -> u8 {
    ret 7u8
}

fn run() -> i64 {
    var total = 0i64
    when flag() {
        total += 1i64
    } else {
        total += 100i64
    }
    ret total
}
