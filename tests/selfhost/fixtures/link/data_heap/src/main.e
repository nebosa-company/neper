use e.data.heap
use e.io
use e.mem

error Failed

type Task = struct { cost: i64, id: i64 }

fn task_cmp(a: Task, b: Task) -> i32 {
    if a.cost < b.cost { ret 0i32 - 1i32 }
    if a.cost > b.cost { ret 1i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (empty, empty_error) = heap.init[i64](a, 0usize)
    if empty_error != ok { ret empty_error }
    var h = empty
    if heap.len[i64](&h) != 0usize { ret Failed }
    let (_, has_peek) = heap.peek[i64](&h)
    let (_, has_pop) = heap.pop[i64](&h)
    if has_peek || has_pop { ret Failed }

    // A min-heap under the supplied cmp for integers.
    try heap.push[i64](&h, 5i64)
    try heap.push[i64](&h, 3i64)
    try heap.push[i64](&h, 9i64)
    try heap.push[i64](&h, 1i64)
    try heap.push[i64](&h, 7i64)
    if heap.len[i64](&h) != 5usize { ret Failed }
    let (smallest, has_smallest) = heap.peek[i64](&h)
    if !has_smallest || smallest != 1i64 { ret Failed }

    var previous = 0i64 - 1i64
    var drained = 0usize
    while true {
        let (value, more) = heap.pop[i64](&h)
        if !more { break }
        if value < previous { ret Failed }
        previous = value
        drained += 1usize
    }
    if drained != 5usize || previous != 9i64 || heap.len[i64](&h) != 0usize { ret Failed }

    // Bulk construction, then a drain in order.
    var source: [6]i64 = [6]i64{ 8i64, 2i64, 6i64, 0i64, 4i64, 2i64 }
    let (bulk, bulk_error) = heap.from_slice[i64](a, source[..])
    if bulk_error != ok { ret bulk_error }
    var b = bulk
    if heap.len[i64](&b) != 6usize { ret Failed }
    let (bulk_smallest, has_bulk_smallest) = heap.peek[i64](&b)
    if !has_bulk_smallest || bulk_smallest != 0i64 { ret Failed }
    var order: [6]i64 = zero
    var at = 0usize
    while at < 6usize {
        let (value, more) = heap.pop[i64](&b)
        if !more { ret Failed }
        order[at] = value
        at += 1usize
    }
    if order[0usize] != 0i64 || order[1usize] != 2i64 || order[2usize] != 2i64 { ret Failed }
    if order[3usize] != 4i64 || order[4usize] != 6i64 || order[5usize] != 8i64 { ret Failed }

    // heapify_in_place over a bare slice, and iteration over internal order.
    var raw: [4]i64 = [4]i64{ 9i64, 1i64, 8i64, 3i64 }
    heap.heapify_in_place[i64](raw[..])
    if raw[0usize] != 1i64 { ret Failed }

    let (view_source, view_error) = heap.from_slice[i64](a, raw[..])
    if view_error != ok { ret view_error }
    var view = view_source
    var it = heap.iter[i64](&view)
    var seen = 0usize
    var total = 0i64
    while true {
        let (value, more) = heap.iter_next[i64](&it)
        if !more { break }
        seen += 1usize
        total += value
    }
    if seen != 4usize || total != 21i64 { ret Failed }

    heap.clear[i64](&view)
    if heap.len[i64](&view) != 0usize { ret Failed }
    let (_, cleared_pop) = heap.pop[i64](&view)
    if cleared_pop { ret Failed }

    // A user type orders by the cmp its own module declares.
    let (tasks_empty, tasks_error) = heap.init[Task](a, 2usize)
    if tasks_error != ok { ret tasks_error }
    var tasks = tasks_empty
    try heap.push[Task](&tasks, Task { cost: 40i64, id: 1i64 })
    try heap.push[Task](&tasks, Task { cost: 10i64, id: 2i64 })
    try heap.push[Task](&tasks, Task { cost: 30i64, id: 3i64 })
    let (cheapest, has_cheapest) = heap.pop[Task](&tasks)
    if !has_cheapest || cheapest.id != 2i64 { ret Failed }
    let (next_cheapest, has_next) = heap.pop[Task](&tasks)
    if !has_next || next_cheapest.id != 3i64 { ret Failed }
    if heap.len[Task](&tasks) != 1usize { ret Failed }

    try io.print("data heap ok\n")
    ret ok
}
