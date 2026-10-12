// `e.ui.tree_adapter` (L067, D3305): sibling order beyond ASCII and lazily loaded folders.
// Part one lists one folder of names (accents, composed and decomposed, German, Greek and
// Cyrillic case pairs, digit runs) in the order of `policy_unicode` and in the order of the
// ASCII `policy`, each against the model in scripts/gen_tree_adapter_unicode_test.py (Python's
// unicodedata NFD and lower, its own natural comparison). Part two walks a folder through
// the lazy-loading flow: `Unloaded` (an expander, no placeholder, named by `pending`), then
// `Loading` (a placeholder), then `Ready` with children of its own, keys kept through
// `prev`; and the refusal of an `Unloaded` folder's children being listed twice. Each check
// exits with its own code.

use e.io
use e.mem
use e.os
use e.str
use e.ui.collection
use e.ui.control
use e.ui.tree_adapter as tree
use e.ui.widget

// BEGIN SCENARIOS
fn names(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "apple", dir: false, state: .Ready }
    out[1usize] = tree.Entry { path: "\xc3\x84pfel", dir: false, state: .Ready }
    out[2usize] = tree.Entry { path: "zebra", dir: false, state: .Ready }
    out[3usize] = tree.Entry { path: "Zo\xc3\xab", dir: false, state: .Ready }
    out[4usize] = tree.Entry { path: "\xc3\xa9clair", dir: false, state: .Ready }
    out[5usize] = tree.Entry { path: "Eclair", dir: false, state: .Ready }
    out[6usize] = tree.Entry { path: "eclair2", dir: false, state: .Ready }
    out[7usize] = tree.Entry { path: "Ecole", dir: false, state: .Ready }
    out[8usize] = tree.Entry { path: "\xc3\xa9cole", dir: false, state: .Ready }
    out[9usize] = tree.Entry { path: "e\xcc\x81cole", dir: false, state: .Ready }
    out[10usize] = tree.Entry { path: "\xc3\xb1andu", dir: false, state: .Ready }
    out[11usize] = tree.Entry { path: "nugget", dir: false, state: .Ready }
    out[12usize] = tree.Entry { path: "Nz", dir: false, state: .Ready }
    out[13usize] = tree.Entry { path: "\xce\xa9mega", dir: false, state: .Ready }
    out[14usize] = tree.Entry { path: "alpha", dir: false, state: .Ready }
    out[15usize] = tree.Entry { path: "\xce\x91\xce\xbb\xcf\x86\xce\xb1", dir: false, state: .Ready }
    out[16usize] = tree.Entry { path: "\xd0\xaf\xd1\x80\xd0\xbb\xd1\x8b\xd0\xba", dir: false, state: .Ready }
    out[17usize] = tree.Entry { path: "\xd1\x8f\xd1\x80\xd0\xbb\xd1\x8b\xd0\xba", dir: false, state: .Ready }
    out[18usize] = tree.Entry { path: "\xd1\x84\xd0\xb0\xd0\xb9\xd0\xbb10", dir: false, state: .Ready }
    out[19usize] = tree.Entry { path: "\xd1\x84\xd0\xb0\xd0\xb9\xd0\xbb2", dir: false, state: .Ready }
    out[20usize] = tree.Entry { path: "\xd0\xa4\xd0\xb0\xd0\xb9\xd0\xbb1", dir: false, state: .Ready }
    out[21usize] = tree.Entry { path: "10 r\xc3\xa9sum\xc3\xa9.txt", dir: false, state: .Ready }
    out[22usize] = tree.Entry { path: "9 resume.txt", dir: false, state: .Ready }
    out[23usize] = tree.Entry { path: "r\xc3\xa9sum\xc3\xa9", dir: false, state: .Ready }
    out[24usize] = tree.Entry { path: "resume", dir: false, state: .Ready }
    out[25usize] = tree.Entry { path: "Resume", dir: false, state: .Ready }
    out[26usize] = tree.Entry { path: "r\xc3\xa9sume", dir: false, state: .Ready }
    out[27usize] = tree.Entry { path: "\xc3\x96l", dir: true, state: .Ready }
    out[28usize] = tree.Entry { path: "ol", dir: true, state: .Ready }
    out[29usize] = tree.Entry { path: "Z\xc3\xbcrich", dir: true, state: .Ready }
    out[30usize] = tree.Entry { path: "zebra-dir", dir: true, state: .Ready }
    out[31usize] = tree.Entry { path: "\xc3\x89ire", dir: true, state: .Ready }
    out[32usize] = tree.Entry { path: "eire", dir: true, state: .Ready }
    out[33usize] = tree.Entry { path: "File007", dir: false, state: .Ready }
    out[34usize] = tree.Entry { path: "file7", dir: false, state: .Ready }
    out[35usize] = tree.Entry { path: "file12", dir: false, state: .Ready }
    ret 36usize
}

fn want_unicode() -> str { ret "0 D eire\n0 D \xc3\x89ire\n0 D ol\n0 D \xc3\x96l\n0 D zebra-dir\n0 D Z\xc3\xbcrich\n0 F 9 resume.txt\n0 F 10 r\xc3\xa9sum\xc3\xa9.txt\n0 F alpha\n0 F \xc3\x84pfel\n0 F apple\n0 F Eclair\n0 F \xc3\xa9clair\n0 F eclair2\n0 F Ecole\n0 F e\xcc\x81cole\n0 F \xc3\xa9cole\n0 F file7\n0 F File007\n0 F file12\n0 F \xc3\xb1andu\n0 F nugget\n0 F Nz\n0 F Resume\n0 F resume\n0 F r\xc3\xa9sume\n0 F r\xc3\xa9sum\xc3\xa9\n0 F zebra\n0 F Zo\xc3\xab\n0 F \xce\x91\xce\xbb\xcf\x86\xce\xb1\n0 F \xce\xa9mega\n0 F \xd0\xa4\xd0\xb0\xd0\xb9\xd0\xbb1\n0 F \xd1\x84\xd0\xb0\xd0\xb9\xd0\xbb2\n0 F \xd1\x84\xd0\xb0\xd0\xb9\xd0\xbb10\n0 F \xd0\xaf\xd1\x80\xd0\xbb\xd1\x8b\xd0\xba\n0 F \xd1\x8f\xd1\x80\xd0\xbb\xd1\x8b\xd0\xba\n" }

fn want_ascii() -> str { ret "0 D eire\n0 D ol\n0 D zebra-dir\n0 D Z\xc3\xbcrich\n0 D \xc3\x89ire\n0 D \xc3\x96l\n0 F 9 resume.txt\n0 F 10 r\xc3\xa9sum\xc3\xa9.txt\n0 F alpha\n0 F apple\n0 F Eclair\n0 F eclair2\n0 F Ecole\n0 F e\xcc\x81cole\n0 F file7\n0 F File007\n0 F file12\n0 F nugget\n0 F Nz\n0 F Resume\n0 F resume\n0 F r\xc3\xa9sume\n0 F r\xc3\xa9sum\xc3\xa9\n0 F zebra\n0 F Zo\xc3\xab\n0 F \xc3\x84pfel\n0 F \xc3\xa9clair\n0 F \xc3\xa9cole\n0 F \xc3\xb1andu\n0 F \xce\x91\xce\xbb\xcf\x86\xce\xb1\n0 F \xce\xa9mega\n0 F \xd0\xa4\xd0\xb0\xd0\xb9\xd0\xbb1\n0 F \xd0\xaf\xd1\x80\xd0\xbb\xd1\x8b\xd0\xba\n0 F \xd1\x84\xd0\xb0\xd0\xb9\xd0\xbb2\n0 F \xd1\x84\xd0\xb0\xd0\xb9\xd0\xbb10\n0 F \xd1\x8f\xd1\x80\xd0\xbb\xd1\x8b\xd0\xba\n" }

fn lazy_1(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "src", dir: true, state: .Unloaded }
    out[1usize] = tree.Entry { path: "README.md", dir: false, state: .Ready }
    out[2usize] = tree.Entry { path: "docs", dir: true, state: .Ready }
    out[3usize] = tree.Entry { path: "docs/a.txt", dir: false, state: .Ready }
    ret 4usize
}

fn lazy_2(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "src", dir: true, state: .Loading }
    out[1usize] = tree.Entry { path: "README.md", dir: false, state: .Ready }
    out[2usize] = tree.Entry { path: "docs", dir: true, state: .Ready }
    out[3usize] = tree.Entry { path: "docs/a.txt", dir: false, state: .Ready }
    ret 4usize
}

fn lazy_3(out: []tree.Entry) -> usize {
    out[0usize] = tree.Entry { path: "src", dir: true, state: .Ready }
    out[1usize] = tree.Entry { path: "src/main.e", dir: false, state: .Ready }
    out[2usize] = tree.Entry { path: "src/lib", dir: true, state: .Unloaded }
    out[3usize] = tree.Entry { path: "README.md", dir: false, state: .Ready }
    out[4usize] = tree.Entry { path: "docs", dir: true, state: .Ready }
    out[5usize] = tree.Entry { path: "docs/a.txt", dir: false, state: .Ready }
    ret 6usize
}

fn want_lazy_1() -> str { ret "0 D docs\n1 F a.txt\n0 D? src\n0 F README.md\n" }

fn want_lazy_2() -> str { ret "0 D docs\n1 F a.txt\n0 D src\n1 L \n0 F README.md\n" }

fn want_lazy_3() -> str { ret "0 D docs\n1 F a.txt\n0 D src\n1 D? lib\n1 F main.e\n0 F README.md\n" }
// END SCENARIOS

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
    let (scratch, e7) = mem.alloc[u8](a, 512usize)
    if e7 != ok { ret (zero, e7) }
    ret (tree.Storage { nodes: nodes, kids: kids, paths: paths, slots: slots, by_path: by_path, order: order, scratch: scratch }, ok)
}

fn kind_letter(k: tree.NodeKind) -> str {
    if k == .Folder { ret "D" }
    if k == .File { ret "F" }
    if k == .Loading { ret "L" }
    ret "X"
}

// Every node depth first, siblings in order: "depth kind name".
fn dump(b: *str.Builder, t: *const tree.Tree) -> err {
    var stack_at: [32]usize = zero
    var stack_end: [32]usize = zero
    var depth = 0usize
    stack_at[0usize] = t.root_first
    stack_end[0usize] = t.root_first + t.root_count
    while true {
        if stack_at[depth] >= stack_end[depth] {
            if depth == 0usize { break }
            depth -= 1usize
            continue
        }
        let node = usize(t.kids[stack_at[depth]])
        stack_at[depth] += 1usize
        try str.push_u64(b, u64(depth))
        try str.push(b, " ")
        try str.push(b, kind_letter(t.nodes[node].kind))
        if t.nodes[node].lazy {
            try str.push(b, "?")
        }
        try str.push(b, " ")
        let name = tree.name_of(t, node)
        var k = 0usize
        while k < name.len {
            if name[k] == 0u8 || name[k] == 1u8 || name[k] == 2u8 {
                try str.push(b, "~")
            } else {
                try str.push(b, name[k..k + 1usize])
            }
            k += 1usize
        }
        try str.push(b, "\n")
        if t.nodes[node].child_count > 0usize && depth + 1usize < 32usize {
            depth += 1usize
            stack_at[depth] = t.nodes[node].first_child
            stack_end[depth] = t.nodes[node].first_child + t.nodes[node].child_count
        }
    }
    ret ok
}

fn listing(a: *mem.Arena, t: *const tree.Tree) -> (str, err) {
    let (b, b_error) = str.builder(a, 8192usize)
    if b_error != ok { ret ("", b_error) }
    var bb = b
    let e = dump(&bb, t)
    if e != ok { ret ("", e) }
    ret (str.done(&bb), ok)
}

fn key_of(t: *const tree.Tree, p: str) -> u64 {
    let (at, found) = tree.find_path(t, p)
    if !found { ret 0u64 }
    ret t.nodes[usize(at)].key
}

fn main(a: *mem.Arena, args: []str) -> err {
    var raw: [64]tree.Entry = zero
    let (st1, st1_error) = storage(a, 160usize, 4096usize)
    if st1_error != ok { os.exit(1) }
    let (st2, st2_error) = storage(a, 160usize, 4096usize)
    if st2_error != ok { os.exit(2) }
    let (st3, st3_error) = storage(a, 160usize, 4096usize)
    if st3_error != ok { os.exit(3) }
    var none: tree.Tree = zero
    var none_renames: [1]tree.Rename = zero

    // Names: Unicode order against ASCII order over one folder.
    let n = names(raw[0..])
    let (u, u_error) = tree.build(raw[0usize..n], none_renames[0usize..0usize], &none, tree.policy_unicode(true), st1)
    if u_error != ok { os.exit(4) }
    let (u_text, u_text_error) = listing(a, &u)
    if u_text_error != ok { os.exit(5) }
    if !str.eq(u_text, want_unicode()) {
        try io.print(u_text)
        os.exit(6)
    }
    let (p, p_error) = tree.build(raw[0usize..n], none_renames[0usize..0usize], &none, tree.policy(true), st2)
    if p_error != ok { os.exit(7) }
    let (p_text, p_text_error) = listing(a, &p)
    if p_text_error != ok { os.exit(8) }
    if !str.eq(p_text, want_ascii()) {
        try io.print(p_text)
        os.exit(9)
    }
    if str.eq(u_text, p_text) { os.exit(10) }
    // The same entries listed in another order build the same tree under either policy.
    var k = 0usize
    while k < n / 2usize {
        let swap = raw[k]
        raw[k] = raw[n - 1usize - k]
        raw[n - 1usize - k] = swap
        k += 1usize
    }
    let (r, r_error) = tree.build(raw[0usize..n], none_renames[0usize..0usize], &none, tree.policy_unicode(true), st3)
    if r_error != ok { os.exit(11) }
    let (r_text, r_text_error) = listing(a, &r)
    if r_text_error != ok || !str.eq(r_text, u_text) { os.exit(12) }

    // Lazy loading: Unloaded, Loading, Ready; keys kept through prev.
    var theme: control.Theme = zero
    var s1: [8]tree.Entry = zero
    let n1 = lazy_1(s1[0..])
    let (t1, t1_error) = tree.build(s1[0usize..n1], none_renames[0usize..0usize], &none, tree.policy(true), st1)
    if t1_error != ok { os.exit(20) }
    let (t1_text, t1_text_error) = listing(a, &t1)
    if t1_text_error != ok || !str.eq(t1_text, want_lazy_1()) {
        try io.print(t1_text)
        os.exit(21)
    }
    let src_key = key_of(&t1, "src")
    let docs_key = key_of(&t1, "docs")
    if src_key == 0u64 || docs_key == 0u64 { os.exit(22) }
    if !tree.is_lazy(&t1, src_key) || tree.is_lazy(&t1, docs_key) { os.exit(23) }
    var open: [4]widget.Key = zero
    open[0usize] = docs_key
    open[1usize] = src_key
    var wanted: [4]widget.Key = zero
    let waiting = tree.pending(&t1, open[..], 2usize, wanted[..])
    if waiting != 1usize || wanted[0usize] != src_key { os.exit(24) }
    var bridge = tree.Bridge { tree: &t1, theme: &theme }
    let source = tree.source(&bridge)
    if !source.has_children(source.ctx, src_key) { os.exit(25) }
    if source.has_children(source.ctx, key_of(&t1, "README.md")) { os.exit(26) }
    var rows: [16]collection.TreeRow = zero
    let shown = tree.visible(&bridge, open[0usize..2usize], rows[..])
    // README.md, docs (open: a.txt), src (open, nothing yet): folders first.
    if shown != 4usize { os.exit(27) }

    var s2: [8]tree.Entry = zero
    let n2 = lazy_2(s2[0..])
    let (t2, t2_error) = tree.build(s2[0usize..n2], none_renames[0usize..0usize], &t1, tree.policy(true), st2)
    if t2_error != ok { os.exit(30) }
    let (t2_text, t2_text_error) = listing(a, &t2)
    if t2_text_error != ok || !str.eq(t2_text, want_lazy_2()) {
        try io.print(t2_text)
        os.exit(31)
    }
    if key_of(&t2, "src") != src_key || key_of(&t2, "docs") != docs_key { os.exit(32) }
    if tree.pending(&t2, open[..], 2usize, wanted[..]) != 0usize { os.exit(33) }

    var s3: [8]tree.Entry = zero
    let n3 = lazy_3(s3[0..])
    let (t3, t3_error) = tree.build(s3[0usize..n3], none_renames[0usize..0usize], &t2, tree.policy(true), st3)
    if t3_error != ok { os.exit(40) }
    let (t3_text, t3_text_error) = listing(a, &t3)
    if t3_text_error != ok || !str.eq(t3_text, want_lazy_3()) {
        try io.print(t3_text)
        os.exit(41)
    }
    if key_of(&t3, "src") != src_key { os.exit(42) }
    let lib_key = key_of(&t3, "src/lib")
    open[2usize] = lib_key
    let waiting3 = tree.pending(&t3, open[..], 3usize, wanted[..])
    if waiting3 != 1usize || wanted[0usize] != lib_key { os.exit(43) }
    // A key that is gone, or a file, is never pending.
    open[3usize] = 12345u64
    if tree.pending(&t3, open[..], 4usize, wanted[..]) != 1usize { os.exit(44) }
    if tree.is_lazy(&t3, key_of(&t3, "src/main.e")) { os.exit(45) }
    // The output is bounded by `out`.
    var one: [1]widget.Key = zero
    open[0usize] = lib_key
    open[1usize] = lib_key
    if tree.pending(&t3, open[..], 2usize, one[..]) != 1usize { os.exit(46) }

    try io.print("ui tree adapter unicode ok\n")
    ret ok
}
