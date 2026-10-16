// `e.fmt.dom`: a parsed tree mutated through every operation -- creation, insertion (before a
// reference, of a fragment), removal, replacement, cloning, normalising -- with the refusals
// (a cycle, a non-child), attributes, the class list and dataset, text and markup in and
// out, the id, tag, class, selector and live-collection queries, and a TreeWalker. Each
// check has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.dom as dom
use e.fmt.html as html

fn options() -> html.Options {
    ret html.Options { max_bytes: 65536usize, max_nodes: 512usize, max_attributes: 32usize, max_depth: 32u16, preserve_comments: true }
}

fn same(x: str, y: str) -> bool { ret str.eq(x, y) }

fn attr(t: *const dom.Dom, id: dom.NodeId, name: str) -> str {
    let (value, _) = dom.get_attribute(t, id, name)
    ret value
}

fn main(a: *mem.Arena, args: []str) -> err {
    let source = "<!DOCTYPE html><div id=app class=\"a b\"><p>one</p><p class=x>two</p><!--c--><span data-foo-bar=1>three</span></div>"
    let (d, e0) = dom.parse(a, source, options(), 64usize)
    if e0 != ok { os.exit(1) }
    var tree = d
    let app = dom.get_element_by_id(&tree, tree.root, "app")
    if app == dom.NONE || !same(dom.name_of(&tree, app), "div") { os.exit(2) }
    if dom.get_element_by_id(&tree, tree.root, "nope") != dom.NONE { os.exit(3) }

    // Queries.
    var found: [8]dom.NodeId = zero
    if dom.elements_by_tag(&tree, app, "P", found[0..]) != 2usize { os.exit(4) }
    if dom.elements_by_tag(&tree, app, "*", found[0..]) != 3usize { os.exit(5) }
    if dom.elements_by_class(&tree, tree.root, "x", found[0..]) != 1usize || !same(dom.name_of(&tree, found[0usize]), "p") { os.exit(6) }
    let paragraphs = dom.Collection { kind: dom.CollectionTag, root: app, key: "p" }
    if dom.collection_len(&tree, paragraphs) != 2usize { os.exit(7) }
    let (hit, e1) = dom.query_selector(a, &tree, app, "div > p.x")
    if e1 != ok || hit != found[0usize] { os.exit(8) }
    let (count_all, e2) = dom.query_selector_all(a, &tree, tree.root, "p, span", found[0..])
    if e2 != ok || count_all != 3usize { os.exit(9) }
    let (is_match, e3) = dom.matches(a, &tree, hit, ".x")
    if e3 != ok || !is_match { os.exit(10) }
    let (up, e4) = dom.closest(a, &tree, hit, "#app")
    if e4 != ok || up != app { os.exit(11) }
    let (_, bad) = dom.query_selector(a, &tree, app, "p[")
    if bad != dom.SyntaxError { os.exit(12) }

    // Creation, insertion, a live collection.
    let version = tree.version
    let (fresh, e5) = dom.create_element(&tree, "P")
    if e5 != ok || !same(dom.name_of(&tree, fresh), "p") { os.exit(13) }
    let (words, e6) = dom.create_text(&tree, "zero")
    if e6 != ok || dom.append_child(&tree, fresh, words) != ok { os.exit(14) }
    let first_p = dom.first_element_child(&tree, app)
    if dom.insert_before(&tree, app, fresh, first_p) != ok { os.exit(15) }
    if dom.first_element_child(&tree, app) != fresh || dom.collection_len(&tree, paragraphs) != 3usize { os.exit(16) }
    if dom.collection_item(&tree, paragraphs, 0usize) != fresh || dom.collection_item(&tree, paragraphs, 3usize) != dom.NONE { os.exit(17) }
    if tree.version == version || dom.child_index(&tree, first_p) != 1usize { os.exit(18) }

    // Refusals.
    if dom.append_child(&tree, fresh, app) != dom.HierarchyRequest { os.exit(19) }
    if dom.remove_child(&tree, fresh, first_p) != dom.NotChild { os.exit(20) }
    if dom.insert_before(&tree, fresh, words, first_p) != dom.NotChild { os.exit(21) }

    // A fragment moves its children.
    let (frag, e7) = dom.create_fragment(&tree)
    if e7 != ok { os.exit(22) }
    let (s1, _) = dom.create_element(&tree, "i")
    let (s2, _) = dom.create_element(&tree, "b")
    if dom.append_child(&tree, frag, s1) != ok || dom.append_child(&tree, frag, s2) != ok { os.exit(23) }
    if dom.append_child(&tree, app, frag) != ok || dom.child_count(&tree, frag) != 0usize { os.exit(24) }
    if dom.last_element_child(&tree, app) != s2 || dom.previous_element_sibling(&tree, s2) != s1 { os.exit(25) }

    // Removal and replacement.
    dom.remove(&tree, s1)
    if dom.parent_of(&tree, s1) != dom.NONE || dom.is_connected(&tree, s1) || !dom.is_connected(&tree, s2) { os.exit(26) }
    if dom.replace_child(&tree, app, s1, s2) != ok || dom.parent_of(&tree, s1) != app || dom.parent_of(&tree, s2) != dom.NONE { os.exit(27) }

    // Attributes, the class list, the dataset.
    if !same(attr(&tree, app, "CLASS"), "a b") { os.exit(28) }
    if dom.set_attribute(&tree, app, "Title", "T") != ok { os.exit(29) }
    let (title, has_title) = dom.get_attribute(&tree, app, "title")
    if !has_title || !same(title, "T") || dom.attribute_count(&tree, app) != 3usize { os.exit(30) }
    if dom.set_attribute(&tree, app, "title", "U") != ok || !same(attr(&tree, app, "TITLE"), "U") || dom.attribute_count(&tree, app) != 3usize { os.exit(31) }
    if dom.remove_attribute(&tree, app, "title") != ok || dom.has_attribute(&tree, app, "title") { os.exit(32) }
    if !dom.class_contains(&tree, app, "b") || dom.class_contains(&tree, app, "c") { os.exit(33) }
    if dom.class_add(&tree, app, "c") != ok || !same(attr(&tree, app, "class"), "a b c") { os.exit(34) }
    if dom.class_remove(&tree, app, "b") != ok || !same(attr(&tree, app, "class"), "a c") { os.exit(35) }
    let (present, e8) = dom.class_toggle(&tree, app, "a")
    if e8 != ok || present || !same(attr(&tree, app, "class"), "c") { os.exit(36) }
    var spans: [4]dom.NodeId = zero
    if dom.elements_by_tag(&tree, app, "span", spans[0..]) != 1usize { os.exit(37) }
    let (foo, has_foo, e9) = dom.dataset_get(a, &tree, spans[0usize], "fooBar")
    if e9 != ok || !has_foo || !same(foo, "1") { os.exit(38) }
    if dom.dataset_set(&tree, spans[0usize], "bazQux", "2") != ok || !same(attr(&tree, spans[0usize], "data-baz-qux"), "2") { os.exit(39) }
    if dom.dataset_remove(&tree, spans[0usize], "fooBar") != ok || dom.has_attribute(&tree, spans[0usize], "data-foo-bar") { os.exit(40) }

    // Text and markup.
    let (txt, e10) = dom.text_content(a, &tree, app)
    if e10 != ok || !same(txt, "zeroonetwothree") { os.exit(41) }
    if dom.set_text_content(&tree, spans[0usize], "x<y") != ok { os.exit(42) }
    let (outer, e11) = dom.outer_html(a, &tree, spans[0usize])
    if e11 != ok || !same(outer, "<span data-baz-qux=\"2\">x&lt;y</span>") { os.exit(43) }
    if dom.set_inner_html(&tree, spans[0usize], "<b>k</b>m", options()) != ok { os.exit(44) }
    let (inner, e12) = dom.inner_html(a, &tree, spans[0usize])
    if e12 != ok || !same(inner, "<b>k</b>m") { os.exit(45) }

    // Cloning and normalising.
    let before = tree.used
    let (copy, e13) = dom.clone_node(&tree, spans[0usize], true)
    if e13 != ok || tree.used != before + 4usize || dom.parent_of(&tree, copy) != dom.NONE { os.exit(46) }
    let (t1, _) = dom.create_text(&tree, "a")
    let (t2, _) = dom.create_text(&tree, "")
    let (t3, _) = dom.create_text(&tree, "b")
    if dom.append_child(&tree, copy, t1) != ok || dom.append_child(&tree, copy, t2) != ok || dom.append_child(&tree, copy, t3) != ok { os.exit(47) }
    if dom.normalize(&tree, copy) != ok { os.exit(48) }
    let (merged, _) = dom.inner_html(a, &tree, copy)
    if !same(merged, "<b>k</b>mab") { os.exit(49) }

    // A TreeWalker over the elements.
    var w = dom.walker(app, dom.ShowElement)
    var walked = 0usize
    while dom.walker_next(&tree, &w) != dom.NONE { walked += 1usize }
    if walked != 6usize { os.exit(50) }
    var back = 0usize
    while dom.walker_previous(&tree, &w) != dom.NONE { back += 1usize }
    if back != 5usize { os.exit(51) }
    var w2 = dom.walker(app, dom.ShowElement)
    let kid = dom.walker_child(&tree, &w2, false)
    if kid != fresh || dom.walker_sibling(&tree, &w2, false) != first_p { os.exit(52) }
    ret ok
}
