// `e.fmt.yaml`: a document with nested block mappings and sequences, a sequence of
// mappings, flow collections, every scalar form -- plain null/bool/integer/float/
// string, single and double quotes with escapes, hex and octal, infinities -- literal
// and folded blocks with chomping, comments and a leading `---`; the writer's block
// output read back equal; the typed codec both ways; refusals for a tab indent, a
// duplicate key (and its allowance), a depth over the limit, an alias, a second
// document, and an unclosed flow. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.yaml as yaml

type Config = struct { name: str, port: i32, ratio: f64, debug: bool }

fn options(depth: u16, duplicates: bool) -> yaml.Options {
    ret yaml.Options { max_depth: depth, allow_duplicate_keys: duplicates }
}

fn lookup(pairs: []const yaml.Pair, name: str) -> (yaml.Value, bool) {
    var i = 0usize
    while i < pairs.len {
        var matched = false
        switch pairs[i].key {
        case .String as key:
            matched = str.eq(key, name)
        default:
            matched = false
        }
        if matched { ret (pairs[i].value, true) }
        i += 1usize
    }
    ret (.Null, false)
}

fn mapping_of(value: yaml.Value, code: i32) -> []const yaml.Pair {
    switch value {
    case .Mapping as pairs:
        ret pairs
    default:
        os.exit(code)
    }
    ret zero
}

fn sequence_of(value: yaml.Value, code: i32) -> []const yaml.Value {
    switch value {
    case .Sequence as items:
        ret items
    default:
        os.exit(code)
    }
    ret zero
}

fn text_of(value: yaml.Value, code: i32) -> str {
    switch value {
    case .String as text:
        ret text
    default:
        os.exit(code)
    }
    ret ""
}

fn integer_of(value: yaml.Value, code: i32) -> i64 {
    switch value {
    case .Integer as number:
        ret number
    default:
        os.exit(code)
    }
    ret 0i64
}

fn float_of(value: yaml.Value, code: i32) -> f64 {
    switch value {
    case .Float as number:
        ret number
    default:
        os.exit(code)
    }
    ret 0.0
}

fn is_null(value: yaml.Value) -> bool {
    switch value {
    case .Null:
        ret true
    default:
        ret false
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let doc = "--- # the document\nname: neper   # a comment\nport: 8080\nratio: 0.75\nhex: 0x1f\noct: 0o17\nneg: -12\nbig: 1e3\ninf: -.inf\nempty:\ntilde: ~\nyes: true\nno: False\nquoted: \"a\\tb\\u00e9\\\"q\\\"\"\nsingle: 'it''s'\nplainish: 12ab\nlist:\n  - one\n  - 2\n  - [x, y, {k: v}]\n  - key: inner\n    other: 3\n  -\n    - deep\nflow: {a: 1, b: [true, null], c: \"s, s\"}\nliteral: |\n  line one\n  line two\n\nfolded: >-\n  folded\n  text\n\n  gap\nnested:\n  child:\n    leaf: end\n"
    let (root, e1) = yaml.parse(a, doc, options(8u16, false))
    if e1 != ok { os.exit(1) }
    let top = mapping_of(root, 2)
    if top.len != 20usize { os.exit(3) }
    let (name, has_name) = lookup(top, "name")
    if !has_name || !str.eq(text_of(name, 4), "neper") { os.exit(5) }
    let (port, has_port) = lookup(top, "port")
    if !has_port || integer_of(port, 6) != 8080i64 { os.exit(7) }
    let (ratio, has_ratio) = lookup(top, "ratio")
    if !has_ratio || float_of(ratio, 8) != 0.75 { os.exit(9) }
    let (hex, has_hex) = lookup(top, "hex")
    if !has_hex || integer_of(hex, 10) != 31i64 { os.exit(11) }
    let (oct, has_oct) = lookup(top, "oct")
    if !has_oct || integer_of(oct, 12) != 15i64 { os.exit(13) }
    let (neg, has_neg) = lookup(top, "neg")
    if !has_neg || integer_of(neg, 14) != -12i64 { os.exit(15) }
    let (big, has_big) = lookup(top, "big")
    if !has_big || float_of(big, 16) != 1000.0 { os.exit(17) }
    let (inf, has_inf) = lookup(top, "inf")
    if !has_inf || float_of(inf, 18) > -1.0e300 { os.exit(19) }
    let (empty, has_empty) = lookup(top, "empty")
    if !has_empty || !is_null(empty) { os.exit(20) }
    let (tilde, has_tilde) = lookup(top, "tilde")
    if !has_tilde || !is_null(tilde) { os.exit(21) }
    let (yes, has_yes) = lookup(top, "yes")
    var yes_flag = false
    switch yes {
    case .Bool as flag:
        yes_flag = flag
    default:
        os.exit(22)
    }
    if !has_yes || !yes_flag { os.exit(23) }
    let (no, has_no) = lookup(top, "no")
    switch no {
    case .Bool as flag:
        if flag { os.exit(24) }
    default:
        os.exit(25)
    }
    let (quoted, has_quoted) = lookup(top, "quoted")
    if !has_quoted || !str.eq(text_of(quoted, 26), "a\tb\xc3\xa9\"q\"") { os.exit(27) }
    let (single, has_single) = lookup(top, "single")
    if !has_single || !str.eq(text_of(single, 28), "it's") { os.exit(29) }
    let (plainish, has_plainish) = lookup(top, "plainish")
    if !has_plainish || !str.eq(text_of(plainish, 30), "12ab") { os.exit(31) }
    let (list, has_list) = lookup(top, "list")
    if !has_list { os.exit(32) }
    let items = sequence_of(list, 33)
    if items.len != 5usize { os.exit(34) }
    if !str.eq(text_of(items[0], 35), "one") || integer_of(items[1], 36) != 2i64 { os.exit(37) }
    let flow_items = sequence_of(items[2], 38)
    if flow_items.len != 3usize || !str.eq(text_of(flow_items[1], 39), "y") { os.exit(40) }
    let flow_map = mapping_of(flow_items[2], 41)
    if flow_map.len != 1usize || !str.eq(text_of(flow_map[0].value, 42), "v") { os.exit(43) }
    let item_map = mapping_of(items[3], 44)
    if item_map.len != 2usize || !str.eq(text_of(item_map[0].value, 45), "inner") || integer_of(item_map[1].value, 46) != 3i64 { os.exit(47) }
    let deep = sequence_of(items[4], 48)
    if deep.len != 1usize || !str.eq(text_of(deep[0], 49), "deep") { os.exit(50) }
    let (flow, has_flow) = lookup(top, "flow")
    if !has_flow { os.exit(51) }
    let flow_pairs = mapping_of(flow, 52)
    if flow_pairs.len != 3usize || integer_of(flow_pairs[0].value, 53) != 1i64 { os.exit(54) }
    let b_items = sequence_of(flow_pairs[1].value, 55)
    if b_items.len != 2usize || !is_null(b_items[1]) { os.exit(56) }
    if !str.eq(text_of(flow_pairs[2].value, 57), "s, s") { os.exit(58) }
    let (literal, has_literal) = lookup(top, "literal")
    if !has_literal || !str.eq(text_of(literal, 59), "line one\nline two\n") { os.exit(60) }
    let (folded, has_folded) = lookup(top, "folded")
    if !has_folded || !str.eq(text_of(folded, 61), "folded text\ngap") { os.exit(62) }
    let (nested, has_nested) = lookup(top, "nested")
    let child = mapping_of(nested, 63)
    let leaf = mapping_of(child[0].value, 64)
    if !has_nested || !str.eq(text_of(leaf[0].value, 65), "end") { os.exit(66) }
    // Write it back and read that.
    var buffer: [2048]u8 = zero
    var sink_state = io.SliceWriter { data: buffer[..], off: 0usize }
    var sink = io.slice_writer(&sink_state)
    if yaml.write(&sink, &root, 2u8) != ok { os.exit(67) }
    let written = buffer[..sink_state.off]
    if !str.starts_with(written, "name: neper\nport: 8080\nratio: 0.75\nhex: 31\noct: 15\nneg: -12\nbig: 1000.0\ninf: -.inf\nempty: null\ntilde: null\nyes: true\nno: false\nquoted: \"a\\tb\xc3\xa9\\\"q\\\"\"\nsingle: it's\nplainish: 12ab\nlist:\n  - one\n  - 2\n  - - x\n    - y\n    - k: v\n  - key: inner\n    other: 3\n  - - deep\nflow:\n  a: 1\n  b:\n    - true\n    - null\n  c: s, s\nliteral: \"line one\\nline two\\n\"\nfolded: \"folded text\\ngap\"\nnested:\n  child:\n    leaf: end\n") { os.exit(68) }
    let (again, e2) = yaml.parse(a, written, options(8u16, false))
    if e2 != ok { os.exit(69) }
    let again_top = mapping_of(again, 70)
    if again_top.len != 20usize { os.exit(71) }
    let (again_list, has_again) = lookup(again_top, "list")
    if !has_again || sequence_of(again_list, 72).len != 5usize { os.exit(73) }
    let (again_folded, has_again_folded) = lookup(again_top, "folded")
    if !has_again_folded || !str.eq(text_of(again_folded, 74), "folded text\ngap") { os.exit(75) }
    // The typed codec.
    let (config, e3) = yaml.decode[Config](a, "name: svc\nport: 99\nratio: 2.5\ndebug: true\nextra: ignored\n", options(4u16, false))
    if e3 != ok || !str.eq(config.name, "svc") || config.port != 99 || config.ratio != 2.5 || !config.debug { os.exit(76) }
    var typed_state = io.SliceWriter { data: buffer[..], off: 0usize }
    var typed_sink = io.slice_writer(&typed_state)
    if yaml.encode[Config](&typed_sink, &config) != ok { os.exit(77) }
    if !str.eq(buffer[..typed_state.off], "name: svc\nport: 99\nratio: 2.5\ndebug: true\n") { os.exit(78) }
    let (bad_config, e4) = yaml.decode[Config](a, "name: [1]\n", options(4u16, false))
    if e4 != yaml.Invalid { os.exit(79) }
    // Refusals.
    let (t1, e5) = yaml.parse(a, "a:\n\tb: 1\n", options(4u16, false))
    if e5 != yaml.Invalid { os.exit(80) }
    let (t2, e6) = yaml.parse(a, "a: 1\na: 2\n", options(4u16, false))
    if e6 != yaml.DuplicateKey { os.exit(81) }
    let (t3, e7) = yaml.parse(a, "a: 1\na: 2\n", options(4u16, true))
    if e7 != ok || mapping_of(t3, 82).len != 2usize { os.exit(83) }
    let (t4, e8) = yaml.parse(a, "a:\n  b:\n    c:\n      d: 1\n", options(2u16, false))
    if e8 != yaml.TooDeep { os.exit(84) }
    let (t5, e9) = yaml.parse(a, "a: &anchor 1\n", options(4u16, false))
    if e9 != yaml.Unsupported { os.exit(85) }
    let (t6, e10) = yaml.parse(a, "a: 1\n---\nb: 2\n", options(4u16, false))
    if e10 != yaml.Unsupported { os.exit(86) }
    let (t7, e11) = yaml.parse(a, "a: [1, 2\n", options(4u16, false))
    if e11 != yaml.Invalid { os.exit(87) }
    let (t8, e12) = yaml.parse(a, "", options(4u16, false))
    if e12 != ok || !is_null(t8) { os.exit(88) }
    ret ok
}
