use e.mem as mem

fn run(a: *mem.Arena) -> err {
    let bytes = try mem.alloc[u8](a)
    ret ok
}
