// `e.fmt.yaml`: a document with nested block mappings and sequences, a sequence of
// mappings, flow collections, every scalar form -- plain null/bool/integer/float/
// string, single and double quotes with escapes, hex and octal, infinities -- literal
// and folded blocks with chomping, comments and a leading `---`; the writer's block
// output read back equal; the typed codec both ways; refusals for a tab indent, a
// duplicate key (and its allowance), a depth over the limit, an alias, a second
// document, and an unclosed flow. Issue 150 regressions cover UTF-8, quote-aware
// comments, all YAML escapes, bounded collections and depth, and key equality.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.yaml as yaml

type Config = struct { name: str, port: i32, ratio: f64, debug: bool }
type NarrowConfig = struct { port: u8 }
type NarrowFloat = struct { ratio: f32 }
type WideConfig = struct { big: u64 }

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

fn yaml_limit_input(a: *mem.Arena, count: usize, kind: u8) -> (str, err) {
    let (builder0, builder_error) = str.builder(a, count * 16usize + 8usize)
    if builder_error != ok { ret ("", builder_error) }
    var builder = builder0
    if kind == 0u8 {
        try str.push(&builder, "[")
        var i = 0usize
        while i < count {
            if i > 0usize { try str.push(&builder, ", ") }
            try str.push(&builder, "0")
            i += 1usize
        }
        try str.push(&builder, "]")
    } else {
    if kind == 1u8 {
        var i = 0usize
        while i < count {
            try str.push(&builder, "- 0\n")
            i += 1usize
        }
    } else {
    if kind == 2u8 {
        try str.push(&builder, "{")
        var i = 0usize
        while i < count {
            if i > 0usize { try str.push(&builder, ", ") }
            try str.push(&builder, "k")
            try str.push_usize(&builder, i)
            try str.push(&builder, ": 0")
            i += 1usize
        }
        try str.push(&builder, "}")
    } else {
    if kind == 3u8 {
        var i = 0usize
        while i < count {
            try str.push(&builder, "k")
            try str.push_usize(&builder, i)
            try str.push(&builder, ": 0\n")
            i += 1usize
        }
    }
    }
    }
    }
    ret (str.done(&builder), ok)
}

fn nested_yaml_block(a: *mem.Arena, depth: usize) -> (str, err) {
    let (builder0, builder_error) = str.builder(a, depth * depth * 4usize + 8usize)
    if builder_error != ok { ret ("", builder_error) }
    var builder = builder0
    var i = 0usize
    while i < depth {
        var spaces = 0usize
        while spaces < i * 2usize {
            try str.push(&builder, " ")
            spaces += 1usize
        }
        try str.push(&builder, "a:\n")
        i += 1usize
    }
    var spaces = 0usize
    while spaces < depth * 2usize {
        try str.push(&builder, " ")
        spaces += 1usize
    }
    try str.push(&builder, "x: 1\n")
    ret (str.done(&builder), ok)
}

fn nested_yaml_flow(a: *mem.Arena, depth: usize) -> (str, err) {
    let (builder0, builder_error) = str.builder(a, depth * 2usize + 1usize)
    if builder_error != ok { ret ("", builder_error) }
    var builder = builder0
    var i = 0usize
    while i < depth {
        try str.push(&builder, "[")
        i += 1usize
    }
    try str.push(&builder, "0")
    i = 0usize
    while i < depth {
        try str.push(&builder, "]")
        i += 1usize
    }
    ret (str.done(&builder), ok)
}

fn issue_150_regressions(a: *mem.Arena) -> err {
    let (tab_doc, tab_error) = yaml.parse(a, "script: |\n  echo hi\n  \tindented\n", options(4u16, false))
    if tab_error != ok { os.exit(100) }
    let (script, has_script) = lookup(mapping_of(tab_doc, 101), "script")
    if !has_script || !str.eq(text_of(script, 102), "echo hi\n\tindented\n") { os.exit(103) }

    let (comment_doc, comment_error) = yaml.parse(a, "name: it's fine # note\nsingle: 'it''s # inside' # note\n", options(4u16, false))
    if comment_error != ok { os.exit(104) }
    let comment_pairs = mapping_of(comment_doc, 105)
    let (plain_apostrophe, has_plain_apostrophe) = lookup(comment_pairs, "name")
    let (quoted_apostrophe, has_quoted_apostrophe) = lookup(comment_pairs, "single")
    if !has_plain_apostrophe || !str.eq(text_of(plain_apostrophe, 106), "it's fine") { os.exit(107) }
    if !has_quoted_apostrophe || !str.eq(text_of(quoted_apostrophe, 108), "it's # inside") { os.exit(109) }

    let (escape_doc, escape_error) = yaml.parse(a, "escapes: \"\\a\\b\\f\\e\\v\\N\\_\\L\\P\"\n", options(4u16, false))
    if escape_error != ok { os.exit(110) }
    let (escape_value, has_escapes) = lookup(mapping_of(escape_doc, 111), "escapes")
    let expected_escapes = "\x07\x08\x0c\x1b\x0b\xc2\x85\xc2\xa0\xe2\x80\xa8\xe2\x80\xa9"
    if !has_escapes || !str.eq(text_of(escape_value, 112), expected_escapes) { os.exit(113) }

    var zero_options: yaml.Options = zero
    let (zero_block, zero_block_error) = yaml.parse(a, "a:\n  b: 1\n", zero_options)
    if zero_block_error != ok { os.exit(114) }
    let (zero_flow, zero_flow_error) = yaml.parse(a, "[[1]]", zero_options)
    if zero_flow_error != ok { os.exit(115) }

    let (deep_block, deep_block_build_error) = nested_yaml_block(a, 17usize)
    if deep_block_build_error != ok { os.exit(116) }
    let (too_deep_block, too_deep_block_error) = yaml.parse(a, deep_block, options(100u16, false))
    if too_deep_block_error != yaml.TooDeep { os.exit(117) }
    let (deep_flow, deep_flow_build_error) = nested_yaml_flow(a, 17usize)
    if deep_flow_build_error != ok { os.exit(118) }
    let (too_deep_flow, too_deep_flow_error) = yaml.parse(a, deep_flow, options(100u16, false))
    if too_deep_flow_error != yaml.TooDeep { os.exit(119) }

    let (block_sequence, block_sequence_build_error) = yaml_limit_input(a, 257usize, 1u8)
    if block_sequence_build_error != ok { os.exit(120) }
    let (too_many_block_sequence, too_many_block_sequence_error) = yaml.parse(a, block_sequence, options(4u16, false))
    if too_many_block_sequence_error != yaml.TooLarge { os.exit(121) }
    let (block_mapping, block_mapping_build_error) = yaml_limit_input(a, 257usize, 3u8)
    if block_mapping_build_error != ok { os.exit(122) }
    let (too_many_block_mapping, too_many_block_mapping_error) = yaml.parse(a, block_mapping, options(4u16, false))
    if too_many_block_mapping_error != yaml.TooLarge { os.exit(123) }
    let (flow_sequence, flow_sequence_build_error) = yaml_limit_input(a, 65usize, 0u8)
    if flow_sequence_build_error != ok { os.exit(124) }
    let (too_many_flow_sequence, too_many_flow_sequence_error) = yaml.parse(a, flow_sequence, options(4u16, false))
    if too_many_flow_sequence_error != yaml.TooLarge { os.exit(125) }
    let (flow_mapping, flow_mapping_build_error) = yaml_limit_input(a, 65usize, 2u8)
    if flow_mapping_build_error != ok { os.exit(126) }
    let (too_many_flow_mapping, too_many_flow_mapping_error) = yaml.parse(a, flow_mapping, options(4u16, false))
    if too_many_flow_mapping_error != yaml.TooLarge { os.exit(127) }

    let (block_sequence_limit, block_sequence_limit_build_error) = yaml_limit_input(a, 256usize, 1u8)
    if block_sequence_limit_build_error != ok { os.exit(128) }
    let (block_sequence_limit_value, block_sequence_limit_error) = yaml.parse(a, block_sequence_limit, options(4u16, false))
    if block_sequence_limit_error != ok || sequence_of(block_sequence_limit_value, 129).len != 256usize { os.exit(130) }
    let (block_mapping_limit, block_mapping_limit_build_error) = yaml_limit_input(a, 256usize, 3u8)
    if block_mapping_limit_build_error != ok { os.exit(131) }
    let (block_mapping_limit_value, block_mapping_limit_error) = yaml.parse(a, block_mapping_limit, options(4u16, false))
    if block_mapping_limit_error != ok || mapping_of(block_mapping_limit_value, 132).len != 256usize { os.exit(133) }
    let (flow_sequence_limit, flow_sequence_limit_build_error) = yaml_limit_input(a, 64usize, 0u8)
    if flow_sequence_limit_build_error != ok { os.exit(134) }
    let (flow_sequence_limit_value, flow_sequence_limit_error) = yaml.parse(a, flow_sequence_limit, options(4u16, false))
    if flow_sequence_limit_error != ok || sequence_of(flow_sequence_limit_value, 135).len != 64usize { os.exit(136) }
    let (flow_mapping_limit, flow_mapping_limit_build_error) = yaml_limit_input(a, 64usize, 2u8)
    if flow_mapping_limit_build_error != ok { os.exit(137) }
    let (flow_mapping_limit_value, flow_mapping_limit_error) = yaml.parse(a, flow_mapping_limit, options(4u16, false))
    if flow_mapping_limit_error != ok || mapping_of(flow_mapping_limit_value, 138).len != 64usize { os.exit(139) }

    let (quoted_sequence, quoted_sequence_error) = yaml.parse(a, "- \"a\": 1\n- 'b': 2\n", options(4u16, false))
    if quoted_sequence_error != ok { os.exit(140) }
    let quoted_maps = sequence_of(quoted_sequence, 141)
    if quoted_maps.len != 2usize { os.exit(142) }
    let quoted_first = mapping_of(quoted_maps[0usize], 143)
    let quoted_second = mapping_of(quoted_maps[1usize], 144)
    if quoted_first.len != 1usize || !str.eq(text_of(quoted_first[0usize].key, 145), "a") || integer_of(quoted_first[0usize].value, 146) != 1i64 { os.exit(147) }
    if quoted_second.len != 1usize || !str.eq(text_of(quoted_second[0usize].key, 148), "b") || integer_of(quoted_second[0usize].value, 149) != 2i64 { os.exit(150) }

    let (number_doc, number_error) = yaml.parse(a, "leading: .5\ntrailing: 5.\nplus: +5\nsigned_hex: -0x1F\nsigned_oct: -0o17\n", options(4u16, false))
    if number_error != ok { os.exit(151) }
    let number_pairs = mapping_of(number_doc, 152)
    let (leading, has_leading) = lookup(number_pairs, "leading")
    let (trailing, has_trailing) = lookup(number_pairs, "trailing")
    let (plus, has_plus) = lookup(number_pairs, "plus")
    let (signed_hex, has_signed_hex) = lookup(number_pairs, "signed_hex")
    let (signed_oct, has_signed_oct) = lookup(number_pairs, "signed_oct")
    if !has_leading || float_of(leading, 153) != 0.5 { os.exit(154) }
    if !has_trailing || float_of(trailing, 155) != 5.0 { os.exit(156) }
    if !has_plus || integer_of(plus, 157) != 5i64 { os.exit(158) }
    if !has_signed_hex || !str.eq(text_of(signed_hex, 159), "-0x1F") { os.exit(160) }
    if !has_signed_oct || !str.eq(text_of(signed_oct, 161), "-0o17") { os.exit(162) }

    // Core schema permits a sign for `.inf`, but not for any spelling of `.nan`.
    let (signed_nan_doc, signed_nan_error) = yaml.parse(a, "minus: -.nan\nplus: +.NaN\nplain: .nan\n", options(4u16, false))
    if signed_nan_error != ok { os.exit(500i32) }
    let signed_nan_pairs = mapping_of(signed_nan_doc, 501i32)
    let (minus_nan, has_minus_nan) = lookup(signed_nan_pairs, "minus")
    let (plus_nan, has_plus_nan) = lookup(signed_nan_pairs, "plus")
    let (plain_nan, has_plain_nan) = lookup(signed_nan_pairs, "plain")
    if !has_minus_nan || !str.eq(text_of(minus_nan, 502i32), "-.nan") { os.exit(503i32) }
    if !has_plus_nan || !str.eq(text_of(plus_nan, 504i32), "+.NaN") { os.exit(505i32) }
    if !has_plain_nan || mem.bitcast[u64](float_of(plain_nan, 506i32)) != 9221120237041090560u64 { os.exit(507i32) }

    let (plain_continuation, plain_continuation_error) = yaml.parse(a, "x: this is\n  continued\n", options(4u16, false))
    if plain_continuation_error != yaml.Unsupported { os.exit(163) }
    let (quoted_continuation, quoted_continuation_error) = yaml.parse(a, "x: \"a\n  b\"\n", options(4u16, false))
    if quoted_continuation_error != yaml.Unsupported { os.exit(164) }
    let (single_continuation, single_continuation_error) = yaml.parse(a, "x: 'a\n  b'\n", options(4u16, false))
    if single_continuation_error != yaml.Unsupported { os.exit(165) }

    let (ended_doc, ended_error) = yaml.parse(a, "a: 1\n...\n", options(4u16, false))
    if ended_error != ok || mapping_of(ended_doc, 166).len != 1usize { os.exit(167) }
    let (after_end_doc, after_end_error) = yaml.parse(a, "a: 1\n...\nb: 2\n", options(4u16, false))
    if after_end_error != yaml.Unsupported { os.exit(168) }

    var invalid_yaml: [5]u8 = zero
    invalid_yaml[0usize] = 107u8
    invalid_yaml[1usize] = 58u8
    invalid_yaml[2usize] = 32u8
    invalid_yaml[3usize] = 255u8
    invalid_yaml[4usize] = 10u8
    let (invalid_doc, invalid_doc_error) = yaml.parse(a, invalid_yaml[..], options(4u16, false))
    if invalid_doc_error != yaml.Invalid { os.exit(169) }
    var invalid_value = yaml.Value { String: invalid_yaml[3usize..4usize] }
    var invalid_output: [32]u8 = zero
    var invalid_state = io.SliceWriter { data: invalid_output[..], off: 0usize }
    var invalid_sink = io.slice_writer(&invalid_state)
    if yaml.write(&invalid_sink, &invalid_value, 2u8) != yaml.Invalid || invalid_state.off != 0usize { os.exit(170) }

    let (float_duplicates, float_duplicates_error) = yaml.parse(a, "{1.0: a, 1.0: b}", options(8u16, false))
    if float_duplicates_error != yaml.DuplicateKey { os.exit(171) }
    let (sequence_duplicates, sequence_duplicates_error) = yaml.parse(a, "{[1, 2]: a, [1, 2]: b}", options(8u16, false))
    if sequence_duplicates_error != yaml.DuplicateKey { os.exit(172) }
    let (mapping_duplicates, mapping_duplicates_error) = yaml.parse(a, "{{a: 1, b: 2}: x, {b: 2, a: 1}: y}", options(8u16, false))
    if mapping_duplicates_error != yaml.DuplicateKey { os.exit(173) }
    ret ok
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
    var wide_config: WideConfig = zero
    wide_config.big = 18446744073709551615u64
    var wide_state = io.SliceWriter { data: buffer[..], off: 0usize }
    var wide_sink = io.slice_writer(&wide_state)
    if yaml.encode[WideConfig](&wide_sink, &wide_config) != ok || !str.eq(buffer[..wide_state.off], "big: 18446744073709551615\n") { os.exit(99) }
    let (bad_config, e4) = yaml.decode[Config](a, "name: [1]\n", options(4u16, false))
    if e4 != yaml.Invalid { os.exit(79) }
    let (narrow_config, narrow_error) = yaml.decode[NarrowConfig](a, "port: 256\n", options(4u16, false))
    if narrow_error != yaml.Invalid { os.exit(97) }
    let (narrow_float, narrow_float_error) = yaml.decode[NarrowFloat](a, "ratio: 1e300\n", options(4u16, false))
    if narrow_float_error != yaml.Invalid { os.exit(98) }
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
    let (t9, e13) = yaml.parse(a, "a: \"quote \\\" # inside\"\n", options(4u16, false))
    if e13 != ok { os.exit(89) }
    let (escaped, has_escaped) = lookup(mapping_of(t9, 90), "a")
    if !has_escaped || !str.eq(text_of(escaped, 91), "quote \" # inside") { os.exit(92) }
    // YAML double quotes cannot carry raw C0/DEL bytes.  The writer must use
    // the parser's existing `\\xHH` spelling so arbitrary byte strings round-trip.
    var controls: [3]u8 = zero
    controls[0usize] = 0u8
    controls[1usize] = 1u8
    controls[2usize] = 127u8
    var control_value = yaml.Value { String: controls[..] }
    var control_buffer: [64]u8 = zero
    var control_state = io.SliceWriter { data: control_buffer[..], off: 0usize }
    var control_sink = io.slice_writer(&control_state)
    if yaml.write(&control_sink, &control_value, 2u8) != ok { os.exit(93) }
    let control_text = control_buffer[..control_state.off]
    if !str.eq(control_text, "\"\\x00\\x01\\x7f\"\n") { os.exit(94) }
    let (control_again, control_error) = yaml.parse(a, control_text, options(4u16, false))
    if control_error != ok || !str.eq(text_of(control_again, 95), controls[..]) { os.exit(96) }
    if issue_150_regressions(a) != ok { os.exit(172) }
    ret ok
}
