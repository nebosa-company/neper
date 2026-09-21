use e.mem
use e.os
use helper

// A record that names no declaration -- the synthesized `os.thread_create` --
// keeps naming none after an instance is made (D821): `helper.fill[u8]` is the
// first instance of the program and lands at the index the count had.
type Counter = struct { hits: [4]i64 }

fn bump(c: *Counter) {
    c.hits[0usize] = c.hits[0usize] + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var counter: Counter = zero
    let (worker, started) = os.thread_create[Counter](bump, &counter, 65536usize)
    if started != ok { ret started }
    try os.thread_join(worker)
    var out: [4]u8 = zero
    var source: [4]u8 = zero
    helper.fill[u8](out[..], source[..])
    if helper.count[u8](out[..]) != 4usize { ret mem.Exhausted }
    ret ok
}
