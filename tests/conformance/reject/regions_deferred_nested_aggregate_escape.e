use e.mem

// A nested aggregate literal still carries the address it encloses across the
// deferred-reset boundary (D689).
type Leaf = struct { byte: *u8 }
type Outer = struct { inner: Leaf }

fn borrowed(a: *mem.Arena) -> (Outer, err) {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let outer = Outer { inner: Leaf { byte: &scratch[0usize] } }
    defer mem.reset(a, checkpoint)
    ret (outer, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let outer = try borrowed(a)
    if *outer.inner.byte != 0u8 { ret mem.Exhausted }
    ret ok
}
