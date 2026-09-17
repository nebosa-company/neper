// Every function's first error (D553, H09): three functions that fail, three
// diagnostics from one check, in source order; `third` checks and is silent.
use e.mem

fn first(x: i32) -> i32 {
    ret x + 1u64
}

fn second(y: bool) -> i32 {
    ret y
}

fn third() -> i32 {
    ret 3i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let z: u8 = third()
    ret ok
}
