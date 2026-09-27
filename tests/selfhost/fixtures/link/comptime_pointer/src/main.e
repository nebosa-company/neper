// Pointers in the comptime interpreter (D1573, C066): `&x` of a local, a field and
// an element; a store and a read through `*p`; a field through a pointer; a pointer
// handed to a function that changes what it points at; two addresses compared; and
// `mem.cast` between pointer types over the same bytes, read in the target's layout.
use e.mem

error Wrong

type Counter = struct { hits: u32, misses: u32 }

fn bump(c: *Counter, by: u32) {
    c.hits += by
    let snapshot = *c
    c.misses = snapshot.hits * 2u32
}

fn pointers() -> u32 {
    var total = 5u32
    let p = &total
    *p = *p + 1u32
    var counter = Counter { hits: 1u32, misses: 0u32 }
    bump(&counter, 3u32)
    var cells: [3]u32 = zero
    let second = &cells[1usize]
    *second = 40u32
    let same = &cells[1usize] == second
    var answer = total + counter.hits + counter.misses + cells[1usize]
    if same { answer += 1000u32 }
    ret answer
}

fn low_byte() -> usize {
    var word = 258u32
    let bytes = mem.cast[*u8](&word)
    ret usize(*bytes)
}

const POINTERS = pointers()
const LOW = low_byte()

fn main() -> err {
    if POINTERS != 1058u32 { ret Wrong }
    if LOW != 2usize { ret Wrong }
    var sized: [LOW]u8 = zero
    if sized.len != 2usize { ret Wrong }
    ret ok
}
