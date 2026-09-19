use e.mem

// A third pointer-bearing field retains its own region identity rather than being
// hidden behind the first two fields (D696).
type Stable = struct { value: u8 }
type Trio = struct { first: *Stable, second: *Stable, scratch: *u8 }

fn main(a: *mem.Arena, args: []str) -> err {
    var first = Stable { value: 1u8 }
    var second = Stable { value: 2u8 }
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let trio = Trio { first: &first, second: &second, scratch: &scratch[0usize] }
    mem.reset(a, checkpoint)
    if *trio.scratch != 0u8 { ret mem.Exhausted }
    ret ok
}
