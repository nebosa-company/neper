use e.dist.replica as replica
use e.os

fn main() -> err {
    let top = 0usize -% 1usize
    let (overlap, result) = replica.quorum(top, top, top)
    if result != ok { os.exit(1i32) }
    if !overlap { os.exit(2i32) }
    ret ok
}
