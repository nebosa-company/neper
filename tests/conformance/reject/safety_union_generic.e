// A generic untagged union made a pun by its argument (D924, H03): `Pun[T]` is fine
// until `T` is `bool`, and the instance a body asks for is refused as D921 refuses a
// declared one -- including when a caller probed the literal once and the instance
// was already made.
type Pun[T: type] = union { value: T, bits: u8 }

fn main() -> i32 {
    var pun = Pun[bool] { bits: 7u8 }
    if pun.value { ret 1i32 }
    ret 0i32
}
