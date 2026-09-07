// `os.thread_create[Ctx]` binds the context type at the call and checks the entry
// point against it. The checker half only: nothing links yet, because the runtime
// does not implement `neper_os_thread_create`.

use e.mem
use e.os

type Ctx = struct {
    n: usize,
}

fn worker(c: *Ctx) {
    c.n = 7usize
}

fn main(a: *mem.Arena) -> err {
    var ctx: Ctx = zero
    let (t, e) = os.thread_create[Ctx](worker, &ctx, 1048576usize)
    if e != ok { ret e }
    let j = os.thread_join(t)
    ret j
}
