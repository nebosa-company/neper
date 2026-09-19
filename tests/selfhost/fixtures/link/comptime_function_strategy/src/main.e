// A function selected in brackets is compile-time strategy: it is checked against
// the declared signature, becomes part of the instance identity and is called by
// the specialized body without storing a runtime callback.

error Failed

fn add(a: i64, b: i64) -> i64 { ret a + b }
fn subtract(a: i64, b: i64) -> i64 { ret a - b }

fn apply[T: type, F: fn(T, T) -> T](a: T, b: T) -> T {
    ret F(a, b)
}

fn relay[T: type, F: fn(T, T) -> T](a: T, b: T) -> T {
    ret apply[T, F](a, b)
}

fn main() -> err {
    if apply[i64, add](9i64, 4i64) != 13i64 { ret Failed }
    if apply[i64, subtract](9i64, 4i64) != 5i64 { ret Failed }
    if relay[i64, subtract](12i64, 7i64) != 5i64 { ret Failed }
    ret ok
}
