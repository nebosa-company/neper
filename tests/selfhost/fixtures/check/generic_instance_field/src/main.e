// `e.sync`'s shape: a lock is a struct holding one instance of a generic. An
// aggregate's fields are one contiguous run, and instantiating a generic appends
// the instance's own fields -- which used to split the run being collected here,
// so `Holder` exposed `Box`'s `v` and hid its own `slot`.
type Box[T: type] = struct { v: T }
type Holder = struct { slot: Box[u32], count: u32 }

fn main() -> i64 {
    var h: Holder = zero
    h.slot.v = 7u32
    h.count = 1u32
    let one = h.slot
    if one.v == 7u32 && h.count == 1u32 { ret 0i64 }
    ret 1i64
}
