use e.mem

// The project replaces the toolchain's e.mem with a stub that has no arena_from:
// the diagnostic names the file, since every module is resolved against it.
fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [64]u8 = zero
    var scratch = mem.arena_from(storage[..])
    ret ok
}
