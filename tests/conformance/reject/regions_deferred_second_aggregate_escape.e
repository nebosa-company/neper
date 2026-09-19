use e.mem

// A carrier cannot escape when its second pointer field belongs to the region
// reset before return, even if its first pointer names live storage (D692).
type Stable = struct { value: u8 }
type Pair = struct { stable: *Stable, scratch: *u8 }

fn borrowed(a: *mem.Arena) -> (Pair, err) {
    var stable = Stable { value: 1u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let pair = Pair { stable: &stable, scratch: &scratch[0usize] }
    defer mem.reset(a, checkpoint)
    ret (pair, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pair = try borrowed(a)
    if *pair.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
