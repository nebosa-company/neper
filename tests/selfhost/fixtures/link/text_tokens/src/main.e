// `e.text.tokens`: a small tiktoken-format vocabulary is loaded and texts counted
// against merges worked by hand, the cl100k and o200k splits are compared on
// camelCase and contractions, and the vocabulary-free estimate is checked. Each
// check exits with its own code.

use e.mem
use e.os
use e.text.tokens

fn main(a: *mem.Arena, args: []str) -> err {
    // a b c ' ' d 1 2 3 4 ! \n ab bc ' a' abc
    let text = "YQ== 0\nYg== 1\nYw== 2\nIA== 3\nZA== 4\nMQ== 5\nMg== 6\nMw== 7\nNA== 8\nIQ== 9\nCg== 10\nYWI= 11\nYmM= 12\nIGE= 13\nYWJj 14\n"
    let (v, load_error) = tokens.load(a, text)
    if load_error != ok || v.count != 15usize { os.exit(1i32) }
    let (parts, parts_error) = mem.alloc[usize](a, 64usize)
    if parts_error != ok { os.exit(1i32) }

    // 1: whole-piece hits, merges by lowest rank, no merge available.
    let (abc, e1) = tokens.count(&v, .Cl100k, "abc", parts)
    let (abcd, e2) = tokens.count(&v, .Cl100k, "abcd", parts)
    let (abab, e3) = tokens.count(&v, .Cl100k, "abab", parts)
    if e1 != ok || e2 != ok || e3 != ok || abc != 1usize || abcd != 2usize || abab != 2usize { os.exit(1i32) }

    // 2: the split: words with a leading space, digit groups of three, symbols with their newlines.
    let (sp, e4) = tokens.count(&v, .Cl100k, "a b", parts)
    let (dg, e5) = tokens.count(&v, .Cl100k, "12345", parts)
    let (sy, e6) = tokens.count(&v, .Cl100k, "a!\n\n", parts)
    let (ct, e7) = tokens.count(&v, .Cl100k, "don't", parts)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok { os.exit(2i32) }
    if sp != 3usize || dg != 5usize || sy != 4usize || ct != 5usize { os.exit(2i32) }
    if tokens.piece_end(.Cl100k, "12345", 0usize) != 3usize || tokens.piece_end(.Cl100k, "a  b", 1usize) != 2usize { os.exit(2i32) }
    if tokens.piece_end(.Cl100k, "x \n y", 1usize) != 3usize || tokens.piece_end(.Cl100k, "  ", 0usize) != 2usize { os.exit(2i32) }

    // 3: o200k cuts camelCase and takes the contraction into the word.
    if tokens.piece_end(.Cl100k, "camelCase", 0usize) != 9usize || tokens.piece_end(.O200k, "camelCase", 0usize) != 5usize { os.exit(3i32) }
    if tokens.piece_end(.Cl100k, "don't", 0usize) != 3usize || tokens.piece_end(.O200k, "don't", 0usize) != 5usize { os.exit(3i32) }
    if tokens.piece_end(.O200k, "a/\n", 1usize) != 3usize || tokens.piece_end(.Cl100k, "a/\n", 1usize) != 3usize { os.exit(3i32) }
    if tokens.piece_end(.Cl100k, "é1", 0usize) != 2usize { os.exit(3i32) }
    let (o200, o200_error) = tokens.count(&v, .O200k, "abc", parts)
    if o200_error != ok || o200 != 1usize { os.exit(3i32) }

    // 4: a piece longer than the scratch is refused, and the estimate.
    let (small, small_error) = mem.alloc[usize](a, 2usize)
    if small_error != ok { os.exit(4i32) }
    let (big, big_error) = tokens.count(&v, .Cl100k, "abcdabcd", small)
    if big_error == ok || big != 0usize { os.exit(4i32) }
    if tokens.estimate("") != 0usize || tokens.estimate("abcdefghijklmnopqrstuvwxyz012345678") != 10usize { os.exit(4i32) }
    if tokens.estimate("日本語") != 3usize { os.exit(4i32) }
    ret ok
}
