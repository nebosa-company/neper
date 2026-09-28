// Compiled against `dep.Q`'s layout: its size and the offset of `b`.
use dep
use e.mem

fn read() -> i32 {
    let v = dep.make_q()
    ret i32(mem.size_of[dep.Q]()) + v.b
}
