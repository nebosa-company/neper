// The planned names added across `e.data.*`: linked splice / sublist search /
// move-to-front, queue watermarks with hysteresis, the lazy and persistent
// segment trees by their planned names, the range tree's count against a
// brute-force scan, the succinct entry points through a real query each, a
// binary tree rebuilt from its traversals, the compacted (radix) trie
// answering every lookup of the plain one, and the DABA window aggregator
// against a brute-force scan over a 1,000-step LCG script. Each check exits
// with its own code; the expected literals come from the Python reference.

use e.data.linked as linked
use e.data.queue as queue
use e.data.segment_tree as segment_tree
use e.data.spatial as spatial
use e.data.succinct as succinct
use e.data.tree as tree
use e.data.trie as trie
use e.data.window as window
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

fn add(ctx: *Nothing, x: i64, y: i64) -> i64 { ret x + y }

fn larger(ctx: *Nothing, x: i64, y: i64) -> i64 {
    if x > y { ret x }
    ret y
}

fn collect(l: *const linked.List[i32], out: []i32) -> usize {
    var it = linked.iter[i32](l)
    var n = 0usize
    while true {
        let (v, has) = linked.iter_next[i32](&it)
        if !has { break }
        if n < out.len { out[n] = v }
        n += 1usize
    }
    ret n
}

fn same(xs: []const i32, ys: []const i32) -> bool {
    if xs.len != ys.len { ret false }
    var i = 0usize
    while i < xs.len {
        if xs[i] != ys[i] { ret false }
        i += 1usize
    }
    ret true
}

fn fill(l: *linked.List[i32], values: []const i32, ids: []linked.NodeId) -> err {
    var i = 0usize
    while i < values.len {
        let (id, push_error) = linked.push_back[i32](l, values[i])
        if push_error != ok { ret push_error }
        ids[i] = id
        i += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var nothing = Nothing { unused: 0u8 }
    var got: [16]i32 = zero

    // 1: same-list splice keeps identifiers and moves four links.
    let (a0, a_error) = linked.init[i32](a, 8usize)
    if a_error != ok { os.exit(1i32) }
    var la = a0
    var ids: [6]linked.NodeId = zero
    let lit1 = [6]i32{ 1i32, 2i32, 3i32, 4i32, 5i32, 6i32 }
    if fill(&la, lit1[..], ids[..]) != ok { os.exit(1i32) }
    if linked.splice[i32](&la, ids[4usize], &la, ids[1usize], ids[2usize]) != ok { os.exit(1i32) }
    var n = collect(&la, got[..])
    let lit2 = [6]i32{ 1i32, 4i32, 2i32, 3i32, 5i32, 6i32 }
    if !same(got[..n], lit2[..]) || linked.len[i32](&la) != 6usize { os.exit(1i32) }
    let (two, two_error) = linked.node[i32](&la, ids[1usize])
    if two_error != ok || two.next != ids[2usize] || two.previous != ids[3usize] { os.exit(1i32) }
    let (three, _) = linked.node[i32](&la, ids[2usize])
    if three.next != ids[4usize] { os.exit(1i32) }
    // The target inside the range, and a range whose end is not after its start.
    if linked.splice[i32](&la, ids[2usize], &la, ids[1usize], ids[2usize]) != linked.InvalidNode { os.exit(1i32) }
    if linked.splice[i32](&la, linked.NONE, &la, ids[2usize], ids[1usize]) != linked.InvalidNode { os.exit(1i32) }
    // Moving a range to the very front and to the end.
    if linked.splice[i32](&la, ids[0usize], &la, ids[4usize], ids[5usize]) != ok { os.exit(1i32) }
    n = collect(&la, got[..])
    let lit3 = [6]i32{ 5i32, 6i32, 1i32, 4i32, 2i32, 3i32 }
    if !same(got[..n], lit3[..]) { os.exit(1i32) }
    if linked.splice[i32](&la, linked.NONE, &la, ids[4usize], ids[5usize]) != ok { os.exit(1i32) }
    n = collect(&la, got[..])
    let lit4 = [6]i32{ 1i32, 4i32, 2i32, 3i32, 5i32, 6i32 }
    if !same(got[..n], lit4[..]) { os.exit(1i32) }
    let (f, _) = linked.first[i32](&la)
    let (l, _) = linked.last[i32](&la)
    if f != ids[0usize] || l != ids[5usize] { os.exit(1i32) }

    // 2: cross-list splice moves the values; the source's identifiers die.
    let (b0, b_error) = linked.init[i32](a, 4usize)
    if b_error != ok { os.exit(2i32) }
    var lb = b0
    var bids: [2]linked.NodeId = zero
    let lit5 = [2]i32{ 7i32, 8i32 }
    if fill(&lb, lit5[..], bids[..]) != ok { os.exit(2i32) }
    if linked.splice[i32](&la, linked.NONE, &lb, bids[0usize], bids[1usize]) != ok { os.exit(2i32) }
    if linked.len[i32](&lb) != 0usize || linked.len[i32](&la) != 8usize { os.exit(2i32) }
    let (_, dead) = linked.node[i32](&lb, bids[0usize])
    if dead != linked.InvalidNode { os.exit(2i32) }
    var cids: [1]linked.NodeId = zero
    let lit6 = [1]i32{ 9i32 }
    if fill(&lb, lit6[..], cids[..]) != ok { os.exit(2i32) }
    if linked.splice[i32](&la, ids[0usize], &lb, cids[0usize], cids[0usize]) != ok { os.exit(2i32) }
    n = collect(&la, got[..])
    let lit7 = [9]i32{ 9i32, 1i32, 4i32, 2i32, 3i32, 5i32, 6i32, 7i32, 8i32 }
    if !same(got[..n], lit7[..]) { os.exit(2i32) }
    if linked.splice[i32](&la, linked.NONE, &lb, cids[0usize], cids[0usize]) != linked.InvalidNode { os.exit(2i32) }

    // 3: sublist search and move-to-front.
    let (s0, s_error) = linked.init[i32](a, 4usize)
    if s_error != ok { os.exit(3i32) }
    var sub = s0
    var sids: [3]linked.NodeId = zero
    if !linked.contains_sublist[i32](&la, &sub) { os.exit(3i32) }
    let lit8 = [3]i32{ 2i32, 3i32, 5i32 }
    if fill(&sub, lit8[..], sids[..]) != ok { os.exit(3i32) }
    if !linked.contains_sublist[i32](&la, &sub) { os.exit(3i32) }
    let (_, r3) = linked.remove[i32](&sub, sids[0usize])
    let (_, p3) = linked.push_back[i32](&sub, 2i32)
    if r3 != ok || p3 != ok || linked.contains_sublist[i32](&la, &sub) { os.exit(3i32) }
    if linked.contains_sublist[i32](&sub, &la) { os.exit(3i32) }
    let (position, found) = linked.move_to_front[i32](&la, 5i32)
    if !found || position != 5usize { os.exit(3i32) }
    n = collect(&la, got[..])
    let lit9 = [9]i32{ 5i32, 9i32, 1i32, 4i32, 2i32, 3i32, 6i32, 7i32, 8i32 }
    if !same(got[..n], lit9[..]) { os.exit(3i32) }
    let (again, found_again) = linked.move_to_front[i32](&la, 5i32)
    if !found_again || again != 0usize { os.exit(3i32) }
    let (_, missing) = linked.move_to_front[i32](&la, 42i32)
    if missing || linked.len[i32](&la) != 9usize { os.exit(3i32) }
    let (last_value, last_found) = linked.move_to_front[i32](&la, 8i32)
    if !last_found || last_value != 8usize { os.exit(3i32) }
    let (l3, _) = linked.last[i32](&la)
    let (last_node, _) = linked.node[i32](&la, l3)
    if last_node.value != 7i32 || last_node.next != linked.NONE { os.exit(3i32) }

    // 4: watermarks with hysteresis.
    let (w, w_error) = queue.watermarks(10usize, 3usize, 7usize)
    if w_error != ok { os.exit(4i32) }
    if queue.watermark_state(&w, 2usize) != .Below || queue.watermark_state(&w, 3usize) != .Between || queue.watermark_state(&w, 7usize) != .Between || queue.watermark_state(&w, 8usize) != .Above { os.exit(4i32) }
    if queue.watermark_next(&w, .Below, 4usize) != .Below || queue.watermark_next(&w, .Below, 8usize) != .Above { os.exit(4i32) }
    if queue.watermark_next(&w, .Above, 5usize) != .Above || queue.watermark_next(&w, .Above, 2usize) != .Below || queue.watermark_next(&w, .Between, 5usize) != .Below { os.exit(4i32) }
    // A producer paused past the high mark resumes only under the low one.
    var signal = queue.watermark_next(&w, .Below, 0usize)
    var q_len = 0usize
    while q_len < 8usize {
        q_len += 1usize
        signal = queue.watermark_next(&w, signal, q_len)
    }
    if signal != .Above { os.exit(4i32) }
    while q_len > 3usize {
        q_len -= 1usize
        signal = queue.watermark_next(&w, signal, q_len)
        if signal != .Above { os.exit(4i32) }
    }
    q_len -= 1usize
    if queue.watermark_next(&w, signal, q_len) != .Below { os.exit(4i32) }
    let (_, crossed) = queue.watermarks(10usize, 8usize, 7usize)
    let (_, over) = queue.watermarks(10usize, 3usize, 11usize)
    let (_, empty) = queue.watermarks(0usize, 0usize, 0usize)
    if crossed != queue.Invalid || over != queue.Invalid || empty != queue.Invalid { os.exit(4i32) }

    // 5: the lazy and persistent trees by their planned names.
    var base: [8]i64 = zero
    var state = 5u64
    var i = 0usize
    while i < 8usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        base[i] = i64((state >> 33u32) % 100u64)
        i += 1usize
    }
    if base[0usize] != 92i64 || base[7usize] != 9i64 { os.exit(5i32) }
    var sums: [32]i64 = zero
    var mins: [32]i64 = zero
    var pending: [32]i64 = zero
    let (lazy, lazy_error) = segment_tree.lazy_build(sums[..], mins[..], pending[..], base[..])
    if lazy_error != ok { os.exit(5i32) }
    var lz = lazy
    if segment_tree.update_range(&lz, 1usize, 6usize, 5i64) != ok || segment_tree.update_range(&lz, 3usize, 8usize, 0i64 - 9i64) != ok { os.exit(5i32) }
    let (sum27, sum_error) = segment_tree.lazy_sum(&lz, 2usize, 7usize)
    let (min08, min_error) = segment_tree.lazy_min(&lz, 0usize, 8usize)
    let (min35, min35_error) = segment_tree.lazy_min(&lz, 3usize, 5usize)
    if sum_error != ok || min_error != ok || min35_error != ok || sum27 != 128i64 || min08 != 0i64 || min35 != 1i64 { os.exit(5i32) }
    if segment_tree.update_range(&lz, 0usize, 9usize, 1i64) != segment_tree.Invalid { os.exit(5i32) }
    var left: [64]u32 = zero
    var right: [64]u32 = zero
    var psums: [64]i64 = zero
    let (persistent, root0, persistent_error) = segment_tree.persistent_build(left[..], right[..], psums[..], base[..])
    if persistent_error != ok { os.exit(5i32) }
    var p = persistent
    let (root1, u1) = segment_tree.persistent_update(&p, root0, 3usize, 100i64)
    let (root2, u2) = segment_tree.persistent_update(&p, root1, 5usize, 0i64 - 7i64)
    if u1 != ok || u2 != ok { os.exit(5i32) }
    let (t0, q0) = segment_tree.persistent_query(&p, root0, 0usize, 8usize)
    let (t1, q1) = segment_tree.persistent_query(&p, root1, 0usize, 8usize)
    let (t2, q2) = segment_tree.persistent_query(&p, root2, 0usize, 8usize)
    let (t2m, q2m) = segment_tree.persistent_query(&p, root2, 3usize, 6usize)
    let (t0m, q0m) = segment_tree.persistent_query(&p, root0, 3usize, 6usize)
    if q0 != ok || q1 != ok || q2 != ok || q2m != ok || q0m != ok { os.exit(5i32) }
    if t0 != 318i64 || t1 != 413i64 || t2 != 395i64 || t2m != 168i64 || t0m != 91i64 { os.exit(5i32) }
    let (_, bad_index) = segment_tree.persistent_update(&p, root2, 8usize, 1i64)
    if bad_index != segment_tree.Invalid { os.exit(5i32) }

    // 6: the range tree's count against a scan over 40 LCG points.
    var xs: [40]f64 = zero
    var ys: [40]f64 = zero
    state = 11u64
    i = 0usize
    while i < 40usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        xs[i] = f64((state >> 33u32) % 100u64)
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        ys[i] = f64((state >> 33u32) % 100u64)
        i += 1usize
    }
    var order: [40]usize = zero
    var pool: [280]usize = zero
    let (rt, rt_error) = spatial.range_tree(xs[..], ys[..], 40usize, order[..], pool[..])
    if rt_error != ok { os.exit(6i32) }
    var out: [40]usize = zero
    var total_count = 0usize
    var q = 0usize
    while q < 10usize {
        var corners: [4]u64 = zero
        var k = 0usize
        while k < 4usize {
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            corners[k] = (state >> 33u32) % 100u64
            k += 1usize
        }
        var x1 = f64(corners[0usize])
        var x2 = f64(corners[1usize])
        var y1 = f64(corners[2usize])
        var y2 = f64(corners[3usize])
        if x1 > x2 {
            let t = x1
            x1 = x2
            x2 = t
        }
        if y1 > y2 {
            let t = y1
            y1 = y2
            y2 = t
        }
        var expected = 0usize
        i = 0usize
        while i < 40usize {
            if xs[i] >= x1 && xs[i] <= x2 && ys[i] >= y1 && ys[i] <= y2 { expected += 1usize }
            i += 1usize
        }
        let counted = spatial.range_tree_count(&rt, x1, y1, x2, y2)
        let (listed, list_error) = spatial.range_tree_query(&rt, x1, y1, x2, y2, out[..])
        if list_error != ok || counted != expected || listed != expected { os.exit(6i32) }
        total_count += counted
        q += 1usize
    }
    if total_count != 60usize { os.exit(6i32) }

    // 7: the succinct entry points, each through one real query.
    var first_child: [8]u32 = zero
    var next_sibling: [8]u32 = zero
    i = 0usize
    while i < 8usize {
        first_child[i] = succinct.NONE
        next_sibling[i] = succinct.NONE
        i += 1usize
    }
    first_child[0usize] = 1u32
    next_sibling[1usize] = 2u32
    next_sibling[2usize] = 3u32
    first_child[1usize] = 4u32
    next_sibling[4usize] = 5u32
    first_child[3usize] = 6u32
    first_child[6usize] = 7u32
    var lbits: [1]u64 = zero
    var lcounts: [2]u32 = zero
    var queue_scratch: [8]u32 = zero
    var level_order: [8]usize = zero
    let (lo, lo_error) = succinct.louds(first_child[..], next_sibling[..], 8usize, 0usize, lbits[..], lcounts[..], queue_scratch[..], level_order[..])
    if lo_error != ok || succinct.louds_degree(&lo, 0usize) != 3usize || succinct.louds_child(&lo, 1usize, 1usize) != 5usize || succinct.louds_parent(&lo, 7usize) != 6usize { os.exit(7i32) }
    var pbits: [1]u64 = zero
    var pcounts: [2]u32 = zero
    var stack: [8]u32 = zero
    var opens: [8]usize = zero
    let (bp, bp_error) = succinct.balanced_parens(first_child[..], next_sibling[..], 8usize, 0usize, pbits[..], pcounts[..], stack[..], opens[..])
    if bp_error != ok || succinct.bp_find_close(&bp, 1usize) != 6usize || succinct.bp_subtree_size(&bp, 9usize) != 3usize { os.exit(7i32) }
    let text = "mississippi_banana_mississippi\x00"
    var wbits: [8]u64 = zero
    var wcounts: [16]u32 = zero
    var levels: [8]succinct.BitVector = zero
    var wzeros: [8]usize = zero
    var scratch: [64]u8 = zero
    let (wm, wm_error) = succinct.wavelet_tree(text, text.len, wbits[..], wcounts[..], levels[..], wzeros[..], scratch[..])
    if wm_error != ok || succinct.wavelet_rank(&wm, 115u8, 20usize) != 4usize || succinct.wavelet_access(&wm, 12usize) != 98u8 { os.exit(7i32) }
    var psi: [32]u32 = zero
    var sampled: [32]u32 = zero
    var sa: [32]usize = zero
    var sa_scratch: [400]usize = zero
    let (csa, csa_error) = succinct.compressed_suffix_array(text, 4usize, psi[..], sampled[..], sa[..], sa_scratch[..])
    if csa_error != ok { os.exit(7i32) }
    let (ssi_lo, ssi_hi) = succinct.csa_search(&csa, text, "ssi")
    if ssi_lo != 27usize || ssi_hi != 31usize { os.exit(7i32) }
    var starts: [257]u32 = zero
    var fsampled: [32]u32 = zero
    var bwt_bytes: [32]u8 = zero
    var fbits: [8]u64 = zero
    var fcounts: [16]u32 = zero
    var flevels: [8]succinct.BitVector = zero
    var fzeros: [8]usize = zero
    var fscratch: [64]u8 = zero
    let (fm, fm_error) = succinct.fm_index(text, 4usize, starts[..], fsampled[..], sa[..], sa_scratch[..], bwt_bytes[..], fbits[..], fcounts[..], flevels[..], fzeros[..], fscratch[..])
    if fm_error != ok || succinct.fm_count(&fm, "ssi") != 4usize || succinct.fm_count(&fm, "mississippi") != 2usize || succinct.fm_count(&fm, "x") != 0usize { os.exit(7i32) }

    // 8: a binary tree from preorder + inorder and from postorder + inorder.
    let preorder = [9]i64{ 8i64, 3i64, 1i64, 6i64, 4i64, 7i64, 10i64, 14i64, 13i64 }
    let inorder = [9]i64{ 1i64, 3i64, 4i64, 6i64, 7i64, 8i64, 10i64, 13i64, 14i64 }
    let postorder = [9]i64{ 1i64, 4i64, 7i64, 6i64, 3i64, 13i64, 14i64, 10i64, 8i64 }
    let (root, root_error) = tree.from_traversals[i64, i64](a, preorder[..], inorder[..])
    if root_error != ok || root == nil || root.key != 8i64 || root.parent != nil { os.exit(8i32) }
    if root.left == nil || root.left.key != 3i64 || root.left.parent != root || root.right.right.left.key != 13i64 { os.exit(8i32) }
    var keys: [9]i64 = zero
    if tree.postorder_keys[i64, i64](root, keys[..]) != 9usize { os.exit(8i32) }
    i = 0usize
    while i < 9usize {
        if keys[i] != postorder[i] { os.exit(8i32) }
        i += 1usize
    }
    if tree.inorder_keys[i64, i64](root, keys[..]) != 9usize || keys[0usize] != 1i64 || keys[8usize] != 14i64 { os.exit(8i32) }
    var key_scratch: [9]i64 = zero
    let (root_post, post_error) = tree.from_postorder[i64, i64](a, postorder[..], inorder[..], key_scratch[..])
    if post_error != ok || tree.preorder_keys[i64, i64](root_post, keys[..]) != 9usize { os.exit(8i32) }
    i = 0usize
    while i < 9usize {
        if keys[i] != preorder[i] { os.exit(8i32) }
        i += 1usize
    }
    let (_, mismatch) = tree.from_traversals[i64, i64](a, preorder[..], inorder[..8usize])
    if mismatch != mem.Exhausted { os.exit(8i32) }
    let (empty_root, empty_error) = tree.from_traversals[i64, i64](a, preorder[..0usize], inorder[..0usize])
    if empty_error != ok || empty_root != nil { os.exit(8i32) }

    // 9: the compact (radix) trie answers every lookup of the plain one.
    var tbytes: [64]u8 = zero
    var tfirst: [64]u32 = zero
    var tnext: [64]u32 = zero
    var tterminal: [64]u8 = zero
    var tvalues: [64]u64 = zero
    let (trie0, t_error) = trie.init(tbytes[..], tfirst[..], tnext[..], tterminal[..], tvalues[..], 64usize)
    if t_error != ok { os.exit(9i32) }
    var tr = trie0
    var words: [7]str = zero
    words[0usize] = "car"
    words[1usize] = "card"
    words[2usize] = "care"
    words[3usize] = "cat"
    words[4usize] = "dog"
    words[5usize] = "dodge"
    words[6usize] = "do"
    i = 0usize
    while i < 7usize {
        let (_, insert_error) = trie.insert(&tr, words[i], u64(i) + 1u64)
        if insert_error != ok { os.exit(9i32) }
        i += 1usize
    }
    if trie.len(&tr) != 13usize { os.exit(9i32) }
    var labels: [64]u8 = zero
    var rstarts: [16]u32 = zero
    var rlens: [16]u32 = zero
    var rfirst: [16]u32 = zero
    var rnext: [16]u32 = zero
    var rterminal: [16]u8 = zero
    var rvalues: [16]u64 = zero
    let (radix, radix_error) = trie.compact(&tr, labels[..], rstarts[..], rlens[..], rfirst[..], rnext[..], rterminal[..], rvalues[..], 16usize)
    if radix_error != ok || trie.radix_len(&radix) != 9usize { os.exit(9i32) }
    i = 0usize
    while i < 7usize {
        let (value, hit) = trie.radix_get(&radix, words[i])
        if !hit || value != u64(i) + 1u64 { os.exit(9i32) }
        i += 1usize
    }
    var misses: [5]str = zero
    misses[0usize] = "ca"
    misses[1usize] = "cars"
    misses[2usize] = "d"
    misses[3usize] = "dod"
    misses[4usize] = ""
    i = 0usize
    while i < 5usize {
        let (_, wrong) = trie.radix_get(&radix, misses[i])
        if wrong || trie.contains(&tr, misses[i]) { os.exit(9i32) }
        i += 1usize
    }
    let (_, small) = trie.compact(&tr, labels[..], rstarts[..], rlens[..], rfirst[..], rnext[..], rterminal[..], rvalues[..], 4usize)
    if small != trie.TooSmall { os.exit(9i32) }

    // 10: DABA sums and maxima against a scan over a 1,000-step script.
    var sum_values: [64]i64 = zero
    var sum_aggs: [64]i64 = zero
    var max_values: [64]i64 = zero
    var max_aggs: [64]i64 = zero
    let (ds0, ds_error) = window.daba[i64](sum_values[..], sum_aggs[..], 0i64)
    let (dm0, dm_error) = window.daba[i64](max_values[..], max_aggs[..], 0i64 - 1i64)
    if ds_error != ok || dm_error != ok { os.exit(10i32) }
    var ds = ds0
    var dm = dm0
    var script: [1024]i64 = zero
    var head = 0usize
    var tail = 0usize
    var sum_check = 0u64
    var max_check = 0u64
    var pushes = 0usize
    var pops = 0usize
    state = 99u64
    i = 0usize
    while i < 1000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let x = state >> 33u32
        if x % 3u64 == 2u64 {
            if tail > head {
                let (ps, ps_error) = window.daba_pop[i64, Nothing](&ds, &nothing, add)
                let (pm, pm_error) = window.daba_pop[i64, Nothing](&dm, &nothing, larger)
                if ps_error != ok || pm_error != ok || ps != script[head] || pm != script[head] { os.exit(10i32) }
                head += 1usize
                pops += 1usize
            }
        } else {
            let v = i64(x % 1000u64)
            if tail - head < 64usize {
                script[tail] = v
                tail += 1usize
                if window.daba_push[i64, Nothing](&ds, v, &nothing, add) != ok || window.daba_push[i64, Nothing](&dm, v, &nothing, larger) != ok { os.exit(10i32) }
                pushes += 1usize
            }
        }
        var s = 0i64
        var m = 0i64 - 1i64
        var k = head
        while k < tail {
            s += script[k]
            if script[k] > m { m = script[k] }
            k += 1usize
        }
        if window.daba_query[i64, Nothing](&ds, &nothing, add) != s || window.daba_query[i64, Nothing](&dm, &nothing, larger) != m { os.exit(10i32) }
        if window.daba_len[i64](&ds) != tail - head { os.exit(10i32) }
        sum_check = (sum_check * 31u64 + u64(s)) % 1000003u64
        max_check = (max_check * 31u64 + u64(m + 1i64)) % 1000003u64
        i += 1usize
    }
    if pushes != 385usize || pops != 321usize || tail - head != 64usize || sum_check != 916630u64 || max_check != 286893u64 { os.exit(10i32) }
    if window.daba_push[i64, Nothing](&ds, 1i64, &nothing, add) != window.TooSmall { os.exit(10i32) }
    while tail > head {
        let (_, pop_error) = window.daba_pop[i64, Nothing](&dm, &nothing, larger)
        if pop_error != ok { os.exit(10i32) }
        head += 1usize
    }
    let (_, drained) = window.daba_pop[i64, Nothing](&dm, &nothing, larger)
    if drained != window.Invalid || window.daba_query[i64, Nothing](&dm, &nothing, larger) != 0i64 - 1i64 { os.exit(10i32) }

    try io.print("data gaps ok\n")
    ret ok
}
