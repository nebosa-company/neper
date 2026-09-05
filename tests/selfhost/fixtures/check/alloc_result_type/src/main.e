use e.mem as mem

fn run(a: *mem.Arena) -> err {
    let values: []i32 = try mem.alloc[u8](a, 1usize)
    ret ok
}
