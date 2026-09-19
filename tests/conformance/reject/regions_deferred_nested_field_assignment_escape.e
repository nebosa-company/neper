use e.mem

// Assigning a pointer-bearing aggregate into a field gives the outer aggregate the
// enclosed address's deferred-reset boundary (D690).
type Leaf = struct { byte: *u8 }
type Outer = struct { inner: Leaf }

fn borrowed(a: *mem.Arena) -> (Outer, err) {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    var outer: Outer = zero
    outer.inner = Leaf { byte: &scratch[0usize] }
    defer mem.reset(a, checkpoint)
    ret (outer, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let outer = try borrowed(a)
    if *outer.inner.byte != 0u8 { ret mem.Exhausted }
    ret ok
}
