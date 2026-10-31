// `e.data.rope`: a leaf reports its text, concat joins, and sixty random
// inserts, removes and concats (with a rebalance midway) agree with a
// Python bytearray through a running hash of the flattened rope, its length
// and sampled bytes; the error paths answer Invalid and TooSmall. Each check
// exits with its own code.

use e.data.rope
use e.io
use e.mem
use e.os

fn lcg(s: u64) -> u64 { ret s *% 6364136223846793005u64 +% 1442695040888963407u64 }
fn fnv(h: u64, b: u64) -> u64 { ret (h ^ b) *% 1099511628211u64 }

fn main(a: *mem.Arena, args: []str) -> err {
    var text: [2048]u8 = zero
    var weight: [1024]u32 = zero
    var left: [1024]u32 = zero
    var right: [1024]u32 = zero
    var start: [1024]u32 = zero
    var r = rope.rope(text[..], weight[..], left[..], right[..], start[..])
    var out: [512]u8 = zero

    // 1: a leaf.
    let (hello, hello_error) = rope.from_text(&r, "hello")
    if hello_error != ok || rope.len(&r, hello) != 5usize { os.exit(1i32) }
    let (h1, h1_ok) = rope.byte_at(&r, hello, 1usize)
    if !h1_ok || h1 != 101u8 { os.exit(1i32) }
    let (_, past) = rope.byte_at(&r, hello, 5usize)
    if past { os.exit(1i32) }
    if rope.len(&r, rope.NONE) != 0usize { os.exit(1i32) }

    // 2: concat and report.
    let (world, _) = rope.from_text(&r, ", world")
    let (both, concat_error) = rope.concat(&r, hello, world)
    if concat_error != ok || rope.len(&r, both) != 12usize { os.exit(2i32) }
    let (n2, report_error) = rope.report(&r, both, out[..])
    if report_error != ok || n2 != 12usize { os.exit(2i32) }
    var h = 14695981039346656037u64
    var i = 0usize
    while i < n2 {
        h = fnv(h, u64(out[i]))
        i += 1usize
    }
    if h != 1702823495152329533u64 { os.exit(2i32) }
    let (w7, w7_ok) = rope.byte_at(&r, both, 7usize)
    if !w7_ok || w7 != 119u8 { os.exit(2i32) }
    let (_, small) = rope.report(&r, both, out[..11usize])
    if small != rope.TooSmall { os.exit(2i32) }

    // 3: random edits against the Python reference.
    var expected: [6]u64 = zero
    expected[0usize] = 1420527865555121832u64
    expected[1usize] = 7991944077178456870u64
    expected[2usize] = 13278185070452068923u64
    expected[3usize] = 12966365459185834959u64
    expected[4usize] = 12132832166975569665u64
    expected[5usize] = 13323365985003927909u64
    var state = 12345u64
    var root = rope.NONE
    var word: [8]u8 = zero
    var step = 0usize
    while step < 60usize {
        state = lcg(state)
        let op = (state >> 33u32) % 4u64
        state = lcg(state)
        let pos_draw = state >> 33u32
        state = lcg(state)
        let n = usize((state >> 33u32) % 8u64 + 1u64)
        state = lcg(state)
        let letter = (state >> 33u32) % 26u64
        var j = 0usize
        while j < n {
            word[j] = u8((letter + u64(j)) % 26u64) + 97u8
            j += 1usize
        }
        let length = rope.len(&r, root)
        if op < 2u64 {
            let (new_root, e) = rope.insert(&r, root, usize(pos_draw % u64(length + 1usize)), word[..n])
            if e != ok { os.exit(3i32) }
            root = new_root
        } else if op == 2u64 {
            if length > 0usize {
                let p = usize(pos_draw % u64(length))
                state = lcg(state)
                var c = usize((state >> 33u32) % 6u64 + 1u64)
                if p + c > length { c = length - p }
                let (new_root, e) = rope.remove(&r, root, p, c)
                if e != ok { os.exit(3i32) }
                root = new_root
            }
        } else {
            let (leaf, leaf_error) = rope.from_text(&r, word[..n])
            if leaf_error != ok { os.exit(3i32) }
            let (new_root, e) = rope.concat(&r, root, leaf)
            if e != ok { os.exit(3i32) }
            root = new_root
        }
        if step == 30usize {
            let before = rope.len(&r, root)
            let (balanced, balance_error) = rope.rebalance(&r, root)
            if balance_error != ok || rope.len(&r, balanced) != before { os.exit(4i32) }
            root = balanced
        }
        if step % 10usize == 9usize {
            let (count, e) = rope.report(&r, root, out[..])
            if e != ok || count != rope.len(&r, root) { os.exit(3i32) }
            h = 14695981039346656037u64
            i = 0usize
            while i < count {
                h = fnv(h, u64(out[i]))
                i += 1usize
            }
            h = fnv(h, u64(count))
            var s = 0usize
            while s < 3usize {
                if count > 0usize {
                    state = lcg(state)
                    let (b, b_ok) = rope.byte_at(&r, root, usize((state >> 33u32) % u64(count)))
                    if !b_ok { os.exit(3i32) }
                    h = fnv(h, u64(b))
                }
                s += 1usize
            }
            if h != expected[step / 10usize] { os.exit(3i32) }
        }
        step += 1usize
    }
    if rope.len(&r, root) != 161usize { os.exit(3i32) }

    // 5: error paths.
    let length = rope.len(&r, root)
    let (_, bad_insert) = rope.insert(&r, root, length + 1usize, "x")
    if bad_insert != rope.Invalid { os.exit(5i32) }
    let (_, bad_remove) = rope.remove(&r, root, length - 1usize, 2usize)
    if bad_remove != rope.Invalid { os.exit(5i32) }
    var tiny_text: [4]u8 = zero
    var tiny = rope.rope(tiny_text[..], weight[..2usize], left[..2usize], right[..2usize], start[..2usize])
    let (_, no_room) = rope.from_text(&tiny, "abcde")
    if no_room != rope.TooSmall { os.exit(5i32) }
    let (t1, _) = rope.from_text(&tiny, "ab")
    let (t2, _) = rope.from_text(&tiny, "cd")
    let (_, no_node) = rope.concat(&tiny, t1, t2)
    if no_node != rope.TooSmall { os.exit(5i32) }

    // 6: a failed multi-step edit leaves its old root and pools intact.
    var failed_text: [16]u8 = zero
    var failed_weight: [4]u32 = zero
    var failed_left: [4]u32 = zero
    var failed_right: [4]u32 = zero
    var failed_start: [4]u32 = zero
    var failed_rope = rope.rope(failed_text[..], failed_weight[..], failed_left[..], failed_right[..], failed_start[..])
    let (failed_root, failed_make_error) = rope.from_text(&failed_rope, "abcd")
    let (unchanged_root, failed_insert) = rope.insert(&failed_rope, failed_root, 2usize, "xy")
    var failed_out: [8]u8 = zero
    let (failed_count, failed_report_error) = rope.report(&failed_rope, failed_root, failed_out[..])
    if failed_make_error != ok || failed_insert != rope.TooSmall || unchanged_root != failed_root || failed_rope.used != 4usize || failed_rope.nodes != 1usize || failed_text[4usize] != 0u8 || failed_text[5usize] != 0u8 || failed_weight[1usize] != 0u32 || failed_left[1usize] != 0u32 || failed_right[1usize] != 0u32 || failed_start[1usize] != 0u32 || failed_report_error != ok || failed_count != 4usize || failed_out[0usize] != 97u8 || failed_out[1usize] != 98u8 || failed_out[2usize] != 99u8 || failed_out[3usize] != 100u8 { os.exit(6i32) }
    let (retry_root, retry_error) = rope.insert(&failed_rope, failed_root, 4usize, "z")
    let (retry_count, retry_report_error) = rope.report(&failed_rope, retry_root, failed_out[..])
    if retry_error != ok || retry_report_error != ok || retry_count != 5usize || failed_out[4usize] != 122u8 { os.exit(6i32) }

    // A failed leaf allocation does not consume text-pool bytes either.
    var leaf_text: [8]u8 = zero
    var leaf_weight: [1]u32 = zero
    var leaf_left: [1]u32 = zero
    var leaf_right: [1]u32 = zero
    var leaf_start: [1]u32 = zero
    var leaf_rope = rope.rope(leaf_text[..], leaf_weight[..], leaf_left[..], leaf_right[..], leaf_start[..])
    let (leaf_root, leaf_make_error) = rope.from_text(&leaf_rope, "a")
    let (_, leaf_full_error) = rope.from_text(&leaf_rope, "b")
    if leaf_make_error != ok || leaf_root == rope.NONE || leaf_full_error != rope.TooSmall || leaf_rope.used != 1usize || leaf_rope.nodes != 1usize { os.exit(6i32) }

    // Removing through two leaf cuts, direct builds and rebalancing are transactional too.
    var remove_text: [16]u8 = zero
    var remove_weight: [2]u32 = zero
    var remove_left: [2]u32 = zero
    var remove_right: [2]u32 = zero
    var remove_start: [2]u32 = zero
    var remove_rope = rope.rope(remove_text[..], remove_weight[..], remove_left[..], remove_right[..], remove_start[..])
    let (remove_root, remove_make_error) = rope.from_text(&remove_rope, "abcd")
    let (unchanged_remove_root, failed_remove) = rope.remove(&remove_rope, remove_root, 1usize, 2usize)
    let (remove_count, remove_report_error) = rope.report(&remove_rope, remove_root, failed_out[..])
    if remove_make_error != ok || failed_remove != rope.TooSmall || unchanged_remove_root != remove_root || remove_rope.used != 4usize || remove_rope.nodes != 1usize || remove_report_error != ok || remove_count != 4usize || failed_out[0usize] != 97u8 || failed_out[1usize] != 98u8 || failed_out[2usize] != 99u8 || failed_out[3usize] != 100u8 { os.exit(6i32) }

    var build_text: [128]u8 = zero
    var build_weight: [2]u32 = zero
    var build_left: [2]u32 = zero
    var build_right: [2]u32 = zero
    var build_start: [2]u32 = zero
    var build_rope = rope.rope(build_text[..], build_weight[..], build_left[..], build_right[..], build_start[..])
    let (_, build_error) = rope.build(&build_rope, 0usize, 65usize)
    if build_error != rope.TooSmall || build_rope.used != 0usize || build_rope.nodes != 0usize || build_weight[0usize] != 0u32 { os.exit(6i32) }

    var rebalance_text: [16]u8 = zero
    var rebalance_weight: [1]u32 = zero
    var rebalance_left: [1]u32 = zero
    var rebalance_right: [1]u32 = zero
    var rebalance_start: [1]u32 = zero
    var rebalance_rope = rope.rope(rebalance_text[..], rebalance_weight[..], rebalance_left[..], rebalance_right[..], rebalance_start[..])
    let (rebalance_root, rebalance_make_error) = rope.from_text(&rebalance_rope, "abcd")
    let (unchanged_rebalance_root, rebalance_error) = rope.rebalance(&rebalance_rope, rebalance_root)
    let (rebalance_count, rebalance_report_error) = rope.report(&rebalance_rope, rebalance_root, failed_out[..])
    if rebalance_make_error != ok || rebalance_error != rope.TooSmall || unchanged_rebalance_root != rebalance_root || rebalance_rope.used != 4usize || rebalance_rope.nodes != 1usize || rebalance_report_error != ok || rebalance_count != 4usize || failed_out[0usize] != 97u8 || failed_out[1usize] != 98u8 || failed_out[2usize] != 99u8 || failed_out[3usize] != 100u8 { os.exit(6i32) }

    try io.print("data rope ok\n")
    ret ok
}
