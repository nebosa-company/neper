use e.mem

// A local already bound in an active scope (T029): the inner one is renamed with its
// uses up to the end of its block; the outer one's uses are left alone.
fn main(a: *mem.Arena, args: []str) -> err {
    let count = 2u32
    if count == 2u32 {
        let count = 5u32
        if count != 5u32 { ret mem.Exhausted }
    }
    if count != 2u32 { ret mem.Exhausted }
    ret ok
}
