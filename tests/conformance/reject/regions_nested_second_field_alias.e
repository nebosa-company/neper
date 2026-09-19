use e.mem

// A later pointer below a recursively nested aggregate path keeps its own region
// identity instead of resolving to the first pointer under that path (D701).
type Stable = struct { value: u8 }
type Inner = struct { stable: *Stable, scratch: *u8 }
type Middle = struct { inner: Inner }
type Outer = struct { middle: Middle }

fn main(a: *mem.Arena, args: []str) -> err {
    var stable = Stable { value: 1u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let outer = Outer { middle: Middle { inner: Inner { stable: &stable, scratch: &scratch[0usize] } } }
    mem.reset(a, checkpoint)
    if *outer.middle.inner.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
