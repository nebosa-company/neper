use alpha
use beta

error Failed

// One module instantiating two same-named templates from different modules. Both
// instances are owned here and both are spelled `make`, so their NIR identities
// differ only by the instance discriminator.
fn main() -> err {
    let cell = alpha.make[i64](7i64)
    let pair = beta.make[i64](5i64)
    if cell.value != 7i64 { ret Failed }
    if pair.first != 5i64 || pair.second != 5i64 { ret Failed }
    let narrow = alpha.make[i32](3i32)
    let wide = beta.make[i32](9i32)
    if narrow.value != 3i32 { ret Failed }
    if wide.first != 9i32 || wide.second != 9i32 { ret Failed }
    ret ok
}
