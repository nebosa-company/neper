use e.mem as mem

fn run(a: *mem.Arena) -> err {
    let bytes = try mem.alloc[u8, i32](a, 1usize)
    ret ok
}
