// The other half of `generic_instance_field`: the instance's fields must stay out
// of the enclosing struct's run. `Holder` declares `slot`, never `Box`'s `v`.
type Box[T: type] = struct { v: T }
type Holder = struct { slot: Box[u32] }

fn main() -> i64 {
    var h: Holder = zero
    let stolen = h.v
    ret 0i64
}
