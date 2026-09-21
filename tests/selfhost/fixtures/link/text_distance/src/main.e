// `e.text.distance`: Levenshtein and optimal-string-alignment distances against
// hand-checked pairs, Hamming with its length rule, Jaro and Jaro-Winkler against
// the textbook MARTHA/MARHTA and DWAYNE/DUANE values, the longest common substring
// with its offsets, trigram similarity, and every scratch-size refusal. Each check
// exits with its own code.

use e.io
use e.mem
use e.os
use e.text.distance

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var scratch: [64]usize = zero
    var bytes: [64]u8 = zero
    var words: [64]u32 = zero
    var tiny: [2]usize = zero
    var tiny_bytes: [2]u8 = zero
    var tiny_words: [2]u32 = zero

    // 1: Levenshtein.
    let (kitten, kitten_error) = distance.levenshtein("kitten", "sitting", scratch[..])
    if kitten_error != ok || kitten != 3usize { os.exit(1i32) }
    let (empty, empty_error) = distance.levenshtein("", "abc", scratch[..])
    if empty_error != ok || empty != 3usize { os.exit(1i32) }
    let (flaw, flaw_error) = distance.levenshtein("flaw", "lawn", scratch[..])
    if flaw_error != ok || flaw != 2usize { os.exit(1i32) }
    let (same, same_error) = distance.levenshtein("abc", "abc", scratch[..])
    if same_error != ok || same != 0usize { os.exit(1i32) }
    let (both_empty, both_empty_error) = distance.levenshtein("", "", scratch[..])
    if both_empty_error != ok || both_empty != 0usize { os.exit(1i32) }
    let (_, small_error) = distance.levenshtein("abcd", "efgh", tiny[..])
    if small_error != distance.TooSmall { os.exit(1i32) }

    // 2: transpositions count once under Damerau, twice under Levenshtein.
    let (ca, ca_error) = distance.damerau_levenshtein("ca", "abc", scratch[..])
    if ca_error != ok || ca != 3usize { os.exit(2i32) }
    let (swap, swap_error) = distance.damerau_levenshtein("abcd", "acbd", scratch[..])
    if swap_error != ok || swap != 1usize { os.exit(2i32) }
    let (swap_lev, swap_lev_error) = distance.levenshtein("abcd", "acbd", scratch[..])
    if swap_lev_error != ok || swap_lev != 2usize { os.exit(2i32) }
    let (_, small_dl) = distance.damerau_levenshtein("abcd", "efgh", tiny[..])
    if small_dl != distance.TooSmall { os.exit(2i32) }

    // 3: Hamming.
    let (ham, ham_error) = distance.hamming("karolin", "kathrin")
    if ham_error != ok || ham != 3usize { os.exit(3i32) }
    let (_, ham_mismatch) = distance.hamming("abc", "abcd")
    if ham_mismatch != distance.Mismatch { os.exit(3i32) }

    // 4: Jaro and Jaro-Winkler.
    let (martha, martha_error) = distance.jaro("MARTHA", "MARHTA", bytes[..])
    if martha_error != ok || !near(martha, 0.944444444444f64) { os.exit(4i32) }
    let (martha_w, martha_w_error) = distance.jaro_winkler("MARTHA", "MARHTA", 0.1f64, bytes[..])
    if martha_w_error != ok || !near(martha_w, 0.961111111111f64) { os.exit(4i32) }
    let (dwayne, dwayne_error) = distance.jaro_winkler("DWAYNE", "DUANE", 0.1f64, bytes[..])
    if dwayne_error != ok || !near(dwayne, 0.84f64) { os.exit(4i32) }
    let (none, none_error) = distance.jaro("abc", "xyz", bytes[..])
    if none_error != ok || !near(none, 0.0f64) { os.exit(4i32) }
    let (identical, identical_error) = distance.jaro("same", "same", bytes[..])
    if identical_error != ok || !near(identical, 1.0f64) { os.exit(4i32) }
    let (blank, blank_error) = distance.jaro("", "", bytes[..])
    if blank_error != ok || !near(blank, 1.0f64) { os.exit(4i32) }
    let (_, small_jaro) = distance.jaro("abcd", "efgh", tiny_bytes[..])
    if small_jaro != distance.TooSmall { os.exit(4i32) }

    // 5: the longest common substring and where it sits.
    let (at_a, at_b, run, run_error) = distance.longest_common_substring("xyzabcdefq", "00abcdef11", scratch[..])
    if run_error != ok || run != 6usize || at_a != 3usize || at_b != 2usize { os.exit(5i32) }
    let (_, _, no_run, no_run_error) = distance.longest_common_substring("abc", "xyz", scratch[..])
    if no_run_error != ok || no_run != 0usize { os.exit(5i32) }
    let (_, _, _, small_run) = distance.longest_common_substring("abcd", "efgh", tiny[..])
    if small_run != distance.TooSmall { os.exit(5i32) }

    // 6: trigram Jaccard similarity.
    let (night, night_error) = distance.trigram("night", "nacht", words[..])
    if night_error != ok || !near(night, 0.0f64) { os.exit(6i32) }
    let (whole, whole_error) = distance.trigram("abcde", "abcde", words[..])
    if whole_error != ok || !near(whole, 1.0f64) { os.exit(6i32) }
    let (partial, partial_error) = distance.trigram("abcdef", "xbcdef", words[..])
    if partial_error != ok || !near(partial, 0.6f64) { os.exit(6i32) }
    let (short, short_error) = distance.trigram("ab", "abcdef", words[..])
    if short_error != ok || !near(short, 0.0f64) { os.exit(6i32) }
    let (_, small_tri) = distance.trigram("abcd", "efgh", tiny_words[..])
    if small_tri != distance.TooSmall { os.exit(6i32) }

    try io.print("text distance ok\n")
    ret ok
}
