// Substring search over the bytes of a `str`.
//
// Every finder answers the byte offset of the leftmost match and whether one exists;
// an empty pattern matches at 0. `kmp` and `boyer_moore` take caller storage for the
// pattern's table so a pattern searched many times is preprocessed once; `horspool`
// and `rabin_karp` need none. `aho_corasick_build` compiles a set of patterns into
// an arena-held automaton whose `aho_corasick_find` reports every occurrence of
// every pattern in one pass over the text. `bitap` allows up to `errors`
// edits for a pattern of at most 64 bytes. `z_array` and
// `longest_palindrome` are the linear-time helpers other string algorithms build on.

use e.mem

type Automaton = struct { next: []u32, fail: []u32, output: []u32, length: []u32, states: usize }
error TooLong
error TooSmall

// `table[i]` is the length of the longest proper prefix of `pattern[..i+1]` that is
// also its suffix; `table.len` must be at least `pattern.len`.
fn kmp_table(pattern: str, table: []usize) -> err {
    if table.len < pattern.len { ret TooSmall }
    if pattern.len == 0usize { ret ok }
    table[0usize] = 0usize
    var k = 0usize
    var i = 1usize
    while i < pattern.len {
        while k > 0usize && pattern[i] != pattern[k] { k = table[k - 1usize] }
        if pattern[i] == pattern[k] { k += 1usize }
        table[i] = k
        i += 1usize
    }
    ret ok
}

fn kmp(text: str, pattern: str, table: []const usize) -> (usize, bool) {
    if pattern.len == 0usize { ret (0usize, true) }
    if table.len < pattern.len { ret (0usize, false) }
    var k = 0usize
    var i = 0usize
    while i < text.len {
        while k > 0usize && text[i] != pattern[k] { k = table[k - 1usize] }
        if text[i] == pattern[k] { k += 1usize }
        if k == pattern.len { ret (i + 1usize - pattern.len, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// Boyer-Moore-Horspool: skips by the last byte of the window alone.
fn horspool(text: str, pattern: str) -> (usize, bool) {
    if pattern.len == 0usize { ret (0usize, true) }
    if pattern.len > text.len { ret (0usize, false) }
    var shift: [256]usize = zero
    var b = 0usize
    while b < 256usize {
        shift[b] = pattern.len
        b += 1usize
    }
    var i = 0usize
    while i + 1usize < pattern.len {
        shift[usize(pattern[i])] = pattern.len - 1usize - i
        i += 1usize
    }
    var at = 0usize
    while at + pattern.len <= text.len {
        var j = pattern.len
        while j > 0usize && text[at + j - 1usize] == pattern[j - 1usize] { j -= 1usize }
        if j == 0usize { ret (at, true) }
        at += shift[usize(text[at + pattern.len - 1usize])]
    }
    ret (0usize, false)
}

// The good-suffix shifts in `good_suffix[..m + 1]`; the table needs `2 * m + 2`
// entries, the upper half being scratch for the border pass.
fn boyer_moore_table(pattern: str, good_suffix: []usize) -> err {
    let m = pattern.len
    if good_suffix.len < 2usize * m + 2usize { ret TooSmall }
    if m == 0usize { ret ok }
    let border = good_suffix[m + 1usize..]
    var i = 0usize
    while i <= m {
        good_suffix[i] = 0usize
        i += 1usize
    }
    i = m
    var j = m + 1usize
    border[i] = j
    while i > 0usize {
        while j <= m && pattern[i - 1usize] != pattern[j - 1usize] {
            if good_suffix[j] == 0usize { good_suffix[j] = j - i }
            j = border[j]
        }
        i -= 1usize
        j -= 1usize
        border[i] = j
    }
    j = border[0usize]
    i = 0usize
    while i <= m {
        if good_suffix[i] == 0usize { good_suffix[i] = j }
        if i == j { j = border[j] }
        i += 1usize
    }
    ret ok
}

// Full Boyer-Moore: the larger of the bad-character and good-suffix shifts.
fn boyer_moore(text: str, pattern: str, good_suffix: []const usize) -> (usize, bool) {
    let m = pattern.len
    if m == 0usize { ret (0usize, true) }
    if m > text.len || good_suffix.len < m + 1usize { ret (0usize, false) }
    var last: [256]usize = zero
    var b = 0usize
    while b < 256usize {
        last[b] = m
        b += 1usize
    }
    var i = 0usize
    while i < m {
        last[usize(pattern[i])] = m - 1usize - i
        i += 1usize
    }
    var at = 0usize
    while at + m <= text.len {
        var j = m
        while j > 0usize && text[at + j - 1usize] == pattern[j - 1usize] { j -= 1usize }
        if j == 0usize { ret (at, true) }
        // Bad character: align the mismatched text byte with its last pattern occurrence.
        let mismatch = usize(text[at + j - 1usize])
        var bad = 1usize
        if last[mismatch] + j > m { bad = last[mismatch] + j - m }
        var shift = good_suffix[j]
        if bad > shift { shift = bad }
        at += shift
    }
    ret (0usize, false)
}

// Rolling hash over a 64-bit modulus-free ring, every hash hit verified byte by byte.
fn rabin_karp(text: str, pattern: str) -> (usize, bool) {
    let m = pattern.len
    if m == 0usize { ret (0usize, true) }
    if m > text.len { ret (0usize, false) }
    let base = 257u64
    var high = 1u64
    var i = 1usize
    while i < m {
        high = high *% base
        i += 1usize
    }
    var want = 0u64
    var have = 0u64
    i = 0usize
    while i < m {
        want = want *% base +% u64(pattern[i])
        have = have *% base +% u64(text[i])
        i += 1usize
    }
    var at = 0usize
    while true {
        if have == want {
            var j = 0usize
            while j < m && text[at + j] == pattern[j] { j += 1usize }
            if j == m { ret (at, true) }
        }
        if at + m >= text.len { break }
        have = (have -% u64(text[at]) *% high) *% base +% u64(text[at + m])
        at += 1usize
    }
    ret (0usize, false)
}

// A dense byte-transition automaton over the patterns: `(total pattern bytes + 1) * 256`
// transitions, so it suits dictionaries of moderate size.
fn aho_corasick_build(a: *mem.Arena, patterns: []const str) -> (Automaton, err) {
    var total = 1usize
    var p = 0usize
    while p < patterns.len {
        total += patterns[p].len
        p += 1usize
    }
    if total > 4294967295usize / 256usize { ret (zero, TooLong) }
    let (next, next_error) = mem.alloc[u32](a, total * 256usize)
    if next_error != ok { ret (zero, next_error) }
    let (fail, fail_error) = mem.alloc[u32](a, total)
    if fail_error != ok { ret (zero, fail_error) }
    let (output, output_error) = mem.alloc[u32](a, total)
    if output_error != ok { ret (zero, output_error) }
    let (length, length_error) = mem.alloc[u32](a, total)
    if length_error != ok { ret (zero, length_error) }
    var i = 0usize
    while i < total * 256usize {
        next[i] = 0u32
        i += 1usize
    }
    i = 0usize
    while i < total {
        fail[i] = 0u32
        output[i] = 4294967295u32
        length[i] = 0u32
        i += 1usize
    }
    // The trie: state 0 is the root; a zero transition from any other state means
    // "not yet set" while building and is resolved to the failure chain below.
    var states = 1usize
    p = 0usize
    while p < patterns.len {
        var state = 0usize
        var k = 0usize
        while k < patterns[p].len {
            let slot = state * 256usize + usize(patterns[p][k])
            if next[slot] == 0u32 {
                next[slot] = u32(states)
                states += 1usize
            }
            state = usize(next[slot])
            k += 1usize
        }
        if patterns[p].len > 0usize && output[state] == 4294967295u32 {
            output[state] = u32(p)
            length[state] = u32(patterns[p].len)
        }
        p += 1usize
    }
    // Breadth-first over the trie sets failure links and completes the transitions.
    let (queue, queue_error) = mem.alloc[u32](a, states)
    if queue_error != ok { ret (zero, queue_error) }
    var head = 0usize
    var tail = 0usize
    var b = 0usize
    while b < 256usize {
        let child = next[b]
        if child != 0u32 {
            fail[usize(child)] = 0u32
            queue[tail] = child
            tail += 1usize
        }
        b += 1usize
    }
    while head < tail {
        let state = usize(queue[head])
        head += 1usize
        b = 0usize
        while b < 256usize {
            let slot = state * 256usize + b
            let child = next[slot]
            if child != 0u32 {
                fail[usize(child)] = next[usize(fail[state]) * 256usize + b]
                queue[tail] = child
                tail += 1usize
            } else {
                next[slot] = next[usize(fail[state]) * 256usize + b]
            }
            b += 1usize
        }
    }
    ret (Automaton { next: next, fail: fail, output: output, length: length, states: states }, ok)
}

// Calls `on_match(ctx, end, pattern)` for every pattern ending at byte `end`
// (exclusive), longest suffix first; a `false` answer stops the scan and is returned.
fn aho_corasick_find[Ctx: type](m: *const Automaton, text: str, ctx: *Ctx, on_match: fn(*Ctx, usize, usize) -> bool) -> bool {
    var state = 0usize
    var i = 0usize
    while i < text.len {
        state = usize(m.next[state * 256usize + usize(text[i])])
        var report = state
        while report != 0usize {
            if m.output[report] != 4294967295u32 {
                if !on_match(ctx, i + 1usize, usize(m.output[report])) { ret false }
            }
            report = usize(m.fail[report])
        }
        i += 1usize
    }
    ret true
}

// `z[i]` is the length of the longest prefix of `s` that starts at `i`; `z[0]` is `s.len`.
fn z_array(s: str, z: []usize) -> err {
    if z.len < s.len { ret TooSmall }
    if s.len == 0usize { ret ok }
    z[0usize] = s.len
    var left = 0usize
    var right = 0usize
    var i = 1usize
    while i < s.len {
        var k = 0usize
        if i < right {
            k = z[i - left]
            if k > right - i { k = right - i }
        }
        while i + k < s.len && s[k] == s[i + k] { k += 1usize }
        z[i] = k
        if i + k > right {
            left = i
            right = i + k
        }
        i += 1usize
    }
    ret ok
}

// Shift-Or (Wu-Manber) allowing up to `errors` edits -- substitutions, insertions or
// deletions; the pattern is at most 64 bytes and `errors` at most 63.
fn bitap(text: str, pattern: str, errors: u32) -> (usize, bool) {
    let m = pattern.len
    if m == 0usize { ret (0usize, true) }
    if m > 64usize || errors > 63u32 { ret (0usize, false) }
    var masks: [256]u64 = zero
    var b = 0usize
    while b < 256usize {
        masks[b] = 18446744073709551615u64
        b += 1usize
    }
    var i = 0usize
    while i < m {
        masks[usize(pattern[i])] = masks[usize(pattern[i])] & ~(1u64 << u64(i))
        i += 1usize
    }
    var rows: [64]u64 = zero
    let levels = usize(errors) + 1usize
    var d = 0usize
    while d < levels {
        rows[d] = 18446744073709551615u64 << u64(d)
        d += 1usize
    }
    let accept = 1u64 << u64(m - 1usize)
    i = 0usize
    while i < text.len {
        var previous = rows[0usize]
        rows[0usize] = (previous << 1u64) | masks[usize(text[i])]
        d = 1usize
        while d < levels {
            let current = rows[d]
            rows[d] = ((current << 1u64) | masks[usize(text[i])]) & (previous << 1u64) & (rows[d - 1usize] << 1u64) & previous
            previous = current
            d += 1usize
        }
        if (rows[levels - 1usize] & accept) == 0u64 {
            var start = 0usize
            if i + 1usize > m { start = i + 1usize - m }
            ret (start, true)
        }
        i += 1usize
    }
    ret (0usize, false)
}

// Manacher's algorithm: the start and length of the longest palindromic substring.
// `scratch.len` must be at least `2 * s.len + 1`.
fn longest_palindrome(s: str, scratch: []usize) -> (usize, usize, err) {
    if s.len == 0usize { ret (0usize, 0usize, ok) }
    let n = 2usize * s.len + 1usize
    if scratch.len < n { ret (0usize, 0usize, TooSmall) }
    // Position `i` of the widened string is a gap when even and `s[i / 2]` when odd.
    var center = 0usize
    var right = 0usize
    var best_at = 0usize
    var best_len = 0usize
    var i = 0usize
    while i < n {
        var radius = 0usize
        if i < right {
            radius = scratch[2usize * center - i]
            if radius > right - i { radius = right - i }
        }
        while i + radius + 1usize < n && i >= radius + 1usize {
            let lo = i - radius - 1usize
            let hi = i + radius + 1usize
            var same = (lo % 2usize) == 0usize
            if !same { same = s[lo / 2usize] == s[hi / 2usize] }
            if !same { break }
            radius += 1usize
        }
        scratch[i] = radius
        if i + radius > right {
            center = i
            right = i + radius
        }
        if radius > best_len {
            best_len = radius
            best_at = (i - radius) / 2usize
        }
        i += 1usize
    }
    if best_len == 0usize { ret (0usize, 1usize, ok) }
    ret (best_at, best_len, ok)
}
