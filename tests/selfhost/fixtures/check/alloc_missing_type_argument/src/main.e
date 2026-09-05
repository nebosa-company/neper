use e.mem as mem

fn run(a: *mem.Arena) -> err {
    let bytes = try mem.alloc[](a, 1usize)
    ret ok
}
