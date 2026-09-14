use e.mem
use e.atomic

fn main(a: *mem.Arena, args: []str) -> err {
    var n = atomic.init(0u32)
    let v = atomic.load(&n, .Release)
    ret ok
}
