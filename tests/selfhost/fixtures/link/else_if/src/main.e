// `else if` (D245): grammar if_stmt's `else (if expression block | block)` form, lowered as
// the nested `if` it is. Each check returns its number when it fails; 0 is every check passed.

fn classify(n: i32) -> i32 {
    if n < 0 {
        ret -1
    } else if n == 0 {
        ret 0
    } else if n < 10 {
        ret 1
    } else {
        ret 2
    }
}

// A chain whose arms fall through to a shared merge, inside a loop with break and continue.
fn tally(limit: i32) -> i32 {
    var total = 0i32
    var i = 0i32
    while i < limit {
        i += 1
        if i % 6 == 0 {
            break
        } else if i % 2 == 0 {
            continue
        } else if i % 3 == 0 {
            total += 100
        } else {
            total += 1
        }
        total += 1000
    }
    ret total
}

// An `else if` with no final `else`.
fn open_ended(n: i32) -> i32 {
    var out = 7i32
    if n == 1 {
        out = 10
    } else if n == 2 {
        out = 20
    }
    ret out
}

fn main() -> i64 {
    if classify(-5) != -1 { ret 1i64 }
    if classify(0) != 0 { ret 2i64 }
    if classify(3) != 1 { ret 3i64 }
    if classify(42) != 2 { ret 4i64 }
    // i=1 odd: +1 +1000; i=2 even: continue; i=3: +100 +1000; i=4: continue; i=5: +1 +1000; i=6: break
    if tally(100) != 3102 { ret 5i64 }
    if open_ended(1) != 10 { ret 6i64 }
    if open_ended(2) != 20 { ret 7i64 }
    if open_ended(3) != 7 { ret 8i64 }
    ret 0i64
}
