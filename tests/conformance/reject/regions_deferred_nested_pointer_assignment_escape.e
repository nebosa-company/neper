use e.mem

// Separate assignments to recursively nested pointer fields retain both owners,
// including the later pointer into the deferred-reset region (D704).
type Stable = struct { value: u8 }
type Inner = struct { stable: *Stable, scratch: *u8 }
type Middle = struct { inner: Inner }
type Outer = struct { middle: Middle }

fn borrowed(a: *mem.Arena) -> (Outer, err) {
    var stable = Stable { value: 1u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    var outer: Outer = zero
    outer.middle.inner.stable = &stable
    outer.middle.inner.scratch = &scratch[0usize]
    defer mem.reset(a, checkpoint)
    ret (outer, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let outer = try borrowed(a)
    if *outer.middle.inner.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
