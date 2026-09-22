// Section 4's alignment attribute must be a power of two (D925): `@align(12)` names
// no alignment an address can have, and is refused at the declaration rather than
// laid out as something else.
@align(12)
type Line = struct { first: u8 }

fn main() -> i32 {
    ret 0i32
}
