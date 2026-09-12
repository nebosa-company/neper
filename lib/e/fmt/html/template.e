// HTML templates over `e.text.template`: the same `{{name}}`, `{{#if}}`/`{{else}}`
// and `{{#repeat}}` syntax, with every interpolation escaped for the context the
// literal text before it establishes -- element text, an attribute value in either
// quote, the value of `href`/`src`/`action` (a URI, its scheme checked), a `style`
// attribute or element (CSS), a `script` element. Contexts are found at parse time
// by walking the text nodes with a small HTML state machine; an interpolation that
// lands where escaping cannot make it safe -- inside a tag but outside a value, in
// an attribute or tag name, in an unquoted value, in a comment -- is
// `UnsafeContext` at parse. Values that are not text (numbers, bools) print as the
// core engine prints them, then escaped the same way. There is no raw insertion.
use e.io
use e.mem
use e.meta
use e.str
use e.text.template as template

type Template = struct { inner: template.Template }
type Options = struct { max_bytes: usize, max_nodes: usize, max_depth: u16 }
error InvalidTemplate
error UnsafeContext
error MissingValue
error TooLarge

// Contexts: 0 text, 1 attribute value (double quote), 2 attribute value (single),
// 3 URI attribute (double), 4 URI attribute (single), 5 CSS (style attribute, in a
// quote or the style element), 6 script element, 7 unsafe.
type Scan = struct { in_tag: bool, in_value: bool, quote: u8, attribute_kind: u8, element: str, in_comment: bool, in_raw: u8 }

// The inner state's layout with the contexts after it: a pointer to this is also a
// pointer to `template.State`, which is how `template.validate` still reads it.
type State = struct { nodes: []template.Node, contexts: []u8 }

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 12u8 }

fn is_uri_attribute(name: str) -> bool {
    ret str.compare_ascii_fold(name, "href") == 0 || str.compare_ascii_fold(name, "src") == 0 || str.compare_ascii_fold(name, "action") == 0 || str.compare_ascii_fold(name, "formaction") == 0
}

// Feeds literal text through the scanner; the context after it is what an
// interpolation there would be in.
fn scan(s: *Scan, text: str) {
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if s.in_comment {
            if str.starts_with(text[i..], "-->") {
                s.in_comment = false
                i += 3usize
                continue
            }
            i += 1usize
            continue
        }
        if s.in_raw != 0u8 {
            // Inside a script or style element: only its end tag leaves.
            var closer = "</script"
            if s.in_raw == 2u8 { closer = "</style" }
            if i + closer.len <= text.len && str.compare_ascii_fold(text[i..i + closer.len], closer) == 0 {
                s.in_raw = 0u8
                s.in_tag = true
                s.element = ""
                i += closer.len
                continue
            }
            i += 1usize
            continue
        }
        if !s.in_tag {
            if str.starts_with(text[i..], "<!--") {
                s.in_comment = true
                i += 4usize
                continue
            }
            if c == 60u8 && (i + 1usize == text.len || (i + 2usize == text.len && text[i + 1usize] == 47u8)) {
                // A tag whose name is what comes next: an interpolation there is unsafe.
                s.in_tag = true
                s.in_value = false
                s.quote = 0u8
                s.element = ""
                i = text.len
                continue
            }
            if c == 60u8 && i + 1usize < text.len && (str.is_ascii_alpha(text[i + 1usize]) || text[i + 1usize] == 47u8) {
                s.in_tag = true
                s.in_value = false
                s.quote = 0u8
                var stop = i + 1usize
                if text[stop] == 47u8 { stop += 1usize }
                let start = stop
                while stop < text.len && (str.is_ascii_alnum(text[stop]) || text[stop] == 45u8) { stop += 1usize }
                s.element = text[start..stop]
                if text[i + 1usize] == 47u8 { s.element = "" }
                i = stop
                continue
            }
            i += 1usize
            continue
        }
        // Inside a tag.
        if s.in_value {
            if s.quote != 0u8 {
                if c == s.quote {
                    s.in_value = false
                    s.quote = 0u8
                }
            } else {
                if is_space(c) || c == 62u8 {
                    s.in_value = false
                    if c == 62u8 { leave_tag(s) }
                }
            }
            i += 1usize
            continue
        }
        if c == 62u8 {
            leave_tag(s)
            i += 1usize
            continue
        }
        if c == 61u8 {
            // The attribute name is what preceded this sign.
            var name_stop = i
            while name_stop > 0usize && is_space(text[name_stop - 1usize]) { name_stop -= 1usize }
            var name_start = name_stop
            while name_start > 0usize && !is_space(text[name_start - 1usize]) && text[name_start - 1usize] != 60u8 && text[name_start - 1usize] != 34u8 && text[name_start - 1usize] != 39u8 { name_start -= 1usize }
            let name = text[name_start..name_stop]
            s.attribute_kind = 1u8
            if is_uri_attribute(name) { s.attribute_kind = 2u8 }
            if str.compare_ascii_fold(name, "style") == 0 { s.attribute_kind = 3u8 }
            if name.len > 2usize && (name[0] == 111u8 || name[0] == 79u8) && (name[1] == 110u8 || name[1] == 78u8) { s.attribute_kind = 4u8 }
            var j = i + 1usize
            while j < text.len && is_space(text[j]) { j += 1usize }
            s.in_value = true
            s.quote = 0u8
            if j < text.len && (text[j] == 34u8 || text[j] == 39u8) {
                s.quote = text[j]
                i = j + 1usize
                continue
            }
            i = j
            continue
        }
        i += 1usize
    }
}

fn leave_tag(s: *Scan) {
    s.in_tag = false
    s.in_value = false
    s.quote = 0u8
    if str.compare_ascii_fold(s.element, "script") == 0 { s.in_raw = 1u8 }
    if str.compare_ascii_fold(s.element, "style") == 0 { s.in_raw = 2u8 }
    s.element = ""
}

fn context_of(s: *const Scan) -> u8 {
    if s.in_comment { ret 7u8 }
    if s.in_raw == 1u8 { ret 6u8 }
    if s.in_raw == 2u8 { ret 5u8 }
    if !s.in_tag { ret 0u8 }
    if !s.in_value || s.quote == 0u8 { ret 7u8 }
    if s.attribute_kind == 4u8 { ret 7u8 }
    if s.attribute_kind == 3u8 { ret 5u8 }
    if s.attribute_kind == 2u8 {
        if s.quote == 34u8 { ret 3u8 }
        ret 4u8
    }
    if s.quote == 34u8 { ret 1u8 }
    ret 2u8
}

fn parse(a: *mem.Arena, source: str, options: Options) -> (Template, err) {
    let inner_options = template.Options { max_bytes: options.max_bytes, max_nodes: options.max_nodes, max_depth: options.max_depth }
    let (inner, parse_error) = template.parse(a, source, inner_options)
    if parse_error == template.TooLarge { ret (zero, TooLarge) }
    if parse_error == template.TooDeep { ret (zero, TooLarge) }
    if parse_error != ok { ret (zero, InvalidTemplate) }
    let nodes = mem.cast[*template.State](inner.state).nodes
    let (contexts, contexts_error) = mem.alloc[u8](a, nodes.len)
    if contexts_error != ok { ret (zero, contexts_error) }
    // One linear scan over the literal text decides every interpolation's context;
    // a block's branches are scanned in order, which is right when both branches
    // leave the scanner where they found it, and refused when they do not.
    var scanner: Scan = zero
    var i = 0usize
    while i < nodes.len {
        let node = nodes[i]
        if node.kind == 0u8 { scan(&scanner, node.text) }
        if node.kind == 1u8 || node.kind == 6u8 {
            let context = context_of(&scanner)
            if context == 7u8 { ret (zero, UnsafeContext) }
            contexts[i] = context
        }
        i += 1usize
    }
    if scanner.in_tag || scanner.in_comment { ret (zero, UnsafeContext) }
    let (state, state_error) = mem.alloc[State](a, 1usize)
    if state_error != ok { ret (zero, state_error) }
    state[0].nodes = nodes
    state[0].contexts = contexts
    var t: Template = zero
    t.inner = inner
    t.inner.state = mem.cast[*void](&state[0])
    ret (t, ok)
}

// --- Escaping.

fn hex_digit(nibble: u8) -> u8 {
    if nibble < 10u8 { ret 48u8 + nibble }
    ret 55u8 + nibble
}

fn write_text_escaped(writer: *io.Writer, text: str) -> err {
    var from = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        var replacement = ""
        if c == 38u8 { replacement = "&amp;" }
        if c == 60u8 { replacement = "&lt;" }
        if c == 62u8 { replacement = "&gt;" }
        if c == 34u8 { replacement = "&#34;" }
        if c == 39u8 { replacement = "&#39;" }
        if replacement.len > 0usize {
            try io.write_all(writer, text[from..i])
            try io.write_all(writer, replacement)
            from = i + 1usize
        }
        i += 1usize
    }
    ret io.write_all(writer, text[from..])
}

fn is_uri_safe(c: u8) -> bool {
    ret str.is_ascii_alnum(c) || c == 45u8 || c == 46u8 || c == 95u8 || c == 126u8 || c == 47u8 || c == 58u8 || c == 63u8 || c == 61u8 || c == 38u8 || c == 35u8 || c == 43u8 || c == 44u8 || c == 59u8 || c == 64u8 || c == 37u8 || c == 33u8 || c == 36u8 || c == 40u8 || c == 41u8 || c == 42u8 || c == 91u8 || c == 93u8
}

// A URI value: a scheme other than http, https, mailto or a relative reference is
// replaced; the rest is percent-encoded where it is not URI-safe, then attribute-escaped.
fn write_uri_escaped(writer: *io.Writer, text: str) -> err {
    let (colon, has_colon) = str.find(text, ":")
    if has_colon {
        let scheme = text[..colon]
        let known = str.compare_ascii_fold(scheme, "http") == 0 || str.compare_ascii_fold(scheme, "https") == 0 || str.compare_ascii_fold(scheme, "mailto") == 0
        var plain = true
        var k = 0usize
        while k < scheme.len {
            if !str.is_ascii_alpha(scheme[k]) { plain = false }
            k += 1usize
        }
        if plain && !known { ret io.write_all(writer, "#unsafe") }
    }
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if is_uri_safe(c) && c != 38u8 && c != 34u8 && c != 39u8 && c != 60u8 && c != 62u8 {
            var one: [1]u8 = zero
            one[0] = c
            try io.write_all(writer, one[0..])
        } else {
            if c == 38u8 {
                try io.write_all(writer, "&amp;")
            } else {
                var encoded: [3]u8 = zero
                encoded[0] = 37u8
                encoded[1] = hex_digit(c >> 4u8)
                encoded[2] = hex_digit(c & 15u8)
                try io.write_all(writer, encoded[0..])
            }
        }
        i += 1usize
    }
    ret ok
}

// CSS: anything outside letters, digits, space, `-`, `_`, `.`, `%`, `#` and `,` is
// written as a CSS hex escape.
fn write_css_escaped(writer: *io.Writer, text: str) -> err {
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if str.is_ascii_alnum(c) || c == 32u8 || c == 45u8 || c == 95u8 || c == 46u8 || c == 37u8 || c == 35u8 || c == 44u8 {
            var one: [1]u8 = zero
            one[0] = c
            try io.write_all(writer, one[0..])
        } else {
            var escaped: [4]u8 = zero
            escaped[0] = 92u8
            escaped[1] = hex_digit(c >> 4u8)
            escaped[2] = hex_digit(c & 15u8)
            escaped[3] = 32u8
            try io.write_all(writer, escaped[0..])
        }
        i += 1usize
    }
    ret ok
}

// Script: the value becomes a JavaScript string literal, every byte outside the
// plain printable set as a `\xNN` escape, so no `</script` or quote can form.
fn write_script_escaped(writer: *io.Writer, text: str) -> err {
    try io.write_all(writer, "\"")
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c >= 32u8 && c < 127u8 && c != 34u8 && c != 92u8 && c != 60u8 && c != 62u8 && c != 38u8 && c != 39u8 {
            var one: [1]u8 = zero
            one[0] = c
            try io.write_all(writer, one[0..])
        } else {
            var escaped: [4]u8 = zero
            escaped[0] = 92u8
            escaped[1] = 120u8
            escaped[2] = hex_digit(c >> 4u8)
            escaped[3] = hex_digit(c & 15u8)
            try io.write_all(writer, escaped[0..])
        }
        i += 1usize
    }
    ret io.write_all(writer, "\"")
}

fn write_escaped(writer: *io.Writer, context: u8, text: str) -> err {
    if context == 3u8 || context == 4u8 { ret write_uri_escaped(writer, text) }
    if context == 5u8 { ret write_css_escaped(writer, text) }
    if context == 6u8 { ret write_script_escaped(writer, text) }
    ret write_text_escaped(writer, text)
}

// A value as text, through the core engine's own formatting into a stack buffer.
fn value_text(value: template.Value, scratch: []u8) -> (str, err) {
    var state = io.SliceWriter { data: scratch, off: 0usize }
    var sink = io.slice_writer(&state)
    let write_error = template.write_value(&sink, value)
    if write_error != ok { ret ("", write_error) }
    ret (scratch[..state.off], ok)
}

fn run(nodes: []const template.Node, contexts: []const u8, from: usize, to: usize, writer: *io.Writer, bindings: []const template.Binding, index: u64) -> err {
    var at = from
    while at < to {
        let node = nodes[at]
        if node.kind == 0u8 {
            try io.write_all(writer, node.text)
        } else {
        if node.kind == 1u8 || node.kind == 6u8 {
            var value: template.Value = template.Value{ U64: index }
            if node.kind == 1u8 {
                let (found, present) = template.lookup(bindings, node.text)
                if !present { ret MissingValue }
                value = found
            }
            var scratch: [512]u8 = zero
            let (text, text_error) = value_text(value, scratch[0..])
            if text_error != ok { ret TooLarge }
            try write_escaped(writer, contexts[at], text)
        } else {
        if node.kind == 2u8 {
            let (value, found) = template.lookup(bindings, node.text)
            if !found { ret MissingValue }
            if template.truthy(value) {
                var stop = node.close
                if node.other != 0usize { stop = node.other }
                try run(nodes, contexts, at + 1usize, stop, writer, bindings, index)
            } else {
                if node.other != 0usize { try run(nodes, contexts, node.other + 1usize, node.close, writer, bindings, index) }
            }
            at = node.close
        } else {
        if node.kind == 5u8 {
            let (value, found) = template.lookup(bindings, node.text)
            if !found { ret MissingValue }
            let (times, is_count) = template.count_of(value)
            if !is_count { ret MissingValue }
            var i = 0u64
            while i < times {
                try run(nodes, contexts, at + 1usize, node.close, writer, bindings, i)
                i += 1u64
            }
            at = node.close
        }
        }
        }
        }
        at += 1usize
    }
    ret ok
}

fn execute(value: *const Template, writer: *io.Writer, bindings: []const template.Binding) -> err {
    let s = mem.cast[*State](value.inner.state)
    ret run(s.nodes, s.contexts, 0usize, s.nodes.len, writer, bindings, 0u64)
}

fn validate[T: type](value: *const Template) -> err {
    let inner_error = template.validate[T](&value.inner)
    if inner_error != ok { ret MissingValue }
    ret ok
}

fn execute_typed[T: type](value: *const Template, writer: *io.Writer, data: *const T) -> err {
    try validate[T](value)
    var bindings: [32]template.Binding = zero
    if template.field_count[T]() > 32usize { ret TooLarge }
    var used = 0usize
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](data)
        bindings[used].name = f.name
        if meta.kind[f.ty]() == .Bool {
            bindings[used].value = template.Value{ Bool: slot }
        } else {
        if meta.kind[f.ty]() == .Int {
            bindings[used].value = template.Value{ I64: i64(slot) }
        } else {
        if meta.kind[f.ty]() == .Float {
            bindings[used].value = template.Value{ F64: f64(slot) }
        } else {
        if meta.kind[f.ty]() == .Slice {
            bindings[used].value = template.Value{ Text: slot }
        } else {
            bindings[used].value = .Null
        }
        }
        }
        }
        used += 1usize
    }
    ret execute(value, writer, bindings[..used])
}
