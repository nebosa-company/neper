type Item = struct { key: i64, payload: i64 }

fn item_cmp(a: Item, b: Item) -> i32 {
    if a.key < b.key { ret 0i32 - 1i32 }
    if a.key > b.key { ret 1i32 }
    ret 0i32
}

fn reverse_cmp(a: Item, b: Item) -> i32 { ret 0i32 - item_cmp(a, b) }
