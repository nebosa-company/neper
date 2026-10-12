// `e.ui.tree_adapter` (L067): a refresh-stable file-tree model over `e.ui.collection`'s
// `TreeSource`. A host's enumeration is a flat list of `Entry` (relative path, folder or
// file, a folder's load state); `build` turns it into a `Tree` in caller storage: folders
// first and natural order inside each folder (`e.text.collate`, digit runs by magnitude,
// ties broken by code point so the order is total), a loading or failed folder carrying a
// placeholder row, and a stable 64-bit key per node. `source` hands the tree to
// `e.ui.collection` (`flatten`, `tree_with`) as a `TreeSource`; there is no second tree
// widget.
//
// Identity: a node's key comes from its path under the `Policy`'s path-identity rule --
// bytes as they are on a case-sensitive host, ASCII-folded on a case-insensitive one
// (`case_sensitive_paths`), never lowercased unconditionally. Two entries with the same
// identity are `Duplicate`. The key is the policy's hash of the identity path; a node that
// existed in the `prev` tree (found by identity path, or by the `Rename` that moved it,
// which also carries every descendant of a renamed folder) keeps its key, so an
// expansion, selection or scroll anchor held by key survives a refresh and a rename. A
// new node whose hash is taken is probed upward (key + 1, skipping 0) in identity-path
// order, so keys are the same whatever order the host listed the entries in, and distinct
// always. Removal needs no work: `retain` drops keys that are no longer in the tree and
// `settle` picks the neighbour a removed selection should fall to.
//
// What this module does not do: enumerate, resolve or authorize anything -- the host's
// filesystem service owns that; the tree is the snapshot it was given. The `build`
// callback of `source` makes a text row in the theme; rows with icons, rename editors and
// drag are `e.ui.collection`'s `TreeOptions`.
//
// Names: the default order is `collate`'s (ASCII case folding and numeric runs); under
// `policy_unicode` a name is decomposed (NFD), lowered by Unicode's simple mapping and
// compared first without its combining marks (digit runs by magnitude), then with them,
// so `e`, `é` and a decomposed `é` sort together before `f` and a composed and a decomposed
// spelling are equal until the byte tie-break.
//
// Lazy loading: a folder listed as `Unloaded` has an expander and no children; `pending`
// names the expanded ones for the host to enumerate, which lists them again as `Loading`
// (a placeholder row) and then `Ready` with their entries, the keys kept through `prev`.
//
// `policy_language` adds one language's tailoring to that order (Swedish `å ä ö` after `z`,
// Polish `ł` after `l`, Czech `ch` after `h`, ... -- see `tailoring_of`), keyed by the tag's
// language subtag.
//
// ponytail: only the tailorings of nine languages, none per region or traditional (no UCA
// contractions beyond Czech `ch`, no Han readings, no `aa` as `å` in Danish), a name is compared on its
// first 512 NFD scalars; a node's parent is found by a binary search over identity paths, so build is
// O(n log n) in the entry count; `prev` and the new `Storage` must be different buffers.

use e.algo.hash as hash
use e.mem
use e.text.collate as collate
use e.text.normalize as normalize
use e.text.unicode as unicode
use e.ui.collection
use e.ui.control
use e.ui.widget

const NONE: u32 = 4294967295u32

type NodeKind = enum u8 { File, Folder, Loading, Failed }
// `Unloaded`: a folder whose contents the host has not listed yet (it shows an expander and
// no placeholder row; `pending` names the expanded ones the host should enumerate).
type DirState = enum u8 { Ready, Loading, Failed, Unloaded }

type Entry = struct { path: str, dir: bool, state: DirState }
type Rename = struct { from: str, to: str }
// `unicode_names`: order names by Unicode simple case folding with accents as a second
// level (see `name_order`) rather than by ASCII folding.
// `tailoring`: with `unicode_names`, a language's letters that sort as letters of their own
// (1 Swedish and Finnish, 2 Danish and Norwegian, 3 German, 4 Spanish, 5 Polish, 6 Czech,
// 7 Turkish; 0 none), see `policy_language`.
type Policy = struct { case_sensitive_paths: bool, order: collate.Options, folders_first: bool, hash: fn(str) -> u64, unicode_names: bool, tailoring: u8 }
type Node = struct { key: widget.Key, parent: u32, kind: NodeKind, path_start: usize, path_len: usize, name_start: usize, depth: u32, first_child: usize, child_count: usize, lazy: bool }
type Storage = struct { nodes: []Node, kids: []u32, paths: []u8, slots: []u32, by_path: []u32, order: []u32, scratch: []u8 }
type Tree = struct { nodes: []Node, kids: []u32, paths: []u8, slots: []u32, by_path: []u32, count: usize, root_first: usize, root_count: usize, case_sensitive_paths: bool }

error TooLarge
error Duplicate
error MissingParent
error NotDirectory
error Invalid

fn default_hash(s: str) -> u64 {
    ret hash.fnv1a64(s)
}

// A host's policy: case-sensitive or not path identity, folders first, natural order
// folding ASCII case, the FNV-1a hash.
fn policy(case_sensitive_paths: bool) -> Policy {
    ret Policy { case_sensitive_paths: case_sensitive_paths, order: collate.Options { case_sensitive: false, numeric: true }, folders_first: true, hash: default_hash, unicode_names: false, tailoring: 0u8 }
}

// `policy` with names ordered beyond ASCII: each name is decomposed (NFD), lowered with
// Unicode's simple mapping and compared first without its combining marks (so `e`, `é` and
// `É` sort together, between `d` and `f`, digit runs by magnitude), then with them (the
// plain letter first), then by the byte tie-break every order here ends with.
fn policy_unicode(case_sensitive_paths: bool) -> Policy {
    var p = policy(case_sensitive_paths)
    p.unicode_names = true
    ret p
}

// The tailoring of a language tag's language subtag (`sv`, `da-DK`, `nb`, `de_AT`, ...), 0 for
// a language with none.
fn tailoring_of(tag: str) -> u8 {
    var end = 0usize
    while end < tag.len && tag[end] != 45u8 && tag[end] != 95u8 { end += 1usize }
    if end != 2usize && end != 3usize { ret 0u8 }
    let a = fold_byte(tag[0usize], false)
    let b = fold_byte(tag[1usize], false)
    if end == 3usize {
        // nob, nno: Norwegian.
        if a == 110u8 && b == 111u8 { ret 2u8 }
        ret 0u8
    }
    if a == 115u8 && b == 118u8 { ret 1u8 }
    if a == 102u8 && b == 105u8 { ret 1u8 }
    if a == 100u8 && b == 97u8 { ret 2u8 }
    if a == 110u8 && (b == 98u8 || b == 111u8 || b == 110u8) { ret 2u8 }
    if a == 100u8 && b == 101u8 { ret 3u8 }
    if a == 101u8 && b == 115u8 { ret 4u8 }
    if a == 112u8 && b == 108u8 { ret 5u8 }
    if a == 99u8 && b == 115u8 { ret 6u8 }
    if a == 116u8 && b == 114u8 { ret 7u8 }
    ret 0u8
}

// `policy_unicode` with a language's tailoring (D3604): the letters that sort as letters of their own are placed
// where its alphabet has them -- Swedish and Finnish `å ä ö` after `z`, Danish and Norwegian `æ ø å`, Spanish `ñ` after
// `n`, Polish `ą ć ę ł ń ó ś ź ż`, Czech `č ř š ž` and the digraph `ch` after `h`, Turkish `ç ğ ö ş ü` and `ı` before
// `i` (with `I` and `İ` its dotless and dotted pair), German `ß` as `ss`. Where a language has no row of its own the
// order is `policy_unicode`'s. Regional variants and traditional orders (Spanish `ch` and `ll`, German phone-book
// `ä` as `ae`, Swedish `v` and `w`) are not distinguished.
fn policy_language(tag: str, case_sensitive_paths: bool) -> Policy {
    var p = policy_unicode(case_sensitive_paths)
    p.tailoring = tailoring_of(tag)
    ret p
}

fn fold_byte(ch: u8, sensitive: bool) -> u8 {
    if !sensitive && ch >= 65u8 && ch <= 90u8 { ret ch + 32u8 }
    ret ch
}

fn id_cmp(x: str, y: str, sensitive: bool) -> i32 {
    var i = 0usize
    while i < x.len && i < y.len {
        let p = fold_byte(x[i], sensitive)
        let q = fold_byte(y[i], sensitive)
        if p < q { ret -1i32 }
        if p > q { ret 1i32 }
        i += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

type Ctx = struct { nodes: []Node, paths: []u8, policy: Policy }

fn node_path(c: *const Ctx, i: usize) -> str {
    let n = c.nodes[i]
    ret c.paths[n.path_start..n.path_start + n.path_len]
}

fn node_name(c: *const Ctx, i: usize) -> str {
    let n = c.nodes[i]
    ret c.paths[n.name_start..n.path_start + n.path_len]
}

fn rank_of(c: *const Ctx, n: Node) -> u32 {
    if n.kind == .Loading || n.kind == .Failed { ret 2u32 }
    if n.kind == .Folder && c.policy.folders_first { ret 0u32 }
    ret 1u32
}

const KEY_CAP: usize = 512usize

// The NFD scalars of `name`, lowered with Unicode's simple mapping when `fold`: every one
// into `all`, those that are not combining marks into `base`; both lengths. A name longer
// than KEY_CAP scalars is cut there (the byte tie-break still orders it).
fn fold_keys(name: str, fold: bool, tailoring: u8, all: []u32, base: []u32) -> (usize, usize) {
    var n_all = 0usize
    var n_base = 0usize
    var at = 0usize
    var parts: [18]u32 = zero
    var last_raw = 0u32
    while at < name.len {
        let (scalar, width) = unicode.read_utf8(name, at)
        at += width
        var used = 0usize
        if tailoring == 3u8 && scalar == 223u32 {
            // German sharp s reads as `ss`.
            parts[0usize] = 115u32
            parts[1usize] = 115u32
            used = 2usize
        } else if tailoring == 7u8 && scalar == 73u32 {
            parts[0usize] = 305u32
            used = 1usize
        } else if tailoring == 7u8 && scalar == 304u32 {
            parts[0usize] = 105u32
            used = 1usize
        } else {
            let (used_parts, decompose_error) = normalize.decompose(scalar, false, parts[..], 0usize)
            used = used_parts
            if decompose_error != ok {
                parts[0usize] = scalar
                used = 1usize
            }
        }
        var k = 0usize
        while k < used {
            var s = parts[k]
            if fold { s = unicode.to_lower_simple(s) }
            if n_all < all.len {
                all[n_all] = s
                n_all += 1usize
            }
            if unicode.combining_class(parts[k]) == 0u8 {
                let lowered = unicode.to_lower_simple(parts[k])
                if n_base < base.len {
                    var key = primary_key(tailoring, s)
                    if tailoring != 0u8 {
                        let own = lone_key(tailoring, lowered)
                        if own != 0u32 { key = own }
                    }
                    base[n_base] = key
                    n_base += 1usize
                    // Czech `ch` is one letter after `h`.
                    if tailoring == 6u8 && lowered == 104u32 && last_raw == 99u32 && n_base >= 2usize && base[n_base - 2usize] == primary_key(6u8, 99u32) {
                        base[n_base - 2usize] = primary_key(6u8, 104u32) + 1u32
                        n_base -= 1usize
                    }
                    last_raw = lowered
                }
            } else if tailoring != 0u8 && n_base > 0usize {
                let own = mark_key(tailoring, last_raw, unicode.to_lower_simple(parts[k]))
                if own != 0u32 { base[n_base - 1usize] = own }
            }
            k += 1usize
        }
    }
    ret (n_all, n_base)
}

// The primary key of a base scalar: itself without a tailoring; with one the keys above the digits are spread by 16 so a
// tailored letter can stand between a letter and the next.
fn primary_key(tailoring: u8, s: u32) -> u32 {
    if tailoring == 0u8 || s < 58u32 { ret s }
    ret s * 16u32
}

// The key of a scalar that is a letter of its own in the tailoring, 0 when it is not.
fn lone_key(tailoring: u8, s: u32) -> u32 {
    if tailoring == 1u8 {
        if s == 230u32 { ret primary_key(1u8, 122u32) + 2u32 }
        if s == 248u32 { ret primary_key(1u8, 122u32) + 3u32 }
    }
    if tailoring == 2u8 {
        if s == 230u32 { ret primary_key(2u8, 122u32) + 1u32 }
        if s == 248u32 { ret primary_key(2u8, 122u32) + 2u32 }
    }
    if tailoring == 5u8 && s == 322u32 { ret primary_key(5u8, 108u32) + 1u32 }
    if tailoring == 7u8 && s == 305u32 { ret primary_key(7u8, 105u32) - 1u32 }
    ret 0u32
}

// The key of the base letter `b` carrying the combining mark `m` in the tailoring, 0 when the pair is not a letter of
// its own. `b` and `m` are lowered scalars.
fn mark_key(tailoring: u8, b: u32, m: u32) -> u32 {
    if tailoring == 1u8 {
        if b == 97u32 && m == 778u32 { ret primary_key(1u8, 122u32) + 1u32 }
        if b == 97u32 && m == 776u32 { ret primary_key(1u8, 122u32) + 2u32 }
        if b == 111u32 && m == 776u32 { ret primary_key(1u8, 122u32) + 3u32 }
    }
    if tailoring == 2u8 {
        if b == 97u32 && m == 776u32 { ret primary_key(2u8, 122u32) + 1u32 }
        if b == 111u32 && m == 776u32 { ret primary_key(2u8, 122u32) + 2u32 }
        if b == 97u32 && m == 778u32 { ret primary_key(2u8, 122u32) + 3u32 }
    }
    if tailoring == 4u8 && b == 110u32 && m == 771u32 { ret primary_key(4u8, 110u32) + 1u32 }
    if tailoring == 5u8 {
        if m == 808u32 && (b == 97u32 || b == 101u32) { ret primary_key(5u8, b) + 1u32 }
        if m == 769u32 && (b == 99u32 || b == 110u32 || b == 111u32 || b == 115u32 || b == 122u32) { ret primary_key(5u8, b) + 1u32 }
        if m == 775u32 && b == 122u32 { ret primary_key(5u8, 122u32) + 2u32 }
    }
    if tailoring == 6u8 && m == 780u32 && (b == 99u32 || b == 114u32 || b == 115u32 || b == 122u32) { ret primary_key(6u8, b) + 1u32 }
    if tailoring == 7u8 {
        if m == 807u32 && (b == 99u32 || b == 115u32) { ret primary_key(7u8, b) + 1u32 }
        if m == 774u32 && b == 103u32 { ret primary_key(7u8, 103u32) + 1u32 }
        if m == 776u32 && (b == 111u32 || b == 117u32) { ret primary_key(7u8, b) + 1u32 }
    }
    ret 0u32
}

fn is_digit_scalar(s: u32) -> bool { ret s >= 48u32 && s <= 57u32 }

// -1, 0, 1 over two scalar runs: ASCII digit runs by magnitude (then by length, the shorter
// zero padding first) when `numeric`, everything else by value.
fn natural_scalars(x: []const u32, nx: usize, y: []const u32, ny: usize, numeric: bool) -> i32 {
    var i = 0usize
    var j = 0usize
    while i < nx && j < ny {
        if numeric && is_digit_scalar(x[i]) && is_digit_scalar(y[j]) {
            let si = i
            let sj = j
            while i < nx && is_digit_scalar(x[i]) { i += 1usize }
            while j < ny && is_digit_scalar(y[j]) { j += 1usize }
            var a = si
            var b = sj
            while a < i && x[a] == 48u32 { a += 1usize }
            while b < j && y[b] == 48u32 { b += 1usize }
            let la = i - a
            let lb = j - b
            if la < lb { ret -1i32 }
            if la > lb { ret 1i32 }
            var d = 0usize
            while d < la {
                if x[a + d] < y[b + d] { ret -1i32 }
                if x[a + d] > y[b + d] { ret 1i32 }
                d += 1usize
            }
            if i - si < j - sj { ret -1i32 }
            if i - si > j - sj { ret 1i32 }
            continue
        }
        if x[i] < y[j] { ret -1i32 }
        if x[i] > y[j] { ret 1i32 }
        i += 1usize
        j += 1usize
    }
    if i < nx { ret 1i32 }
    if j < ny { ret -1i32 }
    ret 0i32
}

// The order of two names under the policy: ASCII-folded natural order, or with
// `unicode_names` the base letters (marks dropped, lowered) naturally, then the full NFD
// letters; 0 when both agree (the caller's byte tie-break follows).
fn name_order(c: *const Ctx, a: str, b: str) -> i32 {
    if !c.policy.unicode_names { ret collate.compare(a, b, c.policy.order) }
    var all_a: [512]u32 = zero
    var base_a: [512]u32 = zero
    var all_b: [512]u32 = zero
    var base_b: [512]u32 = zero
    let fold = !c.policy.order.case_sensitive
    let (na, pa) = fold_keys(a, fold, c.policy.tailoring, all_a[..], base_a[..])
    let (nb, pb) = fold_keys(b, fold, c.policy.tailoring, all_b[..], base_b[..])
    let primary = natural_scalars(base_a[..], pa, base_b[..], pb, c.policy.order.numeric)
    if primary != 0i32 { ret primary }
    ret natural_scalars(all_a[..], na, all_b[..], nb, false)
}

// Whether node `x` sorts before `y`: mode 0 by identity path, mode 1 by parent, then
// folders-first rank, natural name order and identity path.
fn before(c: *const Ctx, x: u32, y: u32, mode: u32) -> bool {
    let sensitive = c.policy.case_sensitive_paths
    if mode == 0u32 {
        ret id_cmp(node_path(c, usize(x)), node_path(c, usize(y)), sensitive) < 0i32
    }
    let a = c.nodes[usize(x)]
    let b = c.nodes[usize(y)]
    if a.parent != b.parent { ret a.parent < b.parent }
    let ra = rank_of(c, a)
    let rb = rank_of(c, b)
    if ra != rb { ret ra < rb }
    if ra < 2u32 {
        let by_name = name_order(c, node_name(c, usize(x)), node_name(c, usize(y)))
        if by_name != 0i32 { ret by_name < 0i32 }
    }
    ret id_cmp(node_path(c, usize(x)), node_path(c, usize(y)), sensitive) < 0i32
}

// Bottom-up merge sort of `idx[0..n]` through `tmp`.
fn sort(c: *const Ctx, idx: []u32, tmp: []u32, n: usize, mode: u32) {
    var width = 1usize
    while width < n {
        var lo = 0usize
        while lo < n {
            var mid = lo + width
            if mid > n { mid = n }
            var hi = lo + 2usize * width
            if hi > n { hi = n }
            var i = lo
            var j = mid
            var k = lo
            while i < mid && j < hi {
                if before(c, idx[j], idx[i], mode) {
                    tmp[k] = idx[j]
                    j += 1usize
                } else {
                    tmp[k] = idx[i]
                    i += 1usize
                }
                k += 1usize
            }
            while i < mid {
                tmp[k] = idx[i]
                i += 1usize
                k += 1usize
            }
            while j < hi {
                tmp[k] = idx[j]
                j += 1usize
                k += 1usize
            }
            lo += 2usize * width
        }
        var m = 0usize
        while m < n {
            idx[m] = tmp[m]
            m += 1usize
        }
        width *= 2usize
    }
}

// The node of a tree whose identity path is `p`, by binary search.
fn find_path(t: *const Tree, p: str) -> (u32, bool) {
    var lo = 0usize
    var hi = t.count
    while lo < hi {
        let mid = (lo + hi) / 2usize
        let n = t.nodes[usize(t.by_path[mid])]
        let c = id_cmp(t.paths[n.path_start..n.path_start + n.path_len], p, t.case_sensitive_paths)
        if c == 0i32 { ret (t.by_path[mid], true) }
        if c < 0i32 {
            lo = mid + 1usize
        } else {
            hi = mid
        }
    }
    ret (NONE, false)
}

fn slot_find(slots: []u32, nodes: []Node, key: widget.Key) -> u32 {
    if slots.len == 0usize { ret NONE }
    var at = usize(key % u64(slots.len))
    var probes = 0usize
    while probes < slots.len {
        let held = slots[at]
        if held == 0u32 { ret NONE }
        if nodes[usize(held - 1u32)].key == key { ret held - 1u32 }
        at += 1usize
        if at == slots.len { at = 0usize }
        probes += 1usize
    }
    ret NONE
}

fn slot_put(slots: []u32, key: widget.Key, node: u32) {
    var at = usize(key % u64(slots.len))
    while slots[at] != 0u32 {
        at += 1usize
        if at == slots.len { at = 0usize }
    }
    slots[at] = node + 1u32
}

// The key of the node of `prev` that `p` continues: by identity path, or through the
// rename that moved it (the first whose `to` is `p` or a folder above it).
fn prev_key(prev: *const Tree, renames: []const Rename, p: str, scratch: []u8) -> (widget.Key, bool) {
    if prev.count == 0usize { ret (0u64, false) }
    var r = 0usize
    while r < renames.len {
        let to = renames[r].to
        var hit = false
        var rest = p.len
        if id_cmp(p, to, prev.case_sensitive_paths) == 0i32 {
            hit = true
            rest = to.len
        } else if p.len > to.len && p[to.len] == 47u8 && id_cmp(p[0usize..to.len], to, prev.case_sensitive_paths) == 0i32 {
            hit = true
            rest = to.len
        }
        if hit {
            let from = renames[r].from
            let tail = p[rest..p.len]
            if from.len + tail.len > scratch.len { ret (0u64, false) }
            var k = 0usize
            while k < from.len {
                scratch[k] = from[k]
                k += 1usize
            }
            k = 0usize
            while k < tail.len {
                scratch[from.len + k] = tail[k]
                k += 1usize
            }
            let (found, ok_found) = find_path(prev, scratch[0usize..from.len + tail.len])
            if ok_found { ret (prev.nodes[usize(found)].key, true) }
            ret (0u64, false)
        }
        r += 1usize
    }
    let (found, ok_found) = find_path(prev, p)
    if ok_found { ret (prev.nodes[usize(found)].key, true) }
    ret (0u64, false)
}

fn put_path(paths: []u8, used: *usize, p: str) -> (usize, err) {
    if *used + p.len > paths.len { ret (0usize, TooLarge) }
    let begin = *used
    var i = 0usize
    while i < p.len {
        paths[begin + i] = p[i]
        i += 1usize
    }
    *used = *used + p.len
    ret (begin, ok)
}

fn last_slash(p: str) -> (usize, bool) {
    var i = p.len
    while i > 0usize {
        i -= 1usize
        if p[i] == 47u8 { ret (i, true) }
    }
    ret (0usize, false)
}

// Builds the tree of `entries` into `st`. `prev` is the previous tree (zero for none) and
// `renames` the moves since it, as `to` paths with their `from`. Errors: `TooLarge` (a
// storage slice, or `scratch` shorter than a path), `Duplicate` (two entries of one
// identity), `MissingParent` (a path whose folder is not listed), `NotDirectory` (a parent
// that is a file) and `Invalid` (an empty path or a trailing slash).
fn build(entries: []const Entry, renames: []const Rename, prev: *const Tree, pol: Policy, st: Storage) -> (Tree, err) {
    let n = entries.len
    var placeholders = 0usize
    var e = 0usize
    while e < n {
        if entries[e].dir && (entries[e].state == .Loading || entries[e].state == .Failed) { placeholders += 1usize }
        e += 1usize
    }
    let total = n + placeholders
    if total > st.nodes.len || total > st.by_path.len || total > st.order.len || total > st.kids.len || st.slots.len < total * 2usize + 1usize { ret (zero, TooLarge) }
    var used = 0usize
    var i = 0usize
    while i < n {
        let p = entries[i].path
        if p.len == 0usize || p[p.len - 1usize] == 47u8 || p[0usize] == 47u8 { ret (zero, Invalid) }
        let (begin, put_error) = put_path(st.paths, &used, p)
        if put_error != ok { ret (zero, put_error) }
        let (slash, has_slash) = last_slash(p)
        var name_start = begin
        if has_slash { name_start = begin + slash + 1usize }
        var kind: NodeKind = .File
        if entries[i].dir { kind = .Folder }
        st.nodes[i] = Node { key: 0u64, parent: NONE, kind: kind, path_start: begin, path_len: p.len, name_start: name_start, depth: 0u32, first_child: 0usize, child_count: 0usize, lazy: entries[i].dir && entries[i].state == .Unloaded }
        st.by_path[i] = u32(i)
        i += 1usize
    }
    var c = Ctx { nodes: st.nodes, paths: st.paths, policy: pol }
    sort(&c, st.by_path, st.order, n, 0u32)
    // Duplicates, parents and depths, in identity order (a folder sorts before its contents).
    var shell = Tree { nodes: st.nodes, kids: st.kids, paths: st.paths, slots: st.slots, by_path: st.by_path, count: n, root_first: 0usize, root_count: 0usize, case_sensitive_paths: pol.case_sensitive_paths }
    i = 0usize
    while i < n {
        let at = usize(st.by_path[i])
        if i > 0usize && id_cmp(node_path(&c, at), node_path(&c, usize(st.by_path[i - 1usize])), pol.case_sensitive_paths) == 0i32 { ret (zero, Duplicate) }
        let p = node_path(&c, at)
        let (slash, has_slash) = last_slash(p)
        if has_slash {
            let (parent, found) = find_path(&shell, p[0usize..slash])
            if !found { ret (zero, MissingParent) }
            if st.nodes[usize(parent)].kind != .Folder { ret (zero, NotDirectory) }
            st.nodes[at].parent = parent
            st.nodes[at].depth = st.nodes[usize(parent)].depth + 1u32
        }
        i += 1usize
    }
    // Placeholders for loading and failed folders, in identity order of their folders.
    var next = n
    i = 0usize
    while i < n {
        let at = usize(st.by_path[i])
        let nd = st.nodes[at]
        let entry = entries[at]
        if entry.dir && (entry.state == .Loading || entry.state == .Failed) {
            var synthetic: [2]u8 = zero
            synthetic[0usize] = 0u8
            synthetic[1usize] = 1u8
            var kind: NodeKind = .Loading
            if entry.state == .Failed {
                synthetic[1usize] = 2u8
                kind = .Failed
            }
            let (begin, put_error) = put_path(st.paths, &used, entry.path)
            if put_error != ok { ret (zero, put_error) }
            let (_, slash_error) = put_path(st.paths, &used, "/")
            if slash_error != ok { ret (zero, slash_error) }
            let (_, mark_error) = put_path(st.paths, &used, synthetic[0usize..2usize])
            if mark_error != ok { ret (zero, mark_error) }
            let len = entry.path.len + 3usize
            st.nodes[next] = Node { key: 0u64, parent: u32(at), kind: kind, path_start: begin, path_len: len, name_start: begin + len, depth: nd.depth + 1u32, first_child: 0usize, child_count: 0usize, lazy: false }
            st.by_path[next] = u32(next)
            next += 1usize
        }
        i += 1usize
    }
    c.nodes = st.nodes
    c.paths = st.paths
    sort(&c, st.by_path, st.order, total, 0u32)
    shell.count = total
    // Keys. Pass one: what `prev` knew. Pass two: the rest by hash, probed, in identity order.
    var slot = 0usize
    while slot < st.slots.len {
        st.slots[slot] = 0u32
        slot += 1usize
    }
    i = 0usize
    while i < total {
        let at = usize(st.by_path[i])
        let (known, has_known) = prev_key(prev, renames, node_path(&c, at), st.scratch)
        if has_known && slot_find(st.slots, st.nodes, known) == NONE {
            st.nodes[at].key = known
            slot_put(st.slots, known, u32(at))
        }
        i += 1usize
    }
    i = 0usize
    while i < total {
        let at = usize(st.by_path[i])
        if st.nodes[at].key == 0u64 {
            let p = node_path(&c, at)
            if p.len > st.scratch.len { ret (zero, TooLarge) }
            var k = 0usize
            while k < p.len {
                st.scratch[k] = fold_byte(p[k], pol.case_sensitive_paths)
                k += 1usize
            }
            var key = pol.hash(st.scratch[0usize..p.len])
            if key == 0u64 { key = 1u64 }
            while slot_find(st.slots, st.nodes, key) != NONE {
                key += 1u64
                if key == 0u64 { key = 1u64 }
            }
            st.nodes[at].key = key
            slot_put(st.slots, key, u32(at))
        }
        i += 1usize
    }
    // Sibling order, then the child runs.
    i = 0usize
    while i < total {
        st.kids[i] = u32(i)
        i += 1usize
    }
    sort(&c, st.kids, st.order, total, 1u32)
    var root_first = total
    var root_count = 0usize
    i = 0usize
    while i < total {
        let parent = st.nodes[usize(st.kids[i])].parent
        var run = 1usize
        while i + run < total && st.nodes[usize(st.kids[i + run])].parent == parent { run += 1usize }
        if parent == NONE {
            root_first = i
            root_count = run
        } else {
            st.nodes[usize(parent)].first_child = i
            st.nodes[usize(parent)].child_count = run
        }
        i += run
    }
    ret (Tree { nodes: st.nodes, kids: st.kids, paths: st.paths, slots: st.slots, by_path: st.by_path, count: total, root_first: root_first, root_count: root_count, case_sensitive_paths: pol.case_sensitive_paths }, ok)
}

// The node index of a key.
fn find(t: *const Tree, key: widget.Key) -> (usize, bool) {
    let at = slot_find(t.slots, t.nodes, key)
    if at == NONE { ret (0usize, false) }
    ret (usize(at), true)
}

fn path_of(t: *const Tree, node: usize) -> str {
    let n = t.nodes[node]
    ret t.paths[n.path_start..n.path_start + n.path_len]
}

fn name_of(t: *const Tree, node: usize) -> str {
    let n = t.nodes[node]
    ret t.paths[n.name_start..n.path_start + n.path_len]
}

// Keeps the keys of `keys[0..n]` that are still in the tree (a folder only, when
// `folders_only`), in their order; the new count. An expansion list is `folders_only`.
fn retain(t: *const Tree, keys: []widget.Key, n: usize, folders_only: bool) -> usize {
    var kept = 0usize
    var i = 0usize
    while i < n {
        let (at, found) = find(t, keys[i])
        if found && (!folders_only || t.nodes[at].kind == .Folder) {
            keys[kept] = keys[i]
            kept += 1usize
        }
        i += 1usize
    }
    ret kept
}

// Where a selection goes when its node was removed: the key itself if it survives;
// otherwise the sibling at the same position under the nearest surviving parent (clamped
// to its last child), else that parent; 0 when the whole chain is gone.
fn settle(prev: *const Tree, next: *const Tree, key: widget.Key) -> widget.Key {
    let (here, here_found) = find(next, key)
    if here_found { ret key }
    let (old, old_found) = find(prev, key)
    if !old_found { ret 0u64 }
    var cur = old
    while true {
        let parent = prev.nodes[cur].parent
        if parent == NONE {
            // Everything above is gone (or the node was top level): the root's sibling.
            if next.root_count == 0usize { ret 0u64 }
            var pick = position_of(prev, cur)
            if pick >= next.root_count { pick = next.root_count - 1usize }
            ret next.nodes[usize(next.kids[next.root_first + pick])].key
        }
        let (alive, is_alive) = find(next, prev.nodes[usize(parent)].key)
        if is_alive {
            let n = next.nodes[alive]
            if cur != old || n.child_count == 0usize { ret n.key }
            var pick = position_of(prev, old)
            if pick >= n.child_count { pick = n.child_count - 1usize }
            ret next.nodes[usize(next.kids[n.first_child + pick])].key
        }
        cur = usize(parent)
    }
    ret 0u64
}

// A node's index among its siblings.
fn position_of(t: *const Tree, node: usize) -> usize {
    let parent = t.nodes[node].parent
    var base = t.root_first
    var siblings = t.root_count
    if parent != NONE {
        base = t.nodes[usize(parent)].first_child
        siblings = t.nodes[usize(parent)].child_count
    }
    var i = 0usize
    while i < siblings {
        if usize(t.kids[base + i]) == node { ret i }
        i += 1usize
    }
    ret 0usize
}

// A scroll offset that keeps the row under the viewport top where it was: the row at
// `offset` in `before_rows` is looked up by key in `after_rows` and the offset moves with
// it (the same distance into the row); if it is gone, the first later row of
// `before_rows` that survives is the anchor, else the last earlier one, else zero. The
// result is clamped to the new content.
fn anchor_offset(before_rows: []const collection.TreeRow, after_rows: []const collection.TreeRow, offset: f32, row_height: f32, viewport: f32) -> f32 {
    if before_rows.len == 0usize || after_rows.len == 0usize || row_height <= 0.0 { ret 0.0 }
    var index = usize(offset / row_height)
    if index >= before_rows.len { index = before_rows.len - 1usize }
    let within = offset - f32(index) * row_height
    var found = false
    var landing = 0usize
    var d = index
    while d < before_rows.len && !found {
        var j = 0usize
        while j < after_rows.len && !found {
            if after_rows[j].key == before_rows[d].key {
                found = true
                landing = j
            }
            j += 1usize
        }
        if !found { d += 1usize }
    }
    var carry = within
    if found && d != index { carry = 0.0 }
    if !found {
        d = index
        while d > 0usize && !found {
            d -= 1usize
            var j = 0usize
            while j < after_rows.len && !found {
                if after_rows[j].key == before_rows[d].key {
                    found = true
                    landing = j
                }
                j += 1usize
            }
        }
        carry = 0.0
    }
    var out = f32(landing) * row_height + carry
    var most = f32(after_rows.len) * row_height - viewport
    if most < 0.0 { most = 0.0 }
    if out > most { out = most }
    if out < 0.0 { out = 0.0 }
    ret out
}

// The tree as an `e.ui.collection` source; the bridge carries the tree and the theme the
// row text is built in.
type Bridge = struct { tree: *const Tree, theme: *const control.Theme }

fn bridge_count(ctx: *void, key: widget.Key) -> usize {
    let b = mem.cast[*Bridge](ctx)
    if key == 0u64 { ret b.tree.root_count }
    let (at, found) = find(b.tree, key)
    if !found { ret 0usize }
    ret b.tree.nodes[at].child_count
}

fn bridge_key(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    let b = mem.cast[*Bridge](ctx)
    if parent == 0u64 { ret b.tree.nodes[usize(b.tree.kids[b.tree.root_first + index])].key }
    let (at, found) = find(b.tree, parent)
    if !found { ret 0u64 }
    ret b.tree.nodes[usize(b.tree.kids[b.tree.nodes[at].first_child + index])].key
}

fn bridge_has_children(ctx: *void, key: widget.Key) -> bool {
    if bridge_count(ctx, key) > 0usize { ret true }
    let b = mem.cast[*Bridge](ctx)
    let (at, found) = find(b.tree, key)
    ret found && b.tree.nodes[at].lazy
}

// Whether the folder `key` is an `Unloaded` one: its children are not listed yet.
fn is_lazy(t: *const Tree, key: widget.Key) -> bool {
    let (at, found) = find(t, key)
    ret found && t.nodes[at].lazy
}

// The keys of `expanded[0..n]` that are `Unloaded` folders, in order, into `out`: the folders
// the host should enumerate (and list again as `Loading`, then `Ready`, keeping their keys
// through `prev`); the count written, at most `out.len`.
fn pending(t: *const Tree, expanded: []const widget.Key, n: usize, out: []widget.Key) -> usize {
    var written = 0usize
    var i = 0usize
    while i < n && written < out.len {
        if is_lazy(t, expanded[i]) {
            out[written] = expanded[i]
            written += 1usize
        }
        i += 1usize
    }
    ret written
}

fn bridge_build(ctx: *void, a: *mem.Arena, key: widget.Key, out: *widget.Node) -> err {
    let b = mem.cast[*Bridge](ctx)
    let (at, found) = find(b.tree, key)
    if !found { ret Invalid }
    var label = name_of(b.tree, at)
    if b.tree.nodes[at].kind == .Loading { label = "Loading" }
    if b.tree.nodes[at].kind == .Failed { label = "Could not load" }
    var options = control.text_options()
    options.wrap = .None
    let (node, node_error) = control.text(a, key, label, b.theme, options)
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

fn source(b: *Bridge) -> collection.TreeSource {
    ret collection.TreeSource { ctx: mem.cast[*void](b), count: bridge_count, key: bridge_key, has_children: bridge_has_children, build: bridge_build }
}

// The visible rows of the tree with `expanded` open, through `collection.flatten`.
fn visible(b: *Bridge, expanded: []const widget.Key, out: []collection.TreeRow) -> usize {
    ret collection.flatten(source(b), expanded, 0u64, 0usize, out, 0usize)
}
