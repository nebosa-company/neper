// `e.data.map`: a hash map keyed by anything with a `hash` and an `eq`. What is worth pinning
// is what open addressing gets wrong when it is wrong -- a key placed past a hole that a later
// removal turns into a dead slot, a table that grows while its entries are looked up, a probe
// that wraps the end of the table -- so the fixture fills past several doublings, removes from
// the middle, and asks for everything again.

use e.mem
use e.os
use e.str
use e.data.map

type Point = struct { x: i64, y: i64 }

// A struct gets no supplied `hash` or `eq` (rule 4), so this one says what its are.
fn point_hash(p: Point) -> u64 {
    ret u64(p.x) * 31u64 + u64(p.y)
}

fn point_eq(a: Point, b: Point) -> bool {
    ret a.x == b.x && a.y == b.y
}

fn main(a: *mem.Arena) -> err {
    // --- Integers, through several doublings. Every key put is found with the value it was
    // given, and a key never put is not.
    let (table, init_error) = map.init[u64, u64](a, 0usize)
    if init_error != ok { os.exit(10i32) }
    var counts = table
    if map.len[u64, u64](&counts) != 0usize { os.exit(11i32) }
    var k = 0u64
    while k < 1000u64 {
        let (fresh, put_error) = map.put[u64, u64](&counts, k, k * k)
        if put_error != ok { os.exit(12i32) }
        if !fresh { os.exit(13i32) }
        k += 1u64
    }
    if map.len[u64, u64](&counts) != 1000usize { os.exit(14i32) }
    k = 0u64
    while k < 1000u64 {
        let (value, present) = map.get[u64, u64](&counts, k)
        if !present { os.exit(15i32) }
        if value != k * k { os.exit(16i32) }
        k += 1u64
    }
    let (_, absent) = map.get[u64, u64](&counts, 5000u64)
    if absent { os.exit(17i32) }

    // --- A put over a key that is there replaces the value and is not a new entry.
    let (replaced_fresh, replace_error) = map.put[u64, u64](&counts, 7u64, 1u64)
    if replace_error != ok { os.exit(20i32) }
    if replaced_fresh { os.exit(21i32) }
    if map.len[u64, u64](&counts) != 1000usize { os.exit(22i32) }
    let (seven, seven_present) = map.get[u64, u64](&counts, 7u64)
    if !seven_present || seven != 1u64 { os.exit(23i32) }

    // --- `get_ptr` writes through, and the write is what `get` then sees.
    let (slot, slot_present) = map.get_ptr[u64, u64](&counts, 8u64)
    if !slot_present { os.exit(30i32) }
    *slot = 99u64
    let (eight, eight_present) = map.get[u64, u64](&counts, 8u64)
    if !eight_present || eight != 99u64 { os.exit(31i32) }

    // --- Removal from the middle: what is removed is gone and answers its old value once; what
    // was placed past it is still reachable, which is what a dead slot exists for.
    var removed = 0usize
    k = 0u64
    while k < 1000u64 {
        if k % 3u64 == 0u64 {
            let (taken, was_there) = map.remove[u64, u64](&counts, k)
            if !was_there { os.exit(40i32) }
            if k != 7u64 && k != 8u64 && taken != k * k { os.exit(41i32) }
            removed += 1usize
        }
        k += 1u64
    }
    if map.len[u64, u64](&counts) != 1000usize - removed { os.exit(42i32) }
    k = 0u64
    while k < 1000u64 {
        let (value, present) = map.get[u64, u64](&counts, k)
        if k % 3u64 == 0u64 {
            if present { os.exit(43i32) }
        } else {
            if !present { os.exit(44i32) }
            if k == 7u64 {
                if value != 1u64 { os.exit(45i32) }
            } else {
                if k == 8u64 {
                    if value != 99u64 { os.exit(46i32) }
                } else {
                    if value != k * k { os.exit(47i32) }
                }
            }
        }
        k += 1u64
    }
    let (_, gone_again) = map.remove[u64, u64](&counts, 3u64)
    if gone_again { os.exit(48i32) }

    // --- A removed key put again is a new entry, and reuses the hole.
    let (back_fresh, back_error) = map.put[u64, u64](&counts, 3u64, 33u64)
    if back_error != ok { os.exit(50i32) }
    if !back_fresh { os.exit(51i32) }
    let (three, three_present) = map.get[u64, u64](&counts, 3u64)
    if !three_present || three != 33u64 { os.exit(52i32) }

    // --- Iteration visits every live entry exactly once. The sum of the keys says every one
    // was there; the count says none twice.
    var seen = 0usize
    var key_sum = 0u64
    var expected_sum = 0u64
    var walk = map.iter[u64, u64](&counts)
    while true {
        let (key, value, more) = map.iter_next[u64, u64](&walk)
        if !more { break }
        seen += 1usize
        key_sum += key
    }
    k = 0u64
    while k < 1000u64 {
        if k % 3u64 != 0u64 || k == 3u64 { expected_sum += k }
        k += 1u64
    }
    if seen != map.len[u64, u64](&counts) { os.exit(60i32) }
    if key_sum != expected_sum { os.exit(61i32) }

    // --- Cleared: empty, and usable again.
    map.clear[u64, u64](&counts)
    if map.len[u64, u64](&counts) != 0usize { os.exit(70i32) }
    let (_, cleared_present) = map.get[u64, u64](&counts, 1u64)
    if cleared_present { os.exit(71i32) }
    let (after_fresh, after_error) = map.put[u64, u64](&counts, 1u64, 2u64)
    if after_error != ok || !after_fresh { os.exit(72i32) }
    if map.len[u64, u64](&counts) != 1usize { os.exit(73i32) }

    // --- `reserve` makes room without changing what is there.
    let reserve_error = map.reserve[u64, u64](&counts, 5000usize)
    if reserve_error != ok { os.exit(80i32) }
    let (one, one_present) = map.get[u64, u64](&counts, 1u64)
    if !one_present || one != 2u64 { os.exit(81i32) }

    // --- Strings as keys: `str` is a slice, whose supplied `hash` and `eq` are over its bytes,
    // so two spellings of the same text are one key.
    let (names, names_error) = map.init[str, i64](a, 4usize)
    if names_error != ok { os.exit(90i32) }
    var ages = names
    let (_, put_ann) = map.put[str, i64](&ages, "ann", 31i64)
    let (_, put_bob) = map.put[str, i64](&ages, "bob", 42i64)
    if put_ann != ok || put_bob != ok { os.exit(91i32) }
    var spelled: [3]u8 = zero
    spelled[0usize] = 98u8
    spelled[1usize] = 111u8
    spelled[2usize] = 98u8
    let (bob, bob_present) = map.get[str, i64](&ages, spelled[..])
    if !bob_present || bob != 42i64 { os.exit(92i32) }
    let (_, cat_present) = map.get[str, i64](&ages, "cat")
    if cat_present { os.exit(93i32) }

    // --- A struct key, with the `hash` and `eq` its module declares.
    let (grid, grid_error) = map.init[Point, str](a, 0usize)
    if grid_error != ok { os.exit(100i32) }
    var labels = grid
    let (_, put_origin) = map.put[Point, str](&labels, Point { x: 0i64, y: 0i64 }, "origin")
    let (_, put_unit) = map.put[Point, str](&labels, Point { x: 1i64, y: 1i64 }, "unit")
    if put_origin != ok || put_unit != ok { os.exit(101i32) }
    let (origin, origin_present) = map.get[Point, str](&labels, Point { x: 0i64, y: 0i64 })
    if !origin_present || !str.eq(origin, "origin") { os.exit(102i32) }
    let (_, off_grid) = map.get[Point, str](&labels, Point { x: 2i64, y: 0i64 })
    if off_grid { os.exit(103i32) }

    // --- A set is a map that keeps only the keys.
    let (members, members_error) = map.set_init[u64](a, 0usize)
    if members_error != ok { os.exit(110i32) }
    var seen_ids = members
    let (first_add, first_error) = map.set_add[u64](&seen_ids, 5u64)
    if first_error != ok || !first_add { os.exit(111i32) }
    let (second_add, second_error) = map.set_add[u64](&seen_ids, 5u64)
    if second_error != ok || second_add { os.exit(112i32) }
    let (_, third_error) = map.set_add[u64](&seen_ids, 9u64)
    if third_error != ok { os.exit(113i32) }
    if !map.set_has[u64](&seen_ids, 5u64) { os.exit(114i32) }
    if map.set_has[u64](&seen_ids, 6u64) { os.exit(115i32) }
    if !map.set_remove[u64](&seen_ids, 5u64) { os.exit(116i32) }
    if map.set_remove[u64](&seen_ids, 5u64) { os.exit(117i32) }
    if map.set_has[u64](&seen_ids, 5u64) { os.exit(118i32) }
    var set_walk = map.set_iter[u64](&seen_ids)
    let (only, only_more) = map.set_iter_next[u64](&set_walk)
    if !only_more || only != 9u64 { os.exit(119i32) }
    let (_, none_more) = map.set_iter_next[u64](&set_walk)
    if none_more { os.exit(120i32) }
    ret ok
}
