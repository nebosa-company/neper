use e.data.list as list
use e.io
use e.mem

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    let (initial, init_error) = list.init[i64](a, 0usize)
    if init_error != ok { ret init_error }
    var values = initial
    try list.push[i64](&values, 10i64)
    try list.push[i64](&values, 30i64)
    try list.insert[i64](&values, 1usize, 20i64)
    try list.insert[i64](&values, 3usize, 40i64)
    if values.len != 4usize { ret Failed }
    let mutable_view = list.slice[i64](&values)
    if mutable_view.len != 4usize || mutable_view[0usize] != 10i64 || mutable_view[1usize] != 20i64 || mutable_view[2usize] != 30i64 || mutable_view[3usize] != 40i64 { ret Failed }
    let const_view = list.slice_const[i64](&values)
    if const_view.len != 4usize || const_view[2usize] != 30i64 { ret Failed }

    let removed = list.remove[i64](&values, 1usize)
    if removed != 20i64 || values.len != 3usize || list.slice[i64](&values)[1usize] != 30i64 { ret Failed }
    let (popped, has_popped) = list.pop[i64](&values)
    if !has_popped || popped != 40i64 || values.len != 2usize { ret Failed }
    try list.reserve[i64](&values, 16usize)
    if values.items.len < 16usize || list.slice[i64](&values)[0usize] != 10i64 || list.slice[i64](&values)[1usize] != 30i64 { ret Failed }

    var it = list.iter[i64](&values)
    let (first, has_first) = list.iter_next[i64](&it)
    let (second, has_second) = list.iter_next[i64](&it)
    let (_, has_third) = list.iter_next[i64](&it)
    if !has_first || !has_second || has_third || first != 10i64 || second != 30i64 { ret Failed }

    var source: [3]i64 = [3]i64{ 7i64, 8i64, 9i64 }
    let (copied, copy_error) = list.from_slice[i64](a, source[..])
    if copy_error != ok { ret copy_error }
    source[0usize] = 99i64
    if copied.len != 3usize || copied.items[0usize] != 7i64 || copied.items[2usize] != 9i64 { ret Failed }

    list.clear[i64](&values)
    let (_, empty_pop) = list.pop[i64](&values)
    if values.len != 0usize || empty_pop { ret Failed }

    try io.print("data list ok\n")
    ret ok
}
