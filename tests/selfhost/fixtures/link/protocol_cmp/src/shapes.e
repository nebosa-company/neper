// Two types in one module, each carrying its own `cmp` protocol function.

type Point = struct { x: i64, y: i64 }
type Tag = struct { id: i64 }

fn point_cmp(a: Point, b: Point) -> i32 {
    if a.x < b.x { ret 0i32 - 1i32 }
    if a.x > b.x { ret 1i32 }
    ret 0i32
}

fn tag_cmp(a: Tag, b: Tag) -> i32 {
    if a.id > b.id { ret 0i32 - 1i32 }
    if a.id < b.id { ret 1i32 }
    ret 0i32
}
