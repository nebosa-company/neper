use e.mem

// Copying an aggregate preserves a third field's region identity across the
// deferred-reset boundary (D698).
type Stable = struct { value: u8 }
type Trio = struct { first: *Stable, second: *Stable, scratch: *u8 }

fn borrowed(a: *mem.Arena) -> (Trio, err) {
    var first = Stable { value: 1u8 }
    var second = Stable { value: 2u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let trio = Trio { first: &first, second: &second, scratch: &scratch[0usize] }
    let copy = trio
    defer mem.reset(a, checkpoint)
    ret (copy, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let trio = try borrowed(a)
    if *trio.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
