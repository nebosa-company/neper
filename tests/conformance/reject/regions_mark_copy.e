use e.mem

// A copied checkpoint still resets from the original mark position (D677).
fn main(a: *mem.Arena, args: []str) -> err {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let saved = checkpoint
    mem.reset(a, saved)
    scratch[0usize] = 1u8
    ret ok
}
