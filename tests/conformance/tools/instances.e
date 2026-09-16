// A specialization budget (D426, H06): three instances of one generic function.
fn twice[T: type](x: T) -> T { ret x + x }

fn main() -> i32 {
    let a = twice[i32](1i32)
    let b = twice[i64](2i64)
    let c = twice[u8](3u8)
    ret a + i32(b) + i32(c) - 12i32
}
