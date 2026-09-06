use e.algo.bitset as bitset
use e.io
use e.mem

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    var too_small: [1]u64 = zero
    let (_, small_error) = bitset.init(too_small[..], 65usize)
    if small_error != bitset.TooSmall { ret Failed }

    var left_storage: [3]u64 = zero
    var right_storage: [3]u64 = zero
    let (left_value, left_error) = bitset.init(left_storage[..], 130usize)
    if left_error != ok { ret left_error }
    let (right_value, right_error) = bitset.init(right_storage[..], 130usize)
    if right_error != ok { ret right_error }
    var left = left_value
    var right = right_value
    if bitset.len(&left) != 130usize { ret Failed }

    bitset.set(&left, 0usize)
    bitset.set(&left, 63usize)
    bitset.set(&left, 64usize)
    bitset.set(&left, 129usize)
    if !bitset.get(&left, 0usize) || !bitset.get(&left, 63usize) || !bitset.get(&left, 64usize) || !bitset.get(&left, 129usize) { ret Failed }
    if bitset.count(&left) != 4usize { ret Failed }
    let (first, has_first) = bitset.first_set(&left)
    if !has_first || first != 0usize { ret Failed }
    let (second, has_second) = bitset.next_set(&left, first)
    if !has_second || second != 63usize { ret Failed }
    let (third, has_third) = bitset.next_set(&left, second)
    if !has_third || third != 64usize { ret Failed }
    let (fourth, has_fourth) = bitset.next_set(&left, third)
    if !has_fourth || fourth != 129usize { ret Failed }
    let (_, has_fifth) = bitset.next_set(&left, fourth)
    if has_fifth { ret Failed }

    bitset.unset(&left, 63usize)
    bitset.toggle(&left, 64usize)
    bitset.toggle(&left, 65usize)
    if bitset.count(&left) != 3usize || !bitset.get(&left, 65usize) { ret Failed }

    bitset.set(&right, 65usize)
    if !bitset.is_subset(&right, &left) { ret Failed }
    bitset.set(&right, 80usize)
    if bitset.is_subset(&right, &left) { ret Failed }

    bitset.union_in_place(&left, &right)
    if bitset.count(&left) != 4usize || !bitset.get(&left, 80usize) { ret Failed }
    bitset.intersect_in_place(&left, &right)
    if bitset.count(&left) != 2usize || !bitset.get(&left, 65usize) || !bitset.get(&left, 80usize) { ret Failed }
    bitset.difference_in_place(&left, &right)
    if bitset.count(&left) != 0usize { ret Failed }

    bitset.fill_all(&left)
    if bitset.count(&left) != 130usize || left.words[2usize] != 3u64 { ret Failed }
    bitset.complement_in_place(&left)
    if bitset.count(&left) != 0usize || left.words[2usize] != 0u64 { ret Failed }
    bitset.fill_all(&right)
    bitset.complement_in_place(&right)
    if !bitset.eq(&left, &right) { ret Failed }
    bitset.fill_all(&left)
    bitset.clear_all(&left)
    if bitset.count(&left) != 0usize { ret Failed }

    var empty_storage: [1]u64 = zero
    let (empty_value, empty_error) = bitset.init(empty_storage[..], 0usize)
    if empty_error != ok { ret empty_error }
    var empty_set = empty_value
    bitset.fill_all(&empty_set)
    bitset.complement_in_place(&empty_set)
    let (_, empty_found) = bitset.first_set(&empty_set)
    if empty_found || bitset.count(&empty_set) != 0usize { ret Failed }

    try io.print("algo bitset ok\n")
    ret ok
}
