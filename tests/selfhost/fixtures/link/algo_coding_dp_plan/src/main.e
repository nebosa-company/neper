// The planned names of `e.algo.coding` and `e.algo.dp` against a Python
// reference: whole-buffer Elias gamma and Rice codes, the `move_to_front` and
// `bwt` entry points, the adaptive arithmetic coder and rANS on a skewed text
// (byte-exact streams by length and fold), LZ78 dictionary coding through a
// table reset, simple8b words, the convex hull trick and the Li Chao tree
// against a scan over the lines, and both monotonic stacks. Each check exits
// with its own code.

use e.algo.coding
use e.algo.dp
use e.io
use e.mem
use e.os

type Gen = struct { state: u64 }

fn draw(g: *Gen) -> u64 {
    g.state = g.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret g.state >> 33u32
}

fn fold_bytes(data: []const u8) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < data.len {
        h = (h ^ u64(data[i])) *% 1099511628211u64
        i += 1usize
    }
    ret h
}

fn fold_words(data: []const u64) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < data.len {
        h = (h ^ data[i]) *% 1099511628211u64
        i += 1usize
    }
    ret h
}

fn main(a: *mem.Arena, args: []str) -> err {
    var g = Gen { state: 20260922u64 }
    var out: [512]u8 = zero
    var back: [512]u8 = zero

    // 1: whole-buffer Elias gamma and Rice codes.
    var gamma_values: [40]u32 = zero
    var i = 0usize
    while i < 40usize {
        gamma_values[i] = u32(draw(&g) % 50u64) + 1u32
        i += 1usize
    }
    let (gamma_len, gamma_error) = coding.elias_gamma(gamma_values[..], out[..])
    if gamma_error != ok || gamma_len != 44usize || fold_bytes(out[..gamma_len]) != 711822610184882954u64 { os.exit(1i32) }
    var decoded: [40]u32 = zero
    if coding.elias_gamma_decode(out[..gamma_len], decoded[..]) != ok { os.exit(1i32) }
    i = 0usize
    while i < 40usize {
        if decoded[i] != gamma_values[i] { os.exit(1i32) }
        i += 1usize
    }
    if coding.elias_gamma_decode(out[..gamma_len - 1usize], decoded[..]) != coding.Invalid { os.exit(1i32) }
    var rice_values: [40]u32 = zero
    i = 0usize
    while i < 40usize {
        rice_values[i] = u32(draw(&g) % 40u64)
        i += 1usize
    }
    let (rice_len, rice_error) = coding.rice_encode(rice_values[..], 3u32, out[..])
    if rice_error != ok || rice_len != 30usize || fold_bytes(out[..rice_len]) != 3825195183298863089u64 { os.exit(1i32) }
    if coding.rice_decode(out[..rice_len], 3u32, decoded[..]) != ok { os.exit(1i32) }
    i = 0usize
    while i < 40usize {
        if decoded[i] != rice_values[i] { os.exit(1i32) }
        i += 1usize
    }
    let (_, gamma_room) = coding.elias_gamma(gamma_values[..], out[..10usize])
    if gamma_room != coding.TooSmall { os.exit(1i32) }

    // 2: the transform entry points.
    if coding.move_to_front("banana", out[..6usize]) != ok { os.exit(2i32) }
    if out[0usize] != 98u8 || out[1usize] != 98u8 || out[2usize] != 110u8 || out[3usize] != 1u8 || out[5usize] != 1u8 { os.exit(2i32) }
    if coding.move_to_front_decode(out[..6usize], back[..6usize]) != ok || !mem.eq[u8](back[..6usize], "banana") { os.exit(2i32) }
    var rotations: [64]usize = zero
    let (row, bwt_error) = coding.bwt("banana", out[..], rotations[..])
    if bwt_error != ok || row != 3usize || !mem.eq[u8](out[..6usize], "nnbaaa") { os.exit(2i32) }
    if coding.bwt_decode(out[..6usize], row, back[..], rotations[..]) != ok || !mem.eq[u8](back[..6usize], "banana") { os.exit(2i32) }

    // 3: the arithmetic coder on a skewed 400-byte text.
    var text: [400]u8 = zero
    i = 0usize
    while i < 400usize {
        let v = draw(&g) % 100u64
        if v < 70u64 { text[i] = 97u8 + u8(v % 3u64) } else { text[i] = 97u8 + u8(v % 26u64) }
        i += 1usize
    }
    if fold_bytes(text[..]) != 6604648624325911322u64 { os.exit(3i32) }
    let (arith_len, arith_error) = coding.arithmetic_encode(text[..], out[..])
    if arith_error != ok || arith_len != 181usize || fold_bytes(out[..arith_len]) != 793723864162708226u64 { os.exit(3i32) }
    let (arith_back, arith_back_error) = coding.arithmetic_decode(out[..arith_len], back[..])
    if arith_back_error != ok || arith_back != 400usize || !mem.eq[u8](back[..400usize], text[..]) { os.exit(3i32) }
    let (empty_len, empty_error) = coding.arithmetic_encode("", out[..])
    if empty_error != ok || empty_len != 2usize || out[0usize] != 0u8 || out[1usize] != 64u8 { os.exit(3i32) }
    let (empty_back, empty_back_error) = coding.arithmetic_decode(out[..2usize], back[..])
    if empty_back_error != ok || empty_back != 0usize { os.exit(3i32) }
    let (_, arith_room) = coding.arithmetic_encode(text[..], out[..100usize])
    if arith_room != coding.TooSmall { os.exit(3i32) }
    let (_, arith_tight) = coding.arithmetic_decode(out[..arith_len], back[..100usize])
    if arith_tight != coding.TooSmall { os.exit(3i32) }

    // 4: rANS over a static table of the same text.
    var freqs: [256]u32 = zero
    if coding.ans_frequencies(text[..], freqs[..]) != ok || freqs[97usize] != 942u32 || freqs[122usize] != 92u32 { os.exit(4i32) }
    var freq_sum = 0u32
    i = 0usize
    while i < 256usize {
        freq_sum += freqs[i]
        i += 1usize
    }
    if freq_sum != 4096u32 { os.exit(4i32) }
    let (ans_len, ans_error) = coding.ans_encode(text[..], freqs[..], out[..])
    if ans_error != ok || ans_len != 161usize || fold_bytes(out[..ans_len]) != 14586783864795025118u64 { os.exit(4i32) }
    let (ans_back, ans_back_error) = coding.ans_decode(out[..ans_len], freqs[..], back[..])
    if ans_back_error != ok || ans_back != 400usize || !mem.eq[u8](back[..400usize], text[..]) { os.exit(4i32) }
    let (_, ans_cut) = coding.ans_decode(out[..ans_len - 20usize], freqs[..], back[..])
    if ans_cut != coding.Invalid { os.exit(4i32) }
    freqs[97usize] += 1u32
    let (_, ans_bad) = coding.ans_encode(text[..], freqs[..], out[..])
    if ans_bad != coding.Invalid { os.exit(4i32) }
    if coding.ans_frequencies("", freqs[..]) != coding.Invalid { os.exit(4i32) }

    // 5: LZ78 on a short text and through a full table.
    var table: [12288]u32 = zero
    let small = "abracadabra abracadabra abracadabra"
    let (small_len, small_error) = coding.dictionary_encode(small, out[..], table[..])
    if small_error != ok || small_len != 40usize || fold_bytes(out[..small_len]) != 14160070639049435804u64 { os.exit(5i32) }
    let (small_back, small_back_error) = coding.dictionary_decode(out[..small_len], back[..], table[..])
    if small_back_error != ok || small_back != 35usize || !mem.eq[u8](back[..35usize], small) { os.exit(5i32) }
    let (_, small_cut) = coding.dictionary_decode(out[..small_len - 3usize], back[..], table[..])
    if small_cut != coding.Invalid { os.exit(5i32) }
    var big: [8200]u8 = zero
    i = 0usize
    while i < 8200usize {
        big[i] = u8(draw(&g) & 255u64)
        i += 1usize
    }
    if fold_bytes(big[..]) != 12916254288315163991u64 { os.exit(5i32) }
    var big_out: [12000]u8 = zero
    var big_back: [8200]u8 = zero
    let (big_len, big_error) = coding.dictionary_encode(big[..], big_out[..], table[..])
    if big_error != ok || big_len != 10567usize || fold_bytes(big_out[..big_len]) != 4212660901841286547u64 { os.exit(5i32) }
    let (big_back_len, big_back_error) = coding.dictionary_decode(big_out[..big_len], big_back[..], table[..])
    if big_back_error != ok || big_back_len != 8200usize || !mem.eq[u8](big_back[..], big[..]) { os.exit(5i32) }
    let (_, dict_room) = coding.dictionary_encode(big[..], out[..], table[..])
    if dict_room != coding.TooSmall { os.exit(5i32) }

    // 6: simple8b: 300 ones then 200 values of random width.
    var values: [500]u64 = zero
    i = 0usize
    while i < 300usize {
        values[i] = 1u64
        i += 1usize
    }
    while i < 500usize {
        let width = draw(&g) % 61u64
        let wide = (draw(&g) << 29u64) | draw(&g)
        values[i] = wide & ((1u64 << width) - 1u64)
        i += 1usize
    }
    var words: [256]u64 = zero
    let (word_count, words_error) = coding.simple8b_encode(values[..], words[..])
    if words_error != ok || word_count != 164usize || fold_words(words[..word_count]) != 11953035158671785520u64 { os.exit(6i32) }
    if (words[0usize] >> 60u64) != 0u64 || (words[1usize] >> 60u64) != 2u64 { os.exit(6i32) }
    var unpacked: [500]u64 = zero
    let (value_count, unpack_error) = coding.simple8b_decode(words[..word_count], unpacked[..])
    if unpack_error != ok || value_count != 500usize { os.exit(6i32) }
    i = 0usize
    while i < 500usize {
        if unpacked[i] != values[i] { os.exit(6i32) }
        i += 1usize
    }
    let (_, unpack_room) = coding.simple8b_decode(words[..word_count], unpacked[..499usize])
    if unpack_room != coding.TooSmall { os.exit(6i32) }
    values[0usize] = 1u64 << 60u64
    let (_, too_wide) = coding.simple8b_encode(values[..], words[..])
    if too_wide != coding.Invalid { os.exit(6i32) }

    // 7: the convex hull trick against a scan, unsorted and sorted queries.
    var slopes: [30]i64 = zero
    var intercepts: [30]i64 = zero
    i = 0usize
    while i < 30usize {
        slopes[i] = i64(draw(&g) % 101u64) - 50i64
        intercepts[i] = i64(draw(&g) % 2001u64) - 1000i64
        i += 1usize
    }
    slopes[7usize] = slopes[3usize]
    slopes[11usize] = slopes[3usize]
    var queries: [40]i64 = zero
    i = 0usize
    while i < 40usize {
        queries[i] = i64(draw(&g) % 201u64) - 100i64
        i += 1usize
    }
    var hull: [30]dp.Line = zero
    var answers: [40]i64 = zero
    if dp.convex_hull_trick(slopes[..], intercepts[..], queries[..], answers[..], hull[..]) != ok { os.exit(7i32) }
    i = 0usize
    while i < 40usize {
        var least = slopes[0usize] * queries[i] + intercepts[0usize]
        var k = 1usize
        while k < 30usize {
            let v = slopes[k] * queries[i] + intercepts[k]
            if v < least { least = v }
            k += 1usize
        }
        if answers[i] != least { os.exit(7i32) }
        i += 1usize
    }
    var sorted: [40]i64 = zero
    i = 0usize
    while i < 40usize {
        sorted[i] = 0i64 - 100i64 + 5i64 * i64(i)
        i += 1usize
    }
    if dp.convex_hull_trick(slopes[..], intercepts[..], sorted[..], answers[..], hull[..]) != ok { os.exit(7i32) }
    i = 0usize
    while i < 40usize {
        var least = slopes[0usize] * sorted[i] + intercepts[0usize]
        var k = 1usize
        while k < 30usize {
            let v = slopes[k] * sorted[i] + intercepts[k]
            if v < least { least = v }
            k += 1usize
        }
        if answers[i] != least { os.exit(7i32) }
        i += 1usize
    }
    if dp.convex_hull_trick(slopes[..], intercepts[..], sorted[..], answers[..], hull[..20usize]) != dp.TooSmall { os.exit(7i32) }
    if dp.convex_hull_trick(slopes[..0usize], intercepts[..0usize], sorted[..], answers[..], hull[..]) != dp.Invalid { os.exit(7i32) }

    // 8: the Li Chao tree agrees.
    var nodes: [1024]dp.Line = zero
    var filled: [1024]u8 = zero
    if dp.li_chao_tree(slopes[..], intercepts[..], queries[..], answers[..], nodes[..], filled[..]) != ok { os.exit(8i32) }
    i = 0usize
    while i < 40usize {
        var least = slopes[0usize] * queries[i] + intercepts[0usize]
        var k = 1usize
        while k < 30usize {
            let v = slopes[k] * queries[i] + intercepts[k]
            if v < least { least = v }
            k += 1usize
        }
        if answers[i] != least { os.exit(8i32) }
        i += 1usize
    }
    if dp.li_chao_tree(slopes[..], intercepts[..], queries[..], answers[..], nodes[..100usize], filled[..]) != dp.TooSmall { os.exit(8i32) }
    if dp.li_chao_tree(slopes[..], intercepts[..], queries[..0usize], answers[..], nodes[..], filled[..]) != ok { os.exit(8i32) }

    // 9: both monotonic stacks and the next greater element.
    var run: [9]i64 = zero
    run[0usize] = 0i64 - 2i64
    run[1usize] = 1i64
    run[2usize] = 0i64 - 3i64
    run[3usize] = 4i64
    run[4usize] = 0i64 - 1i64
    run[5usize] = 2i64
    run[6usize] = 1i64
    run[7usize] = 0i64 - 5i64
    run[8usize] = 4i64
    var prev: [9]usize = zero
    var after: [9]usize = zero
    var stack: [9]usize = zero
    if dp.monotonic_stack(run[..], prev[..], after[..], stack[..]) != ok { os.exit(9i32) }
    // prev: 9 0 9 2 2 4 4 9 7; next smaller: 2 2 7 4 7 6 7 9 9
    if prev[0usize] != 9usize || prev[1usize] != 0usize || prev[3usize] != 2usize || prev[5usize] != 4usize || prev[8usize] != 7usize { os.exit(9i32) }
    if after[0usize] != 2usize || after[1usize] != 2usize || after[2usize] != 7usize || after[3usize] != 4usize || after[4usize] != 7usize { os.exit(9i32) }
    if after[5usize] != 6usize || after[6usize] != 7usize || after[7usize] != 9usize || after[8usize] != 9usize { os.exit(9i32) }
    if dp.next_greater(run[..], after[..], stack[..]) != ok { os.exit(9i32) }
    // next greater: 1 3 3 9 5 8 8 8 9
    if after[0usize] != 1usize || after[1usize] != 3usize || after[2usize] != 3usize || after[3usize] != 9usize || after[4usize] != 5usize { os.exit(9i32) }
    if after[5usize] != 8usize || after[6usize] != 8usize || after[7usize] != 8usize || after[8usize] != 9usize { os.exit(9i32) }
    if dp.monotonic_stack(run[..], prev[..], after[..5usize], stack[..]) != dp.TooSmall { os.exit(9i32) }

    try io.print("algo coding dp plan ok\n")
    ret ok
}
