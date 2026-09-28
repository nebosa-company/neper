// Compiled against `dep.P`'s layout: its size and the offset of `b`. Only the body
// changes, so `p` is rebuilt against `dep` declared from its Interface (D1511).
use dep
use e.mem

fn read() -> i32 {
    let v = dep.make_p()
    ret v.b + i32(mem.size_of[dep.P]())
}
