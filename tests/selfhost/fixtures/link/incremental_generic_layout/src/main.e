// A module that takes a generic type only through generic calls, never spelling its
// name: its instances read the type's layout, so a field reorder rebuilds it.
use box

fn main() -> i32 {
    var b = box.make[i32](5i32)
    ret i32(box.count[i32](&b)) - 7i32
}
