use e.mem

// Copying a recursively nested carrier preserves the later pointer path across
// the deferred-reset boundary (D703).
type Stable = struct { value: u8 }
type Inner = struct { stable: *Stable, scratch: *u8 }
type Middle = struct { inner: Inner }
type Outer = struct { middle: Middle }

fn borrowed(a: *mem.Arena) -> (Outer, err) {
    var stable = Stable { value: 1u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let outer = Outer { middle: Middle { inner: Inner { stable: &stable, scratch: &scratch[0usize] } } }
    let copy = outer
    defer mem.reset(a, checkpoint)
    ret (copy, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let outer = try borrowed(a)
    if *outer.middle.inner.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
