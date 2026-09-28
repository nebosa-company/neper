// Compiled against `dep.Q`'s layout: its size and the offset of `b`.
use dep
use e.mem

fn read() -> i32 {
    let v = dep.make_q()
    ret i32(mem.size_of[dep.Q]()) + v.b
}

// A `@reorder` record at a C-convention boundary (D239), refused when `dep` is declared
// from its Interface as when it is parsed.
@cc(c)
fn cross(r: *dep.Q) -> i32 {
    ret 0i32
}
