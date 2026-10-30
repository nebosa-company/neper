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
    let (_, pseudo_query_error) = dom.query_selector(a, &tree, app, "p::before")
    let (_, pseudo_all_error) = dom.query_selector_all(a, &tree, tree.root, "p::before", found[0..])
    let (_, pseudo_matches_error) = dom.matches(a, &tree, hit, "p::before")
    let (_, pseudo_closest_error) = dom.closest(a, &tree, hit, "p::before")
    if pseudo_query_error != dom.SyntaxError || pseudo_all_error != dom.SyntaxError || pseudo_matches_error != dom.SyntaxError || pseudo_closest_error != dom.SyntaxError { os.exit(53) }

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
    if dom.class_add(&tree, app, "") != dom.SyntaxError || dom.class_add(&tree, app, "c d") != dom.InvalidCharacter { os.exit(54) }
    if dom.class_remove(&tree, app, "") != dom.SyntaxError || dom.class_remove(&tree, app, "\t") != dom.InvalidCharacter { os.exit(55) }
    let (invalid_present, invalid_toggle_error) = dom.class_toggle(&tree, app, " ")
    if invalid_present || invalid_toggle_error != dom.InvalidCharacter || !same(attr(&tree, app, "class"), "c") { os.exit(56) }
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
    let root_version = tree.version
    let root_first = dom.first_child(&tree, tree.root)
    let root_children = dom.child_count(&tree, tree.root)
    if dom.set_text_content(&tree, tree.root, "must not replace the document") != ok { os.exit(57) }
    if tree.version != root_version || dom.first_child(&tree, tree.root) != root_first || dom.child_count(&tree, tree.root) != root_children { os.exit(58) }
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

    // Root-document insertions must preserve the DOM child sequence atomically.
    var doctype = dom.NONE
    var scan = 0usize
    while scan < tree.used {
        let id = u32(scan)
        if dom.kind_of(&tree, id) == .Doctype { doctype = id }
        scan += 1usize
    }
    if doctype == dom.NONE { os.exit(59) }
    let doctype_version = tree.version
    let doctype_first = dom.first_child(&tree, tree.root)
    if dom.append_child(&tree, tree.root, doctype) != dom.HierarchyRequest { os.exit(60) }
    if tree.version != doctype_version || dom.first_child(&tree, tree.root) != doctype_first || dom.parent_of(&tree, doctype) != tree.root { os.exit(61) }
    let root_element = dom.first_element_child(&tree, tree.root)
    if root_element == dom.NONE { os.exit(79) }
    let reorder_version = tree.version
    if dom.insert_before(&tree, tree.root, root_element, doctype) != dom.HierarchyRequest { os.exit(80) }
    if tree.version != reorder_version || dom.first_child(&tree, tree.root) != doctype { os.exit(81) }
    let (second_doctype, second_doctype_error) = dom.clone_node(&tree, doctype, false)
    if second_doctype_error != ok { os.exit(62) }
    let second_doctype_version = tree.version
    if dom.insert_before(&tree, tree.root, second_doctype, doctype) != dom.HierarchyRequest { os.exit(63) }
    if tree.version != second_doctype_version || dom.parent_of(&tree, second_doctype) != dom.NONE { os.exit(64) }

    let (made, made_error) = dom.new_document(a, 16usize)
    if made_error != ok { os.exit(65) }
    var single = made
    let (one_root, one_root_error) = dom.create_element(&single, "one")
    let (two_root, two_root_error) = dom.create_element(&single, "two")
    if one_root_error != ok || two_root_error != ok || dom.append_child(&single, single.root, one_root) != ok { os.exit(66) }
    let single_version = single.version
    if dom.append_child(&single, single.root, two_root) != dom.HierarchyRequest { os.exit(67) }
    if single.version != single_version || dom.first_child(&single, single.root) != one_root || dom.parent_of(&single, two_root) != dom.NONE { os.exit(68) }

    let (fragment_made, fragment_made_error) = dom.new_document(a, 16usize)
    if fragment_made_error != ok { os.exit(69) }
    var fragment_doc = fragment_made
    let (two_roots, two_roots_error) = dom.create_fragment(&fragment_doc)
    let (fragment_one, fragment_one_error) = dom.create_element(&fragment_doc, "one")
    let (fragment_two, fragment_two_error) = dom.create_element(&fragment_doc, "two")
    if two_roots_error != ok || fragment_one_error != ok || fragment_two_error != ok || dom.append_child(&fragment_doc, two_roots, fragment_one) != ok || dom.append_child(&fragment_doc, two_roots, fragment_two) != ok { os.exit(70) }
    let fragment_version = fragment_doc.version
    if dom.append_child(&fragment_doc, fragment_doc.root, two_roots) != dom.HierarchyRequest { os.exit(71) }
    if fragment_doc.version != fragment_version || dom.child_count(&fragment_doc, two_roots) != 2usize || dom.parent_of(&fragment_doc, fragment_one) != two_roots { os.exit(72) }
    let (text_fragment, text_fragment_error) = dom.create_fragment(&fragment_doc)
    let (fragment_text, fragment_text_error) = dom.create_text(&fragment_doc, "not a document child")
    if text_fragment_error != ok || fragment_text_error != ok || dom.append_child(&fragment_doc, text_fragment, fragment_text) != ok { os.exit(82) }
    let text_fragment_version = fragment_doc.version
    if dom.append_child(&fragment_doc, fragment_doc.root, text_fragment) != dom.HierarchyRequest { os.exit(83) }
    if fragment_doc.version != text_fragment_version || dom.first_child(&fragment_doc, text_fragment) != fragment_text { os.exit(84) }

    let (replacement_made, replacement_made_error) = dom.new_document(a, 16usize)
    if replacement_made_error != ok { os.exit(73) }
    var replacement_doc = replacement_made
    let (old_root, old_root_error) = dom.create_element(&replacement_doc, "old")
    let (new_root, new_root_error) = dom.create_element(&replacement_doc, "new")
    if old_root_error != ok || new_root_error != ok || dom.append_child(&replacement_doc, replacement_doc.root, old_root) != ok { os.exit(74) }
    if dom.replace_child(&replacement_doc, replacement_doc.root, new_root, old_root) != ok || dom.first_child(&replacement_doc, replacement_doc.root) != new_root || dom.parent_of(&replacement_doc, old_root) != dom.NONE { os.exit(75) }
    let (replacement_fragment, replacement_fragment_error) = dom.create_fragment(&replacement_doc)
    let (replacement_one, replacement_one_error) = dom.create_element(&replacement_doc, "one")
    let (replacement_two, replacement_two_error) = dom.create_element(&replacement_doc, "two")
    if replacement_fragment_error != ok || replacement_one_error != ok || replacement_two_error != ok || dom.append_child(&replacement_doc, replacement_fragment, replacement_one) != ok || dom.append_child(&replacement_doc, replacement_fragment, replacement_two) != ok { os.exit(76) }
    let replacement_version = replacement_doc.version
    if dom.replace_child(&replacement_doc, replacement_doc.root, replacement_fragment, new_root) != dom.HierarchyRequest { os.exit(77) }
    if replacement_doc.version != replacement_version || dom.first_child(&replacement_doc, replacement_doc.root) != new_root || dom.child_count(&replacement_doc, replacement_fragment) != 2usize { os.exit(78) }
    ret ok
}
