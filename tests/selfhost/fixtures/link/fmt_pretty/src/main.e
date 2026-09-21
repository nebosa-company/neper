// `e.fmt.pretty`: Wadler's tree example laid out at four widths against a Python replica of
// the algorithm, a document that pins the lazy lookahead (a later group measured as it will
// render, not flat), soft lines, and the two refusals. Each check exits with its own code.

use e.fmt.pretty
use e.io
use e.mem
use e.os
use e.str

fn tree_name(t: usize) -> str {
    if t == 0usize { ret "aaa" }
    if t == 1usize { ret "bbbbb" }
    if t == 2usize { ret "eee" }
    if t == 3usize { ret "ffff" }
    if t == 4usize { ret "ccc" }
    if t == 5usize { ret "dd" }
    if t == 6usize { ret "gg" }
    if t == 7usize { ret "hhh" }
    ret "ii"
}

fn tree_lo(t: usize) -> usize {
    if t == 0usize { ret 1usize }
    if t == 1usize { ret 4usize }
    if t == 3usize { ret 6usize }
    ret 0usize
}

fn tree_hi(t: usize) -> usize {
    if t == 0usize { ret 4usize }
    if t == 1usize { ret 6usize }
    if t == 3usize { ret 9usize }
    ret 0usize
}

// showTree (Node s ts) = group (text s <> nest (length s) (showBracket ts))
fn show_tree(p: *pretty.Pool, t: usize) -> (u32, err) {
    let name = tree_name(t)
    let (label, e1) = pretty.text(p, name)
    if e1 != ok { ret (0u32, e1) }
    let (bracket, e2) = show_bracket(p, t)
    if e2 != ok { ret (0u32, e2) }
    let (nested, e3) = pretty.nest(p, u32(name.len), bracket)
    if e3 != ok { ret (0u32, e3) }
    let (body, e4) = pretty.concat(p, label, nested)
    if e4 != ok { ret (0u32, e4) }
    let (g, e5) = pretty.group(p, body)
    ret (g, e5)
}

// showBracket [] = nil; showBracket ts = text "[" <> nest 1 (showTrees ts) <> text "]"
fn show_bracket(p: *pretty.Pool, t: usize) -> (u32, err) {
    if tree_lo(t) == tree_hi(t) { ret (0u32, ok) }
    let (open, e1) = pretty.text(p, "[")
    if e1 != ok { ret (0u32, e1) }
    let (inner, e2) = show_trees(p, tree_lo(t), tree_hi(t))
    if e2 != ok { ret (0u32, e2) }
    let (nested, e3) = pretty.nest(p, 1u32, inner)
    if e3 != ok { ret (0u32, e3) }
    let (close, e4) = pretty.text(p, "]")
    if e4 != ok { ret (0u32, e4) }
    let (tail, e5) = pretty.concat(p, nested, close)
    if e5 != ok { ret (0u32, e5) }
    let (whole, e6) = pretty.concat(p, open, tail)
    ret (whole, e6)
}

// showTrees [t] = showTree t; showTrees (t:ts) = showTree t <> text "," <> line <> showTrees ts
fn show_trees(p: *pretty.Pool, lo: usize, hi: usize) -> (u32, err) {
    let (head, e1) = show_tree(p, lo)
    if e1 != ok { ret (0u32, e1) }
    if lo + 1usize == hi { ret (head, ok) }
    let (comma, e2) = pretty.text(p, ",")
    if e2 != ok { ret (0u32, e2) }
    let (brk, e3) = pretty.line(p)
    if e3 != ok { ret (0u32, e3) }
    let (rest, e4) = show_trees(p, lo + 1usize, hi)
    if e4 != ok { ret (0u32, e4) }
    let (tail2, e5) = pretty.concat(p, brk, rest)
    if e5 != ok { ret (0u32, e5) }
    let (tail1, e6) = pretty.concat(p, comma, tail2)
    if e6 != ok { ret (0u32, e6) }
    let (whole, e7) = pretty.concat(p, head, tail1)
    ret (whole, e7)
}

fn render(p: *const pretty.Pool, root: u32, width: usize, out: []u8, stack: []pretty.Frame) -> str {
    let (n, e) = pretty.layout(p, root, width, out, stack)
    if e != ok { ret "<error>" }
    ret out[..n]
}

// "1" line "2" grouped, then "ab" line "cd" grouped.
fn pin_doc(p: *pretty.Pool) -> (u32, err) {
    let (t1, _) = pretty.text(p, "1")
    let (l1, _) = pretty.line(p)
    let (t2, _) = pretty.text(p, "2")
    let (c1, _) = pretty.concat(p, l1, t2)
    let (c2, _) = pretty.concat(p, t1, c1)
    let (g1, _) = pretty.group(p, c2)
    let (t3, _) = pretty.text(p, "ab")
    let (l2, _) = pretty.line(p)
    let (t4, _) = pretty.text(p, "cd")
    let (c3, _) = pretty.concat(p, l2, t4)
    let (c4, _) = pretty.concat(p, t3, c3)
    let (g2, _) = pretty.group(p, c4)
    let (whole, e) = pretty.concat(p, g1, g2)
    ret (whole, e)
}

// group("f(" <> nest(2, softline <> "arg1," <> line <> "arg2") <> softline <> ")")
fn call_doc(p: *pretty.Pool) -> (u32, err) {
    let (open, _) = pretty.text(p, "f(")
    let (s1, _) = pretty.soft_line(p)
    let (a1, _) = pretty.text(p, "arg1,")
    let (l1, _) = pretty.line(p)
    let (a2, _) = pretty.text(p, "arg2")
    let (c1, _) = pretty.concat(p, l1, a2)
    let (c2, _) = pretty.concat(p, a1, c1)
    let (c3, _) = pretty.concat(p, s1, c2)
    let (nested, _) = pretty.nest(p, 2u32, c3)
    let (s2, _) = pretty.soft_line(p)
    let (close, _) = pretty.text(p, ")")
    let (c4, _) = pretty.concat(p, s2, close)
    let (c5, _) = pretty.concat(p, nested, c4)
    let (c6, _) = pretty.concat(p, open, c5)
    let (g, e) = pretty.group(p, c6)
    ret (g, e)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var docs: [256]pretty.Doc = zero
    var out: [512]u8 = zero
    var stack: [128]pretty.Frame = zero
    let (pool, pool_error) = pretty.pool(docs[..])
    if pool_error != ok { os.exit(1i32) }
    var p = pool

    // 1: Wadler's tree at widths 80, 40, 20 and 10.
    let (tree, tree_error) = show_tree(&p, 0usize)
    if tree_error != ok { os.exit(1i32) }
    if !str.eq(render(&p, tree, 80usize, out[..], stack[..]), "aaa[bbbbb[ccc, dd], eee, ffff[gg, hhh, ii]]") { os.exit(2i32) }
    if !str.eq(render(&p, tree, 40usize, out[..], stack[..]), "aaa[bbbbb[ccc, dd],\n    eee,\n    ffff[gg, hhh, ii]]") { os.exit(3i32) }
    if !str.eq(render(&p, tree, 20usize, out[..], stack[..]), "aaa[bbbbb[ccc, dd],\n    eee,\n    ffff[gg,\n         hhh,\n         ii]]") { os.exit(4i32) }
    if !str.eq(render(&p, tree, 10usize, out[..], stack[..]), "aaa[bbbbb[ccc,\n          dd],\n    eee,\n    ffff[gg,\n         hhh,\n         ii]]") { os.exit(5i32) }

    // 2: the lazy lookahead: the second group breaks, so the first fits flat at width 6
    // (a strict measure would see "1 2ab cd" and break the first instead).
    let (pin, pin_error) = pin_doc(&p)
    if pin_error != ok { os.exit(6i32) }
    if !str.eq(render(&p, pin, 6usize, out[..], stack[..]), "1 2ab\ncd") { os.exit(6i32) }

    // 3: soft lines vanish when flat and break with the nest otherwise.
    let (call, call_error) = call_doc(&p)
    if call_error != ok { os.exit(7i32) }
    if !str.eq(render(&p, call, 20usize, out[..], stack[..]), "f(arg1, arg2)") { os.exit(7i32) }
    if !str.eq(render(&p, call, 12usize, out[..], stack[..]), "f(\n  arg1,\n  arg2\n)") { os.exit(8i32) }
    if !str.eq(render(&p, call, 8usize, out[..], stack[..]), "f(\n  arg1,\n  arg2\n)") { os.exit(8i32) }

    // 4: the empty document, and the refusals: a short output, a short stack, a bad root.
    let (empty_n, empty_error) = pretty.layout(&p, 0u32, 10usize, out[..], stack[..])
    if empty_error != ok || empty_n != 0usize { os.exit(9i32) }
    let (_, short_out) = pretty.layout(&p, tree, 80usize, out[..10usize], stack[..])
    if short_out != pretty.TooSmall { os.exit(10i32) }
    let (_, short_stack) = pretty.layout(&p, tree, 80usize, out[..], stack[..2usize])
    if short_stack != pretty.TooSmall { os.exit(11i32) }
    let (_, bad_root) = pretty.layout(&p, 9999u32, 80usize, out[..], stack[..])
    if bad_root != pretty.Invalid { os.exit(12i32) }
    let (_, bad_child) = pretty.group(&p, 9999u32)
    if bad_child != pretty.Invalid { os.exit(13i32) }
    var tiny: [2]pretty.Doc = zero
    let (small, _) = pretty.pool(tiny[..])
    var q = small
    let (_, first) = pretty.text(&q, "x")
    if first != ok { os.exit(14i32) }
    let (_, full) = pretty.text(&q, "y")
    if full != pretty.TooSmall { os.exit(14i32) }

    try io.print("fmt pretty ok\n")
    ret ok
}
