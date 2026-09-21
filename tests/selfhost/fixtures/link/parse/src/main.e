// `e.parse`: the scanner's kinds and spans on a small program, the off-side
// rule's INDENT/DEDENT stream, shunting-yard RPN against a Python
// shunting-yard, the Pratt and recursive-descent ASTs evaluated against
// Python, CYK and Earley on a toy grammar and on LCG-drawn parenthesis
// strings (brute-force checked in Python), Earley next-terminal sets under
// the arithmetic grammar, and a packrat JSON-ish PEG. Each check exits with
// its own code. Expected values: scratchpad parse_ref.py.

use e.io
use e.mem
use e.os
use e.parse
use e.str

fn spans(a: *mem.Arena, tokens: []const parse.Token) -> str {
    var (b, _) = str.builder(a, 512usize)
    var i = 0usize
    while i < tokens.len {
        if str.push_u8(&b, tokens[i].kind) != ok { os.exit(9i32) }
        if str.push_byte(&b, 58u8) != ok { os.exit(9i32) }
        if str.push_usize(&b, tokens[i].start) != ok { os.exit(9i32) }
        if str.push_byte(&b, 58u8) != ok { os.exit(9i32) }
        if str.push_usize(&b, tokens[i].len) != ok { os.exit(9i32) }
        if str.push_byte(&b, 32u8) != ok { os.exit(9i32) }
        i += 1usize
    }
    ret str.done(&b)
}

fn texts(a: *mem.Arena, tokens: []const parse.Token, text: str) -> str {
    var (b, _) = str.builder(a, 256usize)
    var i = 0usize
    while i < tokens.len {
        if str.push(&b, text[tokens[i].start..tokens[i].start + tokens[i].len]) != ok { os.exit(9i32) }
        if str.push_byte(&b, 32u8) != ok { os.exit(9i32) }
        i += 1usize
    }
    ret str.done(&b)
}

fn close(x: f64, y: f64) -> bool {
    var d = x - y
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.000000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var tokens: [64]parse.Token = zero

    // 1: lex kinds and spans.
    let program = "fn add(a, b) -> int { // sum\n  if a >= 10 { ret \"x\\\"y\" }\n  ret a + b == 3\n}\n"
    let lex_want = "1:0:2 1:3:3 4:6:1 1:7:1 4:8:1 1:10:1 4:11:1 4:13:2 1:16:3 4:20:1 1:31:2 1:34:1 4:36:2 2:39:2 4:42:1 1:44:3 3:48:6 4:55:1 1:59:3 1:63:1 4:65:1 1:67:1 4:69:2 2:72:1 4:74:1 "
    let operators = [6]str { "==", "<=", ">=", "!=", "->", "+=" }
    let (lexed, lex_error) = parse.lex(program, operators[..], tokens[..])
    if lex_error != ok || !str.eq(spans(a, tokens[..lexed]), lex_want) { os.exit(1i32) }
    let (_, unterminated) = parse.lex("a \"b", operators[..], tokens[..])
    if unterminated != parse.Invalid { os.exit(1i32) }
    let (_, room) = parse.lex(program, operators[..], tokens[..3usize])
    if room != parse.TooSmall { os.exit(1i32) }

    // 2: the off-side rule.
    let indent_text = "a\n  b\n\n    c\n    d\n  e\n      f\ng\n  h"
    let indent_want = "5:2:2 5:7:4 6:19:2 5:23:6 6:31:2 6:31:0 5:33:2 6:36:0 "
    var stack: [8]usize = zero
    let (indented, indent_error) = parse.lex_indent(indent_text, stack[..], tokens[..])
    if indent_error != ok || !str.eq(spans(a, tokens[..indented]), indent_want) { os.exit(2i32) }
    let (_, inconsistent) = parse.lex_indent("a\n    b\n  c\n", stack[..], tokens[..])
    if inconsistent != parse.Invalid { os.exit(2i32) }

    // 3: shunting-yard RPN; 4: Pratt; 5: recursive descent.
    let exprs = [20]str { "1 + 2 * 3", "(1 + 2) * 3", "2 ^ 3 ^ 2", "10 - 4 - 3", "100 / 5 / 2", "2 * (3 + 4) ^ 2", "7 + 8 * 2 - 9 / 3", "(2 + 3) * (4 - 1) / 5", "2 ^ 10", "1 + 2 + 3 + 4 + 5", "8 / 2 ^ 2", "3 * 4 ^ 2 ^ 1", "((1))", "42", "-2 ^ 2", "2 ^ -1", "-(3 + 4) * 2", "--5 + 1", "3 - -3", "-2 * -3 ^ 2" }
    let rpn_want = [20]str { "1 2 3 * + ", "1 2 + 3 * ", "2 3 2 ^ ^ ", "10 4 - 3 - ", "100 5 / 2 / ", "2 3 4 + 2 ^ * ", "7 8 2 * + 9 3 / - ", "2 3 + 4 1 - * 5 / ", "2 10 ^ ", "1 2 + 3 + 4 + 5 + ", "8 2 2 ^ / ", "3 4 2 1 ^ ^ * ", "1 ", "42 ", "", "", "", "", "", "" }
    let values = [20]f64 { 7.0f64, 9.0f64, 512.0f64, 3.0f64, 10.0f64, 98.0f64, 20.0f64, 3.0f64, 1024.0f64, 15.0f64, 2.0f64, 48.0f64, 1.0f64, 42.0f64, -4.0f64, 0.5f64, -14.0f64, 6.0f64, 6.0f64, 18.0f64 }
    var ops: [6]parse.Op = zero
    ops[0usize] = parse.Op { text: "+", kind: parse.INFIX, prec: 1u8, right: false }
    ops[1usize] = parse.Op { text: "-", kind: parse.INFIX, prec: 1u8, right: false }
    ops[2usize] = parse.Op { text: "*", kind: parse.INFIX, prec: 2u8, right: false }
    ops[3usize] = parse.Op { text: "/", kind: parse.INFIX, prec: 2u8, right: false }
    ops[4usize] = parse.Op { text: "^", kind: parse.INFIX, prec: 4u8, right: true }
    ops[5usize] = parse.Op { text: "-", kind: parse.PREFIX, prec: 3u8, right: false }
    var rpn: [32]parse.Token = zero
    var op_stack: [16]parse.Token = zero
    var kind: [64]u8 = zero
    var left: [64]u32 = zero
    var right: [64]u32 = zero
    var tok: [64]u32 = zero
    var i = 0usize
    while i < 20usize {
        let text = exprs[i]
        let (n, e) = parse.lex(text, operators[..0usize], tokens[..])
        if e != ok { os.exit(3i32) }
        if rpn_want[i].len > 0usize {
            let (m, rpn_error) = parse.shunting_yard(tokens[..n], text, ops[..], rpn[..], op_stack[..])
            if rpn_error != ok || !str.eq(texts(a, rpn[..m], text), rpn_want[i]) { os.exit(3i32) }
        }
        var t = parse.ast(kind[..], left[..], right[..], tok[..])
        let (root, pratt_error) = parse.pratt(tokens[..n], text, ops[..], &t)
        if pratt_error != ok { os.exit(4i32) }
        let (v, v_error) = parse.evaluate(&t, root, tokens[..n], text)
        if v_error != ok || !close(v, values[i]) { os.exit(4i32) }
        var u = parse.ast(kind[..], left[..], right[..], tok[..])
        let (rd_root, rd_error) = parse.recursive_descent(tokens[..n], text, &u)
        if rd_error != ok { os.exit(5i32) }
        let (w, w_error) = parse.evaluate(&u, rd_root, tokens[..n], text)
        if w_error != ok || !close(w, values[i]) { os.exit(5i32) }
        i += 1usize
    }
    let (bad_n, _) = parse.lex("(1 + 2", operators[..0usize], tokens[..])
    let (_, unbalanced) = parse.shunting_yard(tokens[..bad_n], "(1 + 2", ops[..], rpn[..], op_stack[..])
    if unbalanced != parse.Invalid { os.exit(3i32) }
    var t2 = parse.ast(kind[..], left[..], right[..], tok[..])
    let (_, bad_pratt) = parse.pratt(tokens[..bad_n], "(1 + 2", ops[..], &t2)
    if bad_pratt != parse.Invalid { os.exit(4i32) }
    let (_, bad_rd) = parse.recursive_descent(tokens[..bad_n], "(1 + 2", &t2)
    if bad_rd != parse.Invalid { os.exit(5i32) }
    if parse.ast_child(&t2, 1u32, 0usize) != 0u32 { os.exit(4i32) }

    // 6: CYK on the toy grammar and on parenthesis strings.
    let toy_lhs = [8]u32 { 5u32, 6u32, 7u32, 8u32, 8u32, 9u32, 9u32, 10u32 }
    let toy_rhs = [11]u32 { 6u32, 7u32, 8u32, 9u32, 10u32, 6u32, 0u32, 4u32, 1u32, 2u32, 3u32 }
    let toy_start = [9]usize { 0usize, 2usize, 4usize, 6usize, 7usize, 8usize, 9usize, 10usize, 11usize }
    let toy = parse.grammar(toy_lhs[..], toy_rhs[..], toy_start[..], 5u32)
    let toy_lens = [7]usize { 5usize, 5usize, 3usize, 4usize, 6usize, 5usize, 3usize }
    let toy_words = [31]u32 { 0u32, 1u32, 3u32, 4u32, 2u32, 4u32, 2u32, 3u32, 0u32, 1u32, 0u32, 1u32, 3u32, 1u32, 3u32, 4u32, 2u32, 0u32, 0u32, 1u32, 3u32, 4u32, 2u32, 4u32, 1u32, 3u32, 4u32, 1u32, 3u32, 0u32, 2u32 }
    var chart: [64]u64 = zero
    var items: [1024]parse.Item = zero
    var sets: [16]usize = zero
    var toy_cyk = 0u64
    var toy_earley = 0u64
    var offset = 0usize
    i = 0usize
    while i < 7usize {
        let sentence = toy_words[offset..offset + toy_lens[i]]
        let (derived, cyk_error) = parse.cyk(&toy, 5u32, sentence, chart[..])
        if cyk_error != ok { os.exit(6i32) }
        if derived { toy_cyk |= 1u64 << u32(i) }
        let (recognised, _, earley_error) = parse.earley(&toy, 5u32, sentence, items[..], sets[..])
        if earley_error != ok { os.exit(7i32) }
        if recognised { toy_earley |= 1u64 << u32(i) }
        offset += toy_lens[i]
        i += 1usize
    }
    if toy_cyk != 35u64 { os.exit(6i32) }
    if toy_earley != 35u64 { os.exit(7i32) }
    // Balanced parentheses: CNF  L -> ( ; R -> ) ; S -> L R | L X | S S ; X -> S R
    let cnf_lhs = [6]u32 { 2u32, 3u32, 4u32, 4u32, 4u32, 5u32 }
    let cnf_rhs = [10]u32 { 0u32, 1u32, 2u32, 3u32, 2u32, 5u32, 4u32, 4u32, 4u32, 3u32 }
    let cnf_start = [7]usize { 0usize, 1usize, 2usize, 4usize, 6usize, 8usize, 10usize }
    let cnf = parse.grammar(cnf_lhs[..], cnf_rhs[..], cnf_start[..], 2u32)
    // General:  S -> | ( S ) S
    let gen_lhs = [2]u32 { 2u32, 2u32 }
    let gen_rhs = [4]u32 { 0u32, 2u32, 1u32, 2u32 }
    let gen_start = [3]usize { 0usize, 0usize, 4usize }
    let general = parse.grammar(gen_lhs[..], gen_rhs[..], gen_start[..], 2u32)
    var state = 195u64
    var word: [8]u32 = zero
    var cyk_mask = 0u64
    var earley_mask = 0u64
    i = 0usize
    while i < 30usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let length = 2usize + usize((state >> 33u32) % 7u64)
        var j = 0usize
        while j < length {
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            word[j] = u32((state >> 33u32) & 1u64)
            j += 1usize
        }
        let (derived, cyk_error) = parse.cyk(&cnf, 4u32, word[..length], chart[..])
        if cyk_error != ok { os.exit(6i32) }
        if derived { cyk_mask |= 1u64 << u32(i) }
        let (recognised, _, earley_error) = parse.earley(&general, 2u32, word[..length], items[..], sets[..])
        if earley_error != ok { os.exit(7i32) }
        if recognised { earley_mask |= 1u64 << u32(i) }
        i += 1usize
    }
    if cyk_mask != 69732385u64 { os.exit(6i32) }
    if earley_mask != 69732385u64 { os.exit(7i32) }
    let (empty_ok, _, _) = parse.earley(&general, 2u32, word[..0usize], items[..], sets[..])
    if !empty_ok { os.exit(7i32) }
    let (_, unit) = parse.cyk(&general, 2u32, word[..2usize], chart[..])
    if unit != parse.Invalid { os.exit(6i32) }

    // 8: next terminals under  E -> E + T | T ; T -> T * F | F ; F -> ( E ) | n
    let ar_lhs = [6]u32 { 5u32, 5u32, 6u32, 6u32, 7u32, 7u32 }
    let ar_rhs = [12]u32 { 5u32, 1u32, 6u32, 6u32, 6u32, 2u32, 7u32, 7u32, 3u32, 5u32, 4u32, 0u32 }
    let ar_start = [7]usize { 0usize, 3usize, 4usize, 7usize, 8usize, 11usize, 12usize }
    let arith = parse.grammar(ar_lhs[..], ar_rhs[..], ar_start[..], 5u32)
    let prefix_lens = [8]usize { 0usize, 1usize, 2usize, 2usize, 3usize, 3usize, 2usize, 6usize }
    let prefix_words = [19]u32 { 0u32, 0u32, 1u32, 3u32, 0u32, 3u32, 0u32, 4u32, 0u32, 2u32, 3u32, 0u32, 0u32, 3u32, 3u32, 0u32, 4u32, 4u32, 2u32 }
    let prefix_masks = [8]u64 { 9u64, 6u64, 9u64, 22u64, 6u64, 9u64, 0u64, 9u64 }
    var allowed: [8]u32 = zero
    offset = 0usize
    i = 0usize
    while i < 8usize {
        let (count, next_error) = parse.next_terminals(&arith, 5u32, prefix_words[offset..offset + prefix_lens[i]], allowed[..], items[..], sets[..])
        if next_error != ok { os.exit(8i32) }
        var mask = 0u64
        var j = 0usize
        while j < count {
            if j > 0usize && allowed[j] <= allowed[j - 1usize] { os.exit(8i32) }
            mask |= 1u64 << allowed[j]
            j += 1usize
        }
        if mask != prefix_masks[i] { os.exit(8i32) }
        offset += prefix_lens[i]
        i += 1usize
    }

    // 9: packrat PEG over a JSON-ish subset.
    let peg_op = [96]u8 { 1u8, 1u8, 5u8, 6u8, 2u8, 1u8, 8u8, 7u8, 1u8, 7u8, 4u8, 8u8, 4u8, 4u8, 1u8, 3u8, 4u8, 1u8, 9u8, 3u8, 4u8, 5u8, 1u8, 6u8, 1u8, 4u8, 4u8, 11u8, 11u8, 11u8, 4u8, 4u8, 1u8, 11u8, 1u8, 4u8, 6u8, 4u8, 8u8, 1u8, 4u8, 4u8, 4u8, 11u8, 11u8, 11u8, 1u8, 4u8, 4u8, 4u8, 4u8, 1u8, 4u8, 6u8, 4u8, 1u8, 11u8, 11u8, 8u8, 1u8, 4u8, 4u8, 4u8, 11u8, 11u8, 11u8, 11u8, 1u8, 1u8, 1u8, 1u8, 4u8, 4u8, 4u8, 1u8, 1u8, 1u8, 1u8, 1u8, 4u8, 4u8, 4u8, 4u8, 1u8, 1u8, 1u8, 1u8, 4u8, 4u8, 4u8, 5u8, 5u8, 5u8, 5u8, 5u8, 5u8 }
    let peg_a = [96]u32 { 32u32, 10u32, 0u32, 2u32, 48u32, 45u32, 5u32, 4u32, 46u32, 4u32, 8u32, 10u32, 7u32, 6u32, 92u32, 0u32, 14u32, 34u32, 17u32, 0u32, 18u32, 16u32, 34u32, 21u32, 34u32, 23u32, 22u32, 0u32, 1u32, 1u32, 27u32, 28u32, 91u32, 1u32, 44u32, 34u32, 35u32, 31u32, 37u32, 93u32, 38u32, 33u32, 32u32, 1u32, 3u32, 1u32, 58u32, 46u32, 45u32, 44u32, 43u32, 44u32, 51u32, 52u32, 50u32, 123u32, 1u32, 6u32, 57u32, 125u32, 58u32, 56u32, 55u32, 5u32, 4u32, 3u32, 2u32, 116u32, 114u32, 117u32, 101u32, 69u32, 68u32, 67u32, 102u32, 97u32, 108u32, 115u32, 101u32, 77u32, 76u32, 75u32, 74u32, 110u32, 117u32, 108u32, 108u32, 85u32, 84u32, 83u32, 82u32, 73u32, 66u32, 65u32, 64u32, 63u32 }
    let peg_b = [96]u32 { 0u32, 0u32, 1u32, 0u32, 57u32, 0u32, 0u32, 0u32, 0u32, 0u32, 9u32, 0u32, 11u32, 12u32, 0u32, 0u32, 15u32, 0u32, 0u32, 0u32, 19u32, 20u32, 0u32, 0u32, 0u32, 24u32, 25u32, 0u32, 0u32, 0u32, 29u32, 30u32, 0u32, 0u32, 0u32, 31u32, 0u32, 36u32, 0u32, 0u32, 39u32, 40u32, 41u32, 0u32, 0u32, 0u32, 0u32, 31u32, 47u32, 48u32, 49u32, 0u32, 50u32, 0u32, 53u32, 0u32, 0u32, 0u32, 0u32, 0u32, 59u32, 60u32, 61u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 70u32, 71u32, 72u32, 0u32, 0u32, 0u32, 0u32, 0u32, 78u32, 79u32, 80u32, 81u32, 0u32, 0u32, 0u32, 0u32, 86u32, 87u32, 88u32, 89u32, 90u32, 91u32, 92u32, 93u32, 94u32 }
    let peg_rules = [7]u32 { 95u32, 3u32, 13u32, 26u32, 42u32, 62u32, 54u32 }
    let jsons = [8]str { "{\"a\": [1, 2.5, -3], \"b\": {\"c\": \"x\\\"y\"}, \"d\": null}", "[true, false, [ ], {}]", "\"abc", "[1, 2,]", "12.", "{\"k\": 1} extra", "  [1]", "{\"a\" : {\"b\" : [ [ ] ] } }" }
    let peg_want = [8]i64 { 50i64, 22i64, -1i64, -1i64, 2i64, 8i64, -1i64, 25i64 }
    let json_peg = parse.Peg { op: peg_op[..], a: peg_a[..], b: peg_b[..], rules: peg_rules[..] }
    var memo: [512]i64 = zero
    i = 0usize
    while i < 8usize {
        let (length, matched, peg_error) = parse.peg(&json_peg, 0usize, jsons[i], memo[..])
        if peg_error != ok { os.exit(9i32) }
        var got = -1i64
        if matched { got = i64(length) }
        if got != peg_want[i] { os.exit(9i32) }
        i += 1usize
    }
    let (_, _, peg_room) = parse.peg(&json_peg, 0usize, jsons[0usize], memo[..16usize])
    if peg_room != parse.TooSmall { os.exit(9i32) }

    try io.print("parse ok\n")
    ret ok
}
