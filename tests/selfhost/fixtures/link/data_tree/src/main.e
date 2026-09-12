// `e.data.tree`: an ordered map read back ascending after a scrambled insertion, replace
// on an existing key, lower and upper bounds, iteration from a key, removal with node
// reuse, `clear`, a set of strings, and two thousand keys inserted in a stride staying
// sorted. Every check has its own exit code.
use e.os
use e.mem
use e.data.tree as tree

fn text_equal(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var m = tree.init[i64, i64](a)
    if tree.len[i64, i64](&m) != 0usize { os.exit(1) }
    let keys: [10]i64 = [10]i64{ 50, 20, 80, 10, 30, 70, 90, 60, 40, 100 }
    var i = 0usize
    while i < 10usize {
        let (added, put_error) = tree.put[i64, i64](&m, keys[i], keys[i] * 2i64)
        if put_error != ok || !added { os.exit(2) }
        i += 1usize
    }
    if tree.len[i64, i64](&m) != 10usize { os.exit(3) }
    let (replaced, _) = tree.put[i64, i64](&m, 30i64, 333i64)
    if replaced || tree.len[i64, i64](&m) != 10usize { os.exit(4) }
    let (v30, has30) = tree.get[i64, i64](&m, 30i64)
    let (_, has35) = tree.get[i64, i64](&m, 35i64)
    if !has30 || v30 != 333i64 || has35 { os.exit(5) }
    var it = tree.iter[i64, i64](&m)
    var previous = -1i64
    var seen = 0usize
    while true {
        let (k, v, has) = tree.iter_next[i64, i64](&it)
        if !has { break }
        if k <= previous { os.exit(6) }
        if k != 30i64 && v != k * 2i64 { os.exit(7) }
        previous = k
        seen += 1usize
    }
    if seen != 10usize { os.exit(8) }
    let (lk, _, has_l) = tree.lower_bound[i64, i64](&m, 35i64)
    let (uk, _, has_u) = tree.upper_bound[i64, i64](&m, 40i64)
    let (ek, _, has_e) = tree.lower_bound[i64, i64](&m, 40i64)
    let (_, _, past) = tree.lower_bound[i64, i64](&m, 101i64)
    if !has_l || lk != 40i64 || !has_u || uk != 50i64 || !has_e || ek != 40i64 || past { os.exit(9) }
    var from = tree.iter_from[i64, i64](&m, 75i64)
    let (f1, _, _) = tree.iter_next[i64, i64](&from)
    let (f2, _, _) = tree.iter_next[i64, i64](&from)
    if f1 != 80i64 || f2 != 90i64 { os.exit(10) }
    let (removed, was_there) = tree.remove[i64, i64](&m, 50i64)
    let (_, again) = tree.remove[i64, i64](&m, 50i64)
    if !was_there || removed != 100i64 || again || tree.len[i64, i64](&m) != 9usize { os.exit(11) }
    let (_, r10) = tree.remove[i64, i64](&m, 10i64)
    let (_, r100) = tree.remove[i64, i64](&m, 100i64)
    if !r10 || !r100 || tree.len[i64, i64](&m) != 7usize { os.exit(12) }
    it = tree.iter[i64, i64](&m)
    previous = -1i64
    seen = 0usize
    while true {
        let (k, _, has) = tree.iter_next[i64, i64](&it)
        if !has { break }
        if k <= previous || k == 50i64 || k == 10i64 || k == 100i64 { os.exit(13) }
        previous = k
        seen += 1usize
    }
    if seen != 7usize { os.exit(14) }
    let (re_added, _) = tree.put[i64, i64](&m, 50i64, 5i64)
    if !re_added || tree.len[i64, i64](&m) != 8usize { os.exit(15) }
    tree.clear[i64, i64](&m)
    let (_, after) = tree.get[i64, i64](&m, 20i64)
    var none = tree.iter[i64, i64](&m)
    let (_, _, any) = tree.iter_next[i64, i64](&none)
    if tree.len[i64, i64](&m) != 0usize || after || any { os.exit(16) }
    let (back, _) = tree.put[i64, i64](&m, 7i64, 7i64)
    if !back || tree.len[i64, i64](&m) != 1usize { os.exit(17) }
    var s = tree.set_init[str](a)
    let (_, e1) = tree.set_add[str](&s, "pear")
    let (_, e2) = tree.set_add[str](&s, "apple")
    let (dup, e3) = tree.set_add[str](&s, "pear")
    if e1 != ok || e2 != ok || e3 != ok || dup { os.exit(18) }
    if !tree.set_has[str](&s, "apple") || tree.set_has[str](&s, "fig") { os.exit(19) }
    var si = tree.set_iter[str](&s)
    let (first, _) = tree.set_iter_next[str](&si)
    let (second, _) = tree.set_iter_next[str](&si)
    let (_, third) = tree.set_iter_next[str](&si)
    if !text_equal(first, "apple") || !text_equal(second, "pear") || third { os.exit(20) }
    if !tree.set_remove[str](&s, "apple") || tree.set_remove[str](&s, "apple") { os.exit(21) }
    var big = tree.init[u32, u32](a)
    var n = 0u32
    while n < 2000u32 {
        let (_, big_error) = tree.put[u32, u32](&big, n * 7u32 % 2003u32, n)
        if big_error != ok { os.exit(22) }
        n += 1u32
    }
    if tree.len[u32, u32](&big) != 2000usize { os.exit(23) }
    var bi = tree.iter[u32, u32](&big)
    var last = 0u32
    var count = 0usize
    var started = false
    while true {
        let (k, _, has) = tree.iter_next[u32, u32](&bi)
        if !has { break }
        if started && k <= last { os.exit(24) }
        started = true
        last = k
        count += 1usize
    }
    if count != 2000usize { os.exit(25) }
    os.exit(0)
    ret ok
}
