use shapes

// A `cmp` for `shapes.Point` declared here, which rule 4 never reads (D430).
fn point_cmp(p: shapes.Point, q: shapes.Point) -> i32 {
    if p.x < q.x { ret -1i32 }
    ret 0i32
}
