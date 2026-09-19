use e.mem

// Assigning a third pointer field records its region identity independently of
// the two pointer fields already assigned (D699).
type Stable = struct { value: u8 }
type Trio = struct { first: *Stable, second: *Stable, scratch: *u8 }

fn borrowed(a: *mem.Arena) -> (Trio, err) {
    var first = Stable { value: 1u8 }
    var second = Stable { value: 2u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    var trio: Trio = zero
    trio.first = &first
    trio.second = &second
    trio.scratch = &scratch[0usize]
    defer mem.reset(a, checkpoint)
    ret (trio, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let trio = try borrowed(a)
    if *trio.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
