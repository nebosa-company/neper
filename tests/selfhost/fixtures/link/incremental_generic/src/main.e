// An importer of a generic type is kept by an unchanged warm build: the edge to `List`
// must hold against the interface, which declares the generic and not its instances.
use e.data.list as list

type Item = struct { key: i32 }

fn main() -> i32 {
    var items: list.List[Item] = zero
    ret i32(items.len)
}
