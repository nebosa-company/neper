use e.mem

// Copying an arena parameter preserves its lexical storage identity (D676).
fn main(a: *mem.Arena, args: []str) -> err {
    let alias = a
    let checkpoint = mem.mark(alias)
    let scratch = try mem.alloc[u8](a, 8usize)
    mem.reset(a, checkpoint)
    scratch[0usize] = 1u8
    ret ok
}
