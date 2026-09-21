// `e.algo.schedule`: activity selection picks the classic four of six
// intervals, interval covering needs two points for four intervals, job
// sequencing with deadlines places the textbook profit, and the cooldown
// bound matches the known answers. Each check exits with its own code.

use e.algo.schedule
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: activity selection on (1,4) (3,5) (0,6) (5,7) (3,9) (5,9) (6,10) (8,11): four fit.
    var starts: [8]i64 = zero
    var ends: [8]i64 = zero
    starts[0usize] = 1i64
    ends[0usize] = 4i64
    starts[1usize] = 3i64
    ends[1usize] = 5i64
    starts[2usize] = 0i64
    ends[2usize] = 6i64
    starts[3usize] = 5i64
    ends[3usize] = 7i64
    starts[4usize] = 3i64
    ends[4usize] = 9i64
    starts[5usize] = 5i64
    ends[5usize] = 9i64
    starts[6usize] = 6i64
    ends[6usize] = 10i64
    starts[7usize] = 8i64
    ends[7usize] = 11i64
    var chosen: [8]usize = zero
    var order: [8]usize = zero
    let (count, select_error) = schedule.activity_selection(starts[..], ends[..], chosen[..], order[..])
    if select_error != ok || count != 3usize || chosen[0usize] != 0usize || chosen[1usize] != 3usize || chosen[2usize] != 7usize { os.exit(1i32) }
    let (none, none_error) = schedule.activity_selection(starts[..0usize], ends[..], chosen[..], order[..])
    if none_error != ok || none != 0usize { os.exit(1i32) }
    ends[0usize] = 0i64
    let (_, invalid) = schedule.activity_selection(starts[..], ends[..], chosen[..], order[..])
    if invalid != schedule.Invalid { os.exit(1i32) }
    ends[0usize] = 4i64
    let (_, room) = schedule.activity_selection(starts[..], ends[..], chosen[..4usize], order[..])
    if room != schedule.TooSmall { os.exit(1i32) }

    // 2: interval cover.
    var points: [8]i64 = zero
    let (needed, cover_error) = schedule.interval_cover(starts[..], ends[..], points[..], order[..])
    // End order: (1,4) -> point 3 covers (1,4),(3,5),(0,6),(3,9); (5,7) -> point 6 covers (5,7),(5,9),(6,10); (8,11) -> point 10.
    if cover_error != ok || needed != 3usize || points[0usize] != 3i64 || points[1usize] != 6i64 || points[2usize] != 10i64 { os.exit(2i32) }
    starts[0usize] = 4i64
    let (_, cover_invalid) = schedule.interval_cover(starts[..], ends[..], points[..], order[..])
    if cover_invalid != schedule.Invalid { os.exit(2i32) }
    starts[0usize] = 1i64

    // 3: jobs with deadlines (a: 2, 100) (b: 1, 19) (c: 2, 27) (d: 1, 25) (e: 3, 15): c, a, e for 142.
    var deadlines: [5]usize = zero
    var profits: [5]i64 = zero
    deadlines[0usize] = 2usize
    profits[0usize] = 100i64
    deadlines[1usize] = 1usize
    profits[1usize] = 19i64
    deadlines[2usize] = 2usize
    profits[2usize] = 27i64
    deadlines[3usize] = 1usize
    profits[3usize] = 25i64
    deadlines[4usize] = 3usize
    profits[4usize] = 15i64
    var slots: [4]usize = zero
    var parent: [4]usize = zero
    let (profit, placed, jobs_error) = schedule.jobs_with_deadlines(deadlines[..], profits[..], slots[..], parent[..], order[..])
    if jobs_error != ok || profit != 142i64 || placed != 3usize || slots[1usize] != 0usize || slots[0usize] != 2usize || slots[2usize] != 4usize { os.exit(3i32) }
    let (_, _, jobs_room) = schedule.jobs_with_deadlines(deadlines[..], profits[..], slots[..2usize], parent[..], order[..])
    if jobs_room != schedule.TooSmall { os.exit(3i32) }

    // 4: cooldown: AAABBB with gap 2 -> 8; AAABBB gap 0 -> 6; AAAAAABCDEFG gap 2 -> 16.
    var tasks: [12]usize = zero
    tasks[3usize] = 1usize
    tasks[4usize] = 1usize
    tasks[5usize] = 1usize
    var counts: [7]usize = zero
    let (t1, t1_error) = schedule.cooldown(tasks[..6usize], 2usize, 2usize, counts[..])
    if t1_error != ok || t1 != 8usize { os.exit(4i32) }
    let (t2, t2_error) = schedule.cooldown(tasks[..6usize], 2usize, 0usize, counts[..])
    if t2_error != ok || t2 != 6usize { os.exit(4i32) }
    var i = 0usize
    while i < 12usize {
        if i < 6usize { tasks[i] = 0usize } else { tasks[i] = i - 5usize }
        i += 1usize
    }
    let (t3, t3_error) = schedule.cooldown(tasks[..], 7usize, 2usize, counts[..])
    if t3_error != ok || t3 != 16usize { os.exit(4i32) }
    let (t4, t4_error) = schedule.cooldown(tasks[..0usize], 7usize, 2usize, counts[..])
    if t4_error != ok || t4 != 0usize { os.exit(4i32) }
    let (_, t_invalid) = schedule.cooldown(tasks[..], 3usize, 2usize, counts[..])
    if t_invalid != schedule.Invalid { os.exit(4i32) }

    try io.print("algo schedule ok\n")
    ret ok
}
