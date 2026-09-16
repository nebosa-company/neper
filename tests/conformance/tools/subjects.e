use e.mem

// A constant and a global as context subjects (D437, H08): `LIMIT` is settled by
// the interpreter, `counter` is every thread's and starts at zero.
const LIMIT: i64 = 3i64 * 7i64
var counter: u32

fn main(a: *mem.Arena, args: []str) -> err {
    counter = counter + u32(LIMIT)
    ret ok
}
