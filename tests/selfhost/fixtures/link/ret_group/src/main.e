// `ret (expr) op y` (D247): after `ret` a `(` may open the multi-return tuple or merely
// group an expression, and only a top-level comma before the matching `)` tells them
// apart. Each check returns its own number when it fails; 0 is every check passed.

fn pair() -> (i64, i64) {
    ret (1i64, 2i64)
}

fn trip(a: i64) -> (i64, i64, i64) {
    ret (a, a + 1, a + 2)
}

fn add(a: i64, b: i64) -> i64 {
    ret a + b
}

// A grouped left operand carrying a binary operator -- the shape that did not parse.
fn modulo(x: i64) -> i64 {
    ret (x * 7 + 13) % 1009
}

fn product(x: i64, y: i64) -> i64 {
    ret (x + y) * (x - y)
}

// A comma nested inside a call sits at depth two and must not read as a tuple.
fn nested_call(x: i64, y: i64) -> i64 {
    ret (add(x, y) + 1) % 7
}

fn negated(x: i64, y: i64) -> i64 {
    ret -(x + y) % 7
}

fn doubled(x: i64) -> i64 {
    ret ((x)) % 3
}

fn main() -> i64 {
    let (p, q) = pair()
    if p != 1i64 || q != 2i64 { ret 1i64 }
    let (a, b, c) = trip(10i64)
    if a != 10i64 || b != 11i64 || c != 12i64 { ret 2i64 }
    if modulo(5i64) != 48i64 { ret 3i64 }
    if product(9i64, 4i64) != 65i64 { ret 4i64 }
    if nested_call(3i64, 4i64) != 1i64 { ret 5i64 }
    if negated(3i64, 4i64) != -0i64 { ret 6i64 }
    if doubled(7i64) != 1i64 { ret 7i64 }
    ret 0i64
}
