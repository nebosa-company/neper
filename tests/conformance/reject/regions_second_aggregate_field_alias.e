use e.mem

// Each of two pointer fields keeps its own lexical storage identity (D691).
type Stable = struct { value: u8 }
type Pair = struct { stable: *Stable, scratch: *u8 }

fn main(a: *mem.Arena, args: []str) -> err {
    var stable = Stable { value: 1u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let pair = Pair { stable: &stable, scratch: &scratch[0usize] }
    mem.reset(a, checkpoint)
    if *pair.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
