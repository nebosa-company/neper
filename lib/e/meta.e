// Compile-time reflection. Every function answers from the type bound at the call, so
// the answer is a constant and nothing survives to run time -- a neper binary carries
// no runtime type information (spec section 9).
//
// `TypeKind` is ordinary source. The functions are compiler intrinsics, because what
// they report is what the checker knows and a library cannot see. `Field` and `Member`
// are not here yet: both carry a `ty: type`, and a comptime-only field is a shape the
// checker does not represent, which is the same thing that keeps `fields`, `members`,
// `get` and `set` out of this increment.

type TypeKind = enum u8 {
    Int,
    Float,
    Bool,
    Err,
    Pointer,
    Slice,
    Array,
    Struct,
    Enum,
    UnionEnum,
    Vec,
}
