use e.data.ring as ring
use e.io
use e.mem

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [3]i64 = zero
    var values = ring.init[i64](storage[..])
    if ring.len[i64](&values) != 0usize || ring.capacity[i64](&values) != 3usize { ret Failed }

    if !ring.push[i64](&values, 10i64) || !ring.push[i64](&values, 20i64) || !ring.push[i64](&values, 30i64) { ret Failed }
    if ring.push[i64](&values, 40i64) { ret Failed }
    let (front, has_front) = ring.peek[i64](&values)
    if !has_front || front != 10i64 { ret Failed }

    let (first, has_first) = ring.pop[i64](&values)
    if !has_first || first != 10i64 { ret Failed }
    if !ring.push[i64](&values, 40i64) { ret Failed }

    var it = ring.iter[i64](&values)
    let (iter_first, iter_has_first) = ring.iter_next[i64](&it)
    let (iter_second, iter_has_second) = ring.iter_next[i64](&it)
    let (iter_third, iter_has_third) = ring.iter_next[i64](&it)
    let (_, iter_has_fourth) = ring.iter_next[i64](&it)
    if !iter_has_first || !iter_has_second || !iter_has_third || iter_has_fourth { ret Failed }
    if iter_first != 20i64 || iter_second != 30i64 || iter_third != 40i64 { ret Failed }

    let (replaced, did_replace) = ring.push_overwrite[i64](&values, 50i64)
    if !did_replace || replaced != 20i64 { ret Failed }
    let (new_front, has_new_front) = ring.peek[i64](&values)
    if !has_new_front || new_front != 30i64 { ret Failed }

    ring.clear[i64](&values)
    if ring.len[i64](&values) != 0usize { ret Failed }
    let (_, empty_pop) = ring.pop[i64](&values)
    if empty_pop { ret Failed }

    var empty_storage: [0]i64 = zero
    var empty = ring.init[i64](empty_storage[..])
    if ring.capacity[i64](&empty) != 0usize || ring.push[i64](&empty, 1i64) { ret Failed }
    let (_, empty_replaced) = ring.push_overwrite[i64](&empty, 1i64)
    if empty_replaced { ret Failed }

    try io.print("data ring ok\n")
    ret ok
}
