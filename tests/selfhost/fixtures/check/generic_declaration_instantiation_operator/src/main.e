type Item = struct {
    value: i32,
}

fn greater[T: type](left: T, right: T) -> bool {
    ret left > right
}

fn bad(left: Item, right: Item) -> bool {
    ret greater(left, right)
}
