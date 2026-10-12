// `e.ui.tree_adapter` (L067): file trees built from host snapshots, compared row by row with
// the independent model in scripts/gen_tree_adapter_test.py: folders first and natural
// order (digits by magnitude, case folded, `README.md` and `readme.md` both kept on a
// case-sensitive host), loading and failed folders with placeholder rows, keys kept across
// a refresh and a rename, probed apart under a hash that collides, selection settling,
// scroll anchoring and a 3,000-entry tree refreshed with moves, deletions and additions.
// The rows are the ones `e.ui.collection.flatten` visits through the adapter's source.
// Each check exits with its own code.

use e.algo.hash as hash
use e.io
use e.mem
use e.os
use e.str
use e.ui.collection
use e.ui.control
use e.ui.tree_adapter as tree
use e.ui.widget

// BEGIN SCENARIOS
fn s1_entries(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "src/lib/y10.e", dir: false, state: .Ready }
    out[1usize] = tree.Entry { path: "README.md", dir: false, state: .Ready }
    out[2usize] = tree.Entry { path: "readme.md", dir: false, state: .Ready }
    out[3usize] = tree.Entry { path: "docs", dir: true, state: .Ready }
    out[4usize] = tree.Entry { path: "src", dir: true, state: .Ready }
    out[5usize] = tree.Entry { path: "src/lib", dir: true, state: .Ready }
    out[6usize] = tree.Entry { path: "src/main.e", dir: false, state: .Ready }
    out[7usize] = tree.Entry { path: "src/lib/x.e", dir: false, state: .Ready }
    out[8usize] = tree.Entry { path: "docs/a10.txt", dir: false, state: .Ready }
    out[9usize] = tree.Entry { path: "docs/a2.txt", dir: false, state: .Ready }
    out[10usize] = tree.Entry { path: "docs/A1.txt", dir: false, state: .Ready }
    out[11usize] = tree.Entry { path: "docs/B.txt", dir: false, state: .Ready }
    out[12usize] = tree.Entry { path: "Zeta", dir: true, state: .Ready }
    out[13usize] = tree.Entry { path: "alpha", dir: true, state: .Ready }
    out[14usize] = tree.Entry { path: "alpha/one", dir: false, state: .Ready }
    out[15usize] = tree.Entry { path: "10.txt", dir: false, state: .Ready }
    out[16usize] = tree.Entry { path: "9.txt", dir: false, state: .Ready }
    out[17usize] = tree.Entry { path: "09.txt", dir: false, state: .Ready }
    out[18usize] = tree.Entry { path: "net", dir: true, state: .Loading }
    out[19usize] = tree.Entry { path: "bad", dir: true, state: .Failed }
    out[20usize] = tree.Entry { path: "src/lib/y2.e", dir: false, state: .Ready }
    out[21usize] = tree.Entry { path: "Zeta/z", dir: false, state: .Ready }
    ret 22usize
}

fn s2_entries(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "core", dir: true, state: .Ready }
    out[1usize] = tree.Entry { path: "core/main.e", dir: false, state: .Ready }
    out[2usize] = tree.Entry { path: "core/lib", dir: true, state: .Ready }
    out[3usize] = tree.Entry { path: "core/lib/x.e", dir: false, state: .Ready }
    out[4usize] = tree.Entry { path: "core/lib/y2.e", dir: false, state: .Ready }
    out[5usize] = tree.Entry { path: "core/lib/y10.e", dir: false, state: .Ready }
    out[6usize] = tree.Entry { path: "core/added.e", dir: false, state: .Ready }
    out[7usize] = tree.Entry { path: "README.md", dir: false, state: .Ready }
    out[8usize] = tree.Entry { path: "readme.md", dir: false, state: .Ready }
    out[9usize] = tree.Entry { path: "docs", dir: true, state: .Ready }
    out[10usize] = tree.Entry { path: "docs/a10.txt", dir: false, state: .Ready }
    out[11usize] = tree.Entry { path: "docs/a2.txt", dir: false, state: .Ready }
    out[12usize] = tree.Entry { path: "docs/A1.txt", dir: false, state: .Ready }
    out[13usize] = tree.Entry { path: "docs/new.txt", dir: false, state: .Ready }
    out[14usize] = tree.Entry { path: "Zeta", dir: true, state: .Ready }
    out[15usize] = tree.Entry { path: "alpha", dir: true, state: .Ready }
    out[16usize] = tree.Entry { path: "alpha/one", dir: false, state: .Ready }
    out[17usize] = tree.Entry { path: "10.txt", dir: false, state: .Ready }
    out[18usize] = tree.Entry { path: "9.txt", dir: false, state: .Ready }
    out[19usize] = tree.Entry { path: "09.txt", dir: false, state: .Ready }
    out[20usize] = tree.Entry { path: "net", dir: true, state: .Ready }
    out[21usize] = tree.Entry { path: "net/a.c", dir: false, state: .Ready }
    out[22usize] = tree.Entry { path: "bad", dir: true, state: .Ready }
    ret 23usize
}

fn s4_a(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "aaa", dir: false, state: .Ready }
    out[1usize] = tree.Entry { path: "bbb", dir: false, state: .Ready }
    out[2usize] = tree.Entry { path: "ccc", dir: false, state: .Ready }
    out[3usize] = tree.Entry { path: "dd", dir: true, state: .Ready }
    out[4usize] = tree.Entry { path: "dd/ee", dir: false, state: .Ready }
    out[5usize] = tree.Entry { path: "ff", dir: true, state: .Ready }
    ret 6usize
}

fn s4_b(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "ccc", dir: false, state: .Ready }
    out[1usize] = tree.Entry { path: "0zz", dir: false, state: .Ready }
    out[2usize] = tree.Entry { path: "bbb", dir: false, state: .Ready }
    out[3usize] = tree.Entry { path: "ff", dir: true, state: .Ready }
    out[4usize] = tree.Entry { path: "dd/ee", dir: false, state: .Ready }
    out[5usize] = tree.Entry { path: "dd", dir: true, state: .Ready }
    out[6usize] = tree.Entry { path: "aaa", dir: false, state: .Ready }
    out[7usize] = tree.Entry { path: "zzz", dir: false, state: .Ready }
    ret 8usize
}

fn s5_ci(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "docs", dir: true, state: .Ready }
    out[1usize] = tree.Entry { path: "Docs/x", dir: false, state: .Ready }
    ret 2usize
}

fn s5_dup(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "A.txt", dir: false, state: .Ready }
    out[1usize] = tree.Entry { path: "a.txt", dir: false, state: .Ready }
    ret 2usize
}

fn s5_missing(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "a/b", dir: false, state: .Ready }
    ret 1usize
}

fn s5_file_parent(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "a", dir: false, state: .Ready }
    out[1usize] = tree.Entry { path: "a/b", dir: false, state: .Ready }
    ret 2usize
}

fn s5_slash(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "a/", dir: true, state: .Ready }
    ret 1usize
}

fn want_s1() -> str { ret "9999721509958787115 0 D alpha\n14493644119259475408 1 F alpha/one\n16077166718034104 0 D bad\n957230293188580215 1 X bad/<0>X\n15872934032157515122 0 D docs\n13296852565415725759 1 F docs/A1.txt\n9421458824884438006 1 F docs/a2.txt\n12695382910175263981 1 F docs/a10.txt\n13981786419732474201 1 F docs/B.txt\n2393894207391642136 0 D net\n9916722228893162250 1 L net/<0>L\n9392701334512935369 0 D src\n13075554141897544817 1 D src/lib\n10205097901533516647 2 F src/lib/x.e\n16347819896946239480 2 F src/lib/y2.e\n18375542980445829061 2 F src/lib/y10.e\n15084272675615019070 1 F src/main.e\n5284907561566476671 0 D Zeta\n15724328232987086974 1 F Zeta/z\n15634849298518456642 0 F 9.txt\n10205097306761822468 0 F 09.txt\n11764753276866424690 0 F 10.txt\n4545767476213472610 0 F README.md\n6000149457080575714 0 F readme.md\n" }

fn want_s2() -> str { ret "9999721509958787115 0 D alpha\n14493644119259475408 1 F alpha/one\n16077166718034104 0 D bad\n9392701334512935369 0 D core\n13075554141897544817 1 D core/lib\n10205097901533516647 2 F core/lib/x.e\n16347819896946239480 2 F core/lib/y2.e\n18375542980445829061 2 F core/lib/y10.e\n9457678746552340938 1 F core/added.e\n15084272675615019070 1 F core/main.e\n15872934032157515122 0 D docs\n13296852565415725759 1 F docs/A1.txt\n9421458824884438006 1 F docs/a2.txt\n12695382910175263981 1 F docs/a10.txt\n18177004415324657345 1 F docs/new.txt\n2393894207391642136 0 D net\n17761202818146392463 1 F net/a.c\n5284907561566476671 0 D Zeta\n15634849298518456642 0 F 9.txt\n10205097306761822468 0 F 09.txt\n11764753276866424690 0 F 10.txt\n4545767476213472610 0 F README.md\n6000149457080575714 0 F readme.md\n" }

fn want_s4a() -> str { ret "2 0 D dd\n6 1 F dd/ee\n7 0 D ff\n3 0 F aaa\n4 0 F bbb\n5 0 F ccc\n" }

fn want_s4b() -> str { ret "2 0 D dd\n6 1 F dd/ee\n7 0 D ff\n8 0 F 0zz\n3 0 F aaa\n4 0 F bbb\n5 0 F ccc\n9 0 F zzz\n" }

fn want_s5ci() -> str { ret "15872934032157515122 0 D docs\n1860984269363869389 1 F Docs/x\n" }

fn want_settle_docs() -> str { ret "docs/new.txt" }

fn want_settle_gone() -> str { ret "net" }

fn want_l1_digest() -> u64 { ret 18123449198668046902u64 }

fn want_l2_digest() -> u64 { ret 4563485671179642676u64 }

fn want_l_new() -> u64 { ret 18004563948631520837u64 }

fn want_l1_rows() -> usize { ret 3070usize }

fn want_l2_rows() -> usize { ret 3038usize }

fn want_l_stable() -> usize { ret 2934usize }

fn want_rows1() -> usize { ret 24usize }

fn want_rows2() -> usize { ret 23usize }

fn want_anchor(i: usize) -> f32 {
    if i == 0usize { ret 0.0 }
    if i == 1usize { ret 227.0 }
    if i == 2usize { ret 83.0 }
    if i == 3usize { ret 360.0 }
    ret -1.0
}
// END SCENARIOS

fn weak_hash(s: str) -> u64 { ret u64(s.len) }

fn storage(a: *mem.Arena, n: usize, path_bytes: usize) -> (tree.Storage, err) {
    let (nodes, e1) = mem.alloc[tree.Node](a, n)
    if e1 != ok { ret (zero, e1) }
    let (kids, e2) = mem.alloc[u32](a, n)
    if e2 != ok { ret (zero, e2) }
    let (paths, e3) = mem.alloc[u8](a, path_bytes)
    if e3 != ok { ret (zero, e3) }
    let (slots, e4) = mem.alloc[u32](a, n * 2usize + 1usize)
    if e4 != ok { ret (zero, e4) }
    let (by_path, e5) = mem.alloc[u32](a, n)
    if e5 != ok { ret (zero, e5) }
    let (order, e6) = mem.alloc[u32](a, n)
    if e6 != ok { ret (zero, e6) }
    let (scratch, e7) = mem.alloc[u8](a, 256usize)
    if e7 != ok { ret (zero, e7) }
    ret (tree.Storage { nodes: nodes, kids: kids, paths: paths, slots: slots, by_path: by_path, order: order, scratch: scratch }, ok)
}

fn kind_letter(k: tree.NodeKind) -> str {
    if k == .Folder { ret "D" }
    if k == .File { ret "F" }
    if k == .Loading { ret "L" }
    ret "X"
}

// The visible rows of `t` with every folder open, as the model prints them.
fn render(open: []widget.Key, rows: []collection.TreeRow, b: *str.Builder, t: *const tree.Tree) -> err {
    var theme: control.Theme = zero
    var bridge = tree.Bridge { tree: t, theme: &theme }
    var opened = 0usize
    var i = 0usize
    while i < t.count {
        if t.nodes[i].kind == .Folder {
            open[opened] = t.nodes[i].key
            opened += 1usize
        }
        i += 1usize
    }
    let shown = tree.visible(&bridge, open[0usize..opened], rows)
    var r = 0usize
    while r < shown {
        let (at, found) = tree.find(t, rows[r].key)
        if !found { ret tree.Invalid }
        try str.push_u64(b, rows[r].key)
        try str.push(b, " ")
        try str.push_u64(b, u64(rows[r].depth))
        try str.push(b, " ")
        try str.push(b, kind_letter(t.nodes[at].kind))
        try str.push(b, " ")
        let p = tree.path_of(t, at)
        var k = 0usize
        while k < p.len {
            if p[k] == 0u8 {
                try str.push(b, "<0>")
            } else if p[k] == 1u8 {
                try str.push(b, "L")
            } else if p[k] == 2u8 {
                try str.push(b, "X")
            } else {
                try str.push(b, p[k..k + 1usize])
            }
            k += 1usize
        }
        try str.push(b, "\n")
        r += 1usize
    }
    ret ok
}

fn rendered(a: *mem.Arena, t: *const tree.Tree) -> (str, err) {
    let (open, open_error) = mem.alloc[widget.Key](a, t.count + 1usize)
    if open_error != ok { ret ("", open_error) }
    let (rows, rows_error) = mem.alloc[collection.TreeRow](a, t.count + 1usize)
    if rows_error != ok { ret ("", rows_error) }
    let (b, b_error) = str.builder(a, 4096usize)
    if b_error != ok { ret ("", b_error) }
    var bb = b
    let e = render(open, rows, &bb, t)
    if e != ok { ret ("", e) }
    ret (str.done(&bb), ok)
}

fn key_by_path(t: *const tree.Tree, p: str) -> (u64, bool) {
    let (at, found) = tree.find_path(t, p)
    if !found { ret (0u64, false) }
    ret (t.nodes[usize(at)].key, true)
}

fn same(x: str, y: str) -> bool { ret str.eq(x, y) }

fn path_for(t: *const tree.Tree, key: u64) -> str {
    let (at, found) = tree.find(t, key)
    if !found { ret "" }
    ret tree.path_of(t, at)
}

// The generated large snapshot, in the model's order (reversed unless `forward`).
fn large_path(a: *mem.Arena, base: str, file: u32) -> (str, err) {
    let (b, b_error) = str.builder(a, 32usize)
    if b_error != ok { ret ("", b_error) }
    var bb = b
    try str.push(&bb, base)
    if file % 7u32 != 0u32 {
        try str.push(&bb, "/f")
        try str.push_u32(&bb, file)
        try str.push(&bb, ".c")
    } else {
        try str.push(&bb, "/F")
        try str.push_u32(&bb, file)
        try str.push(&bb, ".h")
    }
    ret (str.done(&bb), ok)
}

fn named(a: *mem.Arena, prefix: str, n: u32, suffix: str) -> (str, err) {
    let (b, b_error) = str.builder(a, 32usize)
    if b_error != ok { ret ("", b_error) }
    var bb = b
    try str.push(&bb, prefix)
    try str.push_u32(&bb, n)
    try str.push(&bb, suffix)
    ret (str.done(&bb), ok)
}

fn deleted(d: u32, k: u32) -> bool {
    if d == 2u32 && k % 3u32 == 0u32 { ret true }
    ret d == 11u32 && k == 5u32
}

fn fill_large(a: *mem.Arena, out: []tree.Entry, second: bool, forward: bool) -> (usize, err) {
    var n = 0usize
    var d = 0u32
    while d < 30u32 {
        var base: str = ""
        let (made, made_error) = named(a, "pkg", d, "")
        if made_error != ok { ret (0usize, made_error) }
        base = made
        if second && d == 3u32 { base = "mod3" }
        out[n] = tree.Entry { path: base, dir: true, state: .Ready }
        n += 1usize
        var k = 0u32
        while k < 100u32 {
            if !(second && deleted(d, k)) {
                let (p, p_error) = large_path(a, base, k)
                if p_error != ok { ret (0usize, p_error) }
                out[n] = tree.Entry { path: p, dir: false, state: .Ready }
                n += 1usize
            }
            k += 1u32
        }
        if second {
            var which = 0u32
            while which < 3u32 {
                var add_d = 7u32
                var add_k = 1u32
                if which == 1u32 { add_k = 2u32 }
                if which == 2u32 {
                    add_d = 19u32
                    add_k = 0u32
                }
                if add_d == d {
                    // `base/new<k>.c`: the base then the file name.
                    let (q, q_error) = named(a, "/new", add_k, ".c")
                    if q_error != ok { ret (0usize, q_error) }
                    let (b2, b2_error) = str.builder(a, 32usize)
                    if b2_error != ok { ret (0usize, b2_error) }
                    var bb = b2
                    try str.push(&bb, base)
                    try str.push(&bb, q)
                    out[n] = tree.Entry { path: str.done(&bb), dir: false, state: .Ready }
                    n += 1usize
                }
                which += 1u32
            }
        }
        d += 1u32
    }
    var t = 0u32
    while t < 40u32 {
        let (p, p_error) = named(a, "top", t, ".txt")
        if p_error != ok { ret (0usize, p_error) }
        out[n] = tree.Entry { path: p, dir: false, state: .Ready }
        n += 1usize
        t += 1u32
    }
    if !forward {
        var lo = 0usize
        var hi = n - 1usize
        while lo < hi {
            let tmp = out[lo]
            out[lo] = out[hi]
            out[hi] = tmp
            lo += 1usize
            hi -= 1usize
        }
    }
    ret (n, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var cs = tree.policy(true)
    var raw: [64]tree.Entry = zero

    // S1 and S2: a case-sensitive host snapshot, then its refresh with a rename.
    let (st1, st1_error) = storage(a, 64usize, 2048usize)
    let (st2, st2_error) = storage(a, 64usize, 2048usize)
    let (st3, st3_error) = storage(a, 64usize, 2048usize)
    if st1_error != ok || st2_error != ok || st3_error != ok { os.exit(1) }
    let n1 = s1_entries(raw[0..])
    var none: tree.Tree = zero
    let (t1, t1_error) = tree.build(raw[0usize..n1], zero, &none, cs, st1)
    if t1_error != ok { os.exit(2) }
    let (got1, got1_error) = rendered(a, &t1)
    if got1_error != ok { os.exit(3) }
    if !same(got1, want_s1()) {
        try io.print(got1)
        os.exit(10)
    }
    var distinct = true
    var i = 0usize
    while i < t1.count {
        let (at, found) = tree.find(&t1, t1.nodes[i].key)
        if !found || at != i { distinct = false }
        i += 1usize
    }
    if !distinct || t1.count != 22usize + 2usize { os.exit(11) }

    var raw2: [64]tree.Entry = zero
    let n2 = s2_entries(raw2[0..])
    var moves: [1]tree.Rename = zero
    moves[0usize] = tree.Rename { from: "src", to: "core" }
    let (t2, t2_error) = tree.build(raw2[0usize..n2], moves[0..], &t1, cs, st2)
    if t2_error != ok { os.exit(4) }
    let (got2, got2_error) = rendered(a, &t2)
    if got2_error != ok { os.exit(5) }
    if !same(got2, want_s2()) {
        try io.print(got2)
        os.exit(12)
    }
    // Keys survive: unchanged paths, and the renamed folder and its contents.
    let (k_a, ok_a) = key_by_path(&t1, "src/main.e")
    let (k_b, ok_b) = key_by_path(&t2, "core/main.e")
    let (k_c, ok_c) = key_by_path(&t1, "src/lib")
    let (k_d, ok_d) = key_by_path(&t2, "core/lib")
    let (k_e, ok_e) = key_by_path(&t1, "docs/a10.txt")
    let (k_f, ok_f) = key_by_path(&t2, "docs/a10.txt")
    if !ok_a || !ok_b || !ok_c || !ok_d || !ok_e || !ok_f { os.exit(13) }
    if k_a != k_b || k_c != k_d || k_e != k_f { os.exit(14) }
    let (k_g, ok_g) = key_by_path(&t2, "core/added.e")
    if !ok_g || k_g == k_a { os.exit(15) }

    // Retained keys: an expansion list keeps folders that exist (src survives as core).
    var keep: [4]u64 = zero
    let (src_key, _) = key_by_path(&t1, "src")
    let (docs_key, _) = key_by_path(&t1, "docs")
    let (file_key, _) = key_by_path(&t1, "README.md")
    keep[0usize] = src_key
    keep[1usize] = file_key
    keep[2usize] = docs_key
    keep[3usize] = 1234567u64
    if tree.retain(&t2, keep[0..], 4usize, true) != 2usize || keep[0usize] != src_key || keep[1usize] != docs_key { os.exit(16) }

    // Selection settling: docs/B.txt is gone, its slot (index 3) now holds docs/new.txt;
    // with all of docs gone the selection falls to the root sibling at docs' position.
    let (sel_key, _) = key_by_path(&t1, "docs/B.txt")
    let settled = tree.settle(&t1, &t2, sel_key)
    if !same(path_for(&t2, settled), want_settle_docs()) { os.exit(17) }
    var raw3: [64]tree.Entry = zero
    var n3 = 0usize
    var j = 0usize
    while j < n2 {
        if !str.starts_with(raw2[j].path, "docs") {
            raw3[n3] = raw2[j]
            n3 += 1usize
        }
        j += 1usize
    }
    let (t3, t3_error) = tree.build(raw3[0usize..n3], zero, &t2, cs, st3)
    if t3_error != ok { os.exit(6) }
    let (a2_key, _) = key_by_path(&t2, "docs/a2.txt")
    let gone = tree.settle(&t2, &t3, a2_key)
    if !same(path_for(&t3, gone), want_settle_gone()) { os.exit(18) }
    if tree.settle(&t2, &t3, 99u64) != 0u64 { os.exit(19) }
    if tree.settle(&t1, &t2, k_e) != k_e { os.exit(20) }

    // Scroll anchor over S1 -> S2 with every folder open: rows are 20 high, the viewport 100.
    var theme: control.Theme = zero
    var br1 = tree.Bridge { tree: &t1, theme: &theme }
    var br2 = tree.Bridge { tree: &t2, theme: &theme }
    let (open1, open1_error) = mem.alloc[u64](a, 64usize)
    let (open2, open2_error) = mem.alloc[u64](a, 64usize)
    let (rows1, rows1_error) = mem.alloc[collection.TreeRow](a, 64usize)
    let (rows2, rows2_error) = mem.alloc[collection.TreeRow](a, 64usize)
    if open1_error != ok || open2_error != ok || rows1_error != ok || rows2_error != ok { os.exit(7) }
    var c1 = 0usize
    i = 0usize
    while i < t1.count {
        if t1.nodes[i].kind == .Folder {
            open1[c1] = t1.nodes[i].key
            c1 += 1usize
        }
        i += 1usize
    }
    var c2 = 0usize
    i = 0usize
    while i < t2.count {
        if t2.nodes[i].kind == .Folder {
            open2[c2] = t2.nodes[i].key
            c2 += 1usize
        }
        i += 1usize
    }
    let shown1 = tree.visible(&br1, open1[0usize..c1], rows1)
    let shown2 = tree.visible(&br2, open2[0usize..c2], rows2)
    if shown1 != want_rows1() || shown2 != want_rows2() { os.exit(21) }
    var offsets: [4]f32 = zero
    offsets[0usize] = 0.0
    offsets[1usize] = 107.0
    offsets[2usize] = 243.0
    offsets[3usize] = 600.0
    var at_offset = 0usize
    while at_offset < 4usize {
        let moved = tree.anchor_offset(rows1[0usize..shown1], rows2[0usize..shown2], offsets[at_offset], 20.0, 100.0)
        if moved != want_anchor(at_offset) { os.exit(22 + i32(at_offset)) }
        at_offset += 1usize
    }

    // Collisions: a hash that is the path's length puts every three-letter name on one key.
    var weak = tree.policy(true)
    weak.hash = weak_hash
    let (sa, sa_error) = storage(a, 16usize, 256usize)
    let (sb, sb_error) = storage(a, 16usize, 256usize)
    if sa_error != ok || sb_error != ok { os.exit(8) }
    var raw_a: [16]tree.Entry = zero
    var raw_b: [16]tree.Entry = zero
    let na = s4_a(raw_a[0..])
    let nb = s4_b(raw_b[0..])
    let (ca, ca_error) = tree.build(raw_a[0usize..na], zero, &none, weak, sa)
    if ca_error != ok { os.exit(9) }
    let (got_a, got_a_error) = rendered(a, &ca)
    if got_a_error != ok || !same(got_a, want_s4a()) {
        try io.print(got_a)
        os.exit(26)
    }
    let (cb, cb_error) = tree.build(raw_b[0usize..nb], zero, &ca, weak, sb)
    if cb_error != ok { os.exit(27) }
    let (got_b, got_b_error) = rendered(a, &cb)
    if got_b_error != ok || !same(got_b, want_s4b()) {
        try io.print(got_b)
        os.exit(28)
    }
    let (key_a, _) = key_by_path(&ca, "aaa")
    let (key_b, _) = key_by_path(&cb, "aaa")
    let (key_c, _) = key_by_path(&ca, "ccc")
    let (key_d, _) = key_by_path(&cb, "ccc")
    if key_a != key_b || key_c != key_d || key_a == key_c { os.exit(29) }

    // Path identity: folded on a case-insensitive host, exact on a case-sensitive one.
    var ci = tree.policy(false)
    let (si, si_error) = storage(a, 16usize, 256usize)
    if si_error != ok { os.exit(30) }
    var raw_i: [16]tree.Entry = zero
    let ni = s5_ci(raw_i[0..])
    let (cit, cit_error) = tree.build(raw_i[0usize..ni], zero, &none, ci, si)
    if cit_error != ok { os.exit(31) }
    let (got_i, got_i_error) = rendered(a, &cit)
    if got_i_error != ok || !same(got_i, want_s5ci()) {
        try io.print(got_i)
        os.exit(32)
    }
    let (_, strict_error) = tree.build(raw_i[0usize..ni], zero, &none, cs, si)
    if strict_error != tree.MissingParent { os.exit(33) }
    var raw_d: [4]tree.Entry = zero
    let nd = s5_dup(raw_d[0..])
    let (_, dup_ci) = tree.build(raw_d[0usize..nd], zero, &none, ci, si)
    if dup_ci != tree.Duplicate { os.exit(34) }
    let (both, dup_cs) = tree.build(raw_d[0usize..nd], zero, &none, cs, si)
    if dup_cs != ok || both.count != 2usize { os.exit(35) }
    var raw_m: [4]tree.Entry = zero
    let nm = s5_missing(raw_m[0..])
    let (_, missing) = tree.build(raw_m[0usize..nm], zero, &none, cs, si)
    if missing != tree.MissingParent { os.exit(36) }
    let nf = s5_file_parent(raw_m[0..])
    let (_, file_parent) = tree.build(raw_m[0usize..nf], zero, &none, cs, si)
    if file_parent != tree.NotDirectory { os.exit(37) }
    let nsl = s5_slash(raw_m[0..])
    let (_, slashed) = tree.build(raw_m[0usize..nsl], zero, &none, cs, si)
    if slashed != tree.Invalid { os.exit(38) }
    let (small, small_error) = storage(a, 1usize, 256usize)
    if small_error != ok { os.exit(39) }
    let (_, too_small) = tree.build(raw_d[0usize..nd], zero, &none, cs, small)
    if too_small != tree.TooLarge { os.exit(40) }

    // A large tree: 30 folders of 100 files and 40 top-level files, listed in reverse,
    // then refreshed with a rename, 35 deletions and 3 additions.
    let big = 3200usize
    let (lg1, lg1_error) = storage(a, big, 65536usize)
    let (lg2, lg2_error) = storage(a, big, 65536usize)
    let (lg3, lg3_error) = storage(a, big, 65536usize)
    if lg1_error != ok || lg2_error != ok || lg3_error != ok { os.exit(41) }
    let (list1, list1_error) = mem.alloc[tree.Entry](a, big)
    let (list2, list2_error) = mem.alloc[tree.Entry](a, big)
    let (list3, list3_error) = mem.alloc[tree.Entry](a, big)
    if list1_error != ok || list2_error != ok || list3_error != ok { os.exit(42) }
    let (m1, m1_error) = fill_large(a, list1, false, false)
    if m1_error != ok { os.exit(43) }
    let (lt1, lt1_error) = tree.build(list1[0usize..m1], zero, &none, cs, lg1)
    if lt1_error != ok { os.exit(44) }
    let (txt1, txt1_error) = rendered(a, &lt1)
    if txt1_error != ok || hash.fnv1a64(txt1) != want_l1_digest() || lt1.count != want_l1_rows() { os.exit(45) }
    // The same snapshot listed forward lands on the same keys: order of listing is not identity.
    let (m3, m3_error) = fill_large(a, list3, false, true)
    if m3_error != ok { os.exit(46) }
    let (lt3, lt3_error) = tree.build(list3[0usize..m3], zero, &none, cs, lg3)
    if lt3_error != ok { os.exit(47) }
    let (txt3, txt3_error) = rendered(a, &lt3)
    if txt3_error != ok || hash.fnv1a64(txt3) != want_l1_digest() { os.exit(48) }
    let (m2, m2_error) = fill_large(a, list2, true, false)
    if m2_error != ok { os.exit(49) }
    var big_moves: [1]tree.Rename = zero
    big_moves[0usize] = tree.Rename { from: "pkg3", to: "mod3" }
    let (lt2, lt2_error) = tree.build(list2[0usize..m2], big_moves[0..], &lt1, cs, lg2)
    if lt2_error != ok { os.exit(50) }
    let (txt2, txt2_error) = rendered(a, &lt2)
    if txt2_error != ok || hash.fnv1a64(txt2) != want_l2_digest() || lt2.count != want_l2_rows() { os.exit(51) }
    // Keys of every path present in both are equal; the renamed folder's too.
    var stable = 0usize
    i = 0usize
    while i < lt1.count {
        let (found_at, found) = tree.find_path(&lt2, tree.path_of(&lt1, i))
        if found && lt2.nodes[usize(found_at)].key == lt1.nodes[i].key { stable += 1usize }
        i += 1usize
    }
    if stable != want_l_stable() { os.exit(52) }
    let (m_old, m_old_ok) = key_by_path(&lt1, "pkg3/f5.c")
    let (m_new, m_new_ok) = key_by_path(&lt2, "mod3/f5.c")
    if !m_old_ok || !m_new_ok || m_old != m_new { os.exit(53) }
    let (new_key, new_ok) = key_by_path(&lt2, "pkg7/new1.c")
    if !new_ok || new_key != want_l_new() { os.exit(54) }

    try io.print("ui tree adapter ok\n")
    ret ok
}
