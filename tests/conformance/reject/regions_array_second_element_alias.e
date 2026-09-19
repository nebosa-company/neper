use e.mem

// Each pointer in a fixed-array literal keeps its comptime element path, so a
// later element cannot hide behind the first element's live owner (D706).
fn main(a: *mem.Arena, args: []str) -> err {
    var stable = 1u8
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let pointers = [2usize]*u8{ &stable, &scratch[0usize] }
    mem.reset(a, checkpoint)
    if *pointers[1usize] != 0u8 { ret mem.Exhausted }
    ret ok
}
