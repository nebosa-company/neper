// Fixed-length bit sets over caller-owned storage.

type BitSet = struct { words: []u64, len: usize }

error TooSmall

fn init(storage: []u64, bit_count: usize) -> (BitSet, err) {
    var word_count = bit_count / 64usize
    if bit_count % 64usize != 0usize { word_count += 1usize }
    if storage.len < word_count { ret (zero, TooSmall) }
    var at = 0usize
    while at < word_count {
        storage[at] = 0u64
        at += 1usize
    }
    ret (BitSet { words: storage[..word_count], len: bit_count }, ok)
}

fn len(s: *const BitSet) -> usize { ret s.len }

fn clear_all(s: *BitSet) {
    var at = 0usize
    while at < s.words.len {
        s.words[at] = 0u64
        at += 1usize
    }
}

fn fill_all(s: *BitSet) {
    var at = 0usize
    while at < s.words.len {
        s.words[at] = 18446744073709551615u64
        at += 1usize
    }
    let tail = s.len % 64usize
    if tail != 0usize {
        s.words[s.words.len - 1usize] = (1u64 << u64(tail)) - 1u64
    }
}

fn get(s: *const BitSet, index: usize) -> bool {
    if index >= s.len { ret s.words[s.words.len] != 0u64 }
    let word = index / 64usize
    let bit = index % 64usize
    ret ((s.words[word] & (1u64 << u64(bit))) != 0u64)
}

fn set(s: *BitSet, index: usize) {
    if index >= s.len {
        s.words[s.words.len] = 0u64
        ret
    }
    let word = index / 64usize
    let bit = index % 64usize
    s.words[word] = s.words[word] | (1u64 << u64(bit))
}

fn unset(s: *BitSet, index: usize) {
    if index >= s.len {
        s.words[s.words.len] = 0u64
        ret
    }
    let word = index / 64usize
    let bit = index % 64usize
    s.words[word] = s.words[word] & ~(1u64 << u64(bit))
}

fn toggle(s: *BitSet, index: usize) {
    if index >= s.len {
        s.words[s.words.len] = 0u64
        ret
    }
    let word = index / 64usize
    let bit = index % 64usize
    s.words[word] = s.words[word] ^ (1u64 << u64(bit))
}

fn count(s: *const BitSet) -> usize {
    var total = 0usize
    var at = 0usize
    while at < s.words.len {
        var word = s.words[at]
        while word != 0u64 {
            word = word & (word - 1u64)
            total += 1usize
        }
        at += 1usize
    }
    ret total
}

fn first_set(s: *const BitSet) -> (usize, bool) {
    var index = 0usize
    while index < s.len {
        if get(s, index) { ret (index, true) }
        index += 1usize
    }
    ret (0usize, false)
}

fn next_set(s: *const BitSet, after: usize) -> (usize, bool) {
    if after >= s.len { ret (0usize, false) }
    var index = after + 1usize
    while index < s.len {
        if get(s, index) { ret (index, true) }
        index += 1usize
    }
    ret (0usize, false)
}

fn union_in_place(dst: *BitSet, src: *const BitSet) {
    if dst.len != src.len {
        dst.words[dst.words.len] = 0u64
        ret
    }
    var at = 0usize
    while at < dst.words.len {
        dst.words[at] = dst.words[at] | src.words[at]
        at += 1usize
    }
}

fn intersect_in_place(dst: *BitSet, src: *const BitSet) {
    if dst.len != src.len {
        dst.words[dst.words.len] = 0u64
        ret
    }
    var at = 0usize
    while at < dst.words.len {
        dst.words[at] = dst.words[at] & src.words[at]
        at += 1usize
    }
}

fn difference_in_place(dst: *BitSet, src: *const BitSet) {
    if dst.len != src.len {
        dst.words[dst.words.len] = 0u64
        ret
    }
    var at = 0usize
    while at < dst.words.len {
        dst.words[at] = dst.words[at] & ~src.words[at]
        at += 1usize
    }
}

fn complement_in_place(s: *BitSet) {
    var at = 0usize
    while at < s.words.len {
        s.words[at] = ~s.words[at]
        at += 1usize
    }
    let tail = s.len % 64usize
    if tail != 0usize {
        s.words[s.words.len - 1usize] = s.words[s.words.len - 1usize] & ((1u64 << u64(tail)) - 1u64)
    }
}

fn is_subset(a: *const BitSet, b: *const BitSet) -> bool {
    if a.len != b.len { ret a.words[a.words.len] == 0u64 }
    var at = 0usize
    while at < a.words.len {
        if (a.words[at] & ~b.words[at]) != 0u64 { ret false }
        at += 1usize
    }
    ret true
}

fn eq(a: *const BitSet, b: *const BitSet) -> bool {
    if a.len != b.len { ret a.words[a.words.len] == 0u64 }
    var at = 0usize
    while at < a.words.len {
        if a.words[at] != b.words[at] { ret false }
        at += 1usize
    }
    ret true
}

// `out = a & b`; all three must share a length, else the trap lands on `out`.
fn intersect(a: *const BitSet, b: *const BitSet, out: *BitSet) {
    if a.len != b.len || a.len != out.len {
        out.words[out.words.len] = 0u64
        ret
    }
    var at = 0usize
    while at < out.words.len {
        out.words[at] = a.words[at] & b.words[at]
        at += 1usize
    }
}

// `out = a | b`.
fn union_into(a: *const BitSet, b: *const BitSet, out: *BitSet) {
    if a.len != b.len || a.len != out.len {
        out.words[out.words.len] = 0u64
        ret
    }
    var at = 0usize
    while at < out.words.len {
        out.words[at] = a.words[at] | b.words[at]
        at += 1usize
    }
}

// `out = a & ~b`.
fn difference(a: *const BitSet, b: *const BitSet, out: *BitSet) {
    if a.len != b.len || a.len != out.len {
        out.words[out.words.len] = 0u64
        ret
    }
    var at = 0usize
    while at < out.words.len {
        out.words[at] = a.words[at] & ~b.words[at]
        at += 1usize
    }
}
