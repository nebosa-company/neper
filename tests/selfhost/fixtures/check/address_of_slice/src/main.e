// A slice is a pointer and a length, so it has no one address to hand back. `&s[0]`
// is how a byte of it is named, and that is what `mem.address_of` takes.
use e.mem

fn run(a: *mem.Arena) -> err {
    let (bytes, allocation_error) = mem.alloc[u8](a, 8usize)
    if allocation_error != ok { ret allocation_error }
    let address = mem.address_of(bytes)
    ret ok
}
