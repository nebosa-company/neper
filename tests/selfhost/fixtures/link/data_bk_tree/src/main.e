// `e.data.bk_tree` over words under the Levenshtein distance: every word
// within one edit of a query is found (and nothing farther), the empty
// tree and a full pool answer, and a too-short stack is reported. Each
// check exits with its own code.

use e.data.bk_tree
use e.io
use e.mem
use e.os
use e.text.distance

type Hits = struct { count: usize, scratch: []usize, found: []str }

fn edits(h: *Hits, a: str, b: str) -> u32 {
    let (d, _) = distance.levenshtein(a, b, h.scratch)
    ret u32(d)
}

fn wide_distance(h: *Hits, a: u32, b: u32) -> u32 {
    if a >= b { ret a - b }
    ret b - a
}

fn note(h: *Hits, item: str, d: u32) {
    if h.count < h.found.len { h.found[h.count] = item }
    h.count += 1usize
}

fn note_wide(h: *Hits, item: u32, d: u32) { h.count += 1usize }

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var items: [16]str = zero
    var first: [16]u32 = zero
    var sibling: [16]u32 = zero
    var edge: [16]u32 = zero
    var t = bk_tree.bk_tree[str](items[..], first[..], sibling[..], edge[..])
    var scratch: [64]usize = zero
    var found: [16]str = zero
    var hits = Hits { count: 0usize, scratch: scratch[..], found: found[..] }
    var stack: [16]u32 = zero

    // 1: the empty tree finds nothing.
    let (none, none_error) = bk_tree.search[str, Hits](&t, "book", 1u32, &hits, edits, note, stack[..])
    if none_error != ok || none != 0usize { os.exit(1i32) }

    // 2: a dictionary and queries within one edit.
    var words: [10]str = zero
    words[0usize] = "book"
    words[1usize] = "books"
    words[2usize] = "cake"
    words[3usize] = "boo"
    words[4usize] = "cape"
    words[5usize] = "cart"
    words[6usize] = "boon"
    words[7usize] = "cook"
    words[8usize] = "cook"
    words[9usize] = "what"
    var i = 0usize
    while i < 10usize {
        if bk_tree.insert[str, Hits](&t, words[i], &hits, edits) != ok { os.exit(2i32) }
        i += 1usize
    }
    hits.count = 0usize
    let (near_book, book_error) = bk_tree.search[str, Hits](&t, "book", 1u32, &hits, edits, note, stack[..])
    // book, books, boo, boon, cook, cook.
    if book_error != ok || near_book != 6usize { os.exit(2i32) }
    i = 0usize
    while i < 6usize {
        let (d, _) = distance.levenshtein(found[i], "book", scratch[..])
        if d > 1usize { os.exit(2i32) }
        i += 1usize
    }
    hits.count = 0usize
    let (near_cape, cape_error) = bk_tree.search[str, Hits](&t, "cape", 1u32, &hits, edits, note, stack[..])
    if cape_error != ok || near_cape != 2usize { os.exit(2i32) }
    hits.count = 0usize
    let (exact, exact_error) = bk_tree.search[str, Hits](&t, "what", 0u32, &hits, edits, note, stack[..])
    if exact_error != ok || exact != 1usize || !same(found[0usize], "what") { os.exit(2i32) }
    hits.count = 0usize
    let (far, far_error) = bk_tree.search[str, Hits](&t, "zzzz", 2u32, &hits, edits, note, stack[..])
    if far_error != ok || far != 0usize { os.exit(2i32) }
    hits.count = 0usize
    let (everything, all_error) = bk_tree.search[str, Hits](&t, "book", 10u32, &hits, edits, note, stack[..])
    if all_error != ok || everything != 10usize { os.exit(2i32) }

    // 3: a full pool and a short stack.
    i = 0usize
    var full = ok
    while i < 10usize && full == ok {
        full = bk_tree.insert[str, Hits](&t, "more", &hits, edits)
        i += 1usize
    }
    if full != bk_tree.TooSmall || t.used != 16usize { os.exit(3i32) }
    hits.count = 0usize
    let (_, stack_room) = bk_tree.search[str, Hits](&t, "book", 10u32, &hits, edits, note, stack[..2usize])
    if stack_room != bk_tree.TooSmall { os.exit(3i32) }

    // 4: the admissible child interval uses a subtraction-safe distance at
    // the end of the u32 metric domain.
    var wide_items: [2]u32 = zero
    var wide_first: [2]u32 = zero
    var wide_sibling: [2]u32 = zero
    var wide_edge: [2]u32 = zero
    var wide = bk_tree.bk_tree[u32](wide_items[..], wide_first[..], wide_sibling[..], wide_edge[..])
    if bk_tree.insert[u32, Hits](&wide, 0u32, &hits, wide_distance) != ok { os.exit(4i32) }
    if bk_tree.insert[u32, Hits](&wide, 4294967295u32, &hits, wide_distance) != ok { os.exit(4i32) }
    hits.count = 0usize
    let (wide_hits, wide_error) = bk_tree.search[u32, Hits](&wide, 4294967295u32, 4294967295u32, &hits, wide_distance, note_wide, stack[..])
    if wide_error != ok || wide_hits != 2usize || hits.count != 2usize { os.exit(4i32) }

    try io.print("data bk tree ok\n")
    ret ok
}
