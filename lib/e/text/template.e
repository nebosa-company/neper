// Templates with `{{name}}` interpolation, `{{#if name}} ... {{else}} ... {{/if}}`
// conditionals and `{{#repeat name}} ... {{/repeat}}` iteration, the count an integer
// binding and `{{@index}}` the position inside. Parsing is bounded by `Options`: a
// source over `max_bytes` or more nodes than `max_nodes` is `TooLarge`, nesting past
// `max_depth` is `TooDeep`, an unbalanced or unknown tag is `InvalidTemplate`. A
// name without a binding is `MissingValue` at execution, and `validate[T]` finds it
// beforehand against a struct's fields, which `execute_typed[T]` binds by kind:
// bool, integer, float and string fields. No escaping happens here; a text or byte
// value is written as it is.
use e.io
use e.mem
use e.meta
use e.str

type Template = struct { state: *void }
type Options = struct { max_bytes: usize, max_nodes: usize, max_depth: u16 }
type Value = union enum u8 { Null, Bool: bool, I64: i64, U64: u64, F64: f64, Text: str, Bytes: []const u8 }
type Binding = struct { name: str, value: Value }
error InvalidTemplate
error MissingValue
error TooDeep
error TooLarge

// Node kinds: 0 text, 1 variable, 2 if, 3 else, 4 end, 5 repeat, 6 index.
type Node = struct { kind: u8, text: str, close: usize, other: usize }
type State = struct { nodes: []Node }

fn parse(a: *mem.Arena, source: str, options: Options) -> (Template, err) {
    if source.len > options.max_bytes { ret (zero, TooLarge) }
    // Count the tags first so the node table is allocated once.
    var count = 1usize
    var at = 0usize
    while at < source.len {
        let (open, found) = str.find_from(source, "{{", at)
        if !found { break }
        count += 2usize
        at = open + 2usize
    }
    if count > options.max_nodes { ret (zero, TooLarge) }
    let (nodes, nodes_error) = mem.alloc[Node](a, count)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (stack, stack_error) = mem.alloc[usize](a, usize(options.max_depth) + 1usize)
    if stack_error != ok { ret (zero, stack_error) }
    var used = 0usize
    var depth = 0usize
    at = 0usize
    while at < source.len {
        let (open, found) = str.find_from(source, "{{", at)
        if !found {
            nodes[used] = Node { kind: 0u8, text: source[at..], close: 0usize, other: 0usize }
            used += 1usize
            break
        }
        if open > at {
            nodes[used] = Node { kind: 0u8, text: source[at..open], close: 0usize, other: 0usize }
            used += 1usize
        }
        let (end, closed) = str.find_from(source, "}}", open + 2usize)
        if !closed { ret (zero, InvalidTemplate) }
        let inner = str.trim(source[open + 2usize..end])
        if inner.len == 0usize { ret (zero, InvalidTemplate) }
        var node = Node { kind: 1u8, text: inner, close: 0usize, other: 0usize }
        if str.starts_with(inner, "#if ") || str.starts_with(inner, "#repeat ") {
            node.kind = 2u8
            var name_at = 4usize
            if inner[1] == 114u8 {
                node.kind = 5u8
                name_at = 8usize
            }
            node.text = str.trim(inner[name_at..])
            if node.text.len == 0usize { ret (zero, InvalidTemplate) }
            if depth >= usize(options.max_depth) { ret (zero, TooDeep) }
            stack[depth] = used
            depth += 1usize
        } else {
        if str.eq(inner, "else") {
            node.kind = 3u8
            if depth == 0usize || nodes[stack[depth - 1usize]].kind != 2u8 { ret (zero, InvalidTemplate) }
            if nodes[stack[depth - 1usize]].other != 0usize { ret (zero, InvalidTemplate) }
            nodes[stack[depth - 1usize]].other = used
        } else {
        if str.eq(inner, "/if") || str.eq(inner, "/repeat") {
            node.kind = 4u8
            if depth == 0usize { ret (zero, InvalidTemplate) }
            let opener = stack[depth - 1usize]
            var wanted = 2u8
            if inner[1] == 114u8 { wanted = 5u8 }
            if nodes[opener].kind != wanted { ret (zero, InvalidTemplate) }
            nodes[opener].close = used
            depth -= 1usize
        } else {
        if str.eq(inner, "@index") {
            node.kind = 6u8
        } else {
            if inner[0] == 35u8 || inner[0] == 47u8 || inner[0] == 64u8 { ret (zero, InvalidTemplate) }
        }
        }
        }
        }
        nodes[used] = node
        used += 1usize
        at = end + 2usize
    }
    if depth != 0usize { ret (zero, InvalidTemplate) }
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    storage[0].nodes = nodes[..used]
    var t: Template = zero
    t.state = mem.cast[*void](&storage[0])
    ret (t, ok)
}

fn lookup(bindings: []const Binding, name: str) -> (Value, bool) {
    var none: Value = .Null
    var i = 0usize
    while i < bindings.len {
        if str.eq(bindings[i].name, name) { ret (bindings[i].value, true) }
        i += 1usize
    }
    ret (none, false)
}

fn truthy(value: Value) -> bool {
    switch value {
    case .Null:
        ret false
    case .Bool as flag:
        ret flag
    case .I64 as signed:
        ret signed != 0i64
    case .U64 as unsigned:
        ret unsigned != 0u64
    case .F64 as number:
        ret number != 0.0
    case .Text as text:
        ret text.len > 0usize
    case .Bytes as bytes:
        ret bytes.len > 0usize
    }
}

fn count_of(value: Value) -> (u64, bool) {
    switch value {
    case .I64 as signed:
        if signed < 0i64 { ret (0u64, false) }
        ret (u64(signed), true)
    case .U64 as unsigned:
        ret (unsigned, true)
    default:
        ret (0u64, false)
    }
}

fn write_number(writer: *io.Writer, value: Value) -> err {
    // Formatted through a builder over a stack arena, which `push_*` need.
    var scratch: [64]u8 = zero
    var arena = mem.arena_from(scratch[0..])
    let (b0, builder_error) = str.builder(&arena, 64usize)
    if builder_error != ok { ret builder_error }
    var b = b0
    switch value {
    case .I64 as signed:
        try str.push_i64(&b, signed)
    case .U64 as unsigned:
        try str.push_u64(&b, unsigned)
    case .F64 as number:
        try str.push_f64(&b, number)
    default:
        ret ok
    }
    ret io.write_all(writer, str.done(&b))
}

fn write_value(writer: *io.Writer, value: Value) -> err {
    switch value {
    case .Null:
        ret ok
    case .Bool as flag:
        if flag { ret io.write_all(writer, "true") }
        ret io.write_all(writer, "false")
    case .Text as text:
        ret io.write_all(writer, text)
    case .Bytes as bytes:
        ret io.write_all(writer, bytes)
    default:
        ret write_number(writer, value)
    }
}

// Runs the nodes in [from, to), `index` being the innermost repeat position.
fn run(nodes: []const Node, from: usize, to: usize, writer: *io.Writer, bindings: []const Binding, index: u64) -> err {
    var at = from
    while at < to {
        let node = nodes[at]
        if node.kind == 0u8 {
            try io.write_all(writer, node.text)
        } else {
        if node.kind == 1u8 {
            let (value, found) = lookup(bindings, node.text)
            if !found { ret MissingValue }
            try write_value(writer, value)
        } else {
        if node.kind == 6u8 {
            try write_number(writer, Value{ U64: index })
        } else {
        if node.kind == 2u8 {
            let (value, found) = lookup(bindings, node.text)
            if !found { ret MissingValue }
            if truthy(value) {
                var stop = node.close
                if node.other != 0usize { stop = node.other }
                try run(nodes, at + 1usize, stop, writer, bindings, index)
            } else {
                if node.other != 0usize { try run(nodes, node.other + 1usize, node.close, writer, bindings, index) }
            }
            at = node.close
        } else {
        if node.kind == 5u8 {
            let (value, found) = lookup(bindings, node.text)
            if !found { ret MissingValue }
            let (times, is_count) = count_of(value)
            if !is_count { ret MissingValue }
            var i = 0u64
            while i < times {
                try run(nodes, at + 1usize, node.close, writer, bindings, i)
                i += 1u64
            }
            at = node.close
        }
        }
        }
        }
        }
        at += 1usize
    }
    ret ok
}

fn execute(template: *const Template, writer: *io.Writer, bindings: []const Binding) -> err {
    let s = mem.cast[*State](template.state)
    ret run(s.nodes, 0usize, s.nodes.len, writer, bindings, 0u64)
}

// Every name the template reads must be a field of `T`.
fn validate[T: type](template: *const Template) -> err {
    let s = mem.cast[*State](template.state)
    var at = 0usize
    while at < s.nodes.len {
        let node = s.nodes[at]
        if node.kind == 1u8 || node.kind == 2u8 || node.kind == 5u8 {
            var found = false
            for f in meta.fields[T]() {
                if str.eq(f.name, node.text) { found = true }
            }
            if !found { ret MissingValue }
        }
        at += 1usize
    }
    ret ok
}

fn field_count[T: type]() -> usize {
    var count = 0usize
    for f in meta.fields[T]() {
        count += 1usize
    }
    ret count
}

fn execute_typed[T: type](template: *const Template, writer: *io.Writer, value: *const T) -> err {
    try validate[T](template)
    // Bindings on the stack: a struct with more fields than this is not a template model.
    var bindings: [32]Binding = zero
    if field_count[T]() > 32usize { ret TooLarge }
    var used = 0usize
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        bindings[used].name = f.name
        if meta.kind[f.ty]() == .Bool {
            bindings[used].value = Value{ Bool: slot }
        } else {
        if meta.kind[f.ty]() == .Int {
            bindings[used].value = Value{ I64: i64(slot) }
        } else {
        if meta.kind[f.ty]() == .Float {
            bindings[used].value = Value{ F64: f64(slot) }
        } else {
        if meta.kind[f.ty]() == .Slice {
            bindings[used].value = Value{ Text: slot }
        } else {
            bindings[used].value = .Null
        }
        }
        }
        }
        used += 1usize
    }
    ret execute(template, writer, bindings[..used])
}
