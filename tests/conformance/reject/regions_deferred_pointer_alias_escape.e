use e.mem

// A pointer read from an aggregate cannot escape the reset of its storage (D682).
type Holder = struct { byte: *u8 }

fn borrowed(a: *mem.Arena) -> (*u8, err) {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let holder = Holder { byte: &scratch[0usize] }
    let result = holder.byte
    defer mem.reset(a, checkpoint)
    ret (result, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let byte = try borrowed(a)
    if *byte != 0u8 { ret mem.Exhausted }
    ret ok
}
