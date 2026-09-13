// `T.trunc(x)` keeps the low bits of an integer: it is not a float conversion, so a
// float argument is refused where `u8(x)` would round it.
fn main() -> err {
    let f = 1.5f64
    let b = u8.trunc(f)
    if b == 1u8 { ret ok }
    ret ok
}
