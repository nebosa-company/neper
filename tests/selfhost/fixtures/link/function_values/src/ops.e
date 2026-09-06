// Comparators handed across a module boundary as values.

fn ascending(a: i64, b: i64) -> i32 {
    if a < b { ret 0i32 - 1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

fn descending(a: i64, b: i64) -> i32 { ret 0i32 - ascending(a, b) }
