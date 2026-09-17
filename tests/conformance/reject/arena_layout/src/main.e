// A project whose own `e.mem` lays the arena out otherwise (D552): the build is
// refused at the declaration, since the embedded runtime reads the fields in place.
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let (bytes, alloc_error) = mem.alloc[u8](a, 16usize)
    if alloc_error != ok { ret alloc_error }
    os.exit(i32(bytes.len))
    ret ok
}
