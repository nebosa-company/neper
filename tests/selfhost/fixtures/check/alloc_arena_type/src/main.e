use e.mem as mem

fn run(pointer: *u8) -> err {
    let bytes = try mem.alloc[u8](pointer, 1usize)
    ret ok
}
