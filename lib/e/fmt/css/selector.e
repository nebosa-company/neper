// The CSS selector model and parser (L038), after Vaper's `selector.dart` and `selector_parser.dart`: complex selectors as
// compounds joined by descendant, child, adjacent-sibling and general-sibling combinators; type, universal, class, id,
// attribute (`=`, `~=`, `|=`, `^=`, `$=`, `*=`, with the `i` flag), the structural pseudo-classes, `:not()`, `:is()`
// (and its legacy alias `:matches()`), `:where()`, `:has()` with relative selectors, and `:nth-*()` with an `of S` list;
// the legacy single-colon `::before`-family pseudo-elements; and specificity as (ids, classes, types) with the
// functional pseudo-classes recursing. The parser takes the source text and the tokens of
// `e.fmt.css.syntax` and drops a selector it cannot represent (an unknown pseudo-element, content after a
// pseudo-element, a dangling combinator) rather than failing the list.
//
// Names are lowercased as ASCII; an attribute value or a class keeps its case.
//
// Memory: the arena is retained; every selector and string lives in it.

use e.data.list as list
use e.fmt.css.syntax as syntax
use e.mem
use e.str

type SimpleKind = enum u8 { Universal, Type, Klass, Id, PseudoClass, FirstChild, LastChild, OnlyChild, NthChild, NthLastChild, NthOfType, NthLastOfType, FirstOfType, LastOfType, OnlyOfType, Empty, Root, Not, Is, Where, Has, Scope, AttrPresent, AttrEquals, AttrIncludes, AttrDash, AttrPrefix, AttrSuffix, AttrSubstring }

type Combinator = enum u8 { Descendant, Child, AdjacentSibling, GeneralSibling }

type PseudoElement = enum u8 { Before, After, Marker, FirstLetter, FirstLine }

// `argument` is the An+B text of an `:nth-*()`, an attribute's expected value, or a functional pseudo-class's raw
// argument; `subs` are the parsed sub-selectors of `:not/:is/:where/:has` and of the `of S` list of `:nth-*()`.
type Simple = struct { kind: SimpleKind, name: str, argument: str, subs: []const Selector, attr_ci: bool }

type Compound = struct { parts: []const Simple }

// `combinators[i]` joins `compounds[i]` to `compounds[i + 1]`.
type Selector = struct { compounds: []const Compound, combinators: []const Combinator }

type RuleSelector = struct { selector: Selector, has_pseudo: bool, pseudo: PseudoElement }

type Specificity = struct { ids: i64, classes: i64, types: i64 }

fn kind_name(k: SimpleKind) -> str {
    switch k {
    case .Universal:
        ret "universal"
    case .Type:
        ret "type"
    case .Klass:
        ret "klass"
    case .Id:
        ret "id"
    case .PseudoClass:
        ret "pseudoClass"
    case .FirstChild:
        ret "firstChild"
    case .LastChild:
        ret "lastChild"
    case .OnlyChild:
        ret "onlyChild"
    case .NthChild:
        ret "nthChild"
    case .NthLastChild:
        ret "nthLastChild"
    case .NthOfType:
        ret "nthOfType"
    case .NthLastOfType:
        ret "nthLastOfType"
    case .FirstOfType:
        ret "firstOfType"
    case .LastOfType:
        ret "lastOfType"
    case .OnlyOfType:
        ret "onlyOfType"
    case .Empty:
        ret "empty_"
    case .Root:
        ret "root_"
    case .Not:
        ret "not_"
    case .Is:
        ret "is_"
    case .Where:
        ret "where_"
    case .Has:
        ret "has_"
    case .Scope:
        ret "scope_"
    case .AttrPresent:
        ret "attrPresent"
    case .AttrEquals:
        ret "attrEquals"
    case .AttrIncludes:
        ret "attrIncludes"
    case .AttrDash:
        ret "attrDash"
    case .AttrPrefix:
        ret "attrPrefix"
    case .AttrSuffix:
        ret "attrSuffix"
    case .AttrSubstring:
        ret "attrSubstring"
    }
}

fn combinator_name(c: Combinator) -> str {
    switch c {
    case .Descendant:
        ret "descendant"
    case .Child:
        ret "child"
    case .AdjacentSibling:
        ret "adjacentSibling"
    case .GeneralSibling:
        ret "generalSibling"
    }
}

fn pseudo_element_name(p: PseudoElement) -> str {
    switch p {
    case .Before:
        ret "before"
    case .After:
        ret "after"
    case .Marker:
        ret "marker"
    case .FirstLetter:
        ret "firstLetter"
    case .FirstLine:
        ret "firstLine"
    }
}

// --- specificity -----------------------------------------------------------------------------------------------------

fn ordinal(s: Specificity) -> i64 { ret s.ids * 1000000i64 + s.classes * 1000i64 + s.types }

fn add_spec(x: Specificity, y: Specificity) -> Specificity {
    ret Specificity { ids: x.ids + y.ids, classes: x.classes + y.classes, types: x.types + y.types }
}

fn zero_spec() -> Specificity { ret Specificity { ids: 0i64, classes: 0i64, types: 0i64 } }

// The specificity of one simple selector (https://www.w3.org/TR/selectors-4/#specificity-rules).
fn simple_specificity(s: Simple) -> Specificity {
    switch s.kind {
    case .Id:
        ret Specificity { ids: 1i64, classes: 0i64, types: 0i64 }
    case .Type:
        ret Specificity { ids: 0i64, classes: 0i64, types: 1i64 }
    case .Universal:
        ret zero_spec()
    case .Scope:
        ret zero_spec()
    case .Not, .Is, .Has:
        if s.subs.len == 0usize { ret Specificity { ids: 0i64, classes: 1i64, types: 0i64 } }
        var best = zero_spec()
        var at = 0usize
        while at < s.subs.len {
            let sp = specificity(s.subs[at])
            if ordinal(sp) > ordinal(best) { best = sp }
            at += 1usize
        }
        ret best
    case .Where:
        if s.subs.len == 0usize { ret Specificity { ids: 0i64, classes: 1i64, types: 0i64 } }
        ret zero_spec()
    default:
        ret Specificity { ids: 0i64, classes: 1i64, types: 0i64 }
    }
}

// The sum over every simple selector; a functional pseudo-class counts its most specific argument.
fn specificity(sel: Selector) -> Specificity {
    var total = zero_spec()
    var c = 0usize
    while c < sel.compounds.len {
        var p = 0usize
        while p < sel.compounds[c].parts.len {
            total = add_spec(total, simple_specificity(sel.compounds[c].parts[p]))
            p += 1usize
        }
        c += 1usize
    }
    ret total
}

// --- the parser ------------------------------------------------------------------------------------------------------

type Parser = struct { a: *mem.Arena, src: str }

type SimpleResult = struct { good: bool, has_selector: bool, selector: Simple, has_pseudo: bool, pseudo: PseudoElement, next: usize }

type Complex = struct { good: bool, selector: Selector, has_pseudo: bool, pseudo: PseudoElement }

fn new_simple(kind: SimpleKind, name: str) -> Simple {
    ret Simple { kind: kind, name: name, argument: "", subs: zero, attr_ci: false }
}

fn rejected() -> SimpleResult {
    ret SimpleResult { good: false, has_selector: false, selector: new_simple(.Universal, ""), has_pseudo: false, pseudo: .Before, next: 0usize }
}

fn found_simple(s: Simple, next: usize) -> SimpleResult {
    ret SimpleResult { good: true, has_selector: true, selector: s, has_pseudo: false, pseudo: .Before, next: next }
}

fn found_pseudo(p: PseudoElement, next: usize) -> SimpleResult {
    ret SimpleResult { good: true, has_selector: false, selector: new_simple(.Universal, ""), has_pseudo: true, pseudo: p, next: next }
}

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

fn trim(toks: []const syntax.Token) -> []const syntax.Token {
    var start = 0usize
    var end = toks.len
    while start < end && toks[start].kind == .Whitespace { start += 1usize }
    while end > start && toks[end - 1usize].kind == .Whitespace { end -= 1usize }
    ret toks[start..end]
}

fn skip_ws(toks: []const syntax.Token, from: usize) -> usize {
    var i = from
    while i < toks.len && toks[i].kind == .Whitespace { i += 1usize }
    ret i
}

fn is_delim(t: syntax.Token, value: str) -> bool { ret t.kind == .Delim && str.eq(t.value, value) }

// Split on top-level commas (depth counted over parentheses, brackets and function openers), dropping a trailing `Eof`.
fn split_top_level_comma(a: *mem.Arena, tokens: []const syntax.Token) -> []const []const syntax.Token {
    var toks = tokens
    if toks.len > 0usize && toks[toks.len - 1usize].kind == .Eof { toks = toks[0usize..toks.len - 1usize] }
    let (made, e) = list.init[[]const syntax.Token](a, 4usize)
    if e != ok { ret zero }
    var out = made
    var depth = 0i64
    var start = 0usize
    var i = 0usize
    while i < toks.len {
        let k = toks[i].kind
        if k == .LeftParen || k == .LeftSquare || k == .Function {
            depth += 1i64
        } else if k == .RightParen || k == .RightSquare {
            if depth > 0i64 { depth -= 1i64 }
        } else if depth == 0i64 && k == .Comma {
            let pushed = list.push[[]const syntax.Token](&out, toks[start..i])
            start = i + 1usize
        }
        i += 1usize
    }
    let last = list.push[[]const syntax.Token](&out, toks[start..])
    ret list.slice_const[[]const syntax.Token](&out)
}

fn rejected_complex() -> Complex {
    ret Complex { good: false, selector: Selector { compounds: zero, combinators: zero }, has_pseudo: false, pseudo: .Before }
}

fn push_simple(l: *list.List[Simple], s: Simple) {
    let e = list.push[Simple](l, s)
}

fn new_simples(a: *mem.Arena) -> list.List[Simple] {
    let (l, e) = list.init[Simple](a, 4usize)
    if e != ok { ret list.List[Simple] { items: zero, len: 0usize, arena: a } }
    ret l
}

fn parse_complex(p: *const Parser, toks: []const syntax.Token) -> Complex {
    let a = p.a
    let (cm, ce) = list.init[Compound](a, 4usize)
    let (cb, be) = list.init[Combinator](a, 4usize)
    if ce != ok || be != ok { ret rejected_complex() }
    var compounds = cm
    var combinators = cb
    var current = new_simples(a)
    var pending: Combinator = .Descendant
    var has_pending = false
    var pending_explicit = false
    var pseudo_el: PseudoElement = .Before
    var has_pseudo = false
    var i = 0usize
    let n = toks.len
    while i < n {
        let t = toks[i]
        if t.kind == .Whitespace {
            if (current.len > 0usize || compounds.len > 0usize) && !has_pending {
                pending = .Descendant
                has_pending = true
            }
            i += 1usize
        } else if t.kind == .Delim && (str.eq(t.value, ">") || str.eq(t.value, "+") || str.eq(t.value, "~")) {
            if current.len > 0usize {
                let pushed = list.push[Compound](&compounds, Compound { parts: list.slice_const[Simple](&current) })
                current = new_simples(a)
            }
            if str.eq(t.value, ">") {
                pending = .Child
            } else if str.eq(t.value, "+") {
                pending = .AdjacentSibling
            } else {
                pending = .GeneralSibling
            }
            has_pending = true
            pending_explicit = true
            i += 1usize
        } else {
            if has_pending {
                if current.len > 0usize {
                    let pushed = list.push[Compound](&compounds, Compound { parts: list.slice_const[Simple](&current) })
                    current = new_simples(a)
                }
                if compounds.len > 0usize {
                    let pushed = list.push[Combinator](&combinators, pending)
                }
                has_pending = false
                pending_explicit = false
            }
            if has_pseudo { ret rejected_complex() }
            let res = parse_simple(p, toks, i)
            if !res.good { ret rejected_complex() }
            i = res.next
            if res.has_pseudo {
                pseudo_el = res.pseudo
                has_pseudo = true
            } else if res.has_selector {
                push_simple(&current, res.selector)
            }
        }
    }
    if pending_explicit && current.len == 0usize { ret rejected_complex() }
    if current.len > 0usize {
        let pushed = list.push[Compound](&compounds, Compound { parts: list.slice_const[Simple](&current) })
    }
    if compounds.len == 0usize {
        if has_pseudo {
            var only = new_simples(a)
            push_simple(&only, new_simple(.Universal, "*"))
            let pushed = list.push[Compound](&compounds, Compound { parts: list.slice_const[Simple](&only) })
        } else {
            ret rejected_complex()
        }
    }
    ret Complex { good: true, selector: Selector { compounds: list.slice_const[Compound](&compounds), combinators: list.slice_const[Combinator](&combinators) }, has_pseudo: has_pseudo, pseudo: pseudo_el }
}

fn parse_simple(p: *const Parser, toks: []const syntax.Token, start: usize) -> SimpleResult {
    let n = toks.len
    var i = start
    var t = toks[i]
    if is_delim(t, "|") {
        i += 1usize
        if i >= n { ret rejected() }
        t = toks[i]
    } else if (t.kind == .Ident || is_delim(t, "*")) && i + 1usize < n && is_delim(toks[i + 1usize], "|") && i + 2usize < n {
        i += 2usize
        t = toks[i]
    }
    if t.kind == .Delim {
        if str.eq(t.value, "*") { ret found_simple(new_simple(.Universal, "*"), i + 1usize) }
        if str.eq(t.value, ".") {
            if i + 1usize < n && toks[i + 1usize].kind == .Ident {
                ret found_simple(new_simple(.Klass, toks[i + 1usize].value), i + 2usize)
            }
            ret rejected()
        }
        ret rejected()
    }
    if t.kind == .Ident { ret found_simple(new_simple(.Type, lower(p.a, t.value)), i + 1usize) }
    if t.kind == .Hash { ret found_simple(new_simple(.Id, t.value), i + 1usize) }
    if t.kind == .LeftSquare { ret parse_attribute(p, toks, i) }
    if t.kind == .Colon { ret parse_pseudo(p, toks, i) }
    ret rejected()
}

fn parse_attribute(p: *const Parser, toks: []const syntax.Token, open: usize) -> SimpleResult {
    var close = toks.len
    var depth = 0i64
    var j = open
    var done = false
    while j < toks.len && !done {
        let k = toks[j].kind
        if k == .LeftSquare {
            depth += 1i64
        } else if k == .RightSquare {
            depth -= 1i64
            if depth == 0i64 {
                close = j
                done = true
            }
        }
        j += 1usize
    }
    if close == toks.len { ret rejected() }
    let inner = trim(toks[open + 1usize..close])
    let (sel, good) = attribute_from_inner(p, inner)
    if !good { ret rejected() }
    ret found_simple(sel, close + 1usize)
}

fn attribute_from_inner(p: *const Parser, inner: []const syntax.Token) -> (Simple, bool) {
    let none = new_simple(.AttrPresent, "")
    if inner.len == 0usize { ret (none, false) }
    var idx = 0usize
    if is_delim(inner[idx], "|") && idx + 1usize < inner.len && inner[idx + 1usize].kind == .Ident {
        idx += 1usize
    } else if idx + 2usize < inner.len && (inner[idx].kind == .Ident || is_delim(inner[idx], "*")) && is_delim(inner[idx + 1usize], "|") && inner[idx + 2usize].kind == .Ident {
        idx += 2usize
    }
    if idx >= inner.len || inner[idx].kind != .Ident { ret (none, false) }
    let name = lower(p.a, inner[idx].value)
    idx += 1usize
    idx = skip_ws(inner, idx)
    if idx >= inner.len { ret (new_simple(.AttrPresent, name), true) }
    if inner[idx].kind != .Delim { ret (none, false) }
    let c = inner[idx].value
    var kind: SimpleKind = .AttrEquals
    if str.eq(c, "=") {
        kind = .AttrEquals
        idx += 1usize
    } else if (str.eq(c, "~") || str.eq(c, "^") || str.eq(c, "$") || str.eq(c, "*") || str.eq(c, "|")) && idx + 1usize < inner.len && is_delim(inner[idx + 1usize], "=") {
        if str.eq(c, "~") { kind = .AttrIncludes }
        if str.eq(c, "|") { kind = .AttrDash }
        if str.eq(c, "^") { kind = .AttrPrefix }
        if str.eq(c, "$") { kind = .AttrSuffix }
        if str.eq(c, "*") { kind = .AttrSubstring }
        idx += 2usize
    } else {
        ret (none, false)
    }
    idx = skip_ws(inner, idx)
    if idx >= inner.len { ret (none, false) }
    let val = inner[idx]
    var value = ""
    if val.kind == .String || val.kind == .Ident {
        value = val.value
    } else if val.kind == .Number || val.kind == .Dimension || val.kind == .Percentage {
        value = p.src[val.start..val.end]
    } else {
        ret (none, false)
    }
    idx += 1usize
    idx = skip_ws(inner, idx)
    var ci = false
    if idx < inner.len && inner[idx].kind == .Ident {
        let flag = lower(p.a, inner[idx].value)
        if str.eq(flag, "i") { ci = true }
    }
    ret (Simple { kind: kind, name: name, argument: value, subs: zero, attr_ci: ci }, true)
}

fn pseudo_class_by_name(name: str) -> Simple {
    if str.eq(name, "first-child") { ret new_simple(.FirstChild, "") }
    if str.eq(name, "last-child") { ret new_simple(.LastChild, "") }
    if str.eq(name, "only-child") { ret new_simple(.OnlyChild, "") }
    if str.eq(name, "first-of-type") { ret new_simple(.FirstOfType, "") }
    if str.eq(name, "last-of-type") { ret new_simple(.LastOfType, "") }
    if str.eq(name, "only-of-type") { ret new_simple(.OnlyOfType, "") }
    if str.eq(name, "empty") { ret new_simple(.Empty, "") }
    if str.eq(name, "root") { ret new_simple(.Root, "") }
    ret new_simple(.PseudoClass, name)
}

fn pseudo_element_of(name: str, next: usize) -> SimpleResult {
    if str.eq(name, "before") { ret found_pseudo(.Before, next) }
    if str.eq(name, "after") { ret found_pseudo(.After, next) }
    if str.eq(name, "marker") { ret found_pseudo(.Marker, next) }
    if str.eq(name, "first-letter") { ret found_pseudo(.FirstLetter, next) }
    if str.eq(name, "first-line") { ret found_pseudo(.FirstLine, next) }
    ret rejected()
}

fn parse_pseudo(p: *const Parser, toks: []const syntax.Token, i: usize) -> SimpleResult {
    let n = toks.len
    if i + 1usize < n && toks[i + 1usize].kind == .Colon {
        if i + 2usize < n && toks[i + 2usize].kind == .Ident {
            ret pseudo_element_of(lower(p.a, toks[i + 2usize].value), i + 3usize)
        }
        ret rejected()
    }
    if i + 1usize >= n { ret rejected() }
    let next = toks[i + 1usize]
    if next.kind == .Ident {
        let name = lower(p.a, next.value)
        if str.eq(name, "before") || str.eq(name, "after") || str.eq(name, "first-line") || str.eq(name, "first-letter") {
            ret pseudo_element_of(name, i + 2usize)
        }
        if str.eq(name, "placeholder") || str.eq(name, "selection") || str.eq(name, "backdrop") { ret rejected() }
        ret found_simple(pseudo_class_by_name(name), i + 2usize)
    }
    if next.kind == .Function {
        let name = lower(p.a, next.value)
        var close = n
        var depth = 1i64
        var j = i + 2usize
        var done = false
        while j < n && !done {
            let k = toks[j].kind
            if k == .LeftParen || k == .Function {
                depth += 1i64
            } else if k == .RightParen {
                depth -= 1i64
                if depth == 0i64 {
                    close = j
                    done = true
                }
            }
            j += 1usize
        }
        if close == n { ret rejected() }
        let arg = trim(toks[i + 2usize..close])
        let (sel, good) = functional_pseudo(p, name, arg)
        if !good { ret rejected() }
        ret found_simple(sel, close + 1usize)
    }
    ret rejected()
}

fn plain_list(p: *const Parser, tokens: []const syntax.Token) -> []const Selector {
    let (made, e) = list.init[Selector](p.a, 4usize)
    if e != ok { ret zero }
    var out = made
    let segs = split_top_level_comma(p.a, tokens)
    var s = 0usize
    while s < segs.len {
        let parsed = parse_complex(p, trim(segs[s]))
        if parsed.good && !parsed.has_pseudo {
            let pushed = list.push[Selector](&out, parsed.selector)
        }
        s += 1usize
    }
    ret list.slice_const[Selector](&out)
}

fn relative_list(p: *const Parser, tokens: []const syntax.Token) -> []const Selector {
    let (made, e) = list.init[Selector](p.a, 4usize)
    if e != ok { ret zero }
    var out = made
    let segs = split_top_level_comma(p.a, tokens)
    var s = 0usize
    while s < segs.len {
        var seg = trim(segs[s])
        var lead: Combinator = .Descendant
        if seg.len > 0usize && seg[0].kind == .Delim {
            if str.eq(seg[0].value, ">") {
                lead = .Child
                seg = trim(seg[1usize..])
            } else if str.eq(seg[0].value, "+") {
                lead = .AdjacentSibling
                seg = trim(seg[1usize..])
            } else if str.eq(seg[0].value, "~") {
                lead = .GeneralSibling
                seg = trim(seg[1usize..])
            }
        }
        let parsed = parse_complex(p, seg)
        if parsed.good && !parsed.has_pseudo {
            let (cm, ce) = list.init[Compound](p.a, parsed.selector.compounds.len + 1usize)
            let (cb, be) = list.init[Combinator](p.a, parsed.selector.combinators.len + 1usize)
            if ce == ok && be == ok {
                var compounds = cm
                var combinators = cb
                var anchor = new_simples(p.a)
                push_simple(&anchor, new_simple(.Scope, ""))
                let a0 = list.push[Compound](&compounds, Compound { parts: list.slice_const[Simple](&anchor) })
                var k = 0usize
                while k < parsed.selector.compounds.len {
                    let pc = list.push[Compound](&compounds, parsed.selector.compounds[k])
                    k += 1usize
                }
                let l0 = list.push[Combinator](&combinators, lead)
                var m = 0usize
                while m < parsed.selector.combinators.len {
                    let pb = list.push[Combinator](&combinators, parsed.selector.combinators[m])
                    m += 1usize
                }
                let pushed = list.push[Selector](&out, Selector { compounds: list.slice_const[Compound](&compounds), combinators: list.slice_const[Combinator](&combinators) })
            }
        }
        s += 1usize
    }
    ret list.slice_const[Selector](&out)
}

fn is_word(c: u8) -> bool { ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 }

fn trim_text(s: str) -> str {
    var start = 0usize
    var end = s.len
    while start < end && (s[start] == 32u8 || (s[start] >= 9u8 && s[start] <= 13u8)) { start += 1usize }
    while end > start && (s[end - 1usize] == 32u8 || (s[end - 1usize] >= 9u8 && s[end - 1usize] <= 13u8)) { end -= 1usize }
    ret s[start..end]
}

// `:nth-*(An+B [of S])`: the An+B text as the argument and the `of` list as sub-selectors.
fn parse_nth(p: *const Parser, kind: SimpleKind, arg: []const syntax.Token) -> Simple {
    let raw = syntax.raw_text(p.src, arg)
    var at = 0usize
    while at + 2usize <= raw.len {
        let o = raw[at] == 79u8 || raw[at] == 111u8
        let f = raw[at + 1usize] == 70u8 || raw[at + 1usize] == 102u8
        let before_ok = at == 0usize || !is_word(raw[at - 1usize])
        let after_ok = at + 2usize == raw.len || !is_word(raw[at + 2usize])
        if o && f && before_ok && after_ok {
            let anb = trim_text(raw[0usize..at])
            let tail = trim_text(raw[at + 2usize..])
            let (sub_tokens, te) = syntax.tokenize(p.a, tail)
            var subs: []const Selector = zero
            if te == ok {
                let inner = Parser { a: p.a, src: tail }
                subs = plain_list(&inner, sub_tokens)
            }
            ret Simple { kind: kind, name: kind_name(kind), argument: anb, subs: subs, attr_ci: false }
        }
        at += 1usize
    }
    ret Simple { kind: kind, name: kind_name(kind), argument: trim_text(raw), subs: zero, attr_ci: false }
}

fn functional_pseudo(p: *const Parser, name: str, arg: []const syntax.Token) -> (Simple, bool) {
    let raw = syntax.raw_text(p.src, arg)
    if str.eq(name, "not") { ret (Simple { kind: .Not, name: name, argument: raw, subs: plain_list(p, arg), attr_ci: false }, true) }
    if str.eq(name, "is") || str.eq(name, "matches") { ret (Simple { kind: .Is, name: "is", argument: raw, subs: plain_list(p, arg), attr_ci: false }, true) }
    if str.eq(name, "where") { ret (Simple { kind: .Where, name: name, argument: raw, subs: plain_list(p, arg), attr_ci: false }, true) }
    if str.eq(name, "has") { ret (Simple { kind: .Has, name: name, argument: raw, subs: relative_list(p, arg), attr_ci: false }, true) }
    if str.eq(name, "nth-child") { ret (parse_nth(p, .NthChild, arg), true) }
    if str.eq(name, "nth-last-child") { ret (parse_nth(p, .NthLastChild, arg), true) }
    if str.eq(name, "nth-of-type") { ret (parse_nth(p, .NthOfType, arg), true) }
    if str.eq(name, "nth-last-of-type") { ret (parse_nth(p, .NthLastOfType, arg), true) }
    ret (new_simple(.PseudoClass, name), true)
}

// Parse a rule's selector list: each comma-separated complex selector that can be represented, with the pseudo-element it
// targets if any; the rest are dropped.
fn parse_selector_list_for_rule(a: *mem.Arena, source: str, tokens: []const syntax.Token) -> ([]const RuleSelector, err) {
    let p = Parser { a: a, src: source }
    let (made, e) = list.init[RuleSelector](a, 4usize)
    if e != ok { ret (zero, e) }
    var out = made
    let segs = split_top_level_comma(a, tokens)
    var s = 0usize
    while s < segs.len {
        let parsed = parse_complex(&p, trim(segs[s]))
        if parsed.good {
            try list.push[RuleSelector](&out, RuleSelector { selector: parsed.selector, has_pseudo: parsed.has_pseudo, pseudo: parsed.pseudo })
        }
        s += 1usize
    }
    ret (list.slice_const[RuleSelector](&out), ok)
}
