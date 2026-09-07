// An entry point taking a different context than the one bound. The two pointers
// have to agree, and the call is the only place the context type still exists.

use e.mem
use e.os

type Ctx = struct { n: usize }
type Other = struct { m: usize }

fn worker(c: *Other) {
    c.m = 1usize
}

fn main(a: *mem.Arena) -> err {
    var ctx: Ctx = zero
    let (t, e) = os.thread_create[Ctx](worker, &ctx, 1048576usize)
    ret e
}
