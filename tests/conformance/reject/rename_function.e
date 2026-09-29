use e.mem

// A local named for a module-scope function (T029): the fix renames the local and
// its uses in scope, and leaves the call of the function alone.
fn text(n: u32) -> u32 { ret n + 1u32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let text = text(2u32)
    let doubled = text * 2u32
    if doubled != 6u32 || text != 3u32 { ret mem.Exhausted }
    ret ok
}
