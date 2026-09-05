use e.mem as mem
use item as item

type Local = struct {
    value: usize,
}

type Bytes = []u8

fn run(a: *mem.Arena) -> err {
    let bytes = try mem.alloc[u8](a, 4usize)
    let (locals, local_error) = mem.alloc[Local](a, 2usize)
    let qualified = try mem.alloc[item.Item](a, 1usize)
    let pointers = try mem.alloc[*u8](a, 3usize)
    let nested = try mem.alloc[Bytes](a, 2usize)
    ret local_error
}
