use e.algo.schedule
use e.mem
use e.os

fn main(a: *mem.Arena) -> err {
    let tasks = [2]usize { 0usize, 0usize }
    var counts: [1]usize = zero
    let (result, e) = schedule.cooldown(tasks[..], 1usize, 18446744073709551615usize, counts[..])
    if e != schedule.Invalid { os.exit(3i32) }
    ret ok
}
