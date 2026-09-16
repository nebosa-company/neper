use e.mem

// A pointer bound from `&cells[0]` reaches the storage the reset took away (D394):
// E-SAFETY-0013 through the alias, as through `cells` itself.
type Cell = struct { hits: i64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let checkpoint = mem.mark(a)
    let cells = try mem.alloc[Cell](a, 4usize)
    let first = &cells[0usize]
    first.hits = 1i64
    mem.reset(a, checkpoint)
    if first.hits != 1i64 { ret mem.Exhausted }
    ret ok
}
