use e.mem

const USED = 1usize
const IDLE = 2usize
error Gone
type Point = struct { x: i32 }
type Spare = struct { y: i32 }
fn point_cmp(a: i32) -> i32 { ret a }
fn helper() -> usize { ret USED }
fn dead() -> usize { ret 0usize }

fn main() {
    var arena: mem.Arena = zero
    let n = helper()
}
