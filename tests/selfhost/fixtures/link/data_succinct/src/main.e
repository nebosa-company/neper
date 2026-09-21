// `e.data.succinct`: rank and select agree with a bit scan, LOUDS and
// balanced parentheses navigate a small tree, the wavelet matrix
// answers rank, access, select and range quantiles of a text, and the
// CSA and FM-index find every occurrence of patterns in
// "mississippi_banana_mississippi" plus a terminator. Each check exits
// with its own code.

use e.data.succinct as succinct
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: rank and select over a 200-bit vector from an LCG.
    var bits: [4]u64 = zero
    var counts: [5]u32 = zero
    var state = 7u64
    var i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        if (state >> 40u32) & 1u64 == 1u64 { succinct.set_bit(bits[..], i, true) }
        i += 1usize
    }
    let (v, v_error) = succinct.bit_vector(bits[..], 200usize, counts[..])
    if v_error != ok { os.exit(1i32) }
    var ones = 0usize
    var zeros = 0usize
    i = 0usize
    while i < 200usize {
        if succinct.rank(&v, i) != ones || succinct.rank0(&v, i) != zeros { os.exit(1i32) }
        if succinct.get_bit(&v, i) {
            if succinct.select(&v, ones) != i { os.exit(1i32) }
            ones += 1usize
        } else {
            if succinct.select0(&v, zeros) != i { os.exit(1i32) }
            zeros += 1usize
        }
        i += 1usize
    }
    if succinct.rank(&v, 200usize) != ones || succinct.select(&v, ones) != 200usize || succinct.select0(&v, zeros) != 200usize { os.exit(1i32) }
    let (_, small_error) = succinct.bit_vector(bits[..], 200usize, counts[..3usize])
    if small_error != succinct.TooSmall { os.exit(1i32) }

    // 2: LOUDS of a tree: 0 -> {1, 2, 3}, 1 -> {4, 5}, 3 -> {6}, 6 -> {7}.
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
    var queue: [8]u32 = zero
    var order: [8]usize = zero
    let (louds, l_error) = succinct.louds_encode(first_child[..], next_sibling[..], 8usize, 0usize, lbits[..], lcounts[..], queue[..], order[..])
    if l_error != ok || louds.n != 17usize { os.exit(2i32) }
    // Level order is the node numbering here.
    i = 0usize
    while i < 8usize {
        if order[i] != i { os.exit(2i32) }
        i += 1usize
    }
    if succinct.louds_degree(&louds, 0usize) != 3usize || succinct.louds_degree(&louds, 1usize) != 2usize || succinct.louds_degree(&louds, 2usize) != 0usize || succinct.louds_degree(&louds, 7usize) != 0usize { os.exit(2i32) }
    if succinct.louds_child(&louds, 0usize, 2usize) != 3usize || succinct.louds_child(&louds, 1usize, 1usize) != 5usize || succinct.louds_child(&louds, 6usize, 0usize) != 7usize || succinct.louds_child(&louds, 2usize, 0usize) != usize(succinct.NONE) { os.exit(2i32) }
    if succinct.louds_parent(&louds, 0usize) != usize(succinct.NONE) || succinct.louds_parent(&louds, 5usize) != 1usize || succinct.louds_parent(&louds, 7usize) != 6usize || succinct.louds_parent(&louds, 3usize) != 0usize { os.exit(2i32) }

    // 3: balanced parentheses of the same tree.
    var pbits: [1]u64 = zero
    var pcounts: [2]u32 = zero
    var stack: [8]u32 = zero
    var opens: [8]usize = zero
    let (bp, bp_error) = succinct.bp_encode(first_child[..], next_sibling[..], 8usize, 0usize, pbits[..], pcounts[..], stack[..], opens[..])
    if bp_error != ok || bp.n != 16usize { os.exit(3i32) }
    // Preorder: 0 1 4 5 2 3 6 7 -> (( () () ) () ( (()) )).
    if opens[0usize] != 0usize || opens[1usize] != 1usize || opens[4usize] != 2usize || opens[5usize] != 4usize || opens[2usize] != 7usize || opens[3usize] != 9usize || opens[6usize] != 10usize || opens[7usize] != 11usize { os.exit(3i32) }
    if succinct.bp_find_close(&bp, 0usize) != 15usize || succinct.bp_find_close(&bp, 1usize) != 6usize || succinct.bp_find_close(&bp, 11usize) != 12usize { os.exit(3i32) }
    if succinct.bp_subtree_size(&bp, 0usize) != 8usize || succinct.bp_subtree_size(&bp, 1usize) != 3usize || succinct.bp_subtree_size(&bp, 9usize) != 3usize || succinct.bp_subtree_size(&bp, 7usize) != 1usize { os.exit(3i32) }
    if succinct.bp_enclose(&bp, 0usize) != 16usize || succinct.bp_enclose(&bp, 4usize) != 1usize || succinct.bp_enclose(&bp, 11usize) != 10usize || succinct.bp_enclose(&bp, 9usize) != 0usize { os.exit(3i32) }
    if succinct.bp_preorder(&bp, 11usize) != 7usize { os.exit(3i32) }

    // 4: wavelet matrix over the text.
    let text = "mississippi_banana_mississippi\x00"
    let n = text.len
    var wbits: [8]u64 = zero
    var wcounts: [16]u32 = zero
    var levels: [8]succinct.BitVector = zero
    var wzeros: [8]usize = zero
    var scratch: [64]u8 = zero
    let (w, w_error) = succinct.wavelet_build(text, n, wbits[..], wcounts[..], levels[..], wzeros[..], scratch[..])
    if w_error != ok { os.exit(4i32) }
    i = 0usize
    while i < n {
        if succinct.wavelet_access(&w, i) != text[i] { os.exit(4i32) }
        i += 1usize
    }
    if succinct.wavelet_rank(&w, 115u8, 20usize) != 4usize || succinct.wavelet_rank(&w, 105u8, n) != 8usize || succinct.wavelet_rank(&w, 120u8, n) != 0usize { os.exit(4i32) }
    let (q, q_error) = succinct.wavelet_quantile(&w, 3usize, 14usize, 2usize)
    if q_error != ok || q != 98u8 { os.exit(4i32) }
    let (median, median_error) = succinct.wavelet_quantile(&w, 0usize, n, 15usize)
    if median_error != ok || median != 109u8 { os.exit(4i32) }
    let (_, bad_error) = succinct.wavelet_quantile(&w, 3usize, 14usize, 11usize)
    if bad_error != succinct.Invalid { os.exit(4i32) }
    if succinct.wavelet_select(&w, 115u8, 2usize) != 5usize || succinct.wavelet_select(&w, 105u8, 3usize) != 10usize || succinct.wavelet_select(&w, 115u8, 8usize) != n { os.exit(4i32) }

    // 5: compressed suffix array.
    var psi: [32]u32 = zero
    var sampled: [32]u32 = zero
    var sa: [32]usize = zero
    var sa_scratch: [400]usize = zero
    let (csa, csa_error) = succinct.csa_build(text, 4usize, psi[..], sampled[..], sa[..], sa_scratch[..])
    if csa_error != ok { os.exit(5i32) }
    if succinct.csa_lookup(&csa, 5usize) != 13usize || succinct.csa_lookup(&csa, 10usize) != 7usize || succinct.csa_lookup(&csa, 0usize) != 30usize { os.exit(5i32) }
    // Rows are a permutation of the positions.
    var seen: [32]u8 = zero
    i = 0usize
    while i < n {
        let pos = succinct.csa_lookup(&csa, i)
        if pos >= n || seen[pos] != 0u8 { os.exit(5i32) }
        seen[pos] = 1u8
        i += 1usize
    }
    let (ssi_lo, ssi_hi) = succinct.csa_search(&csa, text, "ssi")
    if ssi_lo != 27usize || ssi_hi != 31usize { os.exit(5i32) }
    let (ana_lo, ana_hi) = succinct.csa_search(&csa, text, "ana")
    if ana_lo != 4usize || ana_hi != 6usize { os.exit(5i32) }
    let (x_lo, x_hi) = succinct.csa_search(&csa, text, "x")
    if x_lo != x_hi { os.exit(5i32) }
    let (_, bad_csa) = succinct.csa_build("abc", 4usize, psi[..], sampled[..], sa[..], sa_scratch[..])
    if bad_csa != succinct.Invalid { os.exit(5i32) }

    // 6: FM-index count and locate.
    var starts: [257]u32 = zero
    var fsampled: [32]u32 = zero
    var bwt_bytes: [32]u8 = zero
    var fbits: [8]u64 = zero
    var fcounts: [16]u32 = zero
    var flevels: [8]succinct.BitVector = zero
    var fzeros: [8]usize = zero
    var fscratch: [64]u8 = zero
    let (fm, fm_error) = succinct.fm_build(text, 4usize, starts[..], fsampled[..], sa[..], sa_scratch[..], bwt_bytes[..], fbits[..], fcounts[..], flevels[..], fzeros[..], fscratch[..])
    if fm_error != ok { os.exit(6i32) }
    if succinct.fm_count(&fm, "ssi") != 4usize || succinct.fm_count(&fm, "iss") != 4usize || succinct.fm_count(&fm, "mississippi") != 2usize || succinct.fm_count(&fm, "x") != 0usize || succinct.fm_count(&fm, "a") != 3usize { os.exit(6i32) }
    let (m_lo, m_hi) = succinct.fm_search(&fm, "mississippi")
    if m_lo != 15usize || m_hi != 17usize { os.exit(6i32) }
    var found: [2]usize = zero
    found[0usize] = succinct.fm_locate(&fm, m_lo)
    found[1usize] = succinct.fm_locate(&fm, m_lo + 1usize)
    if !((found[0usize] == 0usize && found[1usize] == 19usize) || (found[0usize] == 19usize && found[1usize] == 0usize)) { os.exit(6i32) }
    let (i_lo, i_hi) = succinct.fm_search(&fm, "iss")
    if i_hi - i_lo != 4usize { os.exit(6i32) }
    var total = 0usize
    i = i_lo
    while i < i_hi {
        total += succinct.fm_locate(&fm, i)
        i += 1usize
    }
    // 1 + 4 + 20 + 23.
    if total != 48usize { os.exit(6i32) }

    try io.print("data succinct ok\n")
    ret ok
}
