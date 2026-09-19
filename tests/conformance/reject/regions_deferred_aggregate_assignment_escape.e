use e.mem

// Assigning an aggregate also copies its region-pointer identity (D685).
type Holder = struct { byte: *u8 }

fn borrowed(a: *mem.Arena) -> (Holder, err) {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let holder = Holder { byte: &scratch[0usize] }
    var assigned: Holder = zero
    assigned = holder
    defer mem.reset(a, checkpoint)
    ret (assigned, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let holder = try borrowed(a)
    if *holder.byte != 0u8 { ret mem.Exhausted }
    ret ok
}
