// XML Schema 1.0 validation of an XML instance, over e.fmt.xml and the built-in datatypes of
// e.fmt.xsd. `load` compiles a schema document (one file; no import, include or redefine) into
// type, element and particle tables in an arena; `validate` walks an instance and reports the first
// error with the node it concerns.
//
// Covered: global and local elements and attributes (form, use, default, fixed, nillable via
// xsi:nil), named and anonymous simple types (restriction with the facets length, minLength,
// maxLength, pattern, enumeration, whiteSpace, min/maxInclusive, min/maxExclusive, totalDigits and
// fractionDigits; list; union) and complex types (empty, simple and element content, mixed, sequence,
// choice, all, any, minOccurs and maxOccurs, element and attribute groups, extension and restriction
// of complex and simple content, anyAttribute), ID uniqueness and IDREF resolution.
// Refused at load (`Unsupported`): import, include, redefine, substitutionGroup, abstract, key, keyref,
// unique, notation, xsi:type, and a pattern using \i \I \c \C, class subtraction or \p{...}.
// Limits stated honestly: `\d \w \s` in a pattern are the ASCII ones (the regex engine's); ordered facets
// on date and time types compare as UTC when a value has no zone; the g* types, duration and QName do
// not take ordered facets; and an element's content is matched by the particle tree, not by a compiled
// automaton, so a schema that breaks Unique Particle Attribution is validated by the union of its readings.

use e.fmt.xml as xml
use e.fmt.xsd as xsd
use e.mem
use e.str
use e.text.regex as regex
use e.text.utf8

error Invalid
error Unsupported
error Unresolved
error TooComplex

const NONE: u32 = 4294967295u32
const UNBOUNDED: u32 = 4294967295u32
const ANY_TYPE: u32 = 39u32
const ANY_SIMPLE_TYPE: u32 = 40u32
const BUILTINS: usize = 41usize

type Variety = enum u8 { Atomic, List, Union }
type ParticleKind = enum u8 { Element, Sequence, Choice, All, Any }
type Content = enum u8 { Empty, Simple, Elements, Mixed }

type Facets = struct {
    has_length: bool, length: u64, has_min_length: bool, min_length: u64, has_max_length: bool, max_length: u64,
    has_total: bool, total_digits: u64, has_fraction: bool, fraction_digits: u64,
    has_whitespace: bool, whitespace: xsd.Whitespace, enumeration: []str,
    has_pattern: bool, pattern: regex.Regex,
    has_min_inclusive: bool, min_inclusive: str, has_max_inclusive: bool, max_inclusive: str,
    has_min_exclusive: bool, min_exclusive: str, has_max_exclusive: bool, max_exclusive: str,
}

type AttrUse = struct { name: str, ns: str, type_index: u32, required: bool, prohibited: bool, has_fixed: bool, fixed: str }

type TypeDef = struct {
    name: str, ns: str, complex: bool, builtin: bool,
    variety: Variety, base: u32, item: u32, members: []u32, facets: Facets,
    content: Content, particle: u32, attributes: []AttrUse, any_attribute: bool, simple_type: u32, attr_rule: str, attr_tns: str,
}

type Particle = struct { kind: ParticleKind, min: u32, max: u32, element: u32, children: []u32, rule: str, rule_tns: str }
type ElementDecl = struct { name: str, ns: str, type_index: u32, nillable: bool, has_fixed: bool, fixed: str }

type Schema = struct {
    types: []TypeDef, type_count: usize, particles: []Particle, particle_count: usize,
    elements: []ElementDecl, element_count: usize, roots: []u32, root_count: usize, target_namespace: str,
}

type ErrorCode = enum u8 {
    None, UnknownRoot, UnexpectedElement, MissingContent, UnknownAttribute, MissingAttribute, BadValue, BadAttributeValue,
    NotEmpty, TextNotAllowed, FixedMismatch, NilNotAllowed, DuplicateId, UnresolvedIdref, ProhibitedAttribute,
}

type Result = struct { valid: bool, code: ErrorCode, node: xml.NodeId }

fn xs_namespace() -> str { ret "http://www.w3.org/2001/XMLSchema" }
fn xsi_namespace() -> str { ret "http://www.w3.org/2001/XMLSchema-instance" }

fn same(a: str, b: str) -> bool { ret str.eq(a, b) }

// ---- DOM helpers (namespace resolution through the document's own xmlns attributes) ----

fn node(d: *const xml.Document, id: xml.NodeId) -> xml.Node { ret d.nodes[usize(id)] }

fn split_name(name: str) -> (str, str) {
    let (at, found) = str.find(name, ":")
    if !found { ret ("", name) }
    ret (name[..at], name[at + 1usize..])
}

fn declares(attribute_name: str, prefix: str) -> bool {
    if prefix.len == 0usize { ret same(attribute_name, "xmlns") }
    ret attribute_name.len == prefix.len + 6usize && str.starts_with(attribute_name, "xmlns:") && same(attribute_name[6usize..], prefix)
}

fn resolve(d: *const xml.Document, id: xml.NodeId, prefix: str) -> (str, err) {
    if same(prefix, "xml") { ret ("http://www.w3.org/XML/1998/namespace", ok) }
    var at = id
    while at != NONE {
        let n = node(d, at)
        if n.kind == .Element {
            var i = 0usize
            while i < n.attributes.len {
                if declares(n.attributes[i].name, prefix) { ret (n.attributes[i].value, ok) }
                i += 1usize
            }
        }
        at = n.parent
    }
    if prefix.len == 0usize { ret ("", ok) }
    ret ("", Unresolved)
}

fn expand(d: *const xml.Document, id: xml.NodeId) -> (str, str, err) {
    let (prefix, local) = split_name(node(d, id).name)
    let (uri, resolve_error) = resolve(d, id, prefix)
    ret (uri, local, resolve_error)
}

fn is_named(d: *const xml.Document, id: xml.NodeId, uri: str, local: str) -> bool {
    if node(d, id).kind != .Element { ret false }
    let (found_uri, found_local, expand_error) = expand(d, id)
    ret expand_error == ok && same(found_uri, uri) && same(found_local, local)
}

fn next_element(d: *const xml.Document, from: xml.NodeId) -> xml.NodeId {
    var at = from
    while at != NONE {
        if node(d, at).kind == .Element { ret at }
        at = node(d, at).next_sibling
    }
    ret NONE
}

fn first_child_element(d: *const xml.Document, parent: xml.NodeId) -> xml.NodeId { ret next_element(d, node(d, parent).first_child) }
fn next_sibling_element(d: *const xml.Document, id: xml.NodeId) -> xml.NodeId { ret next_element(d, node(d, id).next_sibling) }

fn attr(d: *const xml.Document, id: xml.NodeId, name: str) -> (str, bool) {
    let n = node(d, id)
    let (value, found) = xml.attribute(&n, name)
    ret (value, found)
}

fn attr_or(d: *const xml.Document, id: xml.NodeId, name: str, fallback: str) -> str {
    let (value, found) = attr(d, id, name)
    if found { ret value }
    ret fallback
}

fn element_text(a: *mem.Arena, d: *const xml.Document, id: xml.NodeId) -> (str, err) {
    var out = ""
    var at = node(d, id).first_child
    var parts = 0usize
    while at != NONE {
        if node(d, at).kind == .Text {
            if parts == 0usize {
                out = node(d, at).value
            } else {
                let (joined, join_error) = str.concat(a, out, node(d, at).value)
                if join_error != ok { ret ("", join_error) }
                out = joined
            }
            parts += 1usize
        }
        at = node(d, at).next_sibling
    }
    ret (out, ok)
}

fn is_blank(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        if !xsd.is_space(text[i]) { ret false }
        i += 1usize
    }
    ret true
}

// ---- compilation ----

type Named = struct { kind: u8, name: str, node: xml.NodeId, index: u32 }

type Compiler = struct {
    a: *mem.Arena, d: *const xml.Document, s: Schema, tns: str, wildcard_rule: str,
    element_qualified: bool, attribute_qualified: bool,
    named: []Named, named_count: usize, depth: u32,
}

fn new_type(c: *Compiler) -> (u32, err) {
    if c.s.type_count >= c.s.types.len { ret (NONE, TooComplex) }
    let at = c.s.type_count
    c.s.types[at] = simple_def("", "")
    c.s.type_count += 1usize
    ret (u32(at), ok)
}

fn empty_facets() -> Facets {
    ret Facets {
        has_length: false, length: 0u64, has_min_length: false, min_length: 0u64, has_max_length: false, max_length: 0u64,
        has_total: false, total_digits: 0u64, has_fraction: false, fraction_digits: 0u64,
        has_whitespace: false, whitespace: xsd.Whitespace.Preserve, enumeration: zero,
        has_pattern: false, pattern: zero,
        has_min_inclusive: false, min_inclusive: "", has_max_inclusive: false, max_inclusive: "",
        has_min_exclusive: false, min_exclusive: "", has_max_exclusive: false, max_exclusive: "",
    }
}

fn simple_def(name: str, ns: str) -> TypeDef {
    ret TypeDef {
        name: name, ns: ns, complex: false, builtin: false, variety: Variety.Atomic, base: NONE, item: NONE, members: zero, facets: empty_facets(),
        content: Content.Empty, particle: NONE, attributes: zero, any_attribute: false, simple_type: NONE, attr_rule: "##any", attr_tns: "",
    }
}

fn builtin_names() -> [39]str {
    ret [39]str{
        "string", "normalizedString", "token", "language", "Name", "NCName", "NMTOKEN", "ID", "IDREF", "anyURI", "QName",
        "boolean", "decimal", "integer", "nonPositiveInteger", "negativeInteger", "nonNegativeInteger", "positiveInteger",
        "long", "int", "short", "byte", "unsignedLong", "unsignedInt", "unsignedShort", "unsignedByte",
        "float", "double", "duration", "dateTime", "time", "date", "gYearMonth", "gYear", "gMonthDay", "gDay", "gMonth",
        "hexBinary", "base64Binary",
    }
}

// The index of a built-in type by local name (the enum order of e.fmt.xsd.Type), or NONE.
fn builtin_index(local: str) -> u32 {
    if same(local, "anyType") { ret ANY_TYPE }
    if same(local, "anySimpleType") { ret ANY_SIMPLE_TYPE }
    let names = builtin_names()
    var i = 0usize
    while i < 39usize {
        if same(names[i], local) { ret u32(i) }
        i += 1usize
    }
    ret NONE
}

fn builtin_type(index: u32) -> xsd.Type {
    let names = builtin_names()
    let (t, _) = xsd.type_named(names[usize(index)])
    ret t
}

fn init_builtins(s: *Schema) {
    let names = builtin_names()
    var i = 0usize
    while i < 39usize {
        var def = simple_def(names[i], xs_namespace())
        def.builtin = true
        s.types[i] = def
        i += 1usize
    }
    var any_type = simple_def("anyType", xs_namespace())
    any_type.builtin = true
    any_type.complex = true
    any_type.content = Content.Mixed
    any_type.any_attribute = true
    s.types[39usize] = any_type
    var any_simple = simple_def("anySimpleType", xs_namespace())
    any_simple.builtin = true
    s.types[40usize] = any_simple
    s.type_count = BUILTINS
}

fn new_particle(c: *Compiler, kind: ParticleKind, min: u32, max: u32) -> (u32, err) {
    if c.s.particle_count >= c.s.particles.len { ret (NONE, TooComplex) }
    let at = c.s.particle_count
    c.s.particles[at] = Particle { kind: kind, min: min, max: max, element: NONE, children: zero, rule: "##any", rule_tns: "" }
    c.s.particle_count += 1usize
    ret (u32(at), ok)
}

fn new_element(c: *Compiler, name: str, ns: str, type_index: u32) -> (u32, err) {
    if c.s.element_count >= c.s.elements.len { ret (NONE, TooComplex) }
    let at = c.s.element_count
    c.s.elements[at] = ElementDecl { name: name, ns: ns, type_index: type_index, nillable: false, has_fixed: false, fixed: "" }
    c.s.element_count += 1usize
    ret (u32(at), ok)
}

fn xs(c: *const Compiler, id: xml.NodeId, local: str) -> bool { ret is_named(c.d, id, xs_namespace(), local) }

// Reject the constructs this validator does not implement, wherever they stand.
fn unsupported_marker(c: *const Compiler, id: xml.NodeId) -> bool {
    let (uri, local, e) = expand(c.d, id)
    if e != ok || !same(uri, xs_namespace()) { ret false }
    ret same(local, "import") || same(local, "include") || same(local, "redefine") || same(local, "key") || same(local, "keyref") || same(local, "unique") || same(local, "notation")
}

fn register(c: *Compiler, kind: u8, name: str, id: xml.NodeId, index: u32) -> err {
    if c.named_count >= c.named.len { ret TooComplex }
    var i = 0usize
    while i < c.named_count {
        if c.named[i].kind == kind && same(c.named[i].name, name) { ret Invalid }
        i += 1usize
    }
    c.named[c.named_count] = Named { kind: kind, name: name, node: id, index: index }
    c.named_count += 1usize
    ret ok
}

fn lookup(c: *const Compiler, kind: u8, name: str) -> (Named, bool) {
    var i = 0usize
    while i < c.named_count {
        if c.named[i].kind == kind && same(c.named[i].name, name) { ret (c.named[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

// A QName attribute value (`xs:int`, `tns:Name`, `Name`) as the namespace and local part, resolved at `id`.
fn qname(c: *const Compiler, id: xml.NodeId, text: str) -> (str, str, err) {
    let (prefix, local) = split_name(str.trim(text))
    let (uri, resolve_error) = resolve(c.d, id, prefix)
    ret (uri, local, resolve_error)
}

fn type_ref(c: *Compiler, id: xml.NodeId, text: str) -> (u32, err) {
    let (uri, local, qname_error) = qname(c, id, text)
    if qname_error != ok { ret (NONE, qname_error) }
    if same(uri, xs_namespace()) {
        let found = builtin_index(local)
        if found == NONE { ret (NONE, Unresolved) }
        ret (found, ok)
    }
    if !same(uri, c.tns) { ret (NONE, Unresolved) }
    let (entry, present) = lookup(c, 1u8, local)
    if !present { ret (NONE, Unresolved) }
    ret (entry.index, ok)
}

fn parse_u64(text: str) -> (u64, bool) {
    let t = str.trim(text)
    if t.len == 0usize || t.len > 18usize { ret (0u64, false) }
    var v = 0u64
    var i = 0usize
    while i < t.len {
        if !xsd.is_digit(t[i]) { ret (0u64, false) }
        v = v * 10u64 + u64(t[i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

fn occurs(c: *const Compiler, id: xml.NodeId) -> (u32, u32, err) {
    var min = 1u32
    var max = 1u32
    let (min_text, has_min) = attr(c.d, id, "minOccurs")
    if has_min {
        let (v, v_ok) = parse_u64(min_text)
        if !v_ok || v > 100000u64 { ret (0u32, 0u32, Invalid) }
        min = u32(v)
    }
    let (max_text, has_max) = attr(c.d, id, "maxOccurs")
    if has_max {
        if same(str.trim(max_text), "unbounded") {
            max = UNBOUNDED
        } else {
            let (v, v_ok) = parse_u64(max_text)
            if !v_ok || v > 100000u64 { ret (0u32, 0u32, Invalid) }
            max = u32(v)
        }
    }
    if max != UNBOUNDED && min > max { ret (0u32, 0u32, Invalid) }
    ret (min, max, ok)
}

// ---- simple types ----

fn parse_whitespace(text: str) -> (xsd.Whitespace, bool) {
    let t = str.trim(text)
    if same(t, "preserve") { ret (xsd.Whitespace.Preserve, true) }
    if same(t, "replace") { ret (xsd.Whitespace.Replace, true) }
    if same(t, "collapse") { ret (xsd.Whitespace.Collapse, true) }
    ret (xsd.Whitespace.Preserve, false)
}

fn compile_pattern(c: *Compiler, groups: []const str) -> (regex.Regex, err) {
    var joined = ""
    var i = 0usize
    while i < groups.len {
        let p = groups[i]
        if str.contains(p, "\\i") || str.contains(p, "\\I") || str.contains(p, "\\c") || str.contains(p, "\\C") || str.contains(p, "-[") || str.contains(p, "\\p") || str.contains(p, "\\P") { ret (zero, Unsupported) }
        let (open, open_error) = str.concat(c.a, "(?:", p)
        if open_error != ok { ret (zero, open_error) }
        let (closed, closed_error) = str.concat(c.a, open, ")")
        if closed_error != ok { ret (zero, closed_error) }
        if i == 0usize {
            joined = closed
        } else {
            let (bar, bar_error) = str.concat(c.a, joined, "|")
            if bar_error != ok { ret (zero, bar_error) }
            let (next, next_error) = str.concat(c.a, bar, closed)
            if next_error != ok { ret (zero, next_error) }
            joined = next
        }
        i += 1usize
    }
    let (head, head_error) = str.concat(c.a, "^(?:", joined)
    if head_error != ok { ret (zero, head_error) }
    let (whole, whole_error) = str.concat(c.a, head, ")$")
    if whole_error != ok { ret (zero, whole_error) }
    let (compiled, compile_error) = regex.compile(c.a, whole, regex.Options { case_insensitive: false, multiline: false, dot_matches_newline: true })
    if compile_error != ok { ret (zero, Unsupported) }
    ret (compiled, ok)
}

fn count_children(c: *const Compiler, id: xml.NodeId, local: str) -> usize {
    var count = 0usize
    var at = first_child_element(c.d, id)
    while at != NONE {
        if xs(c, at, local) { count += 1usize }
        at = next_sibling_element(c.d, at)
    }
    ret count
}

fn one_u64(c: *const Compiler, id: xml.NodeId) -> (u64, err) {
    let (text, _) = attr(c.d, id, "value")
    let (v, v_ok) = parse_u64(text)
    if !v_ok { ret (0u64, Invalid) }
    ret (v, ok)
}

// The facets of one restriction element into `f`.
fn compile_facets(c: *Compiler, restriction: xml.NodeId, f: *Facets) -> err {
    let enumerations = count_children(c, restriction, "enumeration")
    if enumerations > 0usize {
        let (values, alloc_error) = mem.alloc[str](c.a, enumerations)
        if alloc_error != ok { ret alloc_error }
        var used = 0usize
        var at = first_child_element(c.d, restriction)
        while at != NONE {
            if xs(c, at, "enumeration") {
                values[used] = attr_or(c.d, at, "value", "")
                used += 1usize
            }
            at = next_sibling_element(c.d, at)
        }
        f.enumeration = values[..used]
    }
    let pattern_count = count_children(c, restriction, "pattern")
    if pattern_count > 0usize {
        let (groups, alloc_error) = mem.alloc[str](c.a, pattern_count)
        if alloc_error != ok { ret alloc_error }
        var used = 0usize
        var at = first_child_element(c.d, restriction)
        while at != NONE {
            if xs(c, at, "pattern") {
                groups[used] = attr_or(c.d, at, "value", "")
                used += 1usize
            }
            at = next_sibling_element(c.d, at)
        }
        let (compiled, pattern_error) = compile_pattern(c, groups[..used])
        if pattern_error != ok { ret pattern_error }
        f.has_pattern = true
        f.pattern = compiled
    }
    var at = first_child_element(c.d, restriction)
    while at != NONE {
        let (uri, local, e) = expand(c.d, at)
        if e == ok && same(uri, xs_namespace()) {
            if same(local, "length") {
                let (v, ve) = one_u64(c, at)
                if ve != ok { ret ve }
                f.has_length = true
                f.length = v
            } else if same(local, "minLength") {
                let (v, ve) = one_u64(c, at)
                if ve != ok { ret ve }
                f.has_min_length = true
                f.min_length = v
            } else if same(local, "maxLength") {
                let (v, ve) = one_u64(c, at)
                if ve != ok { ret ve }
                f.has_max_length = true
                f.max_length = v
            } else if same(local, "totalDigits") {
                let (v, ve) = one_u64(c, at)
                if ve != ok || v == 0u64 { ret Invalid }
                f.has_total = true
                f.total_digits = v
            } else if same(local, "fractionDigits") {
                let (v, ve) = one_u64(c, at)
                if ve != ok { ret ve }
                f.has_fraction = true
                f.fraction_digits = v
            } else if same(local, "whiteSpace") {
                let (w, w_ok) = parse_whitespace(attr_or(c.d, at, "value", ""))
                if !w_ok { ret Invalid }
                f.has_whitespace = true
                f.whitespace = w
            } else if same(local, "minInclusive") {
                f.has_min_inclusive = true
                f.min_inclusive = attr_or(c.d, at, "value", "")
            } else if same(local, "maxInclusive") {
                f.has_max_inclusive = true
                f.max_inclusive = attr_or(c.d, at, "value", "")
            } else if same(local, "minExclusive") {
                f.has_min_exclusive = true
                f.min_exclusive = attr_or(c.d, at, "value", "")
            } else if same(local, "maxExclusive") {
                f.has_max_exclusive = true
                f.max_exclusive = attr_or(c.d, at, "value", "")
            }
        }
        at = next_sibling_element(c.d, at)
    }
    ret ok
}

fn first_xs_child(c: *const Compiler, id: xml.NodeId, local: str) -> xml.NodeId {
    var at = first_child_element(c.d, id)
    while at != NONE {
        if xs(c, at, local) { ret at }
        at = next_sibling_element(c.d, at)
    }
    ret NONE
}

// The simple type named by `attribute_name` on `id`, or declared inline as a simpleType child.
fn simple_of(c: *Compiler, id: xml.NodeId, attribute_name: str) -> (u32, err) {
    let (text, has) = attr(c.d, id, attribute_name)
    if has {
        let (named, named_error) = type_ref(c, id, text)
        ret (named, named_error)
    }
    let inline = first_xs_child(c, id, "simpleType")
    if inline == NONE { ret (NONE, Invalid) }
    let (index, new_error) = new_type(c)
    if new_error != ok { ret (NONE, new_error) }
    let compile_error = compile_simple(c, inline, index)
    if compile_error != ok { ret (NONE, compile_error) }
    ret (index, ok)
}

fn compile_simple(c: *Compiler, id: xml.NodeId, index: u32) -> err {
    if c.depth > 64u32 { ret TooComplex }
    c.depth += 1u32
    var def = simple_def(c.s.types[usize(index)].name, c.s.types[usize(index)].ns)
    let restriction = first_xs_child(c, id, "restriction")
    let list = first_xs_child(c, id, "list")
    let union_node = first_xs_child(c, id, "union")
    if restriction != NONE {
        let (base, base_error) = simple_of(c, restriction, "base")
        if base_error != ok {
            c.depth -= 1u32
            ret base_error
        }
        if c.s.types[usize(base)].complex {
            c.depth -= 1u32
            ret Invalid
        }
        def.base = base
        def.variety = c.s.types[usize(base)].variety
        def.item = c.s.types[usize(base)].item
        def.members = c.s.types[usize(base)].members
        let facet_error = compile_facets(c, restriction, &def.facets)
        if facet_error != ok {
            c.depth -= 1u32
            ret facet_error
        }
    } else if list != NONE {
        let (item, item_error) = simple_of(c, list, "itemType")
        if item_error != ok {
            c.depth -= 1u32
            ret item_error
        }
        def.variety = Variety.List
        def.item = item
        def.base = ANY_SIMPLE_TYPE
    } else if union_node != NONE {
        var count = count_children(c, union_node, "simpleType")
        let (member_text, has_members) = attr(c.d, union_node, "memberTypes")
        var named_members = 0usize
        if has_members {
            let (parts, split_error) = str.split(str.trim(member_text), " ")
            if split_error != ok {
                c.depth -= 1u32
                ret split_error
            }
            var it = parts
            while true {
                let (piece, more) = str.split_next(&it)
                if !more { break }
                if str.trim(piece).len > 0usize { named_members += 1usize }
            }
        }
        count += named_members
        if count == 0usize {
            c.depth -= 1u32
            ret Invalid
        }
        let (members, alloc_error) = mem.alloc[u32](c.a, count)
        if alloc_error != ok {
            c.depth -= 1u32
            ret alloc_error
        }
        var used = 0usize
        if has_members {
            let (parts, split_error) = str.split(str.trim(member_text), " ")
            if split_error != ok {
                c.depth -= 1u32
                ret split_error
            }
            var it = parts
            while true {
                let (piece, more) = str.split_next(&it)
                if !more { break }
                if str.trim(piece).len > 0usize {
                    let (member, member_error) = type_ref(c, union_node, piece)
                    if member_error != ok {
                        c.depth -= 1u32
                        ret member_error
                    }
                    members[used] = member
                    used += 1usize
                }
            }
        }
        var at = first_child_element(c.d, union_node)
        while at != NONE {
            if xs(c, at, "simpleType") {
                let (inline_index, new_error) = new_type(c)
                if new_error != ok {
                    c.depth -= 1u32
                    ret new_error
                }
                let compile_error = compile_simple(c, at, inline_index)
                if compile_error != ok {
                    c.depth -= 1u32
                    ret compile_error
                }
                members[used] = inline_index
                used += 1usize
            }
            at = next_sibling_element(c.d, at)
        }
        def.variety = Variety.Union
        def.members = members[..used]
        def.base = ANY_SIMPLE_TYPE
    } else {
        c.depth -= 1u32
        ret Invalid
    }
    c.s.types[usize(index)] = def
    c.depth -= 1u32
    ret ok
}

// ---- complex types ----

fn attribute_form(c: *const Compiler, id: xml.NodeId) -> str {
    let form = attr_or(c.d, id, "form", "")
    if same(form, "qualified") || (form.len == 0usize && c.attribute_qualified) { ret c.tns }
    ret ""
}

fn element_form(c: *const Compiler, id: xml.NodeId) -> str {
    let form = attr_or(c.d, id, "form", "")
    if same(form, "qualified") || (form.len == 0usize && c.element_qualified) { ret c.tns }
    ret ""
}

fn count_attribute_decls(c: *const Compiler, id: xml.NodeId, depth: u32) -> usize {
    var count = 0usize
    var at = first_child_element(c.d, id)
    while at != NONE {
        if xs(c, at, "attribute") {
            count += 1usize
        } else if xs(c, at, "attributeGroup") && depth < 16u32 {
            let (ref_text, has_ref) = attr(c.d, at, "ref")
            if has_ref {
                let (_, local, qe) = qname(c, at, ref_text)
                if qe == ok {
                    let (entry, present) = lookup(c, 4u8, local)
                    if present { count += count_attribute_decls(c, entry.node, depth + 1u32) }
                }
            }
        }
        at = next_sibling_element(c.d, at)
    }
    ret count
}

// Append the attribute declarations under `id` (attribute, attributeGroup refs, anyAttribute) to `list`.
fn collect_attributes(c: *Compiler, id: xml.NodeId, list: []AttrUse, count: *usize, any: *bool, depth: u32) -> err {
    if depth > 16u32 { ret TooComplex }
    var at = first_child_element(c.d, id)
    while at != NONE {
        if xs(c, at, "attribute") {
            var attr_use = AttrUse { name: "", ns: "", type_index: ANY_SIMPLE_TYPE, required: false, prohibited: false, has_fixed: false, fixed: "" }
            let (ref_text, has_ref) = attr(c.d, at, "ref")
            var declaration = at
            if has_ref {
                let (uri, local, qe) = qname(c, at, ref_text)
                if qe != ok { ret qe }
                let (entry, present) = lookup(c, 5u8, local)
                if !present || !same(uri, c.tns) { ret Unresolved }
                declaration = entry.node
                attr_use.name = local
                attr_use.ns = c.tns
            } else {
                attr_use.name = attr_or(c.d, at, "name", "")
                if attr_use.name.len == 0usize { ret Invalid }
                attr_use.ns = attribute_form(c, at)
            }
            let (type_text, has_type) = attr(c.d, declaration, "type")
            if has_type {
                let (t, te) = type_ref(c, declaration, type_text)
                if te != ok { ret te }
                attr_use.type_index = t
            } else if first_xs_child(c, declaration, "simpleType") != NONE {
                let (t, te) = simple_of(c, declaration, "type")
                if te != ok { ret te }
                attr_use.type_index = t
            }
            let usage = attr_or(c.d, at, "use", "optional")
            if same(usage, "required") { attr_use.required = true }
            if same(usage, "prohibited") { attr_use.prohibited = true }
            let (fixed_text, has_fixed) = attr(c.d, at, "fixed")
            if has_fixed {
                attr_use.has_fixed = true
                attr_use.fixed = fixed_text
            } else {
                let (declared_fixed, declared_has) = attr(c.d, declaration, "fixed")
                if declared_has {
                    attr_use.has_fixed = true
                    attr_use.fixed = declared_fixed
                }
            }
            // a later declaration of the same attribute replaces an inherited one
            var replaced = false
            var k = 0usize
            while k < (*count) {
                if same(list[k].name, attr_use.name) && same(list[k].ns, attr_use.ns) {
                    list[k] = attr_use
                    replaced = true
                }
                k += 1usize
            }
            if !replaced {
                list[(*count)] = attr_use
                *count += 1usize
            }
        } else if xs(c, at, "attributeGroup") {
            let (ref_text, has_ref) = attr(c.d, at, "ref")
            if has_ref {
                let (_, local, qe) = qname(c, at, ref_text)
                if qe != ok { ret qe }
                let (entry, present) = lookup(c, 4u8, local)
                if !present { ret Unresolved }
                let group_error = collect_attributes(c, entry.node, list, count, any, depth + 1u32)
                if group_error != ok { ret group_error }
            }
        } else if xs(c, at, "anyAttribute") {
            *any = true
            c.wildcard_rule = attr_or(c.d, at, "namespace", "##any")
        }
        at = next_sibling_element(c.d, at)
    }
    ret ok
}

fn compile_element_particle(c: *Compiler, id: xml.NodeId) -> (u32, err) {
    let (min, max, occurs_error) = occurs(c, id)
    if occurs_error != ok { ret (NONE, occurs_error) }
    if attr_or(c.d, id, "substitutionGroup", "").len > 0usize || same(attr_or(c.d, id, "abstract", ""), "true") { ret (NONE, Unsupported) }
    let (p, p_error) = new_particle(c, ParticleKind.Element, min, max)
    if p_error != ok { ret (NONE, p_error) }
    let (ref_text, has_ref) = attr(c.d, id, "ref")
    if has_ref {
        let (uri, local, qe) = qname(c, id, ref_text)
        if qe != ok { ret (NONE, qe) }
        let (entry, present) = lookup(c, 2u8, local)
        if !present || !same(uri, c.tns) { ret (NONE, Unresolved) }
        c.s.particles[usize(p)].element = entry.index
        ret (p, ok)
    }
    let name = attr_or(c.d, id, "name", "")
    if name.len == 0usize { ret (NONE, Invalid) }
    let (decl, decl_error) = new_element(c, name, element_form(c, id), ANY_TYPE)
    if decl_error != ok { ret (NONE, decl_error) }
    let fill_error = fill_element(c, id, decl)
    if fill_error != ok { ret (NONE, fill_error) }
    c.s.particles[usize(p)].element = decl
    ret (p, ok)
}

// The type, nillable and fixed attributes of an element declaration node into declaration `decl`.
fn fill_element(c: *Compiler, id: xml.NodeId, decl: u32) -> err {
    if attr_or(c.d, id, "substitutionGroup", "").len > 0usize || same(attr_or(c.d, id, "abstract", ""), "true") { ret Unsupported }
    var type_index = ANY_TYPE
    let (type_text, has_type) = attr(c.d, id, "type")
    if has_type {
        let (t, te) = type_ref(c, id, type_text)
        if te != ok { ret te }
        type_index = t
    } else if first_xs_child(c, id, "simpleType") != NONE {
        let (t, te) = simple_of(c, id, "type")
        if te != ok { ret te }
        type_index = t
    } else if first_xs_child(c, id, "complexType") != NONE {
        let (index, new_error) = new_type(c)
        if new_error != ok { ret new_error }
        let ce = compile_complex(c, first_xs_child(c, id, "complexType"), index)
        if ce != ok { ret ce }
        type_index = index
    }
    c.s.elements[usize(decl)].type_index = type_index
    c.s.elements[usize(decl)].nillable = same(attr_or(c.d, id, "nillable", ""), "true")
    let (fixed_text, has_fixed) = attr(c.d, id, "fixed")
    if has_fixed {
        c.s.elements[usize(decl)].has_fixed = true
        c.s.elements[usize(decl)].fixed = fixed_text
    }
    ret ok
}

fn compile_group_particle(c: *Compiler, id: xml.NodeId, depth: u32) -> (u32, err) {
    if depth > 24u32 { ret (NONE, TooComplex) }
    let (min, max, occurs_error) = occurs(c, id)
    if occurs_error != ok { ret (NONE, occurs_error) }
    var kind = ParticleKind.Sequence
    if xs(c, id, "choice") { kind = ParticleKind.Choice }
    if xs(c, id, "all") { kind = ParticleKind.All }
    let (p, p_error) = new_particle(c, kind, min, max)
    if p_error != ok { ret (NONE, p_error) }
    var count = 0usize
    var at = first_child_element(c.d, id)
    while at != NONE {
        if xs(c, at, "element") || xs(c, at, "sequence") || xs(c, at, "choice") || xs(c, at, "all") || xs(c, at, "any") || xs(c, at, "group") { count += 1usize }
        at = next_sibling_element(c.d, at)
    }
    if count > 0usize {
        let (children, alloc_error) = mem.alloc[u32](c.a, count)
        if alloc_error != ok { ret (NONE, alloc_error) }
        var used = 0usize
        at = first_child_element(c.d, id)
        while at != NONE {
            var child = NONE
            var child_error = ok
            if xs(c, at, "element") {
                let (made, made_error) = compile_element_particle(c, at)
                child = made
                child_error = made_error
            } else if xs(c, at, "sequence") || xs(c, at, "choice") || xs(c, at, "all") {
                let (made, made_error) = compile_group_particle(c, at, depth + 1u32)
                child = made
                child_error = made_error
            } else if xs(c, at, "any") {
                let (amin, amax, ae) = occurs(c, at)
                if ae != ok { ret (NONE, ae) }
                let (made, made_error) = new_particle(c, ParticleKind.Any, amin, amax)
                child = made
                child_error = made_error
                if made_error == ok {
                    c.s.particles[usize(made)].rule = attr_or(c.d, at, "namespace", "##any")
                    c.s.particles[usize(made)].rule_tns = c.tns
                }
            } else if xs(c, at, "group") {
                let (made, made_error) = compile_group_ref(c, at, depth + 1u32)
                child = made
                child_error = made_error
            } else {
                at = next_sibling_element(c.d, at)
                continue
            }
            if child_error != ok { ret (NONE, child_error) }
            children[used] = child
            used += 1usize
            at = next_sibling_element(c.d, at)
        }
        c.s.particles[usize(p)].children = children[..used]
    }
    ret (p, ok)
}

// <group ref="g"/> expands to the group's model group with the reference's occurrence bounds.
fn compile_group_ref(c: *Compiler, id: xml.NodeId, depth: u32) -> (u32, err) {
    let (ref_text, has_ref) = attr(c.d, id, "ref")
    if !has_ref { ret (NONE, Invalid) }
    let (_, local, qe) = qname(c, id, ref_text)
    if qe != ok { ret (NONE, qe) }
    let (entry, present) = lookup(c, 3u8, local)
    if !present { ret (NONE, Unresolved) }
    var model = NONE
    var at = first_child_element(c.d, entry.node)
    while at != NONE {
        if xs(c, at, "sequence") || xs(c, at, "choice") || xs(c, at, "all") { model = at }
        at = next_sibling_element(c.d, at)
    }
    if model == NONE { ret (NONE, Invalid) }
    let (p, p_error) = compile_group_particle(c, model, depth)
    if p_error != ok { ret (NONE, p_error) }
    let (min, max, occurs_error) = occurs(c, id)
    if occurs_error != ok { ret (NONE, occurs_error) }
    c.s.particles[usize(p)].min = min
    c.s.particles[usize(p)].max = max
    ret (p, ok)
}

fn model_child(c: *const Compiler, id: xml.NodeId) -> xml.NodeId {
    var at = first_child_element(c.d, id)
    while at != NONE {
        if xs(c, at, "sequence") || xs(c, at, "choice") || xs(c, at, "all") || xs(c, at, "group") { ret at }
        at = next_sibling_element(c.d, at)
    }
    ret NONE
}

fn compile_complex(c: *Compiler, id: xml.NodeId, index: u32) -> err {
    if c.depth > 64u32 { ret TooComplex }
    c.depth += 1u32
    var def = simple_def(c.s.types[usize(index)].name, c.s.types[usize(index)].ns)
    def.complex = true
    def.base = ANY_TYPE
    let mixed = same(attr_or(c.d, id, "mixed", ""), "true")
    let simple_content = first_xs_child(c, id, "simpleContent")
    let complex_content = first_xs_child(c, id, "complexContent")
    var derivation = NONE
    var extending = false
    var content_root = id
    if simple_content != NONE {
        derivation = first_xs_child(c, simple_content, "extension")
        if derivation != NONE { extending = true } else { derivation = first_xs_child(c, simple_content, "restriction") }
        content_root = derivation
    } else if complex_content != NONE {
        derivation = first_xs_child(c, complex_content, "extension")
        if derivation != NONE { extending = true } else { derivation = first_xs_child(c, complex_content, "restriction") }
        content_root = derivation
    }
    if (simple_content != NONE || complex_content != NONE) && derivation == NONE {
        c.depth -= 1u32
        ret Invalid
    }
    var base_particle = NONE
    var base_attrs: []AttrUse = zero
    var base_any = false
    var base_rule = "##any"
    c.wildcard_rule = ""
    if derivation != NONE {
        let (base_text, has_base) = attr(c.d, derivation, "base")
        if !has_base {
            c.depth -= 1u32
            ret Invalid
        }
        let (base, base_error) = type_ref(c, derivation, base_text)
        if base_error != ok {
            c.depth -= 1u32
            ret base_error
        }
        def.base = base
        let base_def = c.s.types[usize(base)]
        if simple_content != NONE {
            def.content = Content.Simple
            if base_def.complex {
                def.simple_type = base_def.simple_type
                base_attrs = base_def.attributes
                base_any = base_def.any_attribute
                base_rule = base_def.attr_rule
                if base_def.content != Content.Simple && base != ANY_TYPE {
                    c.depth -= 1u32
                    ret Invalid
                }
            } else {
                def.simple_type = base
            }
            if !extending {
                // a restriction of simple content may narrow the value with facets: make a derived simple type
                let (narrow, narrow_error) = new_type(c)
                if narrow_error != ok {
                    c.depth -= 1u32
                    ret narrow_error
                }
                var narrowed = simple_def("", "")
                narrowed.base = def.simple_type
                narrowed.variety = c.s.types[usize(def.simple_type)].variety
                narrowed.item = c.s.types[usize(def.simple_type)].item
                narrowed.members = c.s.types[usize(def.simple_type)].members
                let facet_error = compile_facets(c, derivation, &narrowed.facets)
                if facet_error != ok {
                    c.depth -= 1u32
                    ret facet_error
                }
                c.s.types[usize(narrow)] = narrowed
                def.simple_type = narrow
            }
        } else if base_def.complex {
            base_particle = base_def.particle
            base_attrs = base_def.attributes
            base_any = base_def.any_attribute
            base_rule = base_def.attr_rule
            def.content = base_def.content
        } else {
            c.depth -= 1u32
            ret Invalid
        }
    }
    // content model of this definition (or of its derivation step)
    if simple_content == NONE {
        let model = model_child(c, content_root)
        var own = NONE
        if model != NONE {
            if xs(c, model, "group") {
                let (made, made_error) = compile_group_ref(c, model, 0u32)
                if made_error != ok {
                    c.depth -= 1u32
                    ret made_error
                }
                own = made
            } else {
                let (made, made_error) = compile_group_particle(c, model, 0u32)
                if made_error != ok {
                    c.depth -= 1u32
                    ret made_error
                }
                own = made
            }
        }
        if extending && base_particle != NONE && own != NONE {
            let (seq, seq_error) = new_particle(c, ParticleKind.Sequence, 1u32, 1u32)
            if seq_error != ok {
                c.depth -= 1u32
                ret seq_error
            }
            let (pair, pair_error) = mem.alloc[u32](c.a, 2usize)
            if pair_error != ok {
                c.depth -= 1u32
                ret pair_error
            }
            pair[0usize] = base_particle
            pair[1usize] = own
            c.s.particles[usize(seq)].children = pair[..2usize]
            def.particle = seq
        } else if own != NONE {
            def.particle = own
        } else if extending {
            def.particle = base_particle
        }
        if def.particle != NONE {
            def.content = Content.Elements
            if mixed { def.content = Content.Mixed }
        } else if mixed {
            def.content = Content.Mixed
        } else if derivation == NONE || !extending {
            def.content = Content.Empty
        }
        if extending && base_particle != NONE && own == NONE { def.content = Content.Elements }
        if extending && mixed { def.content = Content.Mixed }
    }
    // attributes: inherited first, then this step's, which replace a same-named one
    let own_count = count_attribute_decls(c, content_root, 0u32)
    let (list, list_error) = mem.alloc[AttrUse](c.a, own_count + base_attrs.len + 1usize)
    if list_error != ok {
        c.depth -= 1u32
        ret list_error
    }
    var count = 0usize
    var any = base_any
    var k = 0usize
    while k < base_attrs.len {
        list[count] = base_attrs[k]
        count += 1usize
        k += 1usize
    }
    let collect_error = collect_attributes(c, content_root, list, &count, &any, 0u32)
    if collect_error != ok {
        c.depth -= 1u32
        ret collect_error
    }
    // prohibited attributes drop out of the inherited set
    var kept = 0usize
    var j = 0usize
    while j < count {
        if !list[j].prohibited {
            list[kept] = list[j]
            kept += 1usize
        }
        j += 1usize
    }
    def.attributes = list[..kept]
    def.any_attribute = any
    def.attr_rule = base_rule
    if c.wildcard_rule.len > 0usize { def.attr_rule = c.wildcard_rule }
    def.attr_tns = c.tns
    c.s.types[usize(index)] = def
    c.depth -= 1u32
    ret ok
}

// Compile a schema document. The result lives in `a`.
fn load(a: *mem.Arena, source: []const u8) -> (Schema, err) {
    let (d, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (zero, parse_error) }
    if d.root == NONE || !is_named(&d, d.root, xs_namespace(), "schema") { ret (zero, Invalid) }
    let size = d.nodes.len
    let (types, types_error) = mem.alloc[TypeDef](a, BUILTINS + size + 8usize)
    if types_error != ok { ret (zero, types_error) }
    let (particles, particles_error) = mem.alloc[Particle](a, size * 6usize + 16usize)
    if particles_error != ok { ret (zero, particles_error) }
    let (elements, elements_error) = mem.alloc[ElementDecl](a, size * 3usize + 8usize)
    if elements_error != ok { ret (zero, elements_error) }
    let (roots, roots_error) = mem.alloc[u32](a, size + 1usize)
    if roots_error != ok { ret (zero, roots_error) }
    let (named, named_error) = mem.alloc[Named](a, size + 1usize)
    if named_error != ok { ret (zero, named_error) }
    var c = Compiler {
        a: a, d: &d, s: Schema { types: types, type_count: 0usize, particles: particles, particle_count: 0usize, elements: elements, element_count: 0usize, roots: roots, root_count: 0usize, target_namespace: "" },
        tns: attr_or(&d, d.root, "targetNamespace", ""), wildcard_rule: "##any", element_qualified: same(attr_or(&d, d.root, "elementFormDefault", ""), "qualified"),
        attribute_qualified: same(attr_or(&d, d.root, "attributeFormDefault", ""), "qualified"), named: named, named_count: 0usize, depth: 0u32,
    }
    c.s.target_namespace = c.tns
    init_builtins(&c.s)
    // constructs this validator does not implement are refused wherever they stand
    var scan = 0usize
    while scan < d.nodes.len {
        if d.nodes[scan].kind == .Element && unsupported_marker(&c, u32(scan)) { ret (zero, Unsupported) }
        scan += 1usize
    }
    // pass 1: names
    var at = first_child_element(&d, d.root)
    while at != NONE {
        if xs(&c, at, "simpleType") || xs(&c, at, "complexType") {
            let name = attr_or(&d, at, "name", "")
            if name.len == 0usize { ret (zero, Invalid) }
            let (index, new_error) = new_type(&c)
            if new_error != ok { ret (zero, new_error) }
            c.s.types[usize(index)] = simple_def(name, c.tns)
            let reg_error = register(&c, 1u8, name, at, index)
            if reg_error != ok { ret (zero, reg_error) }
        } else if xs(&c, at, "element") {
            let name = attr_or(&d, at, "name", "")
            if name.len == 0usize { ret (zero, Invalid) }
            let (decl, decl_error) = new_element(&c, name, c.tns, ANY_TYPE)
            if decl_error != ok { ret (zero, decl_error) }
            let reg_error = register(&c, 2u8, name, at, decl)
            if reg_error != ok { ret (zero, reg_error) }
            c.s.roots[c.s.root_count] = decl
            c.s.root_count += 1usize
        } else if xs(&c, at, "group") {
            let reg_error = register(&c, 3u8, attr_or(&d, at, "name", ""), at, NONE)
            if reg_error != ok { ret (zero, reg_error) }
        } else if xs(&c, at, "attributeGroup") {
            let reg_error = register(&c, 4u8, attr_or(&d, at, "name", ""), at, NONE)
            if reg_error != ok { ret (zero, reg_error) }
        } else if xs(&c, at, "attribute") {
            let reg_error = register(&c, 5u8, attr_or(&d, at, "name", ""), at, NONE)
            if reg_error != ok { ret (zero, reg_error) }
        }
        at = next_sibling_element(&d, at)
    }
    // pass 2: definitions
    var i = 0usize
    while i < c.named_count {
        let entry = c.named[i]
        if entry.kind == 1u8 {
            var compile_error = ok
            if xs(&c, entry.node, "simpleType") { compile_error = compile_simple(&c, entry.node, entry.index) } else { compile_error = compile_complex(&c, entry.node, entry.index) }
            if compile_error != ok { ret (zero, compile_error) }
        } else if entry.kind == 2u8 {
            let fill_error = fill_element(&c, entry.node, entry.index)
            if fill_error != ok { ret (zero, fill_error) }
        }
        i += 1usize
    }
    ret (c.s, ok)
}

// ---- value checking ----

fn char_length(text: str) -> usize {
    var count = 0usize
    var at = 0usize
    while at < text.len {
        let (dec, e) = utf8.decode(text, at)
        if e != ok {
            at += 1usize
        } else {
            at += usize(dec.width)
        }
        count += 1usize
    }
    ret count
}

fn effective_whitespace(s: *const Schema, t: u32) -> xsd.Whitespace {
    var at = t
    var guard = 0usize
    while at != NONE && guard < 64usize {
        let def = s.types[usize(at)]
        if def.builtin {
            if at < 39u32 { ret xsd.whitespace(builtin_type(at)) }
            ret xsd.Whitespace.Preserve
        }
        if def.facets.has_whitespace { ret def.facets.whitespace }
        if def.variety == Variety.List { ret xsd.Whitespace.Collapse }
        at = def.base
        guard += 1usize
    }
    ret xsd.Whitespace.Preserve
}

// The primitive built-in a simple type derives from (an atomic chain), or NONE for list and union.
fn root_builtin(s: *const Schema, t: u32) -> u32 {
    var at = t
    var guard = 0usize
    while at != NONE && guard < 64usize {
        let def = s.types[usize(at)]
        if def.builtin { ret at }
        if def.variety != Variety.Atomic { ret NONE }
        at = def.base
        guard += 1usize
    }
    ret NONE
}

fn normalize(a: *mem.Arena, ws: xsd.Whitespace, text: str) -> (str, err) {
    if ws == xsd.Whitespace.Preserve { ret (text, ok) }
    let (buffer, alloc_error) = mem.alloc[u8](a, text.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    var used = 0usize
    var pending_space = false
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if ws == xsd.Whitespace.Replace {
            if c == 9u8 || c == 10u8 || c == 13u8 { buffer[used] = 32u8 } else { buffer[used] = c }
            used += 1usize
        } else if xsd.is_space(c) {
            pending_space = used > 0usize
        } else {
            if pending_space {
                buffer[used] = 32u8
                used += 1usize
                pending_space = false
            }
            buffer[used] = c
            used += 1usize
        }
        i += 1usize
    }
    ret (buffer[..used], ok)
}

// Strip sign, leading and trailing zeros from a decimal text: (negative, integer digits, fraction digits).
fn decimal_parts(text: str) -> (bool, str, str) {
    var negative = false
    var s = text
    if s.len > 0usize && (s[0usize] == 43u8 || s[0usize] == 45u8) {
        negative = s[0usize] == 45u8
        s = s[1usize..]
    }
    var integer = s
    var fraction = ""
    let (dot, has_dot) = str.find(s, ".")
    if has_dot {
        integer = s[..dot]
        fraction = s[dot + 1usize..]
    }
    var start = 0usize
    while start < integer.len && integer[start] == 48u8 { start += 1usize }
    integer = integer[start..]
    var end = fraction.len
    while end > 0usize && fraction[end - 1usize] == 48u8 { end -= 1usize }
    fraction = fraction[..end]
    if integer.len == 0usize && fraction.len == 0usize { negative = false }
    ret (negative, integer, fraction)
}

fn cmp_digits(a: str, b: str) -> i32 {
    if a.len != b.len {
        if a.len < b.len { ret -1i32 }
        ret 1i32
    }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] {
            if a[i] < b[i] { ret -1i32 }
            ret 1i32
        }
        i += 1usize
    }
    ret 0i32
}

// Exact comparison of two decimal texts.
fn cmp_decimal(x: str, y: str) -> i32 {
    let (xn, xi, xf) = decimal_parts(x)
    let (yn, yi, yf) = decimal_parts(y)
    if xn != yn {
        if xn { ret -1i32 }
        ret 1i32
    }
    var c = cmp_digits(xi, yi)
    if c == 0i32 {
        // compare fractions as left-aligned digit strings
        var i = 0usize
        let n = xf.len
        let m = yf.len
        var limit = n
        if m > limit { limit = m }
        while i < limit && c == 0i32 {
            var dx = 48u8
            var dy = 48u8
            if i < n { dx = xf[i] }
            if i < m { dy = yf[i] }
            if dx != dy {
                if dx < dy { c = -1i32 } else { c = 1i32 }
            }
            i += 1usize
        }
    }
    if xn { ret 0i32 - c }
    ret c
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    var year = y
    if m <= 2i64 { year -= 1i64 }
    var era = year / 400i64
    if year < 0i64 && year % 400i64 != 0i64 { era = (year - 399i64) / 400i64 }
    let yoe = year - era * 400i64
    var mp = m + 9i64
    if m > 2i64 { mp = m - 3i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + d - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

fn num2(s: str, at: usize) -> i64 { ret i64(s[at] - 48u8) * 10i64 + i64(s[at + 1usize] - 48u8) }

// dateTime, date and time as (days since the epoch, nanoseconds in the day, UTC, has a zone); a value with
// no zone is read at `assumed` minutes east of UTC. `time` is placed on day 0.
fn instant(prim: xsd.Type, s: str, assumed: i64) -> (i64, i64, bool) {
    var at = 0usize
    var year = 0i64
    var month = 1i64
    var day = 1i64
    if prim != xsd.Type.Time {
        var negative = false
        if s[at] == 45u8 {
            negative = true
            at += 1usize
        }
        var y = 0i64
        while at < s.len && xsd.is_digit(s[at]) {
            y = y * 10i64 + i64(s[at] - 48u8)
            at += 1usize
        }
        if negative { y = 1i64 - y }
        year = y
        month = num2(s, at + 1usize)
        day = num2(s, at + 4usize)
        at += 6usize
    }
    var hour = 0i64
    var minute = 0i64
    var seconds = 0i64
    var nanos = 0i64
    if prim != xsd.Type.Date {
        if prim == xsd.Type.DateTime { at += 1usize }
        hour = num2(s, at)
        minute = num2(s, at + 3usize)
        seconds = num2(s, at + 6usize)
        at += 8usize
        if at < s.len && s[at] == 46u8 {
            at += 1usize
            var scale = 100000000i64
            while at < s.len && xsd.is_digit(s[at]) {
                nanos += i64(s[at] - 48u8) * scale
                scale = scale / 10i64
                at += 1usize
            }
        }
    }
    var offset = 0i64
    var zoned = false
    if at < s.len {
        zoned = true
        if s[at] != 90u8 {
            let sign = s[at]
            offset = num2(s, at + 1usize) * 60i64 + num2(s, at + 4usize)
            if sign == 45u8 { offset = 0i64 - offset }
        }
    } else {
        offset = assumed
    }
    var days = 0i64
    if prim != xsd.Type.Time { days = days_from_civil(year, month, day) }
    var total = (hour * 3600i64 + minute * 60i64 + seconds - offset * 60i64) * 1000000000i64 + nanos
    while total < 0i64 {
        total += 86400000000000i64
        days -= 1i64
    }
    while total >= 86400000000000i64 {
        total -= 86400000000000i64
        days += 1i64
    }
    ret (days, total, zoned)
}

fn cmp_instants(d1: i64, t1: i64, d2: i64, t2: i64) -> i32 {
    if d1 != d2 {
        if d1 < d2 { ret -1i32 }
        ret 1i32
    }
    if t1 != t2 {
        if t1 < t2 { ret -1i32 }
        ret 1i32
    }
    ret 0i32
}

// Dates and times: with the same zone status the instants compare directly; a zoneless value against a
// zoned one is ordered only when every zone from -14:00 to +14:00 gives the same answer, else it is 2.
fn compare_temporal(prim: xsd.Type, x: str, y: str) -> i32 {
    let (dx, tx, zx) = instant(prim, x, 0i64)
    let (dy, ty, zy) = instant(prim, y, 0i64)
    if zx == zy { ret cmp_instants(dx, tx, dy, ty) }
    if !zx {
        let (d_early, t_early, _) = instant(prim, x, 840i64)
        let (d_late, t_late, _) = instant(prim, x, -840i64)
        if cmp_instants(d_late, t_late, dy, ty) < 0i32 { ret -1i32 }
        if cmp_instants(d_early, t_early, dy, ty) > 0i32 { ret 1i32 }
        ret 2i32
    }
    let (d_early, t_early, _) = instant(prim, y, 840i64)
    let (d_late, t_late, _) = instant(prim, y, -840i64)
    if cmp_instants(dx, tx, d_late, t_late) > 0i32 { ret 1i32 }
    if cmp_instants(dx, tx, d_early, t_early) < 0i32 { ret -1i32 }
    ret 2i32
}

// -1, 0, 1, or 2 when the values are not ordered (NaN).
fn compare_values(prim: xsd.Type, x: str, y: str) -> i32 {
    if prim == xsd.Type.Decimal || prim == xsd.Type.Integer || prim == xsd.Type.NonPositiveInteger || prim == xsd.Type.NegativeInteger || prim == xsd.Type.NonNegativeInteger || prim == xsd.Type.PositiveInteger || prim == xsd.Type.Long || prim == xsd.Type.Int || prim == xsd.Type.Short || prim == xsd.Type.Byte || prim == xsd.Type.UnsignedLong || prim == xsd.Type.UnsignedInt || prim == xsd.Type.UnsignedShort || prim == xsd.Type.UnsignedByte {
        ret cmp_decimal(x, y)
    }
    if prim == xsd.Type.Float || prim == xsd.Type.Double {
        if same(x, "NaN") || same(y, "NaN") {
            if same(x, y) { ret 0i32 }
            ret 2i32
        }
        var fx = 0.0f64
        var fy = 0.0f64
        if same(x, "INF") { fx = 1.0e308f64 * 10.0f64 } else if same(x, "-INF") { fx = -1.0e308f64 * 10.0f64 } else {
            let (v, ve) = str.parse_f64(x)
            if ve != ok { ret 2i32 }
            fx = v
        }
        if same(y, "INF") { fy = 1.0e308f64 * 10.0f64 } else if same(y, "-INF") { fy = -1.0e308f64 * 10.0f64 } else {
            let (v, ve) = str.parse_f64(y)
            if ve != ok { ret 2i32 }
            fy = v
        }
        if fx < fy { ret -1i32 }
        if fx > fy { ret 1i32 }
        ret 0i32
    }
    if prim == xsd.Type.Boolean {
        let bx = same(x, "true") || same(x, "1")
        let by = same(y, "true") || same(y, "1")
        if bx == by { ret 0i32 }
        if by { ret -1i32 }
        ret 1i32
    }
    if prim == xsd.Type.DateTime || prim == xsd.Type.Date || prim == xsd.Type.Time {
        ret compare_temporal(prim, x, y)
    }
    if same(x, y) { ret 0i32 }
    ret 2i32
}

fn is_ordered(prim: xsd.Type) -> bool {
    ret prim != xsd.Type.Duration && prim != xsd.Type.GYearMonth && prim != xsd.Type.GYear && prim != xsd.Type.GMonthDay && prim != xsd.Type.GDay && prim != xsd.Type.GMonth && prim != xsd.Type.QName && prim != xsd.Type.HexBinary && prim != xsd.Type.Base64Binary
}

fn binary_length(prim: xsd.Type, text: str) -> usize {
    if prim == xsd.Type.HexBinary { ret text.len / 2usize }
    var chars = 0usize
    var pad = 0usize
    var i = 0usize
    while i < text.len {
        if !xsd.is_space(text[i]) {
            chars += 1usize
            if text[i] == 61u8 { pad += 1usize }
        }
        i += 1usize
    }
    ret chars / 4usize * 3usize - pad
}

// The length facets' measure of a value: octets for binary types, characters otherwise.
fn measured_length(prim: xsd.Type, has_prim: bool, text: str) -> usize {
    if has_prim && (prim == xsd.Type.HexBinary || prim == xsd.Type.Base64Binary) { ret binary_length(prim, text) }
    ret char_length(text)
}

fn digit_counts(text: str) -> (usize, usize) {
    let (_, integer, fraction) = decimal_parts(text)
    var total = integer.len + fraction.len
    if total == 0usize { total = 1usize }
    ret (total, fraction.len)
}

fn is_decimal_family(prim: xsd.Type) -> bool {
    ret prim == xsd.Type.Decimal || prim == xsd.Type.Integer || prim == xsd.Type.NonPositiveInteger || prim == xsd.Type.NegativeInteger || prim == xsd.Type.NonNegativeInteger || prim == xsd.Type.PositiveInteger || prim == xsd.Type.Long || prim == xsd.Type.Int || prim == xsd.Type.Short || prim == xsd.Type.Byte || prim == xsd.Type.UnsignedLong || prim == xsd.Type.UnsignedInt || prim == xsd.Type.UnsignedShort || prim == xsd.Type.UnsignedByte
}

fn facet_normal(a: *mem.Arena, s: *const Schema, t: u32, text: str) -> (str, err) {
    let (value, value_error) = normalize(a, effective_whitespace(s, t), text)
    ret (value, value_error)
}

// Whether `text` is a valid value of simple type `t`: its lexical form, then every facet of every
// derivation step, base first.
fn check_simple(a: *mem.Arena, s: *const Schema, t: u32, text: str) -> (bool, err) {
    if t == ANY_SIMPLE_TYPE { ret (true, ok) }
    let def = s.types[usize(t)]
    if def.builtin {
        if t >= 39u32 { ret (true, ok) }
        ret (xsd.valid(builtin_type(t), text), ok)
    }
    let (norm, norm_error) = facet_normal(a, s, t, text)
    if norm_error != ok { ret (false, norm_error) }
    if def.variety == Variety.List {
        var items = 0usize
        var at = 0usize
        let trimmed = norm
        while at < trimmed.len {
            while at < trimmed.len && xsd.is_space(trimmed[at]) { at += 1usize }
            if at >= trimmed.len { break }
            let start = at
            while at < trimmed.len && !xsd.is_space(trimmed[at]) { at += 1usize }
            let (item_ok, item_error) = check_simple(a, s, def.item, trimmed[start..at])
            if item_error != ok { ret (false, item_error) }
            if !item_ok { ret (false, ok) }
            items += 1usize
        }
        let (list_ok, list_error) = facets_ok_list(s, t, def, norm, items)
        ret (list_ok, list_error)
    }
    if def.variety == Variety.Union {
        var any_ok = false
        var k = 0usize
        while k < def.members.len && !any_ok {
            let (member_ok, member_error) = check_simple(a, s, def.members[k], text)
            if member_error != ok { ret (false, member_error) }
            if member_ok { any_ok = true }
            k += 1usize
        }
        if !any_ok && def.base == ANY_SIMPLE_TYPE { ret (false, ok) }
        if def.base != ANY_SIMPLE_TYPE && def.base != NONE {
            let (base_ok, base_error) = check_simple(a, s, def.base, text)
            if base_error != ok || !base_ok { ret (false, base_error) }
        }
        let (union_ok, union_error) = facets_ok_atomic(a, s, t, def, norm)
        ret (union_ok, union_error)
    }
    // atomic restriction: the base first
    if def.base != NONE {
        let (base_ok, base_error) = check_simple(a, s, def.base, text)
        if base_error != ok || !base_ok { ret (false, base_error) }
    }
    let (atomic_ok, atomic_error) = facets_ok_atomic(a, s, t, def, norm)
    ret (atomic_ok, atomic_error)
}

fn facets_ok_list(s: *const Schema, t: u32, def: TypeDef, norm: str, items: usize) -> (bool, err) {
    let f = def.facets
    if f.has_length && u64(items) != f.length { ret (false, ok) }
    if f.has_min_length && u64(items) < f.min_length { ret (false, ok) }
    if f.has_max_length && u64(items) > f.max_length { ret (false, ok) }
    if f.has_pattern && !regex.is_match(&f.pattern, norm) { ret (false, ok) }
    if f.enumeration.len > 0usize {
        var found = false
        var k = 0usize
        while k < f.enumeration.len {
            if same(str.trim(f.enumeration[k]), norm) { found = true }
            k += 1usize
        }
        if !found { ret (false, ok) }
    }
    ret (true, ok)
}

fn facets_ok_atomic(a: *mem.Arena, s: *const Schema, t: u32, def: TypeDef, norm: str) -> (bool, err) {
    let f = def.facets
    let prim_index = root_builtin(s, t)
    var has_prim = false
    var prim = xsd.Type.String
    if prim_index != NONE && prim_index < 39u32 {
        has_prim = true
        prim = builtin_type(prim_index)
    }
    if f.has_length || f.has_min_length || f.has_max_length {
        let n = u64(measured_length(prim, has_prim, norm))
        if f.has_length && n != f.length { ret (false, ok) }
        if f.has_min_length && n < f.min_length { ret (false, ok) }
        if f.has_max_length && n > f.max_length { ret (false, ok) }
    }
    if f.has_pattern && !regex.is_match(&f.pattern, norm) { ret (false, ok) }
    if f.enumeration.len > 0usize {
        var found = false
        var k = 0usize
        while k < f.enumeration.len {
            let (member, member_error) = facet_normal(a, s, t, f.enumeration[k])
            if member_error != ok { ret (false, member_error) }
            var equal = same(norm, member)
            if !equal && has_prim && compare_values(prim, norm, member) == 0i32 { equal = true }
            if equal { found = true }
            k += 1usize
        }
        if !found { ret (false, ok) }
    }
    if has_prim && (f.has_min_inclusive || f.has_max_inclusive || f.has_min_exclusive || f.has_max_exclusive) {
        if !is_ordered(prim) { ret (false, Unsupported) }
        if f.has_min_inclusive {
            let c = compare_values(prim, norm, str.trim(f.min_inclusive))
            if c == 2i32 || c < 0i32 { ret (false, ok) }
        }
        if f.has_max_inclusive {
            let c = compare_values(prim, norm, str.trim(f.max_inclusive))
            if c == 2i32 || c > 0i32 { ret (false, ok) }
        }
        if f.has_min_exclusive {
            let c = compare_values(prim, norm, str.trim(f.min_exclusive))
            if c == 2i32 || c <= 0i32 { ret (false, ok) }
        }
        if f.has_max_exclusive {
            let c = compare_values(prim, norm, str.trim(f.max_exclusive))
            if c == 2i32 || c >= 0i32 { ret (false, ok) }
        }
    }
    if has_prim && is_decimal_family(prim) && (f.has_total || f.has_fraction) {
        let (total, fraction) = digit_counts(norm)
        if f.has_total && u64(total) > f.total_digits { ret (false, ok) }
        if f.has_fraction && u64(fraction) > f.fraction_digits { ret (false, ok) }
    }
    ret (true, ok)
}

// Whether two values of simple type `t` are equal in the value space (for fixed values).
fn values_equal(a: *mem.Arena, s: *const Schema, t: u32, x: str, y: str) -> (bool, err) {
    let (nx, ex) = facet_normal(a, s, t, x)
    if ex != ok { ret (false, ex) }
    let (ny, ey) = facet_normal(a, s, t, y)
    if ey != ok { ret (false, ey) }
    let prim_index = root_builtin(s, t)
    if prim_index != NONE && prim_index < 39u32 { ret (compare_values(builtin_type(prim_index), nx, ny) == 0i32, ok) }
    ret (same(nx, ny), ok)
}

// ---- instance validation ----

type Walk = struct {
    a: *mem.Arena, s: *const Schema, d: *const xml.Document,
    ids: []str, id_nodes: []xml.NodeId, id_count: usize, refs: []str, ref_nodes: []xml.NodeId, ref_count: usize,
    code: ErrorCode, at: xml.NodeId,
}

fn fail(w: *Walk, code: ErrorCode, id: xml.NodeId) -> bool {
    if w.code == ErrorCode.None {
        w.code = code
        w.at = id
    }
    ret false
}

fn is_xmlns_attribute(name: str) -> bool { ret same(name, "xmlns") || str.starts_with(name, "xmlns:") }

// Record an ID or IDREF value of a type that derives from them.
fn note_identity(w: *Walk, t: u32, text: str, id: xml.NodeId) -> bool {
    let prim = root_builtin(w.s, t)
    if prim == NONE { ret true }
    let norm = str.trim(text)
    if builtin_type(prim) == xsd.Type.ID {
        var i = 0usize
        while i < w.id_count {
            if same(w.ids[i], norm) { ret fail(w, ErrorCode.DuplicateId, id) }
            i += 1usize
        }
        w.ids[w.id_count] = norm
        w.id_nodes[w.id_count] = id
        w.id_count += 1usize
    } else if builtin_type(prim) == xsd.Type.IDREF {
        w.refs[w.ref_count] = norm
        w.ref_nodes[w.ref_count] = id
        w.ref_count += 1usize
    }
    ret true
}

fn find_declared(w: *const Walk, uri: str, local: str, decls: []const u32, count: usize) -> u32 {
    var i = 0usize
    while i < count {
        let e = w.s.elements[usize(decls[i])]
        if same(e.name, local) && same(e.ns, uri) { ret decls[i] }
        i += 1usize
    }
    ret NONE
}

// The element declarations reachable in a particle tree, appended to `out`.
fn collect_decls(w: *const Walk, p: u32, out: []u32, count: *usize, depth: u32) {
    if depth > 64u32 || (*count) >= out.len { ret }
    let part = w.s.particles[usize(p)]
    if part.kind == ParticleKind.Element {
        out[(*count)] = part.element
        *count += 1usize
        ret
    }
    var i = 0usize
    while i < part.children.len {
        collect_decls(w, part.children[i], out, count, depth + 1u32)
        i += 1usize
    }
}

fn count_decls(w: *const Walk, p: u32, depth: u32) -> usize {
    if depth > 64u32 { ret 0usize }
    let part = w.s.particles[usize(p)]
    if part.kind == ParticleKind.Element { ret 1usize }
    var total = 0usize
    var i = 0usize
    while i < part.children.len {
        total += count_decls(w, part.children[i], depth + 1u32)
        i += 1usize
    }
    ret total
}

type Kids = struct { ids: []xml.NodeId, names: []str, nss: []str, count: usize }

// Whether a wildcard's namespace constraint admits an element in namespace `uri`.
fn wildcard_allows(rule: str, tns: str, uri: str) -> bool {
    let r = str.trim(rule)
    if same(r, "##any") { ret true }
    if same(r, "##other") { ret uri.len > 0usize && !same(uri, tns) }
    var at = 0usize
    while at < r.len {
        while at < r.len && xsd.is_space(r[at]) { at += 1usize }
        if at >= r.len { break }
        let start = at
        while at < r.len && !xsd.is_space(r[at]) { at += 1usize }
        let token = r[start..at]
        if same(token, "##targetNamespace") && same(uri, tns) { ret true }
        if same(token, "##local") && uri.len == 0usize { ret true }
        if same(token, uri) && uri.len > 0usize { ret true }
    }
    ret false
}

fn matches_decl(w: *const Walk, k: *const Kids, pos: usize, decl: u32) -> bool {
    let e = w.s.elements[usize(decl)]
    ret same(e.name, k.names[pos]) && same(e.ns, k.nss[pos])
}

// ---- the content-model matcher: sets of child positions reachable after a particle ----

fn clear(set: []bool) {
    var i = 0usize
    while i < set.len {
        set[i] = false
        i += 1usize
    }
}

fn any_set(set: []bool) -> bool {
    var i = 0usize
    while i < set.len {
        if set[i] { ret true }
        i += 1usize
    }
    ret false
}

fn add_all(into: []bool, from: []const bool) -> bool {
    var changed = false
    var i = 0usize
    while i < into.len {
        if from[i] && !into[i] {
            into[i] = true
            changed = true
        }
        i += 1usize
    }
    ret changed
}

fn note_reach(furthest: *usize, set: []const bool) {
    var i = 0usize
    while i < set.len {
        if set[i] && i > (*furthest) { *furthest = i }
        i += 1usize
    }
}

// One occurrence of `p` from the positions in `from`, the reachable positions into `out`.
fn step(w: *const Walk, k: *const Kids, p: u32, from: []const bool, out: []bool, furthest: *usize, depth: u32) -> err {
    if depth > 96u32 { ret TooComplex }
    clear(out)
    let part = w.s.particles[usize(p)]
    let n = k.count
    if part.kind == ParticleKind.Element {
        var i = 0usize
        while i < n {
            if from[i] && matches_decl(w, k, i, part.element) { out[i + 1usize] = true }
            i += 1usize
        }
        ret ok
    }
    if part.kind == ParticleKind.Any {
        var i = 0usize
        while i < n {
            if from[i] && wildcard_allows(part.rule, part.rule_tns, k.nss[i]) { out[i + 1usize] = true }
            i += 1usize
        }
        ret ok
    }
    if part.kind == ParticleKind.Sequence {
        let (cur, ce) = mem.alloc[bool](w.a, n + 1usize)
        if ce != ok { ret ce }
        let (nxt, ne) = mem.alloc[bool](w.a, n + 1usize)
        if ne != ok { ret ne }
        var i = 0usize
        while i <= n {
            cur[i] = from[i]
            i += 1usize
        }
        var c = 0usize
        while c < part.children.len {
            let se = repeat(w, k, part.children[c], cur, nxt, furthest, depth + 1u32)
            if se != ok { ret se }
            i = 0usize
            while i <= n {
                cur[i] = nxt[i]
                i += 1usize
            }
            note_reach(furthest, cur)
            c += 1usize
        }
        i = 0usize
        while i <= n {
            out[i] = cur[i]
            i += 1usize
        }
        ret ok
    }
    if part.kind == ParticleKind.Choice {
        let (tmp, te) = mem.alloc[bool](w.a, n + 1usize)
        if te != ok { ret te }
        var c = 0usize
        while c < part.children.len {
            let se = repeat(w, k, part.children[c], from, tmp, furthest, depth + 1u32)
            if se != ok { ret se }
            let _ = add_all(out, tmp)
            c += 1usize
        }
        if part.children.len == 0usize {
            let _ = add_all(out, from)
        }
        ret ok
    }
    // all: every child element at most once (each declared with maxOccurs 1), any order
    let (used, ue) = mem.alloc[bool](w.a, part.children.len + 1usize)
    if ue != ok { ret ue }
    var start = 0usize
    while start <= n {
        if from[start] {
            var j = 0usize
            while j < part.children.len {
                used[j] = false
                j += 1usize
            }
            var pos = start
            var progressed = true
            while progressed && pos < n {
                progressed = false
                var c = 0usize
                while c < part.children.len && !progressed {
                    let child = w.s.particles[usize(part.children[c])]
                    if !used[c] && child.kind == ParticleKind.Element && matches_decl(w, k, pos, child.element) {
                        used[c] = true
                        pos += 1usize
                        progressed = true
                    }
                    c += 1usize
                }
            }
            var complete = true
            var c = 0usize
            while c < part.children.len {
                if !used[c] && w.s.particles[usize(part.children[c])].min > 0u32 { complete = false }
                c += 1usize
            }
            if pos > *furthest { *furthest = pos }
            if complete { out[pos] = true }
        }
        start += 1usize
    }
    ret ok
}

// `p` repeated min..max times from `from`.
fn repeat(w: *const Walk, k: *const Kids, p: u32, from: []const bool, out: []bool, furthest: *usize, depth: u32) -> err {
    let part = w.s.particles[usize(p)]
    let n = k.count
    clear(out)
    let (cur, ce) = mem.alloc[bool](w.a, n + 1usize)
    if ce != ok { ret ce }
    let (nxt, ne) = mem.alloc[bool](w.a, n + 1usize)
    if ne != ok { ret ne }
    var i = 0usize
    while i <= n {
        cur[i] = from[i]
        i += 1usize
    }
    var count = 0u32
    var guard = 0usize
    while true {
        if count >= part.min {
            let _ = add_all(out, cur)
        }
        if part.max != UNBOUNDED && count >= part.max { break }
        if !any_set(cur) { break }
        let se = step(w, k, p, cur, nxt, furthest, depth + 1u32)
        if se != ok { ret se }
        note_reach(furthest, nxt)
        count += 1u32
        guard += 1usize
        // an unbounded repeat ends when a further occurrence adds nothing new
        if part.max == UNBOUNDED && count > part.min {
            var fresh = false
            i = 0usize
            while i <= n {
                if nxt[i] && !out[i] { fresh = true }
                i += 1usize
            }
            if !fresh {
                break
            }
        }
        if guard > n + usize(part.min) + 4usize { break }
        i = 0usize
        while i <= n {
            cur[i] = nxt[i]
            i += 1usize
        }
    }
    ret ok
}

// ---- validating elements ----

fn text_of(w: *Walk, id: xml.NodeId) -> (str, bool) {
    let (text, e) = element_text(w.a, w.d, id)
    if e != ok { ret ("", false) }
    ret (text, true)
}

fn has_element_child(w: *const Walk, id: xml.NodeId) -> xml.NodeId { ret first_child_element(w.d, id) }

fn attribute_ns(w: *const Walk, id: xml.NodeId, name: str) -> (str, str, bool) {
    let (prefix, local) = split_name(name)
    if prefix.len == 0usize { ret ("", local, true) }
    let (uri, e) = resolve(w.d, id, prefix)
    if e != ok { ret ("", local, false) }
    ret (uri, local, true)
}

fn validate_attributes(w: *Walk, def: TypeDef, id: xml.NodeId, allow_none: bool) -> bool {
    let n = node(w.d, id)
    var i = 0usize
    while i < n.attributes.len {
        let name = n.attributes[i].name
        if is_xmlns_attribute(name) {
            i += 1usize
            continue
        }
        let (uri, local, resolved) = attribute_ns(w, id, name)
        if !resolved { ret fail(w, ErrorCode.UnknownAttribute, id) }
        if same(uri, xsi_namespace()) {
            if same(local, "type") { ret fail(w, ErrorCode.UnknownAttribute, id) }
            i += 1usize
            continue
        }
        if allow_none { ret fail(w, ErrorCode.UnknownAttribute, id) }
        var found = false
        var attr_use = AttrUse { name: "", ns: "", type_index: ANY_SIMPLE_TYPE, required: false, prohibited: false, has_fixed: false, fixed: "" }
        var k = 0usize
        while k < def.attributes.len {
            if same(def.attributes[k].name, local) && same(def.attributes[k].ns, uri) {
                found = true
                attr_use = def.attributes[k]
            }
            k += 1usize
        }
        if !found {
            if def.any_attribute && wildcard_allows(def.attr_rule, def.attr_tns, uri) {
                i += 1usize
                continue
            }
            ret fail(w, ErrorCode.UnknownAttribute, id)
        }
        let value = n.attributes[i].value
        let (value_ok, value_error) = check_simple(w.a, w.s, attr_use.type_index, value)
        if value_error != ok || !value_ok { ret fail(w, ErrorCode.BadAttributeValue, id) }
        if attr_use.has_fixed {
            let (equal, equal_error) = values_equal(w.a, w.s, attr_use.type_index, value, attr_use.fixed)
            if equal_error != ok || !equal { ret fail(w, ErrorCode.FixedMismatch, id) }
        }
        if !note_identity(w, attr_use.type_index, value, id) { ret false }
        i += 1usize
    }
    var k = 0usize
    while k < def.attributes.len {
        if def.attributes[k].required {
            var present = false
            var j = 0usize
            while j < n.attributes.len {
                if !is_xmlns_attribute(n.attributes[j].name) {
                    let (uri, local, resolved) = attribute_ns(w, id, n.attributes[j].name)
                    if resolved && same(local, def.attributes[k].name) && same(uri, def.attributes[k].ns) { present = true }
                }
                j += 1usize
            }
            if !present { ret fail(w, ErrorCode.MissingAttribute, id) }
        }
        k += 1usize
    }
    ret true
}

// (xsi:nil is true, the attribute is present, its value is a boolean)
fn nil_value(w: *const Walk, id: xml.NodeId) -> (bool, bool, bool) {
    let n = node(w.d, id)
    var i = 0usize
    while i < n.attributes.len {
        let (uri, local, resolved) = attribute_ns(w, id, n.attributes[i].name)
        if resolved && same(uri, xsi_namespace()) && same(local, "nil") {
            let v = str.trim(n.attributes[i].value)
            if !(same(v, "true") || same(v, "false") || same(v, "1") || same(v, "0")) { ret (false, true, false) }
            ret (same(v, "true") || same(v, "1"), true, true)
        }
        i += 1usize
    }
    ret (false, false, true)
}

fn validate_element(w: *Walk, decl: u32, id: xml.NodeId) -> bool {
    let e = w.s.elements[usize(decl)]
    let (is_nil, has_nil, nil_ok) = nil_value(w, id)
    if has_nil && (!e.nillable || !nil_ok) { ret fail(w, ErrorCode.NilNotAllowed, id) }
    if has_nil && is_nil {
        if e.type_index != ANY_TYPE {
            let nil_def = w.s.types[usize(e.type_index)]
            if !validate_attributes(w, nil_def, id, !nil_def.complex) { ret false }
        }
        if has_element_child(w, id) != NONE { ret fail(w, ErrorCode.NilNotAllowed, id) }
        let (text, text_ok) = text_of(w, id)
        if !text_ok || text.len > 0usize { ret fail(w, ErrorCode.NilNotAllowed, id) }
        ret true
    }
    ret validate_typed(w, e.type_index, id, e)
}

fn validate_typed(w: *Walk, t: u32, id: xml.NodeId, e: ElementDecl) -> bool {
    if t == ANY_TYPE { ret true }
    let def = w.s.types[usize(t)]
    if !def.complex {
        if !validate_attributes(w, def, id, true) { ret false }
        let child = has_element_child(w, id)
        if child != NONE { ret fail(w, ErrorCode.UnexpectedElement, id) }
        let (text, text_ok) = text_of(w, id)
        if !text_ok { ret fail(w, ErrorCode.BadValue, id) }
        var value = text
        if text.len == 0usize && e.has_fixed { value = e.fixed }
        let (value_ok, value_error) = check_simple(w.a, w.s, t, value)
        if value_error != ok || !value_ok { ret fail(w, ErrorCode.BadValue, id) }
        if e.has_fixed {
            let (equal, equal_error) = values_equal(w.a, w.s, t, value, e.fixed)
            if equal_error != ok || !equal { ret fail(w, ErrorCode.FixedMismatch, id) }
        }
        ret note_identity(w, t, value, id)
    }
    if !validate_attributes(w, def, id, false) { ret false }
    if def.content == Content.Simple {
        let child = has_element_child(w, id)
        if child != NONE { ret fail(w, ErrorCode.UnexpectedElement, id) }
        let (text, text_ok) = text_of(w, id)
        if !text_ok { ret fail(w, ErrorCode.BadValue, id) }
        var value = text
        if text.len == 0usize && e.has_fixed { value = e.fixed }
        let (value_ok, value_error) = check_simple(w.a, w.s, def.simple_type, value)
        if value_error != ok || !value_ok { ret fail(w, ErrorCode.BadValue, id) }
        if e.has_fixed {
            let (equal, equal_error) = values_equal(w.a, w.s, def.simple_type, value, e.fixed)
            if equal_error != ok || !equal { ret fail(w, ErrorCode.FixedMismatch, id) }
        }
        ret note_identity(w, def.simple_type, value, id)
    }
    if def.content == Content.Empty {
        let child = has_element_child(w, id)
        if child != NONE { ret fail(w, ErrorCode.UnexpectedElement, id) }
        let (text, text_ok) = text_of(w, id)
        if !text_ok || text.len > 0usize { ret fail(w, ErrorCode.NotEmpty, id) }
        ret true
    }
    var text_pos = 4294967295usize
    if def.content == Content.Elements {
        // where the first non-blank character data falls among the child elements
        var seen = 0usize
        var at = node(w.d, id).first_child
        while at != NONE {
            let n = node(w.d, at)
            if n.kind == .Element { seen += 1usize }
            if n.kind == .Text && !is_blank(n.value) && text_pos == 4294967295usize { text_pos = seen }
            at = n.next_sibling
        }
    }
    ret validate_children(w, def, id, text_pos)
}

fn validate_children(w: *Walk, def: TypeDef, id: xml.NodeId, text_pos: usize) -> bool {
    var count = 0usize
    var at = first_child_element(w.d, id)
    while at != NONE {
        count += 1usize
        at = next_sibling_element(w.d, at)
    }
    if def.particle == NONE {
        if count == 0usize {
            if text_pos != 4294967295usize { ret fail(w, ErrorCode.TextNotAllowed, id) }
            ret true
        }
        if text_pos == 0usize { ret fail(w, ErrorCode.TextNotAllowed, id) }
        ret fail(w, ErrorCode.UnexpectedElement, first_child_element(w.d, id))
    }
    let (ids, ids_error) = mem.alloc[xml.NodeId](w.a, count + 1usize)
    if ids_error != ok { ret fail(w, ErrorCode.BadValue, id) }
    let (names, names_error) = mem.alloc[str](w.a, count + 1usize)
    if names_error != ok { ret fail(w, ErrorCode.BadValue, id) }
    let (nss, nss_error) = mem.alloc[str](w.a, count + 1usize)
    if nss_error != ok { ret fail(w, ErrorCode.BadValue, id) }
    var used = 0usize
    at = first_child_element(w.d, id)
    while at != NONE {
        let (uri, local, expand_error) = expand(w.d, at)
        if expand_error != ok { ret fail(w, ErrorCode.UnexpectedElement, at) }
        ids[used] = at
        names[used] = local
        nss[used] = uri
        used += 1usize
        at = next_sibling_element(w.d, at)
    }
    let kids = Kids { ids: ids, names: names, nss: nss, count: count }
    let (start, start_error) = mem.alloc[bool](w.a, count + 1usize)
    if start_error != ok { ret fail(w, ErrorCode.BadValue, id) }
    let (reached, reached_error) = mem.alloc[bool](w.a, count + 1usize)
    if reached_error != ok { ret fail(w, ErrorCode.BadValue, id) }
    clear(start)
    start[0usize] = true
    var furthest = 0usize
    let run_error = repeat(w, &kids, def.particle, start, reached, &furthest, 0u32)
    if run_error != ok { ret fail(w, ErrorCode.UnexpectedElement, id) }
    let accepted = reached[count]
    var limit = count
    if !accepted && furthest < count { limit = furthest }
    if text_pos < limit { limit = text_pos }
    // the declarations a child can be validated against
    let decl_total = count_decls(w, def.particle, 0u32)
    let (decls, decls_error) = mem.alloc[u32](w.a, decl_total + 1usize)
    if decls_error != ok { ret fail(w, ErrorCode.BadValue, id) }
    var decl_count = 0usize
    collect_decls(w, def.particle, decls, &decl_count, 0u32)
    var i = 0usize
    while i < limit {
        let decl = find_declared(w, nss[i], names[i], decls, decl_count)
        if decl != NONE {
            if !validate_element(w, decl, ids[i]) { ret false }
        } else {
            // matched by a wildcard: validate against a global declaration when there is one
            var global = NONE
            var r = 0usize
            while r < w.s.root_count {
                let e = w.s.elements[usize(w.s.roots[r])]
                if same(e.name, names[i]) && same(e.ns, nss[i]) { global = w.s.roots[r] }
                r += 1usize
            }
            if global != NONE {
                if !validate_element(w, global, ids[i]) { ret false }
            }
        }
        i += 1usize
    }
    if text_pos != 4294967295usize && (accepted || text_pos <= furthest) { ret fail(w, ErrorCode.TextNotAllowed, id) }
    if accepted { ret true }
    if furthest < count { ret fail(w, ErrorCode.UnexpectedElement, ids[furthest]) }
    ret fail(w, ErrorCode.MissingContent, id)
}

// The first error of `d` against the schema, with its node. `err` is for resource limits only.
fn validate(a: *mem.Arena, s: *const Schema, d: *const xml.Document) -> (Result, err) {
    if d.root == NONE { ret (Result { valid: false, code: ErrorCode.UnknownRoot, node: NONE }, ok) }
    let size = d.nodes.len + 1usize
    let (ids, ids_error) = mem.alloc[str](a, size)
    if ids_error != ok { ret (zero, ids_error) }
    let (id_nodes, id_nodes_error) = mem.alloc[xml.NodeId](a, size)
    if id_nodes_error != ok { ret (zero, id_nodes_error) }
    let (refs, refs_error) = mem.alloc[str](a, size)
    if refs_error != ok { ret (zero, refs_error) }
    let (ref_nodes, ref_nodes_error) = mem.alloc[xml.NodeId](a, size)
    if ref_nodes_error != ok { ret (zero, ref_nodes_error) }
    var w = Walk { a: a, s: s, d: d, ids: ids, id_nodes: id_nodes, id_count: 0usize, refs: refs, ref_nodes: ref_nodes, ref_count: 0usize, code: ErrorCode.None, at: NONE }
    let (uri, local, expand_error) = expand(d, d.root)
    if expand_error != ok { ret (Result { valid: false, code: ErrorCode.UnknownRoot, node: d.root }, ok) }
    var decl = NONE
    var r = 0usize
    while r < s.root_count {
        let e = s.elements[usize(s.roots[r])]
        if same(e.name, local) && same(e.ns, uri) { decl = s.roots[r] }
        r += 1usize
    }
    if decl == NONE { ret (Result { valid: false, code: ErrorCode.UnknownRoot, node: d.root }, ok) }
    let good = validate_element(&w, decl, d.root)
    if good && w.code == ErrorCode.None {
        var i = 0usize
        while i < w.ref_count && w.code == ErrorCode.None {
            var found = false
            var k = 0usize
            while k < w.id_count {
                if same(w.ids[k], w.refs[i]) { found = true }
                k += 1usize
            }
            if !found {
                let _ = fail(&w, ErrorCode.UnresolvedIdref, w.ref_nodes[i])
            }
            i += 1usize
        }
    }
    ret (Result { valid: w.code == ErrorCode.None, code: w.code, node: w.at }, ok)
}

// Parse `source` as the instance and validate it.
fn validate_text(a: *mem.Arena, s: *const Schema, source: []const u8) -> (Result, err) {
    let (d, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (zero, parse_error) }
    let (result, validate_error) = validate(a, s, &d)
    ret (result, validate_error)
}

// The path of an element from the root, `/a/b[2]` (an index only where a sibling shares the name).
fn node_path(a: *mem.Arena, d: *const xml.Document, id: xml.NodeId) -> (str, err) {
    var path = ""
    var at = id
    while at != NONE && node(d, at).kind == .Element {
        let n = node(d, at)
        var same_before = 0usize
        var same_total = 0usize
        let parent = n.parent
        if parent != NONE {
            var sib = first_child_element(d, parent)
            while sib != NONE {
                if same(node(d, sib).name, n.name) {
                    same_total += 1usize
                    if sib == at { same_before = same_total }
                }
                sib = next_sibling_element(d, sib)
            }
        }
        var segment = n.name
        if same_total > 1usize {
            let (builder, builder_error) = str.builder(a, 32usize)
            if builder_error != ok { ret ("", builder_error) }
            var b = builder
            try str.push(&b, n.name)
            try str.push(&b, "[")
            try str.push_usize(&b, same_before)
            try str.push(&b, "]")
            segment = str.done(&b)
        }
        let (head, head_error) = str.concat(a, "/", segment)
        if head_error != ok { ret ("", head_error) }
        let (joined, joined_error) = str.concat(a, head, path)
        if joined_error != ok { ret ("", joined_error) }
        path = joined
        at = parent
    }
    ret (path, ok)
}
