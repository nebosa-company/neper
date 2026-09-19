// A function selected in brackets is compile-time strategy: it is checked against
// the declared signature, becomes part of the instance identity and is called by
// the specialized body without storing a runtime callback.

error Failed

fn add(a: i64, b: i64) -> i64 { ret a + b }
fn subtract(a: i64, b: i64) -> i64 { ret a - b }

fn apply[F: fn(i64, i64) -> i64](a: i64, b: i64) -> i64 {
    ret F(a, b)
}

fn main() -> err {
    if apply[add](9i64, 4i64) != 13i64 { ret Failed }
    if apply[subtract](9i64, 4i64) != 5i64 { ret Failed }
    ret ok
}
