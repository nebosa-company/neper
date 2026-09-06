use e.mem
use e.os
use e.io

fn main(a: *mem.Arena, startup: []str) -> err {
    let (args, args_error) = os.args(a)
    if args_error != ok || args.len != startup.len { ret os.Failed }
    let (page, reserve_error) = os.reserve(4096usize)
    if reserve_error != ok { ret reserve_error }
    let commit_error = os.commit(page, 4096usize)
    if commit_error != ok { ret commit_error }
    *page = 77u8
    if *page != 77u8 { ret os.Failed }
    let (wall, wall_error) = os.clock(.Wall)
    if wall_error != ok || wall <= 0i64 { ret os.Failed }
    let (before, before_error) = os.clock(.Monotonic)
    let (after, after_error) = os.clock(.Monotonic)
    if before_error != ok || after_error != ok || after < before { ret os.Failed }
    try io.print("host memory clock ok")
    ret ok
}
