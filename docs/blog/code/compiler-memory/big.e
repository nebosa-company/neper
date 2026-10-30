use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let size = 42949672960usize
    let (table, table_error) = mem.alloc[u8](a, size)
    if table_error != ok { ret table_error }
    table[size - 1usize] = 1u8
    try io.printf["ceiling {} MiB: 40960 MiB allocated\n"](mem.stats(a).capacity / 1048576usize)
    ret ok
}
