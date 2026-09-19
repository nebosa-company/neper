use e.mem

// Copying a two-pointer aggregate preserves the second field's region identity
// across the deferred-reset boundary (D693).
type Stable = struct { value: u8 }
type Pair = struct { stable: *Stable, scratch: *u8 }

fn borrowed(a: *mem.Arena) -> (Pair, err) {
    var stable = Stable { value: 1u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let pair = Pair { stable: &stable, scratch: &scratch[0usize] }
    let copy = pair
    defer mem.reset(a, checkpoint)
    ret (copy, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pair = try borrowed(a)
    if *pair.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
