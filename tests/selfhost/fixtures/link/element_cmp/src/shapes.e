// `tag_cmp` deliberately reverses, so a comparison that ignored the declaration
// and fell back to anything structural would order the other way.

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
