// `type` is a compile-time parameter kind, not something a field can hold. This is
// what `e.meta`'s `Field` needs and cannot have yet, and it used to be reported as a
// location-less "type checking failed" rather than as anything to do with the field.

type Holder = struct {
    ty: type,
}

fn main() -> err { ret ok }
