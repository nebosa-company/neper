use e.mem as mem

fn run(a: *mem.Arena) -> err {
    let count = 1usize
    let bytes = try mem.alloc[count](a, count)
    ret ok
}
