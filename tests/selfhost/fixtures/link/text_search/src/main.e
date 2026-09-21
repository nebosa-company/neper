// `e.text.search`: every single-pattern finder agrees with a naive scan over a
// corpus of keys including absent, empty and end-anchored patterns; Aho-Corasick
// reports every occurrence of every pattern once with overlaps and nested
// patterns; the Z array matches its definition; bitap finds exact and one-edit
// matches; Manacher names the longest palindrome. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.search

type Hits = struct { count: usize, ends: [16]usize, patterns: [16]usize, stop_at: usize }

fn naive(text: str, pattern: str) -> (usize, bool) {
    if pattern.len == 0usize { ret (0usize, true) }
    var at = 0usize
    while at + pattern.len <= text.len {
        var j = 0usize
        while j < pattern.len && text[at + j] == pattern[j] { j += 1usize }
        if j == pattern.len { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn record(ctx: *Hits, end: usize, pattern: usize) -> bool {
    if ctx.count < 16usize {
        ctx.ends[ctx.count] = end
        ctx.patterns[ctx.count] = pattern
    }
    ctx.count += 1usize
    ret ctx.count != ctx.stop_at
}

fn main(a: *mem.Arena, args: []str) -> err {
    let text = "the quick brown fox jumps over the lazy dog; the dog sleeps. abracadabra"
    var patterns: [12]str = zero
    patterns[0usize] = "the"
    patterns[1usize] = "dog"
    patterns[2usize] = "abracadabra"
    patterns[3usize] = "abra"
    patterns[4usize] = "cat"
    patterns[5usize] = ""
    patterns[6usize] = "sleeps."
    patterns[7usize] = "z"
    patterns[8usize] = "jumps over the lazy"
    patterns[9usize] = "the quick brown fox jumps over the lazy dog; the dog sleeps. abracadabra!"
    patterns[10usize] = "aaa"
    patterns[11usize] = "dabra"

    // 1: kmp, horspool, boyer_moore and rabin_karp agree with the naive scan.
    var p = 0usize
    while p < 12usize {
        let pattern = patterns[p]
        let (want_at, want_found) = naive(text, pattern)
        var table: [128]usize = zero
        if search.kmp_table(pattern, table[..]) != ok { os.exit(1i32) }
        let (kmp_at, kmp_found) = search.kmp(text, pattern, table[..])
        if kmp_found != want_found || (want_found && kmp_at != want_at) { os.exit(1i32) }
        let (h_at, h_found) = search.horspool(text, pattern)
        if h_found != want_found || (want_found && h_at != want_at) { os.exit(1i32) }
        var suffix: [256]usize = zero
        if search.boyer_moore_table(pattern, suffix[..]) != ok { os.exit(1i32) }
        let (bm_at, bm_found) = search.boyer_moore(text, pattern, suffix[..])
        if bm_found != want_found || (want_found && bm_at != want_at) { os.exit(1i32) }
        let (rk_at, rk_found) = search.rabin_karp(text, pattern)
        if rk_found != want_found || (want_found && rk_at != want_at) { os.exit(1i32) }
        p += 1usize
    }
    // Repetitive text stresses the good-suffix rule.
    let stripes = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaab"
    var suffix2: [64]usize = zero
    if search.boyer_moore_table("aaab", suffix2[..]) != ok { os.exit(1i32) }
    let (s_at, s_found) = search.boyer_moore(stripes, "aaab", suffix2[..])
    if !s_found || s_at != 27usize { os.exit(1i32) }
    let (_, none_found) = search.boyer_moore(stripes, "aaba", suffix2[..])
    if none_found { os.exit(1i32) }
    // Undersized tables are refused rather than read past.
    var tiny: [2]usize = zero
    if search.kmp_table("abcd", tiny[..]) != search.TooSmall { os.exit(1i32) }
    if search.boyer_moore_table("abcd", tiny[..]) != search.TooSmall { os.exit(1i32) }

    // 2: Aho-Corasick over overlapping and nested patterns.
    var dictionary: [4]str = zero
    dictionary[0usize] = "he"
    dictionary[1usize] = "she"
    dictionary[2usize] = "his"
    dictionary[3usize] = "hers"
    let (automaton, build_error) = search.aho_corasick_build(a, dictionary[..])
    if build_error != ok { os.exit(2i32) }
    var hits = Hits { count: 0usize, ends: zero, patterns: zero, stop_at: 0usize }
    if !search.aho_corasick_find[Hits](&automaton, "ushers", &hits, record) { os.exit(2i32) }
    // "she" ends at 4, "he" ends at 4, "hers" ends at 6.
    if hits.count != 3usize { os.exit(2i32) }
    var seen_she = false
    var seen_he = false
    var seen_hers = false
    var h = 0usize
    while h < 3usize {
        if hits.ends[h] == 4usize && hits.patterns[h] == 1usize { seen_she = true }
        if hits.ends[h] == 4usize && hits.patterns[h] == 0usize { seen_he = true }
        if hits.ends[h] == 6usize && hits.patterns[h] == 3usize { seen_hers = true }
        h += 1usize
    }
    if !seen_she || !seen_he || !seen_hers { os.exit(2i32) }
    // No pattern in the text: no calls.
    hits.count = 0usize
    if !search.aho_corasick_find[Hits](&automaton, "xyz", &hits, record) || hits.count != 0usize { os.exit(2i32) }
    // A `false` answer stops the scan.
    hits.count = 0usize
    hits.stop_at = 1usize
    if search.aho_corasick_find[Hits](&automaton, "ushers", &hits, record) || hits.count != 1usize { os.exit(2i32) }
    // Overlapping occurrences of one pattern are each reported.
    var single: [1]str = zero
    single[0usize] = "aa"
    let (doubled, doubled_error) = search.aho_corasick_build(a, single[..])
    if doubled_error != ok { os.exit(2i32) }
    hits = Hits { count: 0usize, ends: zero, patterns: zero, stop_at: 0usize }
    if !search.aho_corasick_find[Hits](&doubled, "aaaa", &hits, record) || hits.count != 3usize { os.exit(2i32) }

    // 3: the Z array by definition.
    let z_text = "aabxaabxcaabxaabxay"
    var z: [32]usize = zero
    if search.z_array(z_text, z[..]) != ok { os.exit(3i32) }
    if z[0usize] != z_text.len { os.exit(3i32) }
    var i = 1usize
    while i < z_text.len {
        var k = 0usize
        while i + k < z_text.len && z_text[k] == z_text[i + k] { k += 1usize }
        if z[i] != k { os.exit(3i32) }
        i += 1usize
    }
    if z[4usize] != 4usize || z[9usize] != 8usize { os.exit(3i32) }
    if search.z_array("abc", tiny[..]) != search.TooSmall { os.exit(3i32) }

    // 4: bitap, exact and with edits.
    let (b0_at, b0_found) = search.bitap(text, "brown", 0u32)
    if !b0_found || b0_at != 10usize { os.exit(4i32) }
    let (_, b0_miss) = search.bitap(text, "brawn", 0u32)
    if b0_miss { os.exit(4i32) }
    let (b1_at, b1_found) = search.bitap(text, "brawn", 1u32)
    if !b1_found || b1_at != 10usize { os.exit(4i32) }
    let (b2_at, b2_found) = search.bitap(text, "jumpsover", 1u32)
    if !b2_found || b2_at < 19usize || b2_at > 21usize { os.exit(4i32) }
    let (_, too_long) = search.bitap(text, "the quick brown fox jumps over the lazy dog; the dog sleeps. abracadabra", 0u32)
    if too_long { os.exit(4i32) }
    let (e_at, e_found) = search.bitap(text, "", 0u32)
    if !e_found || e_at != 0usize { os.exit(4i32) }

    // 5: the longest palindrome.
    var scratch: [128]usize = zero
    let (p_at, p_len, p_error) = search.longest_palindrome("forgeeksskeegfor", scratch[..])
    if p_error != ok || p_at != 3usize || p_len != 10usize { os.exit(5i32) }
    let (q_at, q_len, q_error) = search.longest_palindrome("abacdfgdcaba", scratch[..])
    if q_error != ok || q_at != 0usize || q_len != 3usize { os.exit(5i32) }
    let (r_at, r_len, r_error) = search.longest_palindrome("xyz", scratch[..])
    if r_error != ok || r_len != 1usize || r_at > 2usize { os.exit(5i32) }
    let (_, s_len, s_error) = search.longest_palindrome("", scratch[..])
    if s_error != ok || s_len != 0usize { os.exit(5i32) }
    let (_, _, t_error) = search.longest_palindrome("abba", tiny[..])
    if t_error != search.TooSmall { os.exit(5i32) }

    try io.print("text search ok\n")
    ret ok
}
