use e.mem

// A local named for a builtin type (T029): renamed where it stands as a value, not
// where `i8` is a type or a conversion.
fn main(a: *mem.Arena, args: []str) -> err {
    let i8 = i8(3i32)
    let wide: i16 = i16(i8)
    let copy: i8 = i8
    if wide != 3i16 || copy != 3i8 { ret mem.Exhausted }
    ret ok
}
