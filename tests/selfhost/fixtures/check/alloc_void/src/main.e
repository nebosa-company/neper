use e.mem as mem

fn run(a: *mem.Arena) -> err {
    let values = try mem.alloc[void](a, 1usize)
    ret ok
}
