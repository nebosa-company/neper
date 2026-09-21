// Distances and similarities between the bytes of two strings.
//
// Every entry point is over caller storage so no call allocates; a `TooSmall`
// answer names scratch that is shorter than the function needs, and the sizes are
// stated at each declaration. Distances count bytes, not scalars: a caller that
// wants scalar edits normalises first (`e.text.normalize`) or compares UTF-32.

use e.algo.sort

error TooSmall
error Mismatch

// The Levenshtein edit distance (insert, delete, substitute). Two rows of
// `b.len + 1` entries: `scratch.len >= 2 * (b.len + 1)`.
fn levenshtein(a: str, b: str, scratch: []usize) -> (usize, err) {
    let width = b.len + 1usize
    if scratch.len < 2usize * width { ret (0usize, TooSmall) }
    var previous = scratch[..width]
    var current = scratch[width..2usize * width]
    var j = 0usize
    while j < width {
        previous[j] = j
        j += 1usize
    }
    var i = 0usize
    while i < a.len {
        current[0usize] = i + 1usize
        j = 0usize
        while j < b.len {
            var cost = previous[j]
            if a[i] != b[j] { cost += 1usize }
            let insert = current[j] + 1usize
            let remove = previous[j + 1usize] + 1usize
            if insert < cost { cost = insert }
            if remove < cost { cost = remove }
            current[j + 1usize] = cost
            j += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        i += 1usize
    }
    ret (previous[b.len], ok)
}

// Optimal string alignment distance: Levenshtein plus transposition of two adjacent
// bytes. Three rows: `scratch.len >= 3 * (b.len + 1)`.
fn damerau_levenshtein(a: str, b: str, scratch: []usize) -> (usize, err) {
    let width = b.len + 1usize
    if scratch.len < 3usize * width { ret (0usize, TooSmall) }
    var before = scratch[..width]
    var previous = scratch[width..2usize * width]
    var current = scratch[2usize * width..3usize * width]
    var j = 0usize
    while j < width {
        previous[j] = j
        j += 1usize
    }
    var i = 0usize
    while i < a.len {
        current[0usize] = i + 1usize
        j = 0usize
        while j < b.len {
            var cost = previous[j]
            if a[i] != b[j] { cost += 1usize }
            let insert = current[j] + 1usize
            let remove = previous[j + 1usize] + 1usize
            if insert < cost { cost = insert }
            if remove < cost { cost = remove }
            if i > 0usize && j > 0usize && a[i] == b[j - 1usize] && a[i - 1usize] == b[j] {
                let swap_cost = before[j - 1usize] + 1usize
                if swap_cost < cost { cost = swap_cost }
            }
            current[j + 1usize] = cost
            j += 1usize
        }
        let rotate = before
        before = previous
        previous = current
        current = rotate
        i += 1usize
    }
    ret (previous[b.len], ok)
}

// The number of positions at which two equal-length strings differ.
fn hamming(a: str, b: str) -> (usize, err) {
    if a.len != b.len { ret (0usize, Mismatch) }
    var count = 0usize
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { count += 1usize }
        i += 1usize
    }
    ret (count, ok)
}

// Jaro similarity in `0..=1`; `scratch.len >= a.len + b.len` holds the match flags.
fn jaro(a: str, b: str, scratch: []u8) -> (f64, err) {
    if scratch.len < a.len + b.len { ret (0.0f64, TooSmall) }
    if a.len == 0usize && b.len == 0usize { ret (1.0f64, ok) }
    if a.len == 0usize || b.len == 0usize { ret (0.0f64, ok) }
    var longer = a.len
    if b.len > longer { longer = b.len }
    var window = 0usize
    if longer / 2usize > 0usize { window = longer / 2usize - 1usize }
    var flags_a = scratch[..a.len]
    var flags_b = scratch[a.len..a.len + b.len]
    var i = 0usize
    while i < a.len + b.len {
        scratch[i] = 0u8
        i += 1usize
    }
    var matches = 0usize
    i = 0usize
    while i < a.len {
        var low = 0usize
        if i > window { low = i - window }
        var high = i + window + 1usize
        if high > b.len { high = b.len }
        var j = low
        while j < high {
            if flags_b[j] == 0u8 && a[i] == b[j] {
                flags_a[i] = 1u8
                flags_b[j] = 1u8
                matches += 1usize
                break
            }
            j += 1usize
        }
        i += 1usize
    }
    if matches == 0usize { ret (0.0f64, ok) }
    var transposed = 0usize
    var k = 0usize
    i = 0usize
    while i < a.len {
        if flags_a[i] != 0u8 {
            while flags_b[k] == 0u8 { k += 1usize }
            if a[i] != b[k] { transposed += 1usize }
            k += 1usize
        }
        i += 1usize
    }
    let m = f64(matches)
    let t = f64(transposed / 2usize)
    ret ((m / f64(a.len) + m / f64(b.len) + (m - t) / m) / 3.0f64, ok)
}

// Jaro-Winkler: Jaro boosted by up to four bytes of common prefix at `scale`
// (0.1 is the usual choice). Same scratch as `jaro`.
fn jaro_winkler(a: str, b: str, scale: f64, scratch: []u8) -> (f64, err) {
    let (base, base_error) = jaro(a, b, scratch)
    if base_error != ok { ret (0.0f64, base_error) }
    var prefix = 0usize
    while prefix < 4usize && prefix < a.len && prefix < b.len && a[prefix] == b[prefix] { prefix += 1usize }
    ret (base + f64(prefix) * scale * (1.0f64 - base), ok)
}

// The longest run of bytes common to both: its offsets in `a` and `b` and its
// length. Two rows: `scratch.len >= 2 * (b.len + 1)`.
fn longest_common_substring(a: str, b: str, scratch: []usize) -> (usize, usize, usize, err) {
    let width = b.len + 1usize
    if scratch.len < 2usize * width { ret (0usize, 0usize, 0usize, TooSmall) }
    var previous = scratch[..width]
    var current = scratch[width..2usize * width]
    var j = 0usize
    while j < width {
        previous[j] = 0usize
        j += 1usize
    }
    var best_len = 0usize
    var best_a = 0usize
    var best_b = 0usize
    var i = 0usize
    while i < a.len {
        current[0usize] = 0usize
        j = 0usize
        while j < b.len {
            if a[i] == b[j] {
                let run = previous[j] + 1usize
                current[j + 1usize] = run
                if run > best_len {
                    best_len = run
                    best_a = i + 1usize - run
                    best_b = j + 1usize - run
                }
            } else {
                current[j + 1usize] = 0usize
            }
            j += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        i += 1usize
    }
    ret (best_a, best_b, best_len, ok)
}

// Jaccard similarity of the byte-trigram multisets, in `0..=1`; a string shorter
// than three bytes has no trigrams. `scratch.len >= a.len + b.len`.
fn trigram(a: str, b: str, scratch: []u32) -> (f64, err) {
    if scratch.len < a.len + b.len { ret (0.0f64, TooSmall) }
    var count_a = 0usize
    if a.len >= 3usize { count_a = a.len - 2usize }
    var count_b = 0usize
    if b.len >= 3usize { count_b = b.len - 2usize }
    if count_a == 0usize && count_b == 0usize { ret (1.0f64, ok) }
    if count_a == 0usize || count_b == 0usize { ret (0.0f64, ok) }
    var grams_a = scratch[..count_a]
    var grams_b = scratch[count_a..count_a + count_b]
    var i = 0usize
    while i < count_a {
        grams_a[i] = (u32(a[i]) << 16u32) | (u32(a[i + 1usize]) << 8u32) | u32(a[i + 2usize])
        i += 1usize
    }
    i = 0usize
    while i < count_b {
        grams_b[i] = (u32(b[i]) << 16u32) | (u32(b[i + 1usize]) << 8u32) | u32(b[i + 2usize])
        i += 1usize
    }
    sort.in_place[u32](grams_a)
    sort.in_place[u32](grams_b)
    var common = 0usize
    i = 0usize
    var j = 0usize
    while i < count_a && j < count_b {
        if grams_a[i] == grams_b[j] {
            common += 1usize
            i += 1usize
            j += 1usize
        } else if grams_a[i] < grams_b[j] {
            i += 1usize
        } else {
            j += 1usize
        }
    }
    ret (f64(common) / f64(count_a + count_b - common), ok)
}
