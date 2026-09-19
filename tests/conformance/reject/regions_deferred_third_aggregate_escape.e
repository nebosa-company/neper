use e.mem

// A carrier cannot escape when its third pointer field belongs to the region
// reset before return, even if its first two pointers name live storage (D697).
type Stable = struct { value: u8 }
type Trio = struct { first: *Stable, second: *Stable, scratch: *u8 }

fn borrowed(a: *mem.Arena) -> (Trio, err) {
    var first = Stable { value: 1u8 }
    var second = Stable { value: 2u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let trio = Trio { first: &first, second: &second, scratch: &scratch[0usize] }
    defer mem.reset(a, checkpoint)
    ret (trio, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let trio = try borrowed(a)
    if *trio.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
