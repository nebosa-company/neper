use e.mem

// Assigning a sibling pointer field does not erase the stored region identity
// of the first field (D694).
type Stable = struct { value: u8 }
type Pair = struct { stable: *Stable, scratch: *u8 }

fn borrowed(a: *mem.Arena) -> (Pair, err) {
    var stable = Stable { value: 1u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    var pair: Pair = zero
    pair.scratch = &scratch[0usize]
    pair.stable = &stable
    defer mem.reset(a, checkpoint)
    ret (pair, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pair = try borrowed(a)
    if *pair.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
