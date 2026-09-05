type Left = enum u8 {
    Value,
}

type Right = enum u8 {
    Value,
}

fn same(left: Left, right: Right) -> bool {
    ret left == right
}
