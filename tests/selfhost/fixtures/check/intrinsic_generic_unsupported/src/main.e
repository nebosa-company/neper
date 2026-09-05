use e.mem as mem

fn run(a: *mem.Arena) {
    mem.alloc[u8](a, 1usize)
}
