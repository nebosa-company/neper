// `e.fmt.css`: a sixteen-element tree, thirty-five selectors whose match sets agree with
// lxml.cssselect, specificity per the Selectors spec examples, the cascade over twelve
// declarations, and the refusals a malformed selector earns. Each check exits with its own
// code.

use e.fmt.css
use e.io
use e.mem
use e.os

fn expect(d: *const css.Dom, selector: str, mask: u32) -> bool {
    var out: [16]u32 = zero
    let (n, e) = css.select(d, selector, out[..])
    if e != ok { ret false }
    var got = 0u32
    var i = 0usize
    while i < n {
        got |= 1u32 << out[i]
        i += 1usize
    }
    ret got == mask
}

fn spec_is(selector: str, wanted: u32) -> bool {
    let (got, e) = css.specificity(selector)
    ret e == ok && got == wanted
}

fn refused(d: *const css.Dom, selector: str) -> bool {
    var out: [16]u32 = zero
    let (_, e) = css.select(d, selector, out[..])
    ret e == css.Invalid
}

fn main(a: *mem.Arena, args: []str) -> err {
    var elements: [16]css.Element = zero
    var classes: [12]str = zero
    var attributes: [7]css.Attribute = zero
    elements[0usize] = css.Element { tag: "html", id: "", class_lo: 0u32, class_hi: 0u32, attr_lo: 0u32, attr_hi: 0u32, parent: css.NONE, prev: css.NONE }
    elements[1usize] = css.Element { tag: "body", id: "", class_lo: 0u32, class_hi: 0u32, attr_lo: 0u32, attr_hi: 0u32, parent: 0u32, prev: css.NONE }
    elements[2usize] = css.Element { tag: "div", id: "main", class_lo: 0u32, class_hi: 2u32, attr_lo: 0u32, attr_hi: 0u32, parent: 1u32, prev: css.NONE }
    elements[3usize] = css.Element { tag: "h1", id: "", class_lo: 2u32, class_hi: 2u32, attr_lo: 0u32, attr_hi: 0u32, parent: 2u32, prev: css.NONE }
    elements[4usize] = css.Element { tag: "p", id: "", class_lo: 2u32, class_hi: 3u32, attr_lo: 0u32, attr_hi: 1u32, parent: 2u32, prev: 3u32 }
    elements[5usize] = css.Element { tag: "p", id: "", class_lo: 3u32, class_hi: 3u32, attr_lo: 1u32, attr_hi: 2u32, parent: 2u32, prev: 4u32 }
    elements[6usize] = css.Element { tag: "ul", id: "list", class_lo: 3u32, class_hi: 3u32, attr_lo: 2u32, attr_hi: 2u32, parent: 2u32, prev: 5u32 }
    elements[7usize] = css.Element { tag: "li", id: "", class_lo: 3u32, class_hi: 5u32, attr_lo: 2u32, attr_hi: 2u32, parent: 6u32, prev: css.NONE }
    elements[8usize] = css.Element { tag: "li", id: "", class_lo: 5u32, class_hi: 6u32, attr_lo: 2u32, attr_hi: 3u32, parent: 6u32, prev: 7u32 }
    elements[9usize] = css.Element { tag: "li", id: "", class_lo: 6u32, class_hi: 8u32, attr_lo: 3u32, attr_hi: 3u32, parent: 6u32, prev: 8u32 }
    elements[10usize] = css.Element { tag: "li", id: "", class_lo: 8u32, class_hi: 9u32, attr_lo: 3u32, attr_hi: 4u32, parent: 6u32, prev: 9u32 }
    elements[11usize] = css.Element { tag: "div", id: "", class_lo: 9u32, class_hi: 10u32, attr_lo: 4u32, attr_hi: 4u32, parent: 1u32, prev: 2u32 }
    elements[12usize] = css.Element { tag: "a", id: "", class_lo: 10u32, class_hi: 10u32, attr_lo: 4u32, attr_hi: 5u32, parent: 11u32, prev: css.NONE }
    elements[13usize] = css.Element { tag: "span", id: "", class_lo: 10u32, class_hi: 11u32, attr_lo: 5u32, attr_hi: 5u32, parent: 11u32, prev: 12u32 }
    elements[14usize] = css.Element { tag: "a", id: "", class_lo: 11u32, class_hi: 11u32, attr_lo: 5u32, attr_hi: 6u32, parent: 11u32, prev: 13u32 }
    elements[15usize] = css.Element { tag: "section", id: "", class_lo: 11u32, class_hi: 12u32, attr_lo: 6u32, attr_hi: 7u32, parent: 1u32, prev: 11u32 }
    classes[0usize] = "container"
    classes[1usize] = "wide"
    classes[2usize] = "intro"
    classes[3usize] = "item"
    classes[4usize] = "first"
    classes[5usize] = "item"
    classes[6usize] = "item"
    classes[7usize] = "odd"
    classes[8usize] = "item"
    classes[9usize] = "footer"
    classes[10usize] = "note"
    classes[11usize] = "wide"
    attributes[0usize] = css.Attribute { name: "data-x", value: "1" }
    attributes[1usize] = css.Attribute { name: "lang", value: "en-US" }
    attributes[2usize] = css.Attribute { name: "data-k", value: "alpha beta" }
    attributes[3usize] = css.Attribute { name: "title", value: "x y" }
    attributes[4usize] = css.Attribute { name: "href", value: "https://example.test/page" }
    attributes[5usize] = css.Attribute { name: "href", value: "mailto:me" }
    attributes[6usize] = css.Attribute { name: "lang", value: "en" }
    let d = css.Dom { elements: elements[..], classes: classes[..], attributes: attributes[..] }

    // 1..: every selector answers the match set lxml.cssselect answers (as a bitmask).
    if !expect(&d, "*", 65535u32) { os.exit(1i32) }
    if !expect(&d, "li", 1920u32) { os.exit(2i32) }
    if !expect(&d, "ul li", 1920u32) { os.exit(3i32) }
    if !expect(&d, "div > p", 48u32) { os.exit(4i32) }
    if !expect(&d, "#main", 4u32) { os.exit(5i32) }
    if !expect(&d, ".item", 1920u32) { os.exit(6i32) }
    if !expect(&d, "li.item.odd", 512u32) { os.exit(7i32) }
    if !expect(&d, "h1 + p", 16u32) { os.exit(8i32) }
    if !expect(&d, "h1 ~ p", 48u32) { os.exit(9i32) }
    if !expect(&d, "p + p", 32u32) { os.exit(10i32) }
    if !expect(&d, "li:first-child", 128u32) { os.exit(11i32) }
    if !expect(&d, "li:nth-child(2)", 256u32) { os.exit(12i32) }
    if !expect(&d, "li:nth-child(odd)", 640u32) { os.exit(13i32) }
    if !expect(&d, "li:nth-child(even)", 1280u32) { os.exit(14i32) }
    if !expect(&d, "li:nth-child(2n+1)", 640u32) { os.exit(15i32) }
    if !expect(&d, "li:nth-child(-n+2)", 384u32) { os.exit(16i32) }
    if !expect(&d, "li:nth-child(n+3)", 1536u32) { os.exit(17i32) }
    if !expect(&d, "[data-x]", 16u32) { os.exit(18i32) }
    if !expect(&d, "[data-x=\"1\"]", 16u32) { os.exit(19i32) }
    if !expect(&d, "[lang|=en]", 32800u32) { os.exit(20i32) }
    if !expect(&d, "[data-k~=beta]", 256u32) { os.exit(21i32) }
    if !expect(&d, "a[href^=https]", 4096u32) { os.exit(22i32) }
    if !expect(&d, "a[href$=\"page\"]", 4096u32) { os.exit(23i32) }
    if !expect(&d, "a[href*='ample']", 4096u32) { os.exit(24i32) }
    if !expect(&d, "div.footer > a", 20480u32) { os.exit(25i32) }
    if !expect(&d, "body > div span", 8192u32) { os.exit(26i32) }
    if !expect(&d, "div div", 0u32) { os.exit(27i32) }
    if !expect(&d, ".container.wide", 4u32) { os.exit(28i32) }
    if !expect(&d, "li, h1", 1928u32) { os.exit(29i32) }
    if !expect(&d, "html > body > div#main > ul > li.item:nth-child(3)", 512u32) { os.exit(30i32) }
    if !expect(&d, "[title=\"x y\"]", 1024u32) { os.exit(31i32) }
    if !expect(&d, "p:first-child", 0u32) { os.exit(32i32) }
    if !expect(&d, "body *:first-child", 4236u32) { os.exit(33i32) }
    if !expect(&d, "div#main>p+p", 32u32) { os.exit(34i32) }
    if !expect(&d, "ul ~ div a", 0u32) { os.exit(35i32) }

    // Specificity, the spec examples included.
    if !spec_is("*", 0u32) { os.exit(36i32) }
    if !spec_is("li", 1u32) { os.exit(37i32) }
    if !spec_is("ul li", 2u32) { os.exit(38i32) }
    if !spec_is("div > p", 2u32) { os.exit(39i32) }
    if !spec_is("#main", 65536u32) { os.exit(40i32) }
    if !spec_is(".item", 256u32) { os.exit(41i32) }
    if !spec_is("li.item.odd", 513u32) { os.exit(42i32) }
    if !spec_is("h1 + p", 2u32) { os.exit(43i32) }
    if !spec_is("h1 ~ p", 2u32) { os.exit(44i32) }
    if !spec_is("p + p", 2u32) { os.exit(45i32) }
    if !spec_is("li:first-child", 257u32) { os.exit(46i32) }
    if !spec_is("li:nth-child(2)", 257u32) { os.exit(47i32) }
    if !spec_is("li:nth-child(odd)", 257u32) { os.exit(48i32) }
    if !spec_is("li:nth-child(even)", 257u32) { os.exit(49i32) }
    if !spec_is("li:nth-child(2n+1)", 257u32) { os.exit(50i32) }
    if !spec_is("li:nth-child(-n+2)", 257u32) { os.exit(51i32) }
    if !spec_is("li:nth-child(n+3)", 257u32) { os.exit(52i32) }
    if !spec_is("[data-x]", 256u32) { os.exit(53i32) }
    if !spec_is("[data-x=\"1\"]", 256u32) { os.exit(54i32) }
    if !spec_is("[lang|=en]", 256u32) { os.exit(55i32) }
    if !spec_is("[data-k~=beta]", 256u32) { os.exit(56i32) }
    if !spec_is("a[href^=https]", 257u32) { os.exit(57i32) }
    if !spec_is("a[href$=\"page\"]", 257u32) { os.exit(58i32) }
    if !spec_is("a[href*='ample']", 257u32) { os.exit(59i32) }
    if !spec_is("div.footer > a", 258u32) { os.exit(60i32) }
    if !spec_is("body > div span", 3u32) { os.exit(61i32) }
    if !spec_is("div div", 2u32) { os.exit(62i32) }
    if !spec_is(".container.wide", 512u32) { os.exit(63i32) }
    if !spec_is("li, h1", 1u32) { os.exit(64i32) }
    if !spec_is("html > body > div#main > ul > li.item:nth-child(3)", 66053u32) { os.exit(65i32) }
    if !spec_is("[title=\"x y\"]", 256u32) { os.exit(66i32) }
    if !spec_is("p:first-child", 257u32) { os.exit(67i32) }
    if !spec_is("body *:first-child", 257u32) { os.exit(68i32) }
    if !spec_is("div#main>p+p", 65539u32) { os.exit(69i32) }
    if !spec_is("ul ~ div a", 3u32) { os.exit(70i32) }
    if !spec_is("*", 0u32) { os.exit(71i32) }
    if !spec_is("li", 1u32) { os.exit(72i32) }
    if !spec_is("ul li", 2u32) { os.exit(73i32) }
    if !spec_is("ul ol+li", 3u32) { os.exit(74i32) }
    if !spec_is("h1 + *[rel=up]", 257u32) { os.exit(75i32) }
    if !spec_is("ul ol li.red", 259u32) { os.exit(76i32) }
    if !spec_is("li.red.level", 513u32) { os.exit(77i32) }
    if !spec_is("#x34y", 65536u32) { os.exit(78i32) }
    if !spec_is("li, #x", 65536u32) { os.exit(79i32) }
    if !spec_is("a:nth-child(2n+1)", 257u32) { os.exit(80i32) }

    // The cascade over twelve declarations, lowest precedence first.
    var decls: [12]css.Decl = zero
    decls[0usize] = css.Decl { origin: .User, important: false, specificity: 257u32, order: 0u32 }
    decls[1usize] = css.Decl { origin: .Author, important: true, specificity: 513u32, order: 1u32 }
    decls[2usize] = css.Decl { origin: .Author, important: true, specificity: 65536u32, order: 2u32 }
    decls[3usize] = css.Decl { origin: .UserAgent, important: false, specificity: 1u32, order: 3u32 }
    decls[4usize] = css.Decl { origin: .UserAgent, important: true, specificity: 257u32, order: 4u32 }
    decls[5usize] = css.Decl { origin: .UserAgent, important: true, specificity: 65536u32, order: 5u32 }
    decls[6usize] = css.Decl { origin: .User, important: true, specificity: 65536u32, order: 6u32 }
    decls[7usize] = css.Decl { origin: .UserAgent, important: false, specificity: 65537u32, order: 7u32 }
    decls[8usize] = css.Decl { origin: .Author, important: false, specificity: 0u32, order: 8u32 }
    decls[9usize] = css.Decl { origin: .Author, important: false, specificity: 0u32, order: 9u32 }
    decls[10usize] = css.Decl { origin: .UserAgent, important: true, specificity: 513u32, order: 10u32 }
    decls[11usize] = css.Decl { origin: .UserAgent, important: true, specificity: 1u32, order: 11u32 }
    var order: [12]u32 = zero
    if css.cascade(decls[..], order[..]) != ok { os.exit(81i32) }
    if order[0usize] != 3u32 { os.exit(81i32) }
    if order[1usize] != 7u32 { os.exit(81i32) }
    if order[2usize] != 0u32 { os.exit(81i32) }
    if order[3usize] != 8u32 { os.exit(81i32) }
    if order[4usize] != 9u32 { os.exit(81i32) }
    if order[5usize] != 1u32 { os.exit(81i32) }
    if order[6usize] != 2u32 { os.exit(81i32) }
    if order[7usize] != 6u32 { os.exit(81i32) }
    if order[8usize] != 11u32 { os.exit(81i32) }
    if order[9usize] != 4u32 { os.exit(81i32) }
    if order[10usize] != 10u32 { os.exit(81i32) }
    if order[11usize] != 5u32 { os.exit(81i32) }

    // Refusals: empty, a dangling combinator, an unclosed bracket, an unknown pseudo-class,
    // a bad nth argument, a stray byte, and an output that is too small.
    if !refused(&d, "") { os.exit(82i32) }
    if !refused(&d, "> p") { os.exit(83i32) }
    if !refused(&d, "a[href") { os.exit(84i32) }
    if !refused(&d, "li:last-child") { os.exit(85i32) }
    if !refused(&d, "li:nth-child(2x+1)") { os.exit(86i32) }
    if !refused(&d, "li!") { os.exit(87i32) }
    var two: [2]u32 = zero
    let (_, small) = css.select(&d, "li", two[..])
    if small != css.TooSmall { os.exit(88i32) }
    let (_, bad_spec) = css.specificity("li, ")
    if bad_spec != css.Invalid { os.exit(89i32) }

    try io.print("fmt css ok\n")
    ret ok
}
