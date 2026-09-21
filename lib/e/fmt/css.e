// CSS selectors and the cascade over a caller element tree. An `Element` names its tag and
// id, a span of `classes` and a span of `attributes`, its `parent` and its previous sibling
// (`NONE` for neither). `matches` and `select` take a selector list: compound selectors of
// a type or `*`, `#id`, `.class`, `[attr]`, `[attr=v]`, `[attr~=v]`, `[attr|=v]`,
// `[attr^=v]`, `[attr$=v]`, `[attr*=v]` (the value bare or quoted), `:first-child` and
// `:nth-child(an+b | odd | even)`, joined by the descendant, `>`, `+` and `~` combinators;
// matching runs right to left from the candidate, so the rightmost compound is tested before
// any ancestor is walked. Tags compare ASCII case-insensitively, everything else exactly.
//
// `specificity` packs (ids, classes+attributes+pseudo-classes, types) as `a << 16 | b << 8 |
// c`, the largest member of a list. `cascade` orders declarations lowest precedence first:
// normal user-agent < user < author, then `!important` with the origins reversed above them
// all, then specificity, then source `order`.

use e.str

type Element = struct { tag: str, id: str, class_lo: u32, class_hi: u32, attr_lo: u32, attr_hi: u32, parent: u32, prev: u32 }
type Attribute = struct { name: str, value: str }
type Dom = struct { elements: []const Element, classes: []const str, attributes: []const Attribute }
type Origin = enum u8 { UserAgent, User, Author }
type Decl = struct { origin: Origin, important: bool, specificity: u32, order: u32 }
error Invalid
error TooSmall

const NONE: u32 = 4294967295u32

fn is_ident(b: u8) -> bool { ret str.is_ascii_alnum(b) || b == 45u8 || b == 95u8 }

fn ident_end(s: str, from: usize) -> usize {
    var i = from
    while i < s.len && is_ident(s[i]) { i += 1usize }
    ret i
}

fn is_combinator(b: u8) -> bool { ret b == 62u8 || b == 43u8 || b == 126u8 }

// The next top-level `sep` at or after `from` (outside brackets, parentheses and quotes);
// to find a closer, start just past its opener.
fn find_top(s: str, from: usize, sep: u8) -> (usize, bool, err) {
    var depth = 0usize
    var quote = 0u8
    var i = from
    while i < s.len {
        let b = s[i]
        if quote != 0u8 {
            if b == quote { quote = 0u8 }
        } else if b == 34u8 || b == 39u8 {
            quote = b
        } else if depth == 0usize && b == sep {
            ret (i, true, ok)
        } else if b == 91u8 || b == 40u8 {
            depth += 1usize
        } else if b == 93u8 || b == 41u8 {
            if depth == 0usize { ret (i, false, Invalid) }
            depth -= 1usize
        }
        i += 1usize
    }
    if depth != 0usize || quote != 0u8 { ret (s.len, false, Invalid) }
    ret (s.len, false, ok)
}

fn has_class(d: *const Dom, e: Element, name: str) -> bool {
    var i = usize(e.class_lo)
    while i < usize(e.class_hi) {
        if str.eq(d.classes[i], name) { ret true }
        i += 1usize
    }
    ret false
}

fn attribute(d: *const Dom, e: Element, name: str) -> (str, bool) {
    var i = usize(e.attr_lo)
    while i < usize(e.attr_hi) {
        if str.eq(d.attributes[i].name, name) { ret (d.attributes[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn word_in(list: str, word: str) -> bool {
    var i = 0usize
    while i <= list.len {
        var j = i
        while j < list.len && list[j] != 32u8 { j += 1usize }
        if str.eq(list[i..j], word) { ret true }
        i = j + 1usize
    }
    ret false
}

// `[name]`, `[name op value]`; `body` is the text between the brackets.
fn match_attribute(d: *const Dom, e: Element, body: str) -> (bool, err) {
    let text = str.trim(body)
    let name_end = ident_end(text, 0usize)
    if name_end == 0usize { ret (false, Invalid) }
    let (value, present) = attribute(d, e, text[..name_end])
    let rest = str.trim(text[name_end..])
    if rest.len == 0usize { ret (present, ok) }
    var op = rest[0usize]
    var at = 1usize
    if op != 61u8 {
        if rest.len < 2usize || rest[1usize] != 61u8 { ret (false, Invalid) }
        if op != 126u8 && op != 94u8 && op != 36u8 && op != 42u8 && op != 124u8 { ret (false, Invalid) }
        at = 2usize
    }
    var wanted = str.trim(rest[at..])
    if wanted.len >= 2usize && (wanted[0usize] == 34u8 || wanted[0usize] == 39u8) {
        if wanted[wanted.len - 1usize] != wanted[0usize] { ret (false, Invalid) }
        wanted = wanted[1usize..wanted.len - 1usize]
    }
    if !present { ret (false, ok) }
    if op == 61u8 { ret (str.eq(value, wanted), ok) }
    if op == 126u8 { ret (word_in(value, wanted), ok) }
    if op == 94u8 { ret (str.starts_with(value, wanted), ok) }
    if op == 36u8 { ret (str.ends_with(value, wanted), ok) }
    if op == 42u8 { ret (str.contains(value, wanted), ok) }
    if str.eq(value, wanted) { ret (true, ok) }
    ret (str.starts_with(value, wanted) && value.len > wanted.len && value[wanted.len] == 45u8, ok)
}

fn skip_spaces(s: str, from: usize) -> usize {
    var i = from
    while i < s.len && s[i] == 32u8 { i += 1usize }
    ret i
}

fn digits(s: str, from: usize) -> (i64, usize) {
    var v = 0i64
    var i = from
    while i < s.len && str.is_ascii_digit(s[i]) {
        v = v * 10i64 + i64(s[i] - 48u8)
        i += 1usize
    }
    ret (v, i)
}

// `an+b`, `odd`, `even`, or a bare `b`.
fn parse_nth(arg: str) -> (i64, i64, err) {
    let text = str.trim(arg)
    if str.eq(text, "odd") { ret (2i64, 1i64, ok) }
    if str.eq(text, "even") { ret (2i64, 0i64, ok) }
    var i = 0usize
    var sign = 1i64
    if i < text.len && text[i] == 45u8 {
        sign = 0i64 - 1i64
        i += 1usize
    } else if i < text.len && text[i] == 43u8 {
        i += 1usize
    }
    let (value, after) = digits(text, i)
    let has_value = after > i
    i = skip_spaces(text, after)
    if i < text.len && text[i] == 110u8 {
        i += 1usize
        var a = sign
        if has_value { a = sign * value }
        var b = 0i64
        i = skip_spaces(text, i)
        if i < text.len {
            var b_sign = 1i64
            if text[i] == 45u8 { b_sign = 0i64 - 1i64 } else if text[i] != 43u8 { ret (0i64, 0i64, Invalid) }
            i = skip_spaces(text, i + 1usize)
            let (b_value, b_after) = digits(text, i)
            if b_after == i { ret (0i64, 0i64, Invalid) }
            b = b_sign * b_value
            i = b_after
        }
        if i != text.len { ret (0i64, 0i64, Invalid) }
        ret (a, b, ok)
    }
    if !has_value || i != text.len { ret (0i64, 0i64, Invalid) }
    ret (0i64, sign * value, ok)
}

fn position(d: *const Dom, index: usize) -> i64 {
    var n = 1i64
    var p = d.elements[index].prev
    while p != NONE {
        n += 1i64
        p = d.elements[usize(p)].prev
    }
    ret n
}

fn match_pseudo(d: *const Dom, index: usize, name: str, arg: str, has_arg: bool) -> (bool, err) {
    if str.eq(name, "first-child") {
        if has_arg { ret (false, Invalid) }
        ret (d.elements[index].prev == NONE, ok)
    }
    if str.eq(name, "nth-child") {
        if !has_arg { ret (false, Invalid) }
        let (a, b, e) = parse_nth(arg)
        if e != ok { ret (false, e) }
        let pos = position(d, index)
        if a == 0i64 { ret (pos == b, ok) }
        let diff = pos - b
        if diff % a != 0i64 { ret (false, ok) }
        if a > 0i64 { ret (diff >= 0i64, ok) }
        ret (diff <= 0i64, ok)
    }
    // ponytail: no other pseudo-classes; `:last-child` and `:not()` would need a next
    // sibling and a nested parse.
    ret (false, Invalid)
}

// One compound selector against element `index`.
fn match_compound(d: *const Dom, index: usize, c: str) -> (bool, err) {
    if c.len == 0usize { ret (false, Invalid) }
    let e = d.elements[index]
    var i = 0usize
    if c[0usize] == 42u8 {
        i = 1usize
    } else if is_ident(c[0usize]) {
        i = ident_end(c, 0usize)
        if str.compare_ascii_fold(c[..i], e.tag) != 0i32 { ret (false, ok) }
    }
    while i < c.len {
        let b = c[i]
        if b == 35u8 || b == 46u8 {
            let end = ident_end(c, i + 1usize)
            if end == i + 1usize { ret (false, Invalid) }
            let name = c[i + 1usize..end]
            if b == 35u8 {
                if !str.eq(e.id, name) { ret (false, ok) }
            } else if !has_class(d, e, name) {
                ret (false, ok)
            }
            i = end
        } else if b == 91u8 {
            let (close, found, e1) = find_top(c, i + 1usize, 93u8)
            if e1 != ok || !found { ret (false, Invalid) }
            let (matched, e2) = match_attribute(d, e, c[i + 1usize..close])
            if e2 != ok { ret (false, e2) }
            if !matched { ret (false, ok) }
            i = close + 1usize
        } else if b == 58u8 {
            let end = ident_end(c, i + 1usize)
            if end == i + 1usize { ret (false, Invalid) }
            let name = c[i + 1usize..end]
            var arg = ""
            var has_arg = false
            i = end
            if i < c.len && c[i] == 40u8 {
                let (close, found, e1) = find_top(c, i + 1usize, 41u8)
                if e1 != ok || !found { ret (false, Invalid) }
                arg = c[i + 1usize..close]
                has_arg = true
                i = close + 1usize
            }
            let (matched, e2) = match_pseudo(d, index, name, arg, has_arg)
            if e2 != ok { ret (false, e2) }
            if !matched { ret (false, ok) }
        } else {
            ret (false, Invalid)
        }
    }
    ret (true, ok)
}

// One complex selector, right to left: the last compound against `index`, then the rest
// against whichever element the combinator names.
fn match_complex(d: *const Dom, index: usize, sel: str) -> (bool, err) {
    let s = str.trim(sel)
    if s.len == 0usize { ret (false, Invalid) }
    var depth = 0usize
    var quote = 0u8
    var i = s.len
    var start = 0usize
    while i > 0usize {
        let b = s[i - 1usize]
        if quote != 0u8 {
            if b == quote { quote = 0u8 }
        } else if b == 34u8 || b == 39u8 {
            quote = b
        } else if b == 93u8 || b == 41u8 {
            depth += 1usize
        } else if b == 91u8 || b == 40u8 {
            if depth == 0usize { ret (false, Invalid) }
            depth -= 1usize
        } else if depth == 0usize && (b == 32u8 || is_combinator(b)) {
            start = i
            break
        }
        i -= 1usize
    }
    if depth != 0usize || quote != 0u8 { ret (false, Invalid) }
    let (matched, e) = match_compound(d, index, s[start..])
    if e != ok { ret (false, e) }
    if !matched { ret (false, ok) }
    if start == 0usize { ret (true, ok) }
    let before = str.trim(s[..start])
    if before.len == 0usize { ret (false, Invalid) }
    var combinator = 32u8
    var head = before
    if is_combinator(before[before.len - 1usize]) {
        combinator = before[before.len - 1usize]
        head = str.trim(before[..before.len - 1usize])
        if head.len == 0usize { ret (false, Invalid) }
    }
    let e0 = d.elements[index]
    if combinator == 62u8 {
        if e0.parent == NONE { ret (false, ok) }
        let (up, e1) = match_complex(d, usize(e0.parent), head)
        ret (up, e1)
    }
    if combinator == 43u8 {
        if e0.prev == NONE { ret (false, ok) }
        let (left, e1) = match_complex(d, usize(e0.prev), head)
        ret (left, e1)
    }
    var p = e0.prev
    if combinator == 32u8 { p = e0.parent }
    while p != NONE {
        let (found, e1) = match_complex(d, usize(p), head)
        if e1 != ok { ret (false, e1) }
        if found { ret (true, ok) }
        if combinator == 32u8 { p = d.elements[usize(p)].parent } else { p = d.elements[usize(p)].prev }
    }
    ret (false, ok)
}

// Does element `index` match the selector list `selector`?
fn matches(d: *const Dom, index: usize, selector: str) -> (bool, err) {
    if index >= d.elements.len { ret (false, Invalid) }
    var from = 0usize
    while from <= selector.len {
        let (comma, found, e) = find_top(selector, from, 44u8)
        if e != ok { ret (false, e) }
        let (matched, e1) = match_complex(d, index, selector[from..comma])
        if e1 != ok { ret (false, e1) }
        if matched { ret (true, ok) }
        if !found { break }
        from = comma + 1usize
    }
    ret (false, ok)
}

// The indices of every element matching `selector`, in document order, into `out`.
fn select(d: *const Dom, selector: str, out: []u32) -> (usize, err) {
    var n = 0usize
    var i = 0usize
    while i < d.elements.len {
        let (matched, e) = matches(d, i, selector)
        if e != ok { ret (n, e) }
        if matched {
            if n >= out.len { ret (n, TooSmall) }
            out[n] = u32(i)
            n += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

fn specificity_one(sel: str) -> (u32, err) {
    let s = str.trim(sel)
    if s.len == 0usize { ret (0u32, Invalid) }
    var a = 0u32
    var b = 0u32
    var c = 0u32
    var i = 0usize
    while i < s.len {
        let byte = s[i]
        if byte == 35u8 || byte == 46u8 || byte == 58u8 {
            let end = ident_end(s, i + 1usize)
            if end == i + 1usize { ret (0u32, Invalid) }
            if byte == 35u8 { a += 1u32 } else { b += 1u32 }
            i = end
            if byte == 58u8 && i < s.len && s[i] == 40u8 {
                let (close, found, e) = find_top(s, i + 1usize, 41u8)
                if e != ok || !found { ret (0u32, Invalid) }
                i = close + 1usize
            }
        } else if byte == 91u8 {
            let (close, found, e) = find_top(s, i + 1usize, 93u8)
            if e != ok || !found { ret (0u32, Invalid) }
            b += 1u32
            i = close + 1usize
        } else if is_ident(byte) {
            c += 1u32
            i = ident_end(s, i)
        } else if byte == 42u8 || byte == 32u8 || is_combinator(byte) {
            i += 1usize
        } else {
            ret (0u32, Invalid)
        }
    }
    ret ((a << 16u32) | (b << 8u32) | c, ok)
}

// (ids, classes+attributes+pseudo-classes, types) packed as `a << 16 | b << 8 | c`; for a
// list, the largest.
fn specificity(selector: str) -> (u32, err) {
    var best = 0u32
    var from = 0usize
    while from <= selector.len {
        let (comma, found, e) = find_top(selector, from, 44u8)
        if e != ok { ret (0u32, e) }
        let (one, e1) = specificity_one(selector[from..comma])
        if e1 != ok { ret (0u32, e1) }
        if one > best { best = one }
        if !found { break }
        from = comma + 1usize
    }
    ret (best, ok)
}

fn rank(decl: Decl) -> u32 {
    var origin = 0u32
    if decl.origin == .User { origin = 1u32 }
    if decl.origin == .Author { origin = 2u32 }
    if decl.important { ret 5u32 - origin }
    ret origin
}

fn precedes(x: Decl, y: Decl) -> bool {
    let rx = rank(x)
    let ry = rank(y)
    if rx != ry { ret rx < ry }
    if x.specificity != y.specificity { ret x.specificity < y.specificity }
    ret x.order < y.order
}

// The indices of `decls` from the lowest precedence to the winning declaration.
fn cascade(decls: []const Decl, out_order: []u32) -> err {
    if out_order.len < decls.len { ret TooSmall }
    // ponytail: insertion sort, stable; a merge sort if a cascade ever sees thousands.
    var i = 0usize
    while i < decls.len {
        var k = i
        while k > 0usize && precedes(decls[i], decls[usize(out_order[k - 1usize])]) {
            out_order[k] = out_order[k - 1usize]
            k -= 1usize
        }
        out_order[k] = u32(i)
        i += 1usize
    }
    ret ok
}
