// An inverted index over documents of space-separated words, built in the
// caller's arena: the distinct terms in byte order, each with its sorted
// posting list of document ids; `lookup` finds a term's postings by binary
// search, `intersect` and `unite` combine lists for AND and OR queries. The
// Elias-Fano codec stores a sorted list of `n` ids below `universe` in
// `n * (2 + log2(universe / n))` bits, low bits packed then high bits in
// unary, and decodes it back.

use e.mem

type Index = struct { terms: []str, starts: []usize, postings: []u32, documents: usize }
error TooSmall
error Invalid

fn compare(a: str, b: str) -> i32 {
    var i = 0usize
    while i < a.len && i < b.len {
        if a[i] < b[i] { ret 0i32 - 1i32 }
        if a[i] > b[i] { ret 1i32 }
        i += 1usize
    }
    if a.len < b.len { ret 0i32 - 1i32 }
    if a.len > b.len { ret 1i32 }
    ret 0i32
}

fn count_words(doc: str) -> usize {
    var count = 0usize
    var i = 0usize
    while i < doc.len {
        if doc[i] == 32u8 {
            i += 1usize
        } else {
            while i < doc.len && doc[i] != 32u8 { i += 1usize }
            count += 1usize
        }
    }
    ret count
}

// Merge sort of `order` (indices into `words`/`docs`) by (word, doc).
fn sort_pairs(words: []const str, docs: []const u32, order: []usize, scratch: []usize, low: usize, high: usize) {
    if high - low < 2usize { ret }
    let mid = low + (high - low) / 2usize
    sort_pairs(words, docs, order, scratch, low, mid)
    sort_pairs(words, docs, order, scratch, mid, high)
    var i = low
    var j = mid
    var k = low
    while i < mid && j < high {
        let a = order[i]
        let b = order[j]
        var c = compare(words[a], words[b])
        if c == 0i32 {
            if docs[a] < docs[b] { c = 0i32 - 1i32 } else if docs[a] > docs[b] { c = 1i32 }
        }
        if c <= 0i32 {
            scratch[k] = a
            i += 1usize
        } else {
            scratch[k] = b
            j += 1usize
        }
        k += 1usize
    }
    while i < mid {
        scratch[k] = order[i]
        i += 1usize
        k += 1usize
    }
    while j < high {
        scratch[k] = order[j]
        j += 1usize
        k += 1usize
    }
    k = low
    while k < high {
        order[k] = scratch[k]
        k += 1usize
    }
}

// Build the index of `docs` (at most 2^32 documents).
fn build(a: *mem.Arena, docs: []const str) -> (Index, err) {
    if docs.len > 4294967295usize { ret (zero, Invalid) }
    var total = 0usize
    var d = 0usize
    while d < docs.len {
        total += count_words(docs[d])
        d += 1usize
    }
    let (words, words_error) = mem.alloc[str](a, total)
    if words_error != ok { ret (zero, words_error) }
    let (owners, owners_error) = mem.alloc[u32](a, total)
    if owners_error != ok { ret (zero, owners_error) }
    let (order, order_error) = mem.alloc[usize](a, total)
    if order_error != ok { ret (zero, order_error) }
    let (scratch, scratch_error) = mem.alloc[usize](a, total)
    if scratch_error != ok { ret (zero, scratch_error) }
    var n = 0usize
    d = 0usize
    while d < docs.len {
        let doc = docs[d]
        var i = 0usize
        while i < doc.len {
            if doc[i] == 32u8 {
                i += 1usize
            } else {
                let start = i
                while i < doc.len && doc[i] != 32u8 { i += 1usize }
                words[n] = doc[start..i]
                owners[n] = u32(d)
                order[n] = n
                n += 1usize
            }
        }
        d += 1usize
    }
    sort_pairs(words, owners, order, scratch, 0usize, total)
    // Count distinct terms and distinct (term, doc) pairs.
    var terms = 0usize
    var pairs = 0usize
    var i = 0usize
    while i < total {
        let w = order[i]
        if i == 0usize || compare(words[order[i - 1usize]], words[w]) != 0i32 {
            terms += 1usize
            pairs += 1usize
        } else if owners[order[i - 1usize]] != owners[w] {
            pairs += 1usize
        }
        i += 1usize
    }
    let (term_list, terms_error) = mem.alloc[str](a, terms)
    if terms_error != ok { ret (zero, terms_error) }
    let (starts, starts_error) = mem.alloc[usize](a, terms + 1usize)
    if starts_error != ok { ret (zero, starts_error) }
    let (postings, postings_error) = mem.alloc[u32](a, pairs)
    if postings_error != ok { ret (zero, postings_error) }
    var t = 0usize
    var p = 0usize
    i = 0usize
    while i < total {
        let w = order[i]
        if i == 0usize || compare(words[order[i - 1usize]], words[w]) != 0i32 {
            term_list[t] = words[w]
            starts[t] = p
            t += 1usize
            postings[p] = owners[w]
            p += 1usize
        } else if owners[order[i - 1usize]] != owners[w] {
            postings[p] = owners[w]
            p += 1usize
        }
        i += 1usize
    }
    starts[terms] = p
    ret (Index { terms: term_list, starts: starts, postings: postings, documents: docs.len }, ok)
}

// The posting list of `term`, empty when it is not indexed.
fn lookup(x: *const Index, term: str) -> []const u32 {
    var low = 0usize
    var high = x.terms.len
    while low < high {
        let mid = low + (high - low) / 2usize
        let c = compare(x.terms[mid], term)
        if c == 0i32 { ret x.postings[x.starts[mid]..x.starts[mid + 1usize]] }
        if c < 0i32 { low = mid + 1usize } else { high = mid }
    }
    ret x.postings[..0usize]
}

// The ids in both sorted lists, into `out`.
fn intersect(a: []const u32, b: []const u32, out: []u32) -> (usize, err) {
    var i = 0usize
    var j = 0usize
    var n = 0usize
    while i < a.len && j < b.len {
        if a[i] < b[j] {
            i += 1usize
        } else if b[j] < a[i] {
            j += 1usize
        } else {
            if n >= out.len { ret (n, TooSmall) }
            out[n] = a[i]
            n += 1usize
            i += 1usize
            j += 1usize
        }
    }
    ret (n, ok)
}

// The ids in either sorted list, into `out`.
fn unite(a: []const u32, b: []const u32, out: []u32) -> (usize, err) {
    var i = 0usize
    var j = 0usize
    var n = 0usize
    while i < a.len || j < b.len {
        var next = 0u32
        if j >= b.len || (i < a.len && a[i] < b[j]) {
            next = a[i]
            i += 1usize
        } else if i >= a.len || b[j] < a[i] {
            next = b[j]
            j += 1usize
        } else {
            next = a[i]
            i += 1usize
            j += 1usize
        }
        if n >= out.len { ret (n, TooSmall) }
        out[n] = next
        n += 1usize
    }
    ret (n, ok)
}

fn low_bits(n: usize, universe: u32) -> u32 {
    if n == 0usize { ret 0u32 }
    var l = 0u32
    while (u64(universe) >> (l + 1u32)) >= u64(n) { l += 1u32 }
    ret l
}

fn set_bit(bits: []u8, at: usize) { bits[at / 8usize] |= u8(1u32 << u32(at % 8usize)) }
fn get_bit(bits: []const u8, at: usize) -> bool { ret (bits[at / 8usize] >> u32(at % 8usize)) & 1u8 == 1u8 }

// The bytes `elias_fano_encode` needs for `n` values below `universe`.
fn elias_fano_size(n: usize, universe: u32) -> usize {
    if n == 0usize { ret 0usize }
    let l = low_bits(n, universe)
    let low = n * usize(l)
    let high = n + (usize(universe) >> l) + 1usize
    ret (low + high + 7usize) / 8usize
}

// Encode the sorted `values` (each below `universe`) into `out`; answers
// the byte count.
fn elias_fano_encode(values: []const u32, universe: u32, out: []u8) -> (usize, err) {
    let n = values.len
    let size = elias_fano_size(n, universe)
    if out.len < size { ret (0usize, TooSmall) }
    let l = low_bits(n, universe)
    var i = 0usize
    while i < size {
        out[i] = 0u8
        i += 1usize
    }
    let high_start = n * usize(l)
    i = 0usize
    while i < n {
        let v = values[i]
        if v >= universe || (i > 0usize && v < values[i - 1usize]) { ret (0usize, Invalid) }
        var bit = 0u32
        while bit < l {
            if (v >> bit) & 1u32 == 1u32 { set_bit(out, i * usize(l) + usize(bit)) }
            bit += 1u32
        }
        // The high part h is coded as a one at position h + i of the high bits.
        set_bit(out, high_start + usize(v >> l) + i)
        i += 1usize
    }
    ret (size, ok)
}

// Decode `n` values below `universe` from `bytes` into `values`.
fn elias_fano_decode(bytes: []const u8, n: usize, universe: u32, values: []u32) -> err {
    if values.len < n || bytes.len < elias_fano_size(n, universe) { ret TooSmall }
    let l = low_bits(n, universe)
    let high_start = n * usize(l)
    let high_bits = n + (usize(universe) >> l) + 1usize
    var i = 0usize
    var pos = 0usize
    while i < n {
        // The i-th set bit of the high part sits at h + i.
        while pos < high_bits && !get_bit(bytes, high_start + pos) { pos += 1usize }
        if pos >= high_bits { ret Invalid }
        var v = u32(pos - i) << l
        var bit = 0u32
        while bit < l {
            if get_bit(bytes, i * usize(l) + usize(bit)) { v |= 1u32 << bit }
            bit += 1u32
        }
        values[i] = v
        pos += 1usize
        i += 1usize
    }
    ret ok
}
