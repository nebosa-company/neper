use e.mem

// A carrier cannot escape when a later pointer on a recursively nested path
// belongs to the region reset before return (D702).
type Stable = struct { value: u8 }
type Inner = struct { stable: *Stable, scratch: *u8 }
type Middle = struct { inner: Inner }
type Outer = struct { middle: Middle }

fn borrowed(a: *mem.Arena) -> (Outer, err) {
    var stable = Stable { value: 1u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let outer = Outer { middle: Middle { inner: Inner { stable: &stable, scratch: &scratch[0usize] } } }
    defer mem.reset(a, checkpoint)
    ret (outer, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let outer = try borrowed(a)
    if *outer.middle.inner.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
