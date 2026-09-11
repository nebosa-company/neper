// `e.data.iter`: every adapter over a list's iterator, stacked two and three deep, and every
// fold run to its end or its first answer. The source is a list because that is what a caller
// has; the adapters are what turns one pull into a pipeline, and the fixture's point is that a
// `Filter` over a `Map` over an `Iter` is one value that pulls through all three.

use e.mem
use e.os
use e.data.list
use e.data.iter

error Odd

type Scale = struct { by: i64 }

// A source with a `next_err`, for the `try_` family: it counts up and fails at a chosen point.
type Counted = struct { current: i64, end: i64, fail_at: i64 }

fn counted_next_err(it: *Counted) -> (i64, bool, err) {
    if it.current == it.fail_at { ret (0i64, false, Odd) }
    if it.current >= it.end { ret (0i64, false, ok) }
    let value = it.current
    it.current += 1i64
    ret (value, true, ok)
}

fn double(x: i64) -> i64 { ret x * 2i64 }
fn is_even(x: i64) -> bool { ret x % 2i64 == 0i64 }
fn is_big(x: i64) -> bool { ret x > 100i64 }
fn add(acc: i64, x: i64) -> i64 { ret acc + x }
fn scale(ctx: *Scale, x: i64) -> i64 { ret x * ctx.by }
fn above(ctx: *Scale, x: i64) -> bool { ret x > ctx.by }
fn add_scaled(ctx: *Scale, acc: i64, x: i64) -> i64 { ret acc + x * ctx.by }
fn to_bool(x: i64) -> bool { ret x != 0i64 }

fn halve_even(ctx: *Scale, x: i64) -> (i64, err) {
    if x % 2i64 != 0i64 { ret (0i64, Odd) }
    ret (x / 2i64, ok)
}

fn keep_small(ctx: *Scale, x: i64) -> (bool, err) {
    if x > 100i64 { ret (false, Odd) }
    ret (x < ctx.by, ok)
}

fn sum_checked(ctx: *Scale, acc: i64, x: i64) -> (i64, err) {
    if x == ctx.by { ret (0i64, Odd) }
    ret (acc + x, ok)
}

fn main(a: *mem.Arena) -> err {
    var values: [6]i64 = zero
    values[0usize] = 1i64
    values[1usize] = 2i64
    values[2usize] = 3i64
    values[3usize] = 4i64
    values[4usize] = 5i64
    values[5usize] = 6i64
    let (held, held_error) = list.from_slice[i64](a, values[..])
    if held_error != ok { os.exit(9i32) }

    // --- map, over the list's own iterator.
    var doubled = iter.map[list.Iter[i64], i64, i64](list.iter[i64](&held), double)
    var seen = 0i64
    var pulled = 0usize
    while true {
        let (value, more) = iter.map_next[list.Iter[i64], i64, i64](&doubled)
        if !more { break }
        seen += value
        pulled += 1usize
    }
    if pulled != 6usize || seen != 42i64 { os.exit(10i32) }

    // --- filter, then a filter over a map: two adapters stacked.
    var evens = iter.filter[list.Iter[i64], i64](list.iter[i64](&held), is_even)
    if iter.count[iter.Filter[list.Iter[i64], i64], i64](&evens) != 3usize { os.exit(11i32) }
    var big_doubles = iter.filter[iter.Map[list.Iter[i64], i64, i64], i64](iter.map[list.Iter[i64], i64, i64](list.iter[i64](&held), double), is_even)
    if iter.count[iter.Filter[iter.Map[list.Iter[i64], i64, i64], i64], i64](&big_doubles) != 6usize { os.exit(12i32) }
    // The same type written out as an annotation is the type the call produced. A nested
    // instance as a type argument used to read its inner argument as the outer's (D145), so
    // this line is the regression: it did not compile.
    var spelled: iter.Filter[iter.Map[list.Iter[i64], i64, i64], i64] = iter.filter[iter.Map[list.Iter[i64], i64, i64], i64](iter.map[list.Iter[i64], i64, i64](list.iter[i64](&held), double), is_even)
    if iter.count[iter.Filter[iter.Map[list.Iter[i64], i64, i64], i64], i64](&spelled) != 6usize { os.exit(70i32) }

    // --- The context forms carry state the callback reads.
    var by_three = Scale { by: 3i64 }
    var tripled = iter.map_ctx[list.Iter[i64], i64, i64, Scale](list.iter[i64](&held), &by_three, scale)
    if iter.reduce[iter.MapCtx[list.Iter[i64], i64, i64, Scale], i64, i64](&tripled, 0i64, add) != 63i64 { os.exit(13i32) }
    var over_three = iter.filter_ctx[list.Iter[i64], i64, Scale](list.iter[i64](&held), &by_three, above)
    if iter.count[iter.FilterCtx[list.Iter[i64], i64, Scale], i64](&over_three) != 3usize { os.exit(14i32) }
    var plain = list.iter[i64](&held)
    if iter.reduce_ctx[list.Iter[i64], i64, i64, Scale](&plain, 0i64, &by_three, add_scaled) != 63i64 { os.exit(15i32) }

    // --- take stops pulling; skip drops and goes on; both are exact at the boundary.
    var first_two = iter.take[i64, list.Iter[i64]](list.iter[i64](&held), 2usize)
    let (t1, t1_more) = iter.take_next[i64, list.Iter[i64]](&first_two)
    let (t2, t2_more) = iter.take_next[i64, list.Iter[i64]](&first_two)
    let (_, t3_more) = iter.take_next[i64, list.Iter[i64]](&first_two)
    if !t1_more || !t2_more || t3_more || t1 != 1i64 || t2 != 2i64 { os.exit(16i32) }
    var past_end = iter.take[i64, list.Iter[i64]](list.iter[i64](&held), 10usize)
    if iter.count[iter.Take[i64, list.Iter[i64]], i64](&past_end) != 6usize { os.exit(17i32) }
    var last_two = iter.skip[i64, list.Iter[i64]](list.iter[i64](&held), 4usize)
    let (s1, s1_more) = iter.skip_next[i64, list.Iter[i64]](&last_two)
    let (s2, s2_more) = iter.skip_next[i64, list.Iter[i64]](&last_two)
    let (_, s3_more) = iter.skip_next[i64, list.Iter[i64]](&last_two)
    if !s1_more || !s2_more || s3_more || s1 != 5i64 || s2 != 6i64 { os.exit(18i32) }
    var skipped_all = iter.skip[i64, list.Iter[i64]](list.iter[i64](&held), 10usize)
    let (_, nothing_left) = iter.skip_next[i64, list.Iter[i64]](&skipped_all)
    if nothing_left { os.exit(19i32) }

    // --- enumerate numbers from zero; the index and the item agree with the list.
    var numbered = iter.enumerate[i64, list.Iter[i64]](list.iter[i64](&held))
    var index_sum = 0usize
    while true {
        let (index, value, more) = iter.enumerate_next[i64, list.Iter[i64]](&numbered)
        if !more { break }
        if i64(index) + 1i64 != value { os.exit(20i32) }
        index_sum += index
    }
    if index_sum != 15usize { os.exit(21i32) }

    // --- chain runs the left to its end and then the right; zip ends with the shorter.
    var both = iter.chain[i64, list.Iter[i64], list.Iter[i64]](list.iter[i64](&held), list.iter[i64](&held))
    if iter.reduce[iter.Chain[i64, list.Iter[i64], list.Iter[i64]], i64, i64](&both, 0i64, add) != 42i64 { os.exit(22i32) }
    var short_two = iter.take[i64, list.Iter[i64]](list.iter[i64](&held), 2usize)
    var paired = iter.zip[i64, i64, list.Iter[i64], iter.Take[i64, list.Iter[i64]]](list.iter[i64](&held), short_two)
    let (z1l, z1r, z1_more) = iter.zip_next[i64, i64, list.Iter[i64], iter.Take[i64, list.Iter[i64]]](&paired)
    let (z2l, z2r, z2_more) = iter.zip_next[i64, i64, list.Iter[i64], iter.Take[i64, list.Iter[i64]]](&paired)
    let (_, _, z3_more) = iter.zip_next[i64, i64, list.Iter[i64], iter.Take[i64, list.Iter[i64]]](&paired)
    if !z1_more || !z2_more || z3_more { os.exit(23i32) }
    if z1l != 1i64 || z1r != 1i64 || z2l != 2i64 || z2r != 2i64 { os.exit(24i32) }

    // --- The searching folds stop at the first answer and leave the source there.
    var searched = list.iter[i64](&held)
    let (found, was_found) = iter.find[list.Iter[i64], i64](&searched, is_even)
    if !was_found || found != 2i64 { os.exit(25i32) }
    let (after, after_more) = list.iter_next[i64](&searched)
    if !after_more || after != 3i64 { os.exit(26i32) }
    var positioned = list.iter[i64](&held)
    let (at, has_position) = iter.position[list.Iter[i64], i64](&positioned, is_even)
    if !has_position || at != 1usize { os.exit(27i32) }
    var missing = list.iter[i64](&held)
    let (_, found_big) = iter.find[list.Iter[i64], i64](&missing, is_big)
    if found_big { os.exit(28i32) }
    var any_source = list.iter[i64](&held)
    if !iter.any[list.Iter[i64], i64](&any_source, is_even) { os.exit(29i32) }
    var none_source = list.iter[i64](&held)
    if iter.any[list.Iter[i64], i64](&none_source, is_big) { os.exit(30i32) }
    var all_source = list.iter[i64](&held)
    if iter.all[list.Iter[i64], i64](&all_source, is_even) { os.exit(31i32) }
    var all_true = iter.filter[list.Iter[i64], i64](list.iter[i64](&held), is_even)
    if !iter.all[iter.Filter[list.Iter[i64], i64], i64](&all_true, is_even) { os.exit(32i32) }
    // `all` of nothing is true and `any` of nothing is false.
    var empty_all = iter.filter[list.Iter[i64], i64](list.iter[i64](&held), is_big)
    if !iter.all[iter.Filter[list.Iter[i64], i64], i64](&empty_all, is_even) { os.exit(33i32) }

    // --- min and max by the item's own `cmp`; nothing from nothing.
    var least = list.iter[i64](&held)
    let (low, has_low) = iter.min[list.Iter[i64], i64](&least)
    if !has_low || low != 1i64 { os.exit(34i32) }
    var most = list.iter[i64](&held)
    let (high, has_high) = iter.max[list.Iter[i64], i64](&most)
    if !has_high || high != 6i64 { os.exit(35i32) }
    var no_items = iter.filter[list.Iter[i64], i64](list.iter[i64](&held), is_big)
    let (_, has_none) = iter.min[iter.Filter[list.Iter[i64], i64], i64](&no_items)
    if has_none { os.exit(36i32) }

    // --- collect and partition, into lists.
    var to_collect = iter.map[list.Iter[i64], i64, i64](list.iter[i64](&held), double)
    let (collected, collect_error) = iter.collect[iter.Map[list.Iter[i64], i64, i64], i64](a, &to_collect)
    if collect_error != ok { os.exit(37i32) }
    var collected_list = collected
    let gathered = list.slice[i64](&collected_list)
    if gathered.len != 6usize || gathered[0usize] != 2i64 || gathered[5usize] != 12i64 { os.exit(38i32) }
    var to_split = list.iter[i64](&held)
    let (evens_list, odds_list, split_error) = iter.partition[list.Iter[i64], i64](a, &to_split, is_even)
    if split_error != ok { os.exit(39i32) }
    var evens_held = evens_list
    var odds_held = odds_list
    let even_items = list.slice[i64](&evens_held)
    let odd_items = list.slice[i64](&odds_held)
    if even_items.len != 3usize || odd_items.len != 3usize { os.exit(40i32) }
    if even_items[0usize] != 2i64 || odd_items[2usize] != 5i64 { os.exit(41i32) }

    // --- The try family. A source that does not fail, through a map that does not fail.
    var counted = Counted { current: 1i64, end: 7i64, fail_at: -1i64 }
    var by_ten = Scale { by: 10i64 }
    var evens_only = Counted { current: 2i64, end: 3i64, fail_at: -1i64 }
    var halved = iter.try_map[Counted, i64, i64, Scale](&evens_only, &by_ten, halve_even)
    let (h1, h1_more, h1_error) = iter.try_map_next_err[Counted, i64, i64, Scale](&halved)
    if h1_error != ok || !h1_more || h1 != 1i64 { os.exit(50i32) }
    let (_, h2_more, h2_error) = iter.try_map_next_err[Counted, i64, i64, Scale](&halved)
    if h2_error != ok || h2_more { os.exit(51i32) }
    // A callback that fails ends the adapter: the error once, then no item and ok.
    var failing_map = iter.try_map[Counted, i64, i64, Scale](&counted, &by_ten, halve_even)
    let (_, f1_more, f1_error) = iter.try_map_next_err[Counted, i64, i64, Scale](&failing_map)
    if f1_error != Odd || f1_more { os.exit(52i32) }
    let (_, f2_more, f2_error) = iter.try_map_next_err[Counted, i64, i64, Scale](&failing_map)
    if f2_error != ok || f2_more { os.exit(53i32) }
    // A source that fails is reported the same way, through a filter.
    var breaking = Counted { current: 1i64, end: 7i64, fail_at: 3i64 }
    var filtered = iter.try_filter[Counted, i64, Scale](&breaking, &by_ten, keep_small)
    let (k1, k1_more, k1_error) = iter.try_filter_next_err[Counted, i64, Scale](&filtered)
    if k1_error != ok || !k1_more || k1 != 1i64 { os.exit(54i32) }
    let (k2, k2_more, k2_error) = iter.try_filter_next_err[Counted, i64, Scale](&filtered)
    if k2_error != ok || !k2_more || k2 != 2i64 { os.exit(55i32) }
    let (_, k3_more, k3_error) = iter.try_filter_next_err[Counted, i64, Scale](&filtered)
    if k3_error != Odd || k3_more { os.exit(56i32) }
    let (_, k4_more, k4_error) = iter.try_filter_next_err[Counted, i64, Scale](&filtered)
    if k4_error != ok || k4_more { os.exit(57i32) }

    // --- try_collect: everything, or nothing and the arena given back.
    var whole = Counted { current: 1i64, end: 4i64, fail_at: -1i64 }
    let (all_of_it, all_error) = iter.try_collect[i64, Counted](a, &whole, 0usize)
    if all_error != ok { os.exit(58i32) }
    var all_held = all_of_it
    if list.slice[i64](&all_held).len != 3usize { os.exit(59i32) }
    let before = mem.mark(a)
    var broken = Counted { current: 1i64, end: 10i64, fail_at: 5i64 }
    let (_, broken_error) = iter.try_collect[i64, Counted](a, &broken, 0usize)
    if broken_error != Odd { os.exit(60i32) }
    if mem.mark(a) != before { os.exit(61i32) }
    var too_many = Counted { current: 1i64, end: 10i64, fail_at: -1i64 }
    let (_, limit_error) = iter.try_collect[i64, Counted](a, &too_many, 4usize)
    if limit_error != mem.Exhausted { os.exit(62i32) }
    if mem.mark(a) != before { os.exit(63i32) }
    var just_enough = Counted { current: 1i64, end: 5i64, fail_at: -1i64 }
    let (exact, exact_error) = iter.try_collect[i64, Counted](a, &just_enough, 4usize)
    if exact_error != ok { os.exit(64i32) }
    var exact_held = exact
    if list.slice[i64](&exact_held).len != 4usize { os.exit(65i32) }

    // --- try_reduce answers the last committed accumulator beside the error.
    var summed = Counted { current: 1i64, end: 5i64, fail_at: -1i64 }
    let (total, total_error) = iter.try_reduce[Counted, i64, i64, Scale](&summed, 0i64, &by_ten, sum_checked)
    if total_error != ok || total != 10i64 { os.exit(66i32) }
    var stops_at_three = Scale { by: 3i64 }
    var partial = Counted { current: 1i64, end: 5i64, fail_at: -1i64 }
    let (so_far, so_far_error) = iter.try_reduce[Counted, i64, i64, Scale](&partial, 0i64, &stops_at_three, sum_checked)
    if so_far_error != Odd || so_far != 3i64 { os.exit(67i32) }
    ret ok
}
