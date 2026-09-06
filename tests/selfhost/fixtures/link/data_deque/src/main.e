use e.data.deque as deque
use e.io
use e.mem

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    let (initial, init_error) = deque.init[i64](a, 1usize)
    if init_error != ok { ret init_error }
    var values = initial
    try deque.push_back[i64](&values, 20i64)
    try deque.push_front[i64](&values, 10i64)
    try deque.push_back[i64](&values, 30i64)
    if deque.len[i64](&values) != 3usize { ret Failed }
    if deque.get[i64](&values, 0usize) != 10i64 || deque.get[i64](&values, 1usize) != 20i64 || deque.get[i64](&values, 2usize) != 30i64 { ret Failed }

    let (front, has_front) = deque.pop_front[i64](&values)
    if !has_front || front != 10i64 { ret Failed }
    try deque.push_back[i64](&values, 40i64)
    try deque.push_front[i64](&values, 10i64)
    try deque.reserve[i64](&values, 9usize)
    if deque.get[i64](&values, 0usize) != 10i64 || deque.get[i64](&values, 1usize) != 20i64 || deque.get[i64](&values, 2usize) != 30i64 || deque.get[i64](&values, 3usize) != 40i64 { ret Failed }

    var it = deque.iter[i64](&values)
    let (one, has_one) = deque.iter_next[i64](&it)
    let (two, has_two) = deque.iter_next[i64](&it)
    let (three, has_three) = deque.iter_next[i64](&it)
    let (four, has_four) = deque.iter_next[i64](&it)
    let (_, has_five) = deque.iter_next[i64](&it)
    if !has_one || !has_two || !has_three || !has_four || has_five { ret Failed }
    if one != 10i64 || two != 20i64 || three != 30i64 || four != 40i64 { ret Failed }

    let (back, has_back) = deque.pop_back[i64](&values)
    if !has_back || back != 40i64 { ret Failed }
    deque.clear[i64](&values)
    if deque.len[i64](&values) != 0usize { ret Failed }
    let (_, empty_front) = deque.pop_front[i64](&values)
    let (_, empty_back) = deque.pop_back[i64](&values)
    if empty_front || empty_back { ret Failed }

    let (empty_initial, empty_error) = deque.init[i64](a, 0usize)
    if empty_error != ok { ret empty_error }
    var empty = empty_initial
    try deque.push_front[i64](&empty, 7i64)
    try deque.push_back[i64](&empty, 8i64)
    if deque.get[i64](&empty, 0usize) != 7i64 || deque.get[i64](&empty, 1usize) != 8i64 { ret Failed }

    try io.print("data deque ok\n")
    ret ok
}
