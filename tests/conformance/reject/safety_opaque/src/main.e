use e.mem
use resource_lib

fn main(a: *mem.Arena, args: []str) -> err {
    let t = try resource_lib.acquire(a)
    let n = t.slot
    ret resource_lib.release(t)
}
