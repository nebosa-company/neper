// A generic function instantiated by name stands as a value (D772): `call[Counter]` is
// a pointer to that instance, so a record can hold a typed trampoline behind a `*void`
// callback and a caller that knows nothing of the type can run it.

use e.io
use e.mem
use e.os

type Erased = struct { ctx: *void, run: fn(*void) -> err }
type Bound[Ctx: type] = struct { ctx: *Ctx, f: fn(*Ctx, u32) -> err, by: u32 }
type Counter = struct { n: u32 }
type Wide = struct { total: u64 }

fn bump(c: *Counter, by: u32) -> err {
    c.n += by
    ret ok
}

fn widen(w: *Wide, by: u32) -> err {
    w.total += u64(by) * 1000u64
    ret ok
}

fn call[Ctx: type](p: *void) -> err {
    let b = mem.cast[*Bound[Ctx]](p)
    ret b.f(b.ctx, b.by)
}

fn erase[Ctx: type](b: *Bound[Ctx]) -> Erased {
    ret Erased { ctx: mem.cast[*void](b), run: call[Ctx] }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var c = Counter { n: 1u32 }
    var w = Wide { total: 5u64 }
    var first = Bound[Counter] { ctx: &c, f: bump, by: 41u32 }
    var second = Bound[Wide] { ctx: &w, f: widen, by: 3u32 }
    var jobs: [2]Erased = [2]Erased{ erase[Counter](&first), erase[Wide](&second) }
    var i = 0usize
    while i < 2usize {
        try jobs[i].run(jobs[i].ctx)
        i += 1usize
    }
    if c.n != 42u32 || w.total != 3005u64 { os.exit(1i32) }
    // The same instance named twice is one function.
    let again = erase[Counter](&first)
    try again.run(again.ctx)
    if c.n != 83u32 { os.exit(2i32) }
    try io.print("generic value ok\n")
    ret ok
}
