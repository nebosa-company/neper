// `e.text.suffix`: the suffix and LCP arrays of banana, abracadabra,
// mississippi, a run of one letter, a periodic text and a random binary
// text agree with a naive Python sort; array search answers the range of
// every occurrence; the suffix automaton accepts exactly the substrings and
// counts them; the suffix tree from the array answers the same membership
// with the expected node count. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.suffix

fn same_array(got: []const usize, want: []const usize) -> bool {
    var i = 0usize
    while i < want.len {
        if got[i] != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn check_arrays(text: str, want_sa: []const usize, want_lcp: []const usize) {
    var sa: [64]usize = zero
    var lcp: [64]usize = zero
    var scratch: [512]usize = zero
    if suffix.array_build(text, sa[..text.len], scratch[..]) != ok { os.exit(1i32) }
    if !same_array(sa[..], want_sa) { os.exit(1i32) }
    if suffix.lcp_array(text, sa[..text.len], lcp[..text.len], scratch[..]) != ok { os.exit(1i32) }
    if !same_array(lcp[..], want_lcp) { os.exit(1i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: arrays.
    var sa_bana: [6]usize = zero
    sa_bana[0usize] = 5usize
    sa_bana[1usize] = 3usize
    sa_bana[2usize] = 1usize
    sa_bana[3usize] = 0usize
    sa_bana[4usize] = 4usize
    sa_bana[5usize] = 2usize
    var lcp_bana: [6]usize = zero
    lcp_bana[0usize] = 0usize
    lcp_bana[1usize] = 1usize
    lcp_bana[2usize] = 3usize
    lcp_bana[3usize] = 0usize
    lcp_bana[4usize] = 0usize
    lcp_bana[5usize] = 2usize
    check_arrays("banana", sa_bana[..], lcp_bana[..])
    var sa_abra: [11]usize = zero
    sa_abra[0usize] = 10usize
    sa_abra[1usize] = 7usize
    sa_abra[2usize] = 0usize
    sa_abra[3usize] = 3usize
    sa_abra[4usize] = 5usize
    sa_abra[5usize] = 8usize
    sa_abra[6usize] = 1usize
    sa_abra[7usize] = 4usize
    sa_abra[8usize] = 6usize
    sa_abra[9usize] = 9usize
    sa_abra[10usize] = 2usize
    var lcp_abra: [11]usize = zero
    lcp_abra[0usize] = 0usize
    lcp_abra[1usize] = 1usize
    lcp_abra[2usize] = 4usize
    lcp_abra[3usize] = 1usize
    lcp_abra[4usize] = 1usize
    lcp_abra[5usize] = 0usize
    lcp_abra[6usize] = 3usize
    lcp_abra[7usize] = 0usize
    lcp_abra[8usize] = 0usize
    lcp_abra[9usize] = 0usize
    lcp_abra[10usize] = 2usize
    check_arrays("abracadabra", sa_abra[..], lcp_abra[..])
    var sa_miss: [11]usize = zero
    sa_miss[0usize] = 10usize
    sa_miss[1usize] = 7usize
    sa_miss[2usize] = 4usize
    sa_miss[3usize] = 1usize
    sa_miss[4usize] = 0usize
    sa_miss[5usize] = 9usize
    sa_miss[6usize] = 8usize
    sa_miss[7usize] = 6usize
    sa_miss[8usize] = 3usize
    sa_miss[9usize] = 5usize
    sa_miss[10usize] = 2usize
    var lcp_miss: [11]usize = zero
    lcp_miss[0usize] = 0usize
    lcp_miss[1usize] = 1usize
    lcp_miss[2usize] = 1usize
    lcp_miss[3usize] = 4usize
    lcp_miss[4usize] = 0usize
    lcp_miss[5usize] = 0usize
    lcp_miss[6usize] = 1usize
    lcp_miss[7usize] = 0usize
    lcp_miss[8usize] = 2usize
    lcp_miss[9usize] = 1usize
    lcp_miss[10usize] = 3usize
    check_arrays("mississippi", sa_miss[..], lcp_miss[..])
    var sa_aaaa: [8]usize = zero
    sa_aaaa[0usize] = 7usize
    sa_aaaa[1usize] = 6usize
    sa_aaaa[2usize] = 5usize
    sa_aaaa[3usize] = 4usize
    sa_aaaa[4usize] = 3usize
    sa_aaaa[5usize] = 2usize
    sa_aaaa[6usize] = 1usize
    sa_aaaa[7usize] = 0usize
    var lcp_aaaa: [8]usize = zero
    lcp_aaaa[0usize] = 0usize
    lcp_aaaa[1usize] = 1usize
    lcp_aaaa[2usize] = 2usize
    lcp_aaaa[3usize] = 3usize
    lcp_aaaa[4usize] = 4usize
    lcp_aaaa[5usize] = 5usize
    lcp_aaaa[6usize] = 6usize
    lcp_aaaa[7usize] = 7usize
    check_arrays("aaaaaaaa", sa_aaaa[..], lcp_aaaa[..])
    var sa_abca: [13]usize = zero
    sa_abca[0usize] = 0usize
    sa_abca[1usize] = 3usize
    sa_abca[2usize] = 6usize
    sa_abca[3usize] = 9usize
    sa_abca[4usize] = 1usize
    sa_abca[5usize] = 4usize
    sa_abca[6usize] = 7usize
    sa_abca[7usize] = 10usize
    sa_abca[8usize] = 2usize
    sa_abca[9usize] = 5usize
    sa_abca[10usize] = 8usize
    sa_abca[11usize] = 11usize
    sa_abca[12usize] = 12usize
    var lcp_abca: [13]usize = zero
    lcp_abca[0usize] = 0usize
    lcp_abca[1usize] = 9usize
    lcp_abca[2usize] = 6usize
    lcp_abca[3usize] = 3usize
    lcp_abca[4usize] = 0usize
    lcp_abca[5usize] = 8usize
    lcp_abca[6usize] = 5usize
    lcp_abca[7usize] = 2usize
    lcp_abca[8usize] = 0usize
    lcp_abca[9usize] = 7usize
    lcp_abca[10usize] = 4usize
    lcp_abca[11usize] = 1usize
    lcp_abca[12usize] = 0usize
    check_arrays("abcabcabcabcd", sa_abca[..], lcp_abca[..])
    var sa_rnd: [60]usize = zero
    sa_rnd[0usize] = 17usize
    sa_rnd[1usize] = 7usize
    sa_rnd[2usize] = 22usize
    sa_rnd[3usize] = 46usize
    sa_rnd[4usize] = 35usize
    sa_rnd[5usize] = 13usize
    sa_rnd[6usize] = 3usize
    sa_rnd[7usize] = 18usize
    sa_rnd[8usize] = 31usize
    sa_rnd[9usize] = 8usize
    sa_rnd[10usize] = 23usize
    sa_rnd[11usize] = 47usize
    sa_rnd[12usize] = 36usize
    sa_rnd[13usize] = 14usize
    sa_rnd[14usize] = 4usize
    sa_rnd[15usize] = 19usize
    sa_rnd[16usize] = 32usize
    sa_rnd[17usize] = 28usize
    sa_rnd[18usize] = 55usize
    sa_rnd[19usize] = 9usize
    sa_rnd[20usize] = 24usize
    sa_rnd[21usize] = 48usize
    sa_rnd[22usize] = 37usize
    sa_rnd[23usize] = 58usize
    sa_rnd[24usize] = 15usize
    sa_rnd[25usize] = 5usize
    sa_rnd[26usize] = 20usize
    sa_rnd[27usize] = 33usize
    sa_rnd[28usize] = 1usize
    sa_rnd[29usize] = 29usize
    sa_rnd[30usize] = 56usize
    sa_rnd[31usize] = 10usize
    sa_rnd[32usize] = 25usize
    sa_rnd[33usize] = 49usize
    sa_rnd[34usize] = 38usize
    sa_rnd[35usize] = 59usize
    sa_rnd[36usize] = 16usize
    sa_rnd[37usize] = 6usize
    sa_rnd[38usize] = 21usize
    sa_rnd[39usize] = 45usize
    sa_rnd[40usize] = 34usize
    sa_rnd[41usize] = 12usize
    sa_rnd[42usize] = 2usize
    sa_rnd[43usize] = 30usize
    sa_rnd[44usize] = 27usize
    sa_rnd[45usize] = 54usize
    sa_rnd[46usize] = 57usize
    sa_rnd[47usize] = 0usize
    sa_rnd[48usize] = 44usize
    sa_rnd[49usize] = 11usize
    sa_rnd[50usize] = 26usize
    sa_rnd[51usize] = 53usize
    sa_rnd[52usize] = 43usize
    sa_rnd[53usize] = 52usize
    sa_rnd[54usize] = 42usize
    sa_rnd[55usize] = 51usize
    sa_rnd[56usize] = 41usize
    sa_rnd[57usize] = 50usize
    sa_rnd[58usize] = 40usize
    sa_rnd[59usize] = 39usize
    var lcp_rnd: [60]usize = zero
    lcp_rnd[0usize] = 0usize
    lcp_rnd[1usize] = 5usize
    lcp_rnd[2usize] = 8usize
    lcp_rnd[3usize] = 6usize
    lcp_rnd[4usize] = 9usize
    lcp_rnd[5usize] = 3usize
    lcp_rnd[6usize] = 9usize
    lcp_rnd[7usize] = 12usize
    lcp_rnd[8usize] = 10usize
    lcp_rnd[9usize] = 4usize
    lcp_rnd[10usize] = 7usize
    lcp_rnd[11usize] = 5usize
    lcp_rnd[12usize] = 8usize
    lcp_rnd[13usize] = 2usize
    lcp_rnd[14usize] = 8usize
    lcp_rnd[15usize] = 11usize
    lcp_rnd[16usize] = 9usize
    lcp_rnd[17usize] = 6usize
    lcp_rnd[18usize] = 4usize
    lcp_rnd[19usize] = 3usize
    lcp_rnd[20usize] = 6usize
    lcp_rnd[21usize] = 4usize
    lcp_rnd[22usize] = 7usize
    lcp_rnd[23usize] = 1usize
    lcp_rnd[24usize] = 2usize
    lcp_rnd[25usize] = 7usize
    lcp_rnd[26usize] = 10usize
    lcp_rnd[27usize] = 8usize
    lcp_rnd[28usize] = 5usize
    lcp_rnd[29usize] = 12usize
    lcp_rnd[30usize] = 3usize
    lcp_rnd[31usize] = 2usize
    lcp_rnd[32usize] = 5usize
    lcp_rnd[33usize] = 3usize
    lcp_rnd[34usize] = 6usize
    lcp_rnd[35usize] = 0usize
    lcp_rnd[36usize] = 1usize
    lcp_rnd[37usize] = 6usize
    lcp_rnd[38usize] = 9usize
    lcp_rnd[39usize] = 7usize
    lcp_rnd[40usize] = 10usize
    lcp_rnd[41usize] = 4usize
    lcp_rnd[42usize] = 10usize
    lcp_rnd[43usize] = 11usize
    lcp_rnd[44usize] = 3usize
    lcp_rnd[45usize] = 5usize
    lcp_rnd[46usize] = 2usize
    lcp_rnd[47usize] = 3usize
    lcp_rnd[48usize] = 1usize
    lcp_rnd[49usize] = 5usize
    lcp_rnd[50usize] = 4usize
    lcp_rnd[51usize] = 6usize
    lcp_rnd[52usize] = 2usize
    lcp_rnd[53usize] = 5usize
    lcp_rnd[54usize] = 3usize
    lcp_rnd[55usize] = 6usize
    lcp_rnd[56usize] = 4usize
    lcp_rnd[57usize] = 7usize
    lcp_rnd[58usize] = 5usize
    lcp_rnd[59usize] = 6usize
    check_arrays("babaaabaaaabbaaabaaaabaaaabbaabaaabaaaabbbbbbbaaaabbbbbaabab", sa_rnd[..], lcp_rnd[..])
    var sa: [16]usize = zero
    var scratch: [512]usize = zero
    if suffix.array_build("", sa[..0usize], scratch[..]) != ok { os.exit(1i32) }
    if suffix.array_build("banana", sa[..5usize], scratch[..]) != suffix.TooSmall { os.exit(1i32) }
    if suffix.array_build("banana", sa[..], scratch[..10usize]) != suffix.TooSmall { os.exit(1i32) }

    // 2: search.
    if suffix.array_build("banana", sa[..6usize], scratch[..]) != ok { os.exit(2i32) }
    let (lo, hi) = suffix.array_search("banana", sa[..6usize], "ana")
    if lo != 1usize || hi != 3usize || sa[lo] != 3usize || sa[lo + 1usize] != 1usize { os.exit(2i32) }
    let (lo2, hi2) = suffix.array_search("banana", sa[..6usize], "a")
    if lo2 != 0usize || hi2 != 3usize { os.exit(2i32) }
    let (lo3, hi3) = suffix.array_search("banana", sa[..6usize], "nab")
    if lo3 != hi3 { os.exit(2i32) }
    let (lo4, hi4) = suffix.array_search("banana", sa[..6usize], "banana")
    if lo4 != 3usize || hi4 != 4usize { os.exit(2i32) }
    let (lo5, hi5) = suffix.array_search("banana", sa[..6usize], "")
    if lo5 != 0usize || hi5 != 6usize { os.exit(2i32) }
    let (lo6, hi6) = suffix.array_search("banana", sa[..6usize], "bananas")
    if lo6 != hi6 { os.exit(2i32) }

    // 3: the automaton.
    let (m, m_error) = suffix.automaton_build(a, "abracadabra")
    if m_error != ok || m.states > 22usize || suffix.automaton_distinct_substrings(&m) != 54u64 { os.exit(3i32) }
    if !suffix.automaton_contains(&m, "cadab") || !suffix.automaton_contains(&m, "abracadabra") || !suffix.automaton_contains(&m, "") { os.exit(3i32) }
    if suffix.automaton_contains(&m, "abrb") || suffix.automaton_contains(&m, "abracadabrac") || suffix.automaton_contains(&m, "z") { os.exit(3i32) }
    let (m2, m2_error) = suffix.automaton_build(a, "aaaaaaaa")
    if m2_error != ok || m2.states != 9usize || suffix.automaton_distinct_substrings(&m2) != 8u64 { os.exit(3i32) }
    let (m3, m3_error) = suffix.automaton_build(a, "mississippi")
    if m3_error != ok || suffix.automaton_distinct_substrings(&m3) != 53u64 || !suffix.automaton_contains(&m3, "ssissip") || suffix.automaton_contains(&m3, "pp i") { os.exit(3i32) }
    let (m4, m4_error) = suffix.automaton_build(a, "")
    if m4_error != ok || m4.states != 1usize || !suffix.automaton_contains(&m4, "") || suffix.automaton_contains(&m4, "a") { os.exit(3i32) }

    // 4: the tree.
    var lcp: [16]usize = zero
    if suffix.lcp_array("banana", sa[..6usize], lcp[..6usize], scratch[..]) != ok { os.exit(4i32) }
    let (t, t_error) = suffix.tree_build(a, "banana", sa[..6usize], lcp[..6usize])
    if t_error != ok || t.nodes != 10usize { os.exit(4i32) }
    if !suffix.tree_contains(&t, "nan") || !suffix.tree_contains(&t, "banana") || !suffix.tree_contains(&t, "a") || !suffix.tree_contains(&t, "") { os.exit(4i32) }
    if suffix.tree_contains(&t, "nab") || suffix.tree_contains(&t, "bananas") || suffix.tree_contains(&t, "c") { os.exit(4i32) }
    // Every leaf's suffix and depth agree, and every internal node has two or more children.
    var node = 0usize
    var leaves = 0usize
    while node < t.nodes {
        if t.suffix[node] != suffix.NONE {
            leaves += 1usize
            if usize(t.depth[node]) != 6usize - usize(t.suffix[node]) || t.first_child[node] != suffix.NONE { os.exit(4i32) }
        } else {
            var children = 0usize
            var c = t.first_child[node]
            while c != suffix.NONE {
                children += 1usize
                if t.parent[usize(c)] != u32(node) { os.exit(4i32) }
                c = t.next_sibling[usize(c)]
            }
            if children < 2usize { os.exit(4i32) }
        }
        node += 1usize
    }
    if leaves != 6usize { os.exit(4i32) }
    if suffix.array_build("mississippi", sa[..11usize], scratch[..]) != ok || suffix.lcp_array("mississippi", sa[..11usize], lcp[..11usize], scratch[..]) != ok { os.exit(4i32) }
    let (t2, t2_error) = suffix.tree_build(a, "mississippi", sa[..11usize], lcp[..11usize])
    if t2_error != ok || !suffix.tree_contains(&t2, "issip") || suffix.tree_contains(&t2, "issim") { os.exit(4i32) }

    try io.print("text suffix ok\n")
    ret ok
}
