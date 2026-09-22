use shapes as s

type Inner = struct {
    value: i32,
}

type Outer = struct {
    inner: Inner,
    values: [3]u16,
}

type Choice = union {
    number: i32,
    flag: u8,
}

type Maybe = union enum u8 {
    None,
    Some: i32,
}

fn mutate(pointer: *Outer, readonly: *const Outer) -> i32 {
    pointer.inner.value = 8i32
    pointer.values[0] = 9u16
    let field_pointer: *i32 = &pointer.inner.value
    let readonly_field: *const i32 = &readonly.inner.value
    *field_pointer = 10i32
    ret *readonly_field
}

fn run() -> i32 {
    var outer = Outer{
        inner: Inner{ value: 1i32 },
        values: [_]u16{ 2u16, 3u16, 4u16 },
    }
    outer.inner.value = 5i32
    outer.values[1] = 6u16
    let field_pointer: *i32 = &outer.inner.value
    let selected = Choice{ number: 7i32 }
    let none = Maybe{ None }
    let some = Maybe{ Some: 8i32 }
    let remote = s.Remote{ value: 9i32 }
    let explicit = [2]i32{ 10i32, 11i32 }
    ret *field_pointer + selected.number + some.Some + remote.value + explicit[0]
}
