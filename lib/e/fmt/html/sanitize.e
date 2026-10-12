// HTML sanitizer (L132), the ammonia model over the `e.fmt.html` parser: untrusted markup is
// parsed into a tree and written back from it, keeping only what a `Policy` names.
//
//   - an element not on the tag allowlist is dropped and its children kept (`<form>`, `<b>`
//     if unlisted, `<html>`, `<body>`); an element on the remove list (`script`, `style` by
//     default) is dropped with everything in it;
//   - an attribute survives only if the policy lists it for that tag or for every tag, and
//     never when its name begins with `on`; attributes that hold URLs (`href`, `src`, `cite`,
//     ...) also need a value whose scheme is on the allowlist or that is relative, judged the
//     way a browser reads it (leading control characters and spaces trimmed, tabs and newlines
//     inside removed, entities already decoded by the parser); a refused value drops the attribute;
//   - `style` is allowed only through a property allowlist, and a declaration whose value has
//     `url(`, `expression(`, `javascript:`, `@`, a backslash, a comment or `<` is dropped;
//   - comments, doctype and processing are dropped; text and attribute values are re-escaped,
//     so what comes out parses back to the tree it was written from;
//   - links get `rel="noopener noreferrer"` (the policy's `link_rel`), replacing any `rel`.
//
// `default_policy` is ammonia's: its tag, attribute and URL-scheme lists, relative URLs
// allowed, `script` and `style` removed with their content, no `style` attribute.
//
// Not here: a different parser (the one in `e.fmt.html` leaves out the adoption agency, foster
// parenting and `tbody` insertion, so mis-nested formatting and a `table` with bare rows
// come out as the tree it builds, which is still safe but is not what ammonia gives),
// `srcset` (always dropped), attribute-value allowlists (`tag_attribute_values`), URL rewriting,
// and an `Err` for nesting past the policy depth rather than a truncated result.
//
// Memory: the result lives in the arena passed in.
use e.mem
use e.str
use e.fmt.html as html

error Encoding
error TooLarge
error TooDeep

type Policy = struct {
    tags: str,
    generic_attributes: str,
    tag_attributes: str,
    url_schemes: str,
    remove_content: str,
    css_properties: str,
    link_rel: str,
    allow_relative: bool,
    max_depth: u16,
}

// ---- policy ------------------------------------------------------------------------------

// Tokens are separated by single spaces: tags by name, tag attributes as `tag:attribute`.
fn default_policy() -> Policy {
    ret Policy {
        tags: "a abbr acronym area article aside b bdi bdo blockquote br caption center cite code col colgroup data dd del details dfn div dl dt em figcaption figure footer h1 h2 h3 h4 h5 h6 header hgroup hr i img ins kbd li map mark nav ol p pre q rp rt rtc ruby s samp small span strike strong sub summary sup table tbody td th thead time tr tt u ul var wbr",
        generic_attributes: "lang title",
        tag_attributes: "bdo:dir col:charoff col:char col:align col:span td:colspan td:char td:align td:charoff td:headers td:rowspan tfoot:charoff tfoot:char tfoot:align tr:charoff tr:char tr:align blockquote:cite ol:start del:datetime del:cite tbody:charoff tbody:char tbody:align img:height img:alt img:align img:width img:src th:rowspan th:scope th:align th:char th:charoff th:headers th:colspan table:charoff table:char table:align table:summary q:cite hr:size hr:align hr:width ins:datetime ins:cite colgroup:charoff colgroup:char colgroup:align colgroup:span thead:charoff thead:char thead:align a:hreflang a:href",
        url_schemes: "bitcoin ftp ftps geo http https im irc ircs magnet mailto mms mx news nntp openpgp4fpr sip sms smsto ssh tel url webcal wtai xmpp",
        remove_content: "script style",
        css_properties: "",
        link_rel: "noopener noreferrer",
        allow_relative: true,
        max_depth: 64u16,
    }
}

fn has_token(list: str, token: str) -> bool {
    if token.len == 0usize { ret false }
    var i = 0usize
    while i < list.len {
        var j = i
        while j < list.len && list[j] != 32u8 { j += 1usize }
        if j - i == token.len {
            var same = true
            var k = 0usize
            while k < token.len {
                if list[i + k] != token[k] { same = false }
                k += 1usize
            }
            if same { ret true }
        }
        i = j + 1usize
    }
    ret false
}

// Whether `tag:name` is in a policy's tag attribute list; `joined` is built by the caller.
fn tag_attribute_allowed(policy: Policy, tag: str, name: str) -> bool {
    var i = 0usize
    let list = policy.tag_attributes
    while i < list.len {
        var j = i
        while j < list.len && list[j] != 32u8 { j += 1usize }
        // list[i..j] is `tag:name`.
        let want = tag.len + 1usize + name.len
        if j - i == want {
            var same = true
            var k = 0usize
            while k < tag.len {
                if list[i + k] != tag[k] { same = false }
                k += 1usize
            }
            if list[i + tag.len] != 58u8 { same = false }
            k = 0usize
            while k < name.len {
                if list[i + tag.len + 1usize + k] != name[k] { same = false }
                k += 1usize
            }
            if same { ret true }
        }
        i = j + 1usize
    }
    ret false
}

fn is_url_attribute(name: str) -> bool {
    ret str.eq(name, "href") || str.eq(name, "src") || str.eq(name, "cite") || str.eq(name, "action") || str.eq(name, "formaction") || str.eq(name, "poster") || str.eq(name, "background") || str.eq(name, "longdesc") || str.eq(name, "usemap") || str.eq(name, "data") || str.eq(name, "manifest") || str.eq(name, "codebase") || str.eq(name, "ping") || str.eq(name, "profile") || str.eq(name, "icon") || str.eq(name, "dynsrc") || str.eq(name, "lowsrc")
}

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// Whether a URL value may be kept: its scheme, read as a browser reads it, is on the list, or
// it is relative and the policy allows those.
fn url_allowed(value: str, policy: Policy) -> bool {
    var start = 0usize
    while start < value.len && (value[start] <= 32u8) { start += 1usize }
    var end = value.len
    while end > start && value[end - 1usize] <= 32u8 { end -= 1usize }
    // The scheme: letters, digits, + - . up to a colon; tab, newline and carriage return are
    // ignored wherever they stand.
    var scheme: [32]u8 = zero
    var n = 0usize
    var i = start
    while i < end {
        let c = value[i]
        if c == 9u8 || c == 10u8 || c == 13u8 {
            i += 1usize
            continue
        }
        if c == 0u8 { ret false }
        if c == 58u8 {
            // A scheme only when it starts with a letter and is made of scheme characters.
            if n == 0usize { ret false }
            let first = scheme[0usize]
            if !(first >= 97u8 && first <= 122u8) { ret policy.allow_relative }
            let text = scheme[0usize..n]
            ret has_token(policy.url_schemes, text)
        }
        let l = lower(c)
        let ok_char = (l >= 97u8 && l <= 122u8) || (l >= 48u8 && l <= 57u8) || l == 43u8 || l == 45u8 || l == 46u8
        if !ok_char {
            // A path, query, fragment or any other character first: relative.
            ret policy.allow_relative
        }
        if n >= 31usize { ret policy.allow_relative }
        scheme[n] = l
        n += 1usize
        i += 1usize
    }
    ret policy.allow_relative
}

// ---- output ------------------------------------------------------------------------------

fn push_text(b: *str.Builder, s: str, attribute: bool) -> err {
    var i = 0usize
    var from = 0usize
    while i < s.len {
        let c = s[i]
        var rep = ""
        var skip = 1usize
        if c == 38u8 {
            rep = "&amp;"
        } else if c == 60u8 {
            rep = "&lt;"
        } else if c == 62u8 {
            rep = "&gt;"
        } else if c == 34u8 && attribute {
            rep = "&quot;"
        } else if c == 194u8 && i + 1usize < s.len && s[i + 1usize] == 160u8 {
            rep = "&nbsp;"
            skip = 2usize
        }
        if rep.len > 0usize {
            try str.push(b, s[from..i])
            try str.push(b, rep)
            from = i + skip
            i += skip
            continue
        }
        i += 1usize
    }
    ret str.push(b, s[from..s.len])
}

fn is_void(name: str) -> bool {
    ret str.eq(name, "br") || str.eq(name, "hr") || str.eq(name, "img") || str.eq(name, "wbr") || str.eq(name, "col") || str.eq(name, "area")
}

// The declarations of a style value the policy lets through: whether there is one, and, when
// `emit`, them written to `b` as `prop: value; ...` (escaped for an attribute).
fn style_walk(b: *str.Builder, value: str, policy: Policy, emit: bool) -> (bool, err) {
    if policy.css_properties.len == 0usize { ret (false, ok) }
    var any = false
    var at = 0usize
    while at <= value.len {
        var end = at
        while end < value.len && value[end] != 59u8 { end += 1usize }
        let decl = value[at..end]
        let (colon, has_colon) = str.find(decl, ":")
        if has_colon {
            let prop = str.trim(decl[0usize..colon])
            let val = str.trim(decl[colon + 1usize..decl.len])
            var prop_ok = prop.len > 0usize
            var k = 0usize
            while k < prop.len {
                let c = prop[k]
                if !((c >= 97u8 && c <= 122u8) || c == 45u8) { prop_ok = false }
                k += 1usize
            }
            var bad = !prop_ok || val.len == 0usize || !has_token(policy.css_properties, prop)
            var j = 0usize
            while j < val.len && !bad {
                let c = val[j]
                if c == 92u8 || c == 64u8 || c == 60u8 || c == 62u8 || c == 123u8 || c == 125u8 || c < 32u8 { bad = true }
                if j + 1usize < val.len && c == 47u8 && val[j + 1usize] == 42u8 { bad = true }
                if lower(c) == 117u8 && j + 3usize < val.len && lower(val[j + 1usize]) == 114u8 && lower(val[j + 2usize]) == 108u8 && val[j + 3usize] == 40u8 { bad = true }
                if lower(c) == 101u8 && j + 3usize < val.len && lower(val[j + 1usize]) == 120u8 && lower(val[j + 2usize]) == 112u8 && lower(val[j + 3usize]) == 114u8 { bad = true }
                if lower(c) == 106u8 && j + 4usize < val.len && lower(val[j + 1usize]) == 97u8 && lower(val[j + 2usize]) == 118u8 && lower(val[j + 3usize]) == 97u8 && lower(val[j + 4usize]) == 115u8 { bad = true }
                if lower(c) == 98u8 && j + 3usize < val.len && lower(val[j + 1usize]) == 101u8 && lower(val[j + 2usize]) == 104u8 && lower(val[j + 3usize]) == 97u8 { bad = true }
                j += 1usize
            }
            if !bad {
                if emit {
                    if any { try str.push(b, "; ") }
                    try str.push(b, prop)
                    try str.push(b, ": ")
                    try push_text(b, val, true)
                }
                any = true
            }
        }
        at = end + 1usize
    }
    ret (any, ok)
}

type Walk = struct { policy: Policy, a: *mem.Arena }

fn walk(w: *Walk, doc: *const html.Document, id: html.NodeId, b: *str.Builder, depth: usize) -> err {
    if depth > usize(w.policy.max_depth) + 8usize { ret TooDeep }
    let n = &doc.nodes[usize(id)]
    if n.kind == .Text { ret push_text(b, n.value, false) }
    if n.kind == .Element {
        let name = n.name
        if has_token(w.policy.remove_content, name) { ret ok }
        let allowed = has_token(w.policy.tags, name)
        if allowed {
            try str.push(b, "<")
            try str.push(b, name)
            var i = 0usize
            while i < n.attributes.len {
                let attr = n.attributes[i]
                let an = attr.name
                var keep = true
                if an.len >= 2usize && an[0usize] == 111u8 && an[1usize] == 110u8 { keep = false }
                if keep && str.eq(name, "a") && str.eq(an, "rel") && w.policy.link_rel.len > 0usize { keep = false }
                if keep && !(has_token(w.policy.generic_attributes, an) || tag_attribute_allowed(w.policy, name, an)) { keep = false }
                if keep && str.eq(an, "srcset") { keep = false }
                if keep && is_url_attribute(an) && !url_allowed(attr.value, w.policy) { keep = false }
                if keep && str.eq(an, "style") {
                    let (any, probe_error) = style_walk(b, attr.value, w.policy, false)
                    if probe_error != ok { ret probe_error }
                    if any {
                        try str.push(b, " style=\"")
                        let (written, write_error) = style_walk(b, attr.value, w.policy, true)
                        if write_error != ok { ret write_error }
                        try str.push(b, "\"")
                    }
                    keep = false
                }
                if keep {
                    try str.push(b, " ")
                    try str.push(b, an)
                    try str.push(b, "=\"")
                    try push_text(b, attr.value, true)
                    try str.push(b, "\"")
                }
                i += 1usize
            }
            if str.eq(name, "a") && w.policy.link_rel.len > 0usize {
                try str.push(b, " rel=\"")
                try push_text(b, w.policy.link_rel, true)
                try str.push(b, "\"")
            }
            try str.push(b, ">")
            if is_void(name) { ret ok }
        }
        var child = n.first_child
        while child != html.NONE {
            try walk(w, doc, child, b, depth + 1usize)
            child = doc.nodes[usize(child)].next_sibling
        }
        if allowed {
            try str.push(b, "</")
            try str.push(b, name)
            try str.push(b, ">")
        }
        ret ok
    }
    var child = n.first_child
    while child != html.NONE {
        try walk(w, doc, child, b, depth + 1usize)
        child = doc.nodes[usize(child)].next_sibling
    }
    ret ok
}

// `source` reduced to what `policy` allows, written as HTML.
fn sanitize(a: *mem.Arena, source: str, policy: Policy) -> (str, err) {
    var cap = source.len + 16usize
    if cap > 400000usize { cap = 400000usize }
    let options = html.Options { max_bytes: source.len + 1usize, max_nodes: cap, max_attributes: 64usize, max_depth: policy.max_depth, preserve_comments: false }
    let (doc, parse_error) = html.parse(a, source, options)
    if parse_error != ok {
        if parse_error == html.InvalidEncoding { ret ("", Encoding) }
        if parse_error == html.TooDeep { ret ("", TooDeep) }
        ret ("", TooLarge)
    }
    var (b, b_error) = str.builder(a, source.len + 64usize)
    if b_error != ok { ret ("", b_error) }
    var w = Walk { policy: policy, a: a }
    let walk_error = walk(&w, &doc, doc.root, &b, 0usize)
    if walk_error != ok { ret ("", walk_error) }
    ret (str.done(&b), ok)
}
