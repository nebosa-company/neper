// Declarative predicates over a resource's attributes (L025), the value-rule subset of petcow's Spartan filter engine
// (`src/spartan/filter.rs`, `predicate.rs`): a Cloud-Custodian-shaped filter is a tree of `and`, `or` and `not` over
// leaves that read a dotted `key` out of a bag of attributes and apply an `op` to a `value`. It is pure: nothing
// runs but the comparison. Not here: the policy sets, GSL, waivers and reports of the full engine.
//
// The attributes and the filter are `e.fmt.json` values (decoded JSON or YAML): the attribute bag is an object.
// Leaf ops: `eq`, `ne` (`==`, `!=`), `gt`, `lt`, `ge`, `le` (numbers only, a non-number never matches), `in` and
// `not_in` (a list `value`), `contains` (a list attribute holds the value, or a string attribute holds the
// substring), `regex` (unanchored, run by `e.text.regex`'s linear-time engine; a pattern that does not compile
// never matches), `glob` (`*` any run, `?` any one character), `present`, `absent`, `any` and `all` (an `element`
// sub-filter over a list attribute, a scalar element tested against the key `""`), and `count` (the number of
// elements, or of those matching `element`, compared with a numeric `value` by `count_op`, default `eq`). A leaf
// with a `value` and no `op` is `eq`. Equality coerces numbers (`1` is `1.0`); a missing attribute never matches
// except for `absent`. A built-in `{builtin: name, args: ...}` runs one of `sg_world_open_ports` (a world-open
// ingress rule covering a port in `args`), `sg_world_open_all_protocols` and `iam_wildcard_principal`; an unknown
// name never matches.
//
// `parse` checks a filter once (every refusal is a named error); `eval` then cannot fail, and takes an arena for
// the regex compile.

use e.fmt.json as json
use e.mem
use e.text.regex as regex
use e.text.utf8 as utf8

error NotMapping
error BoolNotAlone
error NotList
error MissingKey
error BadOp
error MissingOp
error MissingValue
error MissingElement
error CountNeedsNumber
error BadCountOp

type Op = enum u8 { Eq, Ne, Gt, Lt, Ge, Le, In, NotIn, Contains, Regex, Glob, Present, Absent, Any, All, Count }

type Kind = enum u8 { And, Or, Not, Leaf, Builtin }

type Filter = struct {
    kind: Kind,
    children: []const Filter,
    key: str,
    op: Op,
    value: json.Value,
    has_value: bool,
    element: []const Filter,
    count_op: Op,
    has_count_op: bool,
    name: str,
    args: json.Value,
    has_args: bool,
    program: regex.Regex,
    compiled: bool,
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn lower_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

// The canonical operator for a spelling (trimmed, lowercase, `-` as `_`), or false.
fn parse_op(text: str) -> (Op, bool) {
    var start = 0usize
    var end = text.len
    while start < end && is_space(text[start]) { start += 1usize }
    while end > start && is_space(text[end - 1usize]) { end -= 1usize }
    var name: [24]u8 = zero
    if end - start > 12usize { ret (.Eq, false) }
    var n = 0usize
    var i = start
    while i < end {
        var c = lower_byte(text[i])
        if c == 45u8 { c = 95u8 }
        name[n] = c
        n += 1usize
        i += 1usize
    }
    let s = name[0usize..n]
    if same(s, "eq") || same(s, "==") || same(s, "equals") { ret (.Eq, true) }
    if same(s, "ne") || same(s, "!=") || same(s, "not_equals") { ret (.Ne, true) }
    if same(s, "gt") || same(s, ">") { ret (.Gt, true) }
    if same(s, "lt") || same(s, "<") { ret (.Lt, true) }
    if same(s, "ge") || same(s, ">=") || same(s, "gte") { ret (.Ge, true) }
    if same(s, "le") || same(s, "<=") || same(s, "lte") { ret (.Le, true) }
    if same(s, "in") { ret (.In, true) }
    if same(s, "not_in") || same(s, "notin") { ret (.NotIn, true) }
    if same(s, "contains") { ret (.Contains, true) }
    if same(s, "regex") || same(s, "matches") { ret (.Regex, true) }
    if same(s, "glob") { ret (.Glob, true) }
    if same(s, "present") || same(s, "exists") { ret (.Present, true) }
    if same(s, "absent") || same(s, "missing") { ret (.Absent, true) }
    if same(s, "any") { ret (.Any, true) }
    if same(s, "all") { ret (.All, true) }
    if same(s, "count") { ret (.Count, true) }
    ret (.Eq, false)
}

fn object_of(v: json.Value) -> ([]const json.Member, bool) {
    var none: []const json.Member = zero
    switch v {
    case .Object as fields:
        ret (fields, true)
    default:
        ret (none, false)
    }
}

fn is_comparison(op: Op) -> bool {
    ret op == .Eq || op == .Ne || op == .Gt || op == .Lt || op == .Ge || op == .Le
}

fn member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var none: json.Value = zero
    var i = 0usize
    while i < members.len {
        if same(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    ret (none, false)
}

fn string_of(v: json.Value) -> (str, bool) {
    switch v {
    case .String as s:
        ret (s, true)
    default:
        ret ("", false)
    }
}

fn is_number(v: json.Value) -> bool {
    switch v {
    case .Number as n:
        ret true
    default:
        ret false
    }
}

fn number_f64(v: json.Value) -> (f64, bool) {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok { ret (0.0f64, false) }
        ret (x, true)
    default:
        ret (0.0f64, false)
    }
}

// An integer value (no fraction or exponent in its text), as YAML's `as_i64` reads it.
fn integer_of(v: json.Value) -> (i64, bool) {
    switch v {
    case .Number as n:
        var i = 0usize
        while i < n.lexeme.len {
            let c = n.lexeme[i]
            if c == 46u8 || c == 101u8 || c == 69u8 { ret (0i64, false) }
            i += 1usize
        }
        let (x, e) = json.number_i64(n)
        if e != ok { ret (0i64, false) }
        ret (x, true)
    default:
        ret (0i64, false)
    }
}

fn parse_list(a: *mem.Arena, v: json.Value) -> ([]const Filter, err) {
    var none: []const Filter = zero
    switch v {
    case .Array as items:
        if items.len == 0usize { ret (none, ok) }
        let (out, out_error) = mem.alloc[Filter](a, items.len)
        if out_error != ok { ret (none, out_error) }
        var i = 0usize
        while i < items.len {
            let (f, e) = parse(a, items[i])
            if e != ok { ret (none, e) }
            out[i] = f
            i += 1usize
        }
        ret (out, ok)
    default:
        ret (none, NotList)
    }
}

fn single(a: *mem.Arena, f: Filter) -> ([]const Filter, err) {
    var none: []const Filter = zero
    let (out, out_error) = mem.alloc[Filter](a, 1usize)
    if out_error != ok { ret (none, out_error) }
    out[0usize] = f
    ret (out, ok)
}

// Parse a filter. A mapping with `builtin`, or with exactly one of `and`, `or` and `not`, is a combinator or a
// built-in; anything else is a leaf.
fn parse(a: *mem.Arena, v: json.Value) -> (Filter, err) {
    var f: Filter = zero
    var m: []const json.Member = zero
    switch v {
    case .Object as fields:
        m = fields
    default:
        ret (f, NotMapping)
    }
    let (builtin_value, has_builtin) = member(m, "builtin")
    if has_builtin {
        let (name, name_ok) = string_of(builtin_value)
        if name_ok {
            f.kind = .Builtin
            f.name = name
            let (args, has_args) = member(m, "args")
            f.args = args
            f.has_args = has_args
            // The ports built-in takes a list of at most 64 integers; a malformed
            // argument list is refused here rather than silently disabling the rule.
            if same(name, "sg_world_open_ports") && has_args {
                let (items, is_list) = json.array_of(args)
                if !is_list { ret (f, NotList) }
                if items.len > 64usize { ret (f, BadOp) }
                var i = 0usize
                while i < items.len {
                    let (_, is_port) = integer_of(items[i])
                    if !is_port { ret (f, BadOp) }
                    i += 1usize
                }
            }
            ret (f, ok)
        }
    }
    let (and_value, has_and) = member(m, "and")
    let (or_value, has_or) = member(m, "or")
    let (not_value, has_not) = member(m, "not")
    if has_and || has_or || has_not {
        if m.len != 1usize { ret (f, BoolNotAlone) }
        if has_and {
            f.kind = .And
            let (children, e) = parse_list(a, and_value)
            f.children = children
            ret (f, e)
        }
        if has_or {
            f.kind = .Or
            let (children, e) = parse_list(a, or_value)
            f.children = children
            ret (f, e)
        }
        f.kind = .Not
        let (inner, inner_error) = parse(a, not_value)
        if inner_error != ok { ret (f, inner_error) }
        let (children, children_error) = single(a, inner)
        f.children = children
        ret (f, children_error)
    }
    // A leaf.
    f.kind = .Leaf
    let (key_value, has_key) = member(m, "key")
    let (key, key_ok) = string_of(key_value)
    if !has_key || !key_ok { ret (f, MissingKey) }
    f.key = key
    let (value, has_value) = member(m, "value")
    f.value = value
    f.has_value = has_value
    let (op_value, has_op) = member(m, "op")
    let (op_text, op_text_ok) = string_of(op_value)
    var op = Op.Eq
    if has_op && op_text_ok {
        let (parsed, good) = parse_op(op_text)
        if !good { ret (f, BadOp) }
        op = parsed
    } else if !has_value {
        ret (f, MissingOp)
    }
    f.op = op
    let valueless = op == .Present || op == .Absent || op == .Any || op == .All
    if !valueless && !has_value { ret (f, MissingValue) }
    if op == .In || op == .NotIn {
        let (_, is_list) = json.array_of(value)
        if !is_list { ret (f, NotList) }
    }
    if op == .Regex {
        // Compile once here so evaluation of a large batch allocates nothing.
        let (pattern, pattern_ok) = string_of(value)
        if pattern_ok {
            let (program, program_error) = regex.compile(a, pattern, regex.Options { case_insensitive: false, multiline: false, dot_matches_newline: false })
            if program_error == ok {
                f.program = program
                f.compiled = true
            }
        }
    }
    let (element_value, has_element) = member(m, "element")
    if has_element {
        let (element, element_error) = parse(a, element_value)
        if element_error != ok { ret (f, element_error) }
        let (children, children_error) = single(a, element)
        if children_error != ok { ret (f, children_error) }
        f.element = children
    }
    if (op == .Any || op == .All) && !has_element { ret (f, MissingElement) }
    if op == .Count {
        if !is_number(value) { ret (f, CountNeedsNumber) }
        let (count_value, has_count) = member(m, "count_op")
        let (count_text, count_text_ok) = string_of(count_value)
        if has_count && count_text_ok {
            let (count_op, count_good) = parse_op(count_text)
            if !count_good { ret (f, BadOp) }
            if !is_comparison(count_op) { ret (f, BadCountOp) }
            f.count_op = count_op
            f.has_count_op = true
        }
    }
    ret (f, ok)
}

// ---------------------------------------------------------------------------
// Evaluation.

// The attribute at a dotted path, or false. The empty path is the attribute named "" (a scalar list element).
fn navigate(path: str, attrs: []const json.Member) -> (json.Value, bool) {
    var none: json.Value = zero
    if path.len == 0usize {
        let (named, has_named) = member(attrs, "")
        ret (named, has_named)
    }
    var start = 0usize
    var i = 0usize
    var current = none
    var first = true
    while i <= path.len {
        if i == path.len || path[i] == 46u8 {
            let part = path[start..i]
            if first {
                let (found, good) = member(attrs, part)
                if !good { ret (none, false) }
                current = found
                first = false
            } else {
                switch current {
                case .Object as inner:
                    let (found, good) = member(inner, part)
                    if !good { ret (none, false) }
                    current = found
                default:
                    ret (none, false)
                }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret (current, true)
}

fn is_scalar(v: json.Value) -> bool {
    switch v {
    case .Array as items:
        ret false
    case .Object as fields:
        ret false
    default:
        ret true
    }
}

// Scalar equality with number coercion; false for a list or object attribute.
fn scalar_eq(av: json.Value, want: json.Value) -> bool {
    if !is_scalar(av) { ret false }
    let (x, x_ok) = number_f64(av)
    let (y, y_ok) = number_f64(want)
    if x_ok && y_ok { ret x == y }
    switch av {
    case .Null:
        switch want {
        case .Null:
            ret true
        default:
            ret false
        }
    case .Bool as b:
        switch want {
        case .Bool as c:
            ret b == c
        default:
            ret false
        }
    case .String as s:
        switch want {
        case .String as t:
            ret same(s, t)
        default:
            ret false
        }
    default:
        ret false
    }
}

fn contains_text(s: str, needle: str) -> bool {
    if needle.len == 0usize { ret true }
    var i = 0usize
    while i + needle.len <= s.len {
        var j = 0usize
        while j < needle.len && s[i + j] == needle[j] { j += 1usize }
        if j == needle.len { ret true }
        i += 1usize
    }
    ret false
}

// `*` and `?` over Unicode scalars: the whole text must match. Allocation-free, so a
// long batch of evaluations cannot exhaust the caller's arena.
fn glob_match(a: *mem.Arena, pattern: str, text: str) -> bool {
    var pi = 0usize
    var ti = 0usize
    var star = 18446744073709551615usize
    var star_next = 0usize
    var mark = 0usize
    while ti < text.len {
        var have_p = pi < pattern.len
        var pscalar = 0u32
        var pwidth = 0u8
        if have_p {
            let (decoded, decode_error) = utf8.decode(pattern, pi)
            if decode_error != ok { ret false }
            pscalar = decoded.scalar
            pwidth = decoded.width
        }
        if have_p && pscalar == 42u32 {
            star = pi
            star_next = pi + usize(pwidth)
            mark = ti
            pi += usize(pwidth)
            continue
        }
        var matched = false
        let (tdecoded, text_error) = utf8.decode(text, ti)
        if text_error != ok { ret false }
        if have_p && (pscalar == 63u32 || pscalar == tdecoded.scalar) {
            pi += usize(pwidth)
            ti += usize(tdecoded.width)
            matched = true
        }
        if matched { continue }
        if star == 18446744073709551615usize || mark >= text.len { ret false }
        let (advance, advance_error) = utf8.decode(text, mark)
        if advance_error != ok { ret false }
        mark += usize(advance.width)
        ti = mark
        pi = star_next
    }
    while pi < pattern.len {
        let (decoded, decode_error) = utf8.decode(pattern, pi)
        if decode_error != ok { ret false }
        if decoded.scalar != 42u32 { ret false }
        pi += usize(decoded.width)
    }
    ret true
}

fn compare(a: *mem.Arena, op: Op, av: json.Value, want: json.Value) -> bool {
    if op == .Eq { ret scalar_eq(av, want) }
    if op == .Ne { ret !scalar_eq(av, want) }
    if op == .Gt || op == .Lt || op == .Ge || op == .Le {
        let (x, x_ok) = number_f64(av)
        let (y, y_ok) = number_f64(want)
        if !x_ok || !y_ok { ret false }
        if op == .Gt { ret x > y }
        if op == .Lt { ret x < y }
        if op == .Ge { ret x >= y }
        ret x <= y
    }
    if op == .In || op == .NotIn {
        var found = false
        switch want {
        case .Array as items:
            var i = 0usize
            while i < items.len {
                if scalar_eq(av, items[i]) { found = true }
                i += 1usize
            }
        default:
            found = false
        }
        if op == .In { ret found }
        ret !found
    }
    if op == .Contains {
        switch av {
        case .Array as items:
            var i = 0usize
            while i < items.len {
                if scalar_eq(items[i], want) { ret true }
                i += 1usize
            }
            ret false
        case .String as s:
            let (needle, needle_ok) = string_of(want)
            if !needle_ok { ret false }
            ret contains_text(s, needle)
        default:
            ret false
        }
    }
    if op == .Regex {
        let (s, s_ok) = string_of(av)
        let (pattern, pattern_ok) = string_of(want)
        if !s_ok || !pattern_ok { ret false }
        let (compiled, compile_error) = regex.compile(a, pattern, regex.Options { case_insensitive: false, multiline: false, dot_matches_newline: false })
        if compile_error != ok { ret false }
        ret regex.is_match(&compiled, s)
    }
    if op == .Glob {
        let (s, s_ok) = string_of(av)
        let (pattern, pattern_ok) = string_of(want)
        if !s_ok || !pattern_ok { ret false }
        ret glob_match(a, pattern, s)
    }
    ret false
}

// A list element as an attribute bag: an object is its own bag, anything else is the bag {"": element}.
fn element_matches(a: *mem.Arena, sub: *const Filter, element: json.Value) -> bool {
    switch element {
    case .Object as fields:
        ret eval(a, sub, fields)
    default:
        var bag: [1]json.Member = zero
        bag[0usize] = json.Member { key: "", value: element }
        ret eval(a, sub, bag[0..])
    }
}

fn eval_leaf(a: *mem.Arena, f: *const Filter, attrs: []const json.Member) -> bool {
    let (resolved, found) = navigate(f.key, attrs)
    if f.op == .Present { ret found }
    if f.op == .Absent { ret !found }
    if f.op == .Any || f.op == .All {
        if !found { ret false }
        switch resolved {
        case .Array as items:
            var i = 0usize
            while i < items.len {
                let hit = element_matches(a, &f.element[0usize], items[i])
                if f.op == .Any && hit { ret true }
                if f.op == .All && !hit { ret false }
                i += 1usize
            }
            ret f.op == .All
        default:
            ret false
        }
    }
    if f.op == .Count {
        if !found { ret false }
        switch resolved {
        case .Array as items:
            var n = 0usize
            if f.element.len == 1usize {
                var i = 0usize
                while i < items.len {
                    if element_matches(a, &f.element[0usize], items[i]) { n += 1usize }
                    i += 1usize
                }
            } else {
                n = items.len
            }
            var op = Op.Eq
            if f.has_count_op { op = f.count_op }
            let (wanted_count, wanted_ok) = number_f64(f.value)
            if !wanted_ok { ret false }
            let actual = f64(n)
            if op == .Eq { ret actual == wanted_count }
            if op == .Ne { ret actual != wanted_count }
            if op == .Gt { ret actual > wanted_count }
            if op == .Lt { ret actual < wanted_count }
            if op == .Ge { ret actual >= wanted_count }
            ret actual <= wanted_count
        default:
            ret false
        }
    }
    if !found { ret false }
    if f.op == .Regex {
        let (text, text_ok) = string_of(resolved)
        if !text_ok || !f.compiled { ret false }
        ret regex.is_match(&f.program, text)
    }
    ret compare(a, f.op, resolved, f.value)
}

fn digits_of(a: *mem.Arena, n: usize) -> str {
    let (number, e) = json.number_from_u64(a, u64(n))
    if e != ok { ret "0" }
    ret number.lexeme
}

// ---------------------------------------------------------------------------
// Built-in predicates.

fn world_open(rule: []const json.Member) -> bool {
    let (cidr, has_cidr) = member(rule, "cidr")
    if !has_cidr { ret false }
    let (text, text_ok) = string_of(cidr)
    ret text_ok && same(text, "0.0.0.0/0")
}

fn rule_port(rule: []const json.Member, key: str) -> (i64, bool) {
    let (v, has) = member(rule, key)
    if !has { ret (0i64, false) }
    let (port, good) = integer_of(v)
    ret (port, good)
}

// Whether any world-open ingress rule covers one of `ports`: inside its from_port..to_port range, or by its single
// bound, or because it has no port bounds at all (every port).
fn sg_world_open_ports(attrs: []const json.Member, ports: []const i64) -> bool {
    let (ingress, has) = member(attrs, "ingress")
    if !has { ret false }
    switch ingress {
    case .Array as rules:
        var r = 0usize
        while r < rules.len {
            let (rule, is_rule) = object_of(rules[r])
            if is_rule && world_open(rule) {
                let (from_value, has_from) = member(rule, "from_port")
                let (from, from_ok) = integer_of(from_value)
                let (to_value, has_to) = member(rule, "to_port")
                let (to, to_ok) = integer_of(to_value)
                // A bound that is present but not an integer cannot be trusted, so the
                // rule is not proved world-open instead of being treated as unbounded.
                if (has_from && !from_ok) || (has_to && !to_ok) {
                    r += 1usize
                    continue
                }
                if has_from && has_to {
                    var p = 0usize
                    while p < ports.len {
                        if from <= ports[p] && ports[p] <= to { ret true }
                        p += 1usize
                    }
                } else if has_from || has_to {
                    var single_port = from
                    if !has_from { single_port = to }
                    var p = 0usize
                    while p < ports.len {
                        if ports[p] == single_port { ret true }
                        p += 1usize
                    }
                } else {
                    ret true
                }
            }
            r += 1usize
        }
        ret false
    default:
        ret false
    }
}

fn equals_ignore_case(text: str, word: str) -> bool {
    if text.len != word.len { ret false }
    var i = 0usize
    while i < text.len {
        if lower_byte(text[i]) != lower_byte(word[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn sg_world_open_all_protocols(attrs: []const json.Member) -> bool {
    let (ingress, has) = member(attrs, "ingress")
    if !has { ret false }
    switch ingress {
    case .Array as rules:
        var r = 0usize
        while r < rules.len {
            let (rule, is_rule) = object_of(rules[r])
            if is_rule && world_open(rule) {
                let (protocol, has_protocol) = member(rule, "protocol")
                if has_protocol {
                    let (text, text_ok) = string_of(protocol)
                    if text_ok && (same(text, "-1") || equals_ignore_case(text, "all")) { ret true }
                }
            }
            r += 1usize
        }
        ret false
    default:
        ret false
    }
}

fn is_star(v: json.Value) -> bool {
    let (text, text_ok) = string_of(v)
    ret text_ok && same(text, "*")
}

fn principal_has_wildcard(p: json.Value, has: bool) -> bool {
    if !has { ret false }
    switch p {
    case .String as s:
        ret same(s, "*")
    case .Object as fields:
        var i = 0usize
        while i < fields.len {
            switch fields[i].value {
            case .Array as items:
                var k = 0usize
                while k < items.len {
                    if is_star(items[k]) { ret true }
                    k += 1usize
                }
            default:
                if is_star(fields[i].value) { ret true }
            }
            i += 1usize
        }
        ret false
    case .Array as items:
        var k = 0usize
        while k < items.len {
            if is_star(items[k]) { ret true }
            k += 1usize
        }
        ret false
    default:
        ret false
    }
}

fn statement_allows_wildcard(statement: []const json.Member) -> bool {
    let (effect, has_effect) = member(statement, "Effect")
    if !has_effect { ret false }
    let (effect_text, effect_ok) = string_of(effect)
    if !effect_ok || !same(effect_text, "Allow") { ret false }
    let (principal, has_principal) = member(statement, "Principal")
    ret principal_has_wildcard(principal, has_principal)
}

// Whether `assume_role_policy` Allows a wildcard principal: `"*"`, `{AWS: "*"}` or `{AWS: ["*"]}`.
fn iam_wildcard_principal(attrs: []const json.Member) -> bool {
    let (policy_value, has) = member(attrs, "assume_role_policy")
    if !has { ret false }
    switch policy_value {
    case .Object as policy:
        let (statements, has_statements) = member(policy, "Statement")
        if !has_statements { ret false }
        switch statements {
        case .Array as items:
            var i = 0usize
            while i < items.len {
                let (statement, is_statement) = object_of(items[i])
                if is_statement && statement_allows_wildcard(statement) { ret true }
                i += 1usize
            }
            ret false
        case .Object as statement:
            ret statement_allows_wildcard(statement)
        default:
            ret false
        }
    default:
        ret false
    }
}

fn eval_builtin(a: *mem.Arena, f: *const Filter, attrs: []const json.Member) -> bool {
    if same(f.name, "sg_world_open_ports") {
        var ports: [64]i64 = zero
        var n = 0usize
        if f.has_args {
            switch f.args {
            case .Array as items:
                var i = 0usize
                while i < items.len && n < 64usize {
                    let (port, good) = integer_of(items[i])
                    if good {
                        ports[n] = port
                        n += 1usize
                    }
                    i += 1usize
                }
            default:
                n = 0usize
            }
        }
        ret sg_world_open_ports(attrs, ports[0usize..n])
    }
    if same(f.name, "sg_world_open_all_protocols") { ret sg_world_open_all_protocols(attrs) }
    if same(f.name, "iam_wildcard_principal") { ret iam_wildcard_principal(attrs) }
    ret false
}

// Whether the filter holds for the attribute bag.
fn eval(a: *mem.Arena, f: *const Filter, attrs: []const json.Member) -> bool {
    if f.kind == .And {
        var i = 0usize
        while i < f.children.len {
            if !eval(a, &f.children[i], attrs) { ret false }
            i += 1usize
        }
        ret true
    }
    if f.kind == .Or {
        var i = 0usize
        while i < f.children.len {
            if eval(a, &f.children[i], attrs) { ret true }
            i += 1usize
        }
        ret false
    }
    if f.kind == .Not { ret !eval(a, &f.children[0usize], attrs) }
    if f.kind == .Builtin { ret eval_builtin(a, f, attrs) }
    ret eval_leaf(a, f, attrs)
}
