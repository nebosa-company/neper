// A callback the C side calls is handed bytes the C side chose (D920, H03): `ready`
// is a `bool`, which admits only `true` and `false`, and no check stands between the
// caller's byte and the `if` that reads it. The C side's `int` is what a `@cc`
// parameter declares; `ready != 0i32` is the conversion.
@cc(c)
fn on_ready(ready: bool) -> i32 {
    if ready { ret 1i32 }
    ret 0i32
}

fn main() -> i32 {
    ret on_ready(false)
}
