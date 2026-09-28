// Compiled against `dep.P`'s layout: its size and the offset of `b`.
use dep
use e.mem

fn read() -> i32 {
    let v = dep.make_p()
    ret i32(mem.size_of[dep.P]()) + v.b
}
