use e.mem

// `mem.Arena` is affine (D351): an arena moved into another binding is gone from
// the first, so allocating from it there is E-SAFETY-0001.
fn main(a: *mem.Arena, args: []str) -> err {
    var backing: [256]u8 = zero
    var scratch = mem.arena_from(backing[..])
    var taken = scratch
    let (bytes, alloc_error) = mem.alloc[u8](&scratch, 16usize)
    if alloc_error != ok { ret alloc_error }
    let (more, more_error) = mem.alloc[u8](&taken, 16usize)
    ret more_error
}
