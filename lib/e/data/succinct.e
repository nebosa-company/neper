// Succinct structures in caller storage. `BitVector` answers `rank`
// (ones before a position) and `select` (the position of a given one)
// through a cumulative count per 64-bit word; `louds_encode` and
// `bp_encode` write a tree as a level-order unary degree sequence or as
// balanced parentheses, with navigation over the bits; `WaveletMatrix`
// answers rank, access and range quantile over byte sequences in eight
// levels; `Csa` is a suffix array stored as Ψ plus sampled positions,
// and `FmIndex` counts and locates patterns by backward search over the
// Burrows-Wheeler transform held in a wavelet matrix.

use e.text.suffix as suffix

error TooSmall
error Invalid

const NONE: u32 = 4294967295u32

type BitVector = struct { bits: []u64, counts: []u32, n: usize }
type WaveletMatrix = struct { levels: []BitVector, zeros: []usize, n: usize }
type Csa = struct { psi: []u32, sampled: []u32, n: usize, rate: usize }
type FmIndex = struct { bwt: WaveletMatrix, starts: []u32, sampled: []u32, n: usize, rate: usize }

fn popcount(x: u64) -> usize {
    var v = x
    v = v - ((v >> 1u32) & 0x5555555555555555u64)
    v = (v & 0x3333333333333333u64) + ((v >> 2u32) & 0x3333333333333333u64)
    v = (v + (v >> 4u32)) & 0x0f0f0f0f0f0f0f0fu64
    ret usize((v *% 0x0101010101010101u64) >> 56u32)
}

fn words_for(n: usize) -> usize { ret (n + 63usize) / 64usize }

// A bit vector over `bits[..words_for(n)]` with `counts.len > words_for(n)`; the counts are computed here.
fn bit_vector(bits: []u64, n: usize, counts: []u32) -> (BitVector, err) {
    let words = words_for(n)
    if bits.len < words || counts.len < words + 1usize { ret (zero, TooSmall) }
    var total = 0u32
    var w = 0usize
    while w < words {
        counts[w] = total
        total += u32(popcount(bits[w]))
        w += 1usize
    }
    counts[words] = total
    ret (BitVector { bits: bits[..words], counts: counts[..words + 1usize], n: n }, ok)
}

fn get_bit(v: *const BitVector, i: usize) -> bool { ret (v.bits[i / 64usize] >> u32(i % 64usize)) & 1u64 == 1u64 }

fn set_bit(bits: []u64, i: usize, on: bool) {
    if on { bits[i / 64usize] = bits[i / 64usize] | (1u64 << u32(i % 64usize)) } else { bits[i / 64usize] = bits[i / 64usize] & ~(1u64 << u32(i % 64usize)) }
}

// The ones in `[0, i)`.
fn rank(v: *const BitVector, i: usize) -> usize {
    let w = i / 64usize
    let r = i % 64usize
    var c = usize(v.counts[w])
    if r > 0usize { c += popcount(v.bits[w] & ((1u64 << u32(r)) - 1u64)) }
    ret c
}

fn rank0(v: *const BitVector, i: usize) -> usize { ret i - rank(v, i) }

// The position of the `k`-th one (`k` from 0), or `n` when there is none.
fn select(v: *const BitVector, k: usize) -> usize {
    let words = v.bits.len
    if k >= usize(v.counts[words]) { ret v.n }
    // The last word whose cumulative count is at most k.
    var lo = 0usize
    var hi = words
    while hi - lo > 1usize {
        let mid = lo + (hi - lo) / 2usize
        if usize(v.counts[mid]) <= k { lo = mid } else { hi = mid }
    }
    var remaining = k - usize(v.counts[lo])
    var word = v.bits[lo]
    var bit = 0usize
    while true {
        if word & 1u64 == 1u64 {
            if remaining == 0usize { ret lo * 64usize + bit }
            remaining -= 1usize
        }
        word = word >> 1u32
        bit += 1usize
    }
    ret v.n
}

// The position of the `k`-th zero (`k` from 0), or `n` when there is none.
fn select0(v: *const BitVector, k: usize) -> usize {
    let words = v.bits.len
    if k >= v.n - usize(v.counts[words]) { ret v.n }
    var lo = 0usize
    var hi = words
    while hi - lo > 1usize {
        let mid = lo + (hi - lo) / 2usize
        if mid * 64usize - usize(v.counts[mid]) <= k { lo = mid } else { hi = mid }
    }
    var remaining = k - (lo * 64usize - usize(v.counts[lo]))
    var word = v.bits[lo]
    var bit = 0usize
    while true {
        if word & 1u64 == 0u64 {
            if remaining == 0usize { ret lo * 64usize + bit }
            remaining -= 1usize
        }
        word = word >> 1u32
        bit += 1usize
    }
    ret v.n
}

// LOUDS of the tree given by `first_child`/`next_sibling` (`NONE` ends a
// list) rooted at `root`: a super root `10`, then in level order the
// degree of each node in unary. `bits` holds `2n + 1` bits (cleared
// here), `queue.len >= n` is scratch, `order` receives the level-order
// numbering (`order[node] = ordinal`). Answers the bit vector.
fn louds_encode(first_child: []const u32, next_sibling: []const u32, n: usize, root: usize, bits: []u64, counts: []u32, queue: []u32, order: []usize) -> (BitVector, err) {
    let length = 2usize * n + 1usize
    if bits.len < words_for(length) || queue.len < n || order.len < n || first_child.len < n || next_sibling.len < n { ret (zero, TooSmall) }
    if n == 0usize || root >= n { ret (zero, Invalid) }
    var w = 0usize
    while w < words_for(length) {
        bits[w] = 0u64
        w += 1usize
    }
    set_bit(bits, 0usize, true)
    var at = 2usize
    var head = 0usize
    var tail = 1usize
    queue[0usize] = u32(root)
    order[root] = 0usize
    while head < tail {
        let node = usize(queue[head])
        head += 1usize
        var c = first_child[node]
        while c != NONE {
            if tail >= n || at >= length { ret (zero, Invalid) }
            order[usize(c)] = tail
            queue[tail] = c
            tail += 1usize
            set_bit(bits, at, true)
            at += 1usize
            c = next_sibling[usize(c)]
        }
        at += 1usize
    }
    if tail != n || at != length { ret (zero, Invalid) }
    let (v, e) = bit_vector(bits, length, counts)
    ret (v, e)
}

// The number of children of the node with level-order ordinal `i`.
fn louds_degree(v: *const BitVector, i: usize) -> usize { ret select0(v, i + 1usize) - select0(v, i) - 1usize }

// The ordinal of child `k` of node `i`, or `NONE` past its degree.
fn louds_child(v: *const BitVector, i: usize, k: usize) -> usize {
    if k >= louds_degree(v, i) { ret usize(NONE) }
    let p = select0(v, i) + 1usize + k
    ret rank(v, p + 1usize) - 1usize
}

// The ordinal of the parent of node `i` (`NONE` for the root).
fn louds_parent(v: *const BitVector, i: usize) -> usize {
    if i == 0usize { ret usize(NONE) }
    let q = select(v, i)
    ret rank0(v, q) - 1usize
}

// Balanced parentheses of the same tree in preorder: `1` opens, `0`
// closes; `bits` holds `2n` bits, `stack.len >= n` is scratch, `order`
// receives each node's opening position.
fn bp_encode(first_child: []const u32, next_sibling: []const u32, n: usize, root: usize, bits: []u64, counts: []u32, stack: []u32, order: []usize) -> (BitVector, err) {
    let length = 2usize * n
    if bits.len < words_for(length) || stack.len < n || order.len < n || first_child.len < n || next_sibling.len < n { ret (zero, TooSmall) }
    if n == 0usize || root >= n { ret (zero, Invalid) }
    var w = 0usize
    while w < words_for(length) {
        bits[w] = 0u64
        w += 1usize
    }
    var at = 0usize
    var top = 0usize
    stack[0usize] = u32(root)
    top = 1usize
    order[root] = 0usize
    set_bit(bits, 0usize, true)
    at = 1usize
    var visited = 1usize
    // Descend to the first child; on the way up, close and move to the next sibling.
    var node = root
    var descending = true
    while top > 0usize {
        if descending && first_child[node] != NONE {
            node = usize(first_child[node])
            if visited >= n || at >= length { ret (zero, Invalid) }
            order[node] = at
            set_bit(bits, at, true)
            at += 1usize
            visited += 1usize
            stack[top] = u32(node)
            top += 1usize
        } else {
            // Close `node`.
            if at >= length { ret (zero, Invalid) }
            at += 1usize
            top -= 1usize
            if top == 0usize {
                descending = false
            } else if next_sibling[node] != NONE {
                node = usize(next_sibling[node])
                if visited >= n || at >= length { ret (zero, Invalid) }
                order[node] = at
                set_bit(bits, at, true)
                at += 1usize
                visited += 1usize
                stack[top] = u32(node)
                top += 1usize
                descending = true
            } else {
                node = usize(stack[top - 1usize])
                descending = false
            }
        }
    }
    if visited != n || at != length { ret (zero, Invalid) }
    let (v, e) = bit_vector(bits, length, counts)
    ret (v, e)
}

// The matching close of the open at `i`.
// ponytail: linear scan of the excess; a range-min-max tree makes it O(log n).
fn bp_find_close(v: *const BitVector, i: usize) -> usize {
    var excess = 0i64
    var p = i
    while p < v.n {
        if get_bit(v, p) { excess += 1i64 } else { excess -= 1i64 }
        if excess == 0i64 { ret p }
        p += 1usize
    }
    ret v.n
}

// The open of the nearest pair enclosing the open at `i` (`n` at the root).
fn bp_enclose(v: *const BitVector, i: usize) -> usize {
    if i == 0usize { ret v.n }
    var excess = 0i64
    var p = i
    while p > 0usize {
        p -= 1usize
        if get_bit(v, p) { excess += 1i64 } else { excess -= 1i64 }
        if excess == 1i64 { ret p }
    }
    ret v.n
}

// The nodes in the subtree opened at `i`, itself included.
fn bp_subtree_size(v: *const BitVector, i: usize) -> usize { ret (bp_find_close(v, i) - i + 1usize) / 2usize }

// The preorder rank (0-based) of the open at `i`.
fn bp_preorder(v: *const BitVector, i: usize) -> usize { ret rank(v, i) }

// A wavelet matrix over `symbols[..n]`: eight levels from the top bit
// down, each a stable partition of the previous by that bit. `bits`
// holds `8 * words_for(n)` words, `counts` `8 * (words_for(n) + 1)`,
// `levels` and `zeros` eight entries, `scratch` `2n` bytes.
fn wavelet_build(symbols: []const u8, n: usize, bits: []u64, counts: []u32, levels: []BitVector, zeros: []usize, scratch: []u8) -> (WaveletMatrix, err) {
    let words = words_for(n)
    if symbols.len < n || bits.len < 8usize * words || counts.len < 8usize * (words + 1usize) || levels.len < 8usize || zeros.len < 8usize || scratch.len < 2usize * n { ret (zero, TooSmall) }
    var cur = scratch[..n]
    var next = scratch[n..2usize * n]
    var i = 0usize
    while i < n {
        cur[i] = symbols[i]
        i += 1usize
    }
    var level = 0usize
    while level < 8usize {
        let shift = u32(7usize - level)
        let level_bits = bits[level * words..(level + 1usize) * words]
        var w = 0usize
        while w < words {
            level_bits[w] = 0u64
            w += 1usize
        }
        var zero_count = 0usize
        i = 0usize
        while i < n {
            if (cur[i] >> shift) & 1u8 == 1u8 { set_bit(level_bits, i, true) } else { zero_count += 1usize }
            i += 1usize
        }
        // Stable partition: zeros first, then ones.
        var z = 0usize
        var o = zero_count
        i = 0usize
        while i < n {
            if (cur[i] >> shift) & 1u8 == 1u8 {
                next[o] = cur[i]
                o += 1usize
            } else {
                next[z] = cur[i]
                z += 1usize
            }
            i += 1usize
        }
        let (v, e) = bit_vector(level_bits, n, counts[level * (words + 1usize)..(level + 1usize) * (words + 1usize)])
        if e != ok { ret (zero, e) }
        levels[level] = v
        zeros[level] = zero_count
        let tmp = cur
        cur = next
        next = tmp
        level += 1usize
    }
    ret (WaveletMatrix { levels: levels[..8usize], zeros: zeros[..8usize], n: n }, ok)
}

// The symbol at `i`.
fn wavelet_access(w: *const WaveletMatrix, i: usize) -> u8 {
    var p = i
    var c = 0u8
    var level = 0usize
    while level < 8usize {
        let v = &w.levels[level]
        c = c << 1u32
        if get_bit(v, p) {
            c = c | 1u8
            p = w.zeros[level] + rank(v, p)
        } else {
            p = rank0(v, p)
        }
        level += 1usize
    }
    ret c
}

// The occurrences of `c` in `[0, i)`.
fn wavelet_rank(w: *const WaveletMatrix, c: u8, i: usize) -> usize {
    var lo = 0usize
    var hi = i
    var level = 0usize
    while level < 8usize {
        let v = &w.levels[level]
        if (c >> u32(7usize - level)) & 1u8 == 1u8 {
            lo = w.zeros[level] + rank(v, lo)
            hi = w.zeros[level] + rank(v, hi)
        } else {
            lo = rank0(v, lo)
            hi = rank0(v, hi)
        }
        level += 1usize
    }
    ret hi - lo
}

// The `k`-th smallest symbol (`k` from 0) in `[lo, hi)`.
fn wavelet_quantile(w: *const WaveletMatrix, lo: usize, hi: usize, k: usize) -> (u8, err) {
    if hi > w.n || lo >= hi || k >= hi - lo { ret (0u8, Invalid) }
    var a = lo
    var b = hi
    var want = k
    var c = 0u8
    var level = 0usize
    while level < 8usize {
        let v = &w.levels[level]
        let zeros_before = rank0(v, a)
        let zeros_in = rank0(v, b) - zeros_before
        c = c << 1u32
        if want < zeros_in {
            a = zeros_before
            b = zeros_before + zeros_in
        } else {
            want -= zeros_in
            c = c | 1u8
            a = w.zeros[level] + rank(v, a)
            b = w.zeros[level] + rank(v, b)
        }
        level += 1usize
    }
    ret (c, ok)
}

// The `k`-th occurrence of `c` (`k` from 0), or `n` when there is none.
fn wavelet_select(w: *const WaveletMatrix, c: u8, k: usize) -> usize {
    // Descend to the range of `c`, then climb back through selects.
    var lo = 0usize
    var level = 0usize
    while level < 8usize {
        let v = &w.levels[level]
        if (c >> u32(7usize - level)) & 1u8 == 1u8 { lo = w.zeros[level] + rank(v, lo) } else { lo = rank0(v, lo) }
        level += 1usize
    }
    if wavelet_rank(w, c, w.n) <= k { ret w.n }
    var p = lo + k
    level = 8usize
    while level > 0usize {
        level -= 1usize
        let v = &w.levels[level]
        if (c >> u32(7usize - level)) & 1u8 == 1u8 { p = select(v, p - w.zeros[level]) } else { p = select0(v, p) }
    }
    ret p
}

// A compressed suffix array of `text`, which must end in a byte smaller
// than every other (the terminator): `psi[i]` is the row of the next
// suffix, `sampled[i]` the text position of row `i` when it is a multiple
// of `rate` (else `NONE`). `sa` and `scratch` (`3n + 256`) are scratch.
fn csa_build(text: str, rate: usize, psi: []u32, sampled: []u32, sa: []usize, scratch: []usize) -> (Csa, err) {
    let n = text.len
    if psi.len < n || sampled.len < n || sa.len < n { ret (zero, TooSmall) }
    if n == 0usize || rate == 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i + 1usize < n {
        if text[i] <= text[n - 1usize] { ret (zero, Invalid) }
        i += 1usize
    }
    let e = suffix.array_build(text, sa, scratch)
    if e != ok { ret (zero, TooSmall) }
    // The inverse lives in `psi` briefly: isa[pos] = row.
    i = 0usize
    while i < n {
        psi[sa[i]] = u32(i)
        i += 1usize
    }
    i = 0usize
    while i < n {
        let pos = sa[i]
        sampled[i] = NONE
        if pos % rate == 0usize { sampled[i] = u32(pos) }
        // Reuse `sa` for the final psi so the inverse stays readable.
        sa[i] = usize(psi[(pos + 1usize) % n])
        i += 1usize
    }
    i = 0usize
    while i < n {
        psi[i] = u32(sa[i])
        i += 1usize
    }
    ret (Csa { psi: psi[..n], sampled: sampled[..n], n: n, rate: rate }, ok)
}

// The text position of row `i`.
fn csa_lookup(c: *const Csa, i: usize) -> usize {
    var row = i
    var steps = 0usize
    while c.sampled[row] == NONE {
        row = usize(c.psi[row])
        steps += 1usize
    }
    ret (usize(c.sampled[row]) + c.n - steps) % c.n
}

// The rows whose suffixes start with `pattern` (`[lo, hi)`) by binary search over lookups.
fn csa_search(c: *const Csa, text: str, pattern: str) -> (usize, usize) {
    var lo = 0usize
    var hi = c.n
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if suffix.compare_at(text, csa_lookup(c, mid), pattern) <= 0i32 { hi = mid } else { lo = mid + 1usize }
    }
    let first = lo
    hi = c.n
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if suffix.compare_at(text, csa_lookup(c, mid), pattern) < 0i32 { hi = mid } else { lo = mid + 1usize }
    }
    ret (first, lo)
}

// An FM-index of `text` (terminated as for `csa_build`): the BWT in a
// wavelet matrix (`wavelet_build` storage over `n`), `starts.len >= 257`
// symbol starts, sampled positions as the CSA; `sa`, `scratch` and
// `bwt_bytes` (`n`) are scratch.
fn fm_build(text: str, rate: usize, starts: []u32, sampled: []u32, sa: []usize, scratch: []usize, bwt_bytes: []u8, bits: []u64, counts: []u32, levels: []BitVector, zeros: []usize, wave_scratch: []u8) -> (FmIndex, err) {
    let n = text.len
    if starts.len < 257usize || sampled.len < n || sa.len < n || bwt_bytes.len < n { ret (zero, TooSmall) }
    if n == 0usize || rate == 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i + 1usize < n {
        if text[i] <= text[n - 1usize] { ret (zero, Invalid) }
        i += 1usize
    }
    let e = suffix.array_build(text, sa, scratch)
    if e != ok { ret (zero, TooSmall) }
    i = 0usize
    while i <= 256usize {
        starts[i] = 0u32
        i += 1usize
    }
    i = 0usize
    while i < n {
        let pos = sa[i]
        var previous = n - 1usize
        if pos > 0usize { previous = pos - 1usize }
        bwt_bytes[i] = text[previous]
        starts[usize(text[i]) + 1usize] += 1u32
        sampled[i] = NONE
        if pos % rate == 0usize { sampled[i] = u32(pos) }
        i += 1usize
    }
    i = 1usize
    while i <= 256usize {
        starts[i] += starts[i - 1usize]
        i += 1usize
    }
    let (bwt, w_error) = wavelet_build(bwt_bytes, n, bits, counts, levels, zeros, wave_scratch)
    if w_error != ok { ret (zero, w_error) }
    ret (FmIndex { bwt: bwt, starts: starts[..257usize], sampled: sampled[..n], n: n, rate: rate }, ok)
}

// The row range `[lo, hi)` of suffixes starting with `pattern` by backward search.
fn fm_search(f: *const FmIndex, pattern: str) -> (usize, usize) {
    var lo = 0usize
    var hi = f.n
    var i = pattern.len
    while i > 0usize && lo < hi {
        i -= 1usize
        let c = pattern[i]
        lo = usize(f.starts[usize(c)]) + wavelet_rank(&f.bwt, c, lo)
        hi = usize(f.starts[usize(c)]) + wavelet_rank(&f.bwt, c, hi)
    }
    if lo > hi { ret (0usize, 0usize) }
    ret (lo, hi)
}

fn fm_count(f: *const FmIndex, pattern: str) -> usize {
    let (lo, hi) = fm_search(f, pattern)
    ret hi - lo
}

// The text position of row `i` by walking LF to a sampled row.
fn fm_locate(f: *const FmIndex, i: usize) -> usize {
    var row = i
    var steps = 0usize
    while f.sampled[row] == NONE {
        let c = wavelet_access(&f.bwt, row)
        row = usize(f.starts[usize(c)]) + wavelet_rank(&f.bwt, c, row)
        steps += 1usize
    }
    ret (usize(f.sampled[row]) + steps) % f.n
}
