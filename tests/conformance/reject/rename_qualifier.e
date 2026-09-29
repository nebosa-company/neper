use e.mem

// A local named for a use qualifier (T029): renamed where it is the local, not where
// `mem.` still leads to the module.
fn main(a: *mem.Arena, args: []str) -> err {
    let (mem, alloc_error) = mem.alloc[u8](a, 4usize)
    if alloc_error != ok { ret alloc_error }
    mem[0usize] = 104u8
    if mem.len != 4usize { ret mem.Exhausted }
    ret ok
}
