// Signature scanning, a YARA-lite subset (L053). `compile` parses rule text -- `rule name { meta: ... strings: ... condition: ... }`
// with text strings (modifiers `ascii`, `wide`, `nocase`, `fullword`; escapes `\\ \" \n \r \t \xHH`) and hex strings (`4D 5A`,
// `??`, `4?`, `?A`, jumps `[n]` and `[n-m]`) and conditions (`and`, `or`, `not`, parentheses, `true`, `false`, `$a`, `$a at N`,
// `#a OP N`, `filesize OP N`, `any|all|none|N of them`, `... of ($a, $b, $c*)`, numbers in decimal or `0x` with `KB`/`MB`) --
// into arena tables; `scan` counts, per string, the offsets at which it matches (overlapping occurrences count; a string
// matching as both ascii and wide at one offset counts once) and evaluates every rule. Hex strings backtrack over jumps, so
// the cost of one start offset is bounded by the product of the jump widths. Not here: regular expressions, modules,
// imports, `at`/`in` ranges beyond `$a at N`, string alternatives, tags, `private`/`global`, `for` loops, xor/base64.
//
// Memory: tables come from the arena given to `compile`; rule and string names borrow from the source text, which must
// outlive the set. Capacities: 64 rules, 256 strings, 4096 tokens, 1024 condition nodes (`TooMany` beyond them).

use e.mem

error Syntax
error TooMany
error TooSmall

type Token = struct { kind: u8, value: u8, mask: u8, min: u32, max: u32 }

type Pattern = struct { name: str, first: u32, count: u32, hex: bool, nocase: bool, ascii: bool, wide: bool, fullword: bool }

type Node = struct { kind: u8, op: u8, quant: u8, a: u32, b: u32, n: u64 }

type Rule = struct { name: str, first_string: u32, string_count: u32, root: u32 }

type Set = struct { rules: []Rule, patterns: []Pattern, tokens: []Token, nodes: []Node, members: []u32, rule_count: usize, pattern_count: usize, token_count: usize, node_count: usize, member_count: usize }

type Parser = struct { src: str, at: usize, s: Set, rule_first: usize }

const MAX_RULES: usize = 64usize
const MAX_PATTERNS: usize = 256usize
const MAX_TOKENS: usize = 4096usize
const MAX_NODES: usize = 1024usize
const MAX_MEMBERS: usize = 1024usize

// node kinds
const N_TRUE: u8 = 0u8
const N_FALSE: u8 = 1u8
const N_AND: u8 = 2u8
const N_OR: u8 = 3u8
const N_NOT: u8 = 4u8
const N_STRING: u8 = 5u8
const N_AT: u8 = 6u8
const N_COUNT: u8 = 7u8
const N_FILESIZE: u8 = 8u8
const N_OF: u8 = 9u8

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

fn is_ident_start(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || c == 95u8 }

fn is_ident(c: u8) -> bool { ret is_ident_start(c) || (c >= 48u8 && c <= 57u8) }

fn is_alnum(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || (c >= 48u8 && c <= 57u8) }

fn fold(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn same(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn skip(p: *Parser) {
    while p.at < p.src.len {
        let c = p.src[p.at]
        if is_space(c) {
            p.at += 1usize
        } else if c == 47u8 && p.at + 1usize < p.src.len && p.src[p.at + 1usize] == 47u8 {
            while p.at < p.src.len && p.src[p.at] != 10u8 { p.at += 1usize }
        } else if c == 47u8 && p.at + 1usize < p.src.len && p.src[p.at + 1usize] == 42u8 {
            p.at += 2usize
            while p.at + 1usize < p.src.len && !(p.src[p.at] == 42u8 && p.src[p.at + 1usize] == 47u8) { p.at += 1usize }
            p.at += 2usize
        } else {
            break
        }
    }
}

// An identifier at the cursor ("" when there is none); consumes it.
fn word(p: *Parser) -> str {
    skip(p)
    let start = p.at
    if p.at >= p.src.len || !is_ident_start(p.src[p.at]) { ret "" }
    while p.at < p.src.len && is_ident(p.src[p.at]) { p.at += 1usize }
    let w: str = p.src[start..p.at]
    ret w
}

// The identifier at the cursor, left in place.
fn peek_word(p: *Parser) -> str {
    skip(p)
    let save = p.at
    let w = word(p)
    p.at = save
    ret w
}

fn eat(p: *Parser, c: u8) -> bool {
    skip(p)
    if p.at < p.src.len && p.src[p.at] == c {
        p.at += 1usize
        ret true
    }
    ret false
}

fn hexval(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 102u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 70u8 { ret i32(c) - 55i32 }
    ret -1i32
}

// A decimal or 0x number with an optional KB or MB suffix.
fn number(p: *Parser) -> (u64, bool) {
    skip(p)
    var v = 0u64
    var digits = 0usize
    if p.at + 1usize < p.src.len && p.src[p.at] == 48u8 && (p.src[p.at + 1usize] == 120u8 || p.src[p.at + 1usize] == 88u8) {
        p.at += 2usize
        while p.at < p.src.len && hexval(p.src[p.at]) >= 0i32 {
            if v > 0x0FFFFFFFFFFFFFFFu64 { ret (0u64, false) }
            v = v * 16u64 + u64(hexval(p.src[p.at]))
            p.at += 1usize
            digits += 1usize
        }
    } else {
        while p.at < p.src.len && p.src[p.at] >= 48u8 && p.src[p.at] <= 57u8 {
            if v > 1844674407370955160u64 { ret (0u64, false) }
            v = v * 10u64 + u64(p.src[p.at] - 48u8)
            p.at += 1usize
            digits += 1usize
        }
    }
    if digits == 0usize { ret (0u64, false) }
    if p.at + 1usize < p.src.len && p.src[p.at] == 75u8 && p.src[p.at + 1usize] == 66u8 {
        p.at += 2usize
        v = v * 1024u64
    } else if p.at + 1usize < p.src.len && p.src[p.at] == 77u8 && p.src[p.at + 1usize] == 66u8 {
        p.at += 2usize
        v = v * 1048576u64
    }
    ret (v, true)
}

fn new_node(p: *Parser, kind: u8) -> (u32, bool) {
    if p.s.node_count >= MAX_NODES { ret (0u32, false) }
    let i = p.s.node_count
    p.s.nodes[i] = Node { kind: kind, op: 0u8, quant: 0u8, a: 0u32, b: 0u32, n: 0u64 }
    p.s.node_count += 1usize
    ret (u32(i), true)
}

fn push_token(p: *Parser, t: Token) -> bool {
    if p.s.token_count >= MAX_TOKENS { ret false }
    p.s.tokens[p.s.token_count] = t
    p.s.token_count += 1usize
    ret true
}

// `$name` pattern index within the current rule, or -1.
fn find_pattern(p: *Parser, name: str) -> i32 {
    var i = p.rule_first
    while i < p.s.pattern_count {
        if same(p.s.patterns[i].name, name) { ret i32(i) }
        i += 1usize
    }
    ret -1i32
}

// A quoted text string: bytes become tokens; false on a bad escape or an unterminated string.
fn text_string(p: *Parser, pat: *Pattern) -> bool {
    p.at += 1usize
    var count = 0u32
    while true {
        if p.at >= p.src.len { ret false }
        var c = p.src[p.at]
        p.at += 1usize
        if c == 34u8 { break }
        if c == 92u8 {
            if p.at >= p.src.len { ret false }
            let e = p.src[p.at]
            p.at += 1usize
            if e == 110u8 {
                c = 10u8
            } else if e == 114u8 {
                c = 13u8
            } else if e == 116u8 {
                c = 9u8
            } else if e == 92u8 || e == 34u8 {
                c = e
            } else if e == 120u8 {
                if p.at + 1usize >= p.src.len { ret false }
                let hi = hexval(p.src[p.at])
                let lo = hexval(p.src[p.at + 1usize])
                if hi < 0i32 || lo < 0i32 { ret false }
                c = u8(hi * 16i32 + lo)
                p.at += 2usize
            } else {
                ret false
            }
        }
        if !push_token(p, Token { kind: 0u8, value: c, mask: 255u8, min: 0u32, max: 0u32 }) { ret false }
        count += 1u32
    }
    if count == 0u32 { ret false }
    pat.count = count
    ret true
}

// A hex string `{ ... }` with `??`, nibble wildcards and jumps; the cursor is just after the `{`.
fn hex_string(p: *Parser, pat: *Pattern) -> bool {
    var count = 0u32
    var last_jump = true
    var bytes = 0u32
    while true {
        skip(p)
        if p.at >= p.src.len { ret false }
        let c = p.src[p.at]
        if c == 125u8 {
            p.at += 1usize
            break
        }
        if c == 91u8 {
            if last_jump { ret false }
            p.at += 1usize
            let (lo, lo_ok) = number(p)
            if !lo_ok { ret false }
            var hi = lo
            skip(p)
            if p.at < p.src.len && p.src[p.at] == 45u8 {
                p.at += 1usize
                let (h, h_ok) = number(p)
                if !h_ok { ret false }
                hi = h
            }
            skip(p)
            if p.at >= p.src.len || p.src[p.at] != 93u8 { ret false }
            p.at += 1usize
            if hi < lo || hi > 1000u64 { ret false }
            if !push_token(p, Token { kind: 1u8, value: 0u8, mask: 0u8, min: u32(lo), max: u32(hi) }) { ret false }
            count += 1u32
            last_jump = true
        } else {
            if p.at + 1usize >= p.src.len { ret false }
            let d = p.src[p.at + 1usize]
            var hi_v = 0u8
            var hi_m = 0u8
            var lo_v = 0u8
            var lo_m = 0u8
            if c != 63u8 {
                if hexval(c) < 0i32 { ret false }
                hi_v = u8(hexval(c)) << 4u8
                hi_m = 240u8
            }
            if d != 63u8 {
                if hexval(d) < 0i32 { ret false }
                lo_v = u8(hexval(d))
                lo_m = 15u8
            }
            p.at += 2usize
            if !push_token(p, Token { kind: 0u8, value: hi_v | lo_v, mask: hi_m | lo_m, min: 0u32, max: 0u32 }) { ret false }
            count += 1u32
            bytes += 1u32
            last_jump = false
        }
    }
    if last_jump || bytes == 0u32 { ret false }
    pat.count = count
    ret true
}

// One `$name = ...` declaration; the cursor is just after the `$`.
fn declaration(p: *Parser) -> err {
    let start = p.at
    while p.at < p.src.len && is_ident(p.src[p.at]) { p.at += 1usize }
    if p.at == start { ret Syntax }
    let name: str = p.src[start..p.at]
    if find_pattern(p, name) >= 0i32 { ret Syntax }
    if p.s.pattern_count >= MAX_PATTERNS { ret TooMany }
    if !eat(p, 61u8) { ret Syntax }
    var pat = Pattern { name: name, first: u32(p.s.token_count), count: 0u32, hex: false, nocase: false, ascii: false, wide: false, fullword: false }
    skip(p)
    if p.at >= p.src.len { ret Syntax }
    if p.src[p.at] == 34u8 {
        if !text_string(p, &pat) { ret Syntax }
        while true {
            let w = peek_word(p)
            if same(w, "ascii") {
                pat.ascii = true
            } else if same(w, "wide") {
                pat.wide = true
            } else if same(w, "nocase") {
                pat.nocase = true
            } else if same(w, "fullword") {
                pat.fullword = true
            } else {
                break
            }
            let consumed = word(p)
        }
        if !pat.ascii && !pat.wide { pat.ascii = true }
    } else if p.src[p.at] == 123u8 {
        p.at += 1usize
        pat.hex = true
        if !hex_string(p, &pat) { ret Syntax }
    } else {
        ret Syntax
    }
    if p.s.token_count > MAX_TOKENS { ret TooMany }
    p.s.patterns[p.s.pattern_count] = pat
    p.s.pattern_count += 1usize
    ret ok
}

fn compare_op(p: *Parser) -> (u8, bool) {
    skip(p)
    if p.at >= p.src.len { ret (0u8, false) }
    let c = p.src[p.at]
    var next = 0u8
    if p.at + 1usize < p.src.len { next = p.src[p.at + 1usize] }
    if c == 61u8 && next == 61u8 {
        p.at += 2usize
        ret (0u8, true)
    }
    if c == 33u8 && next == 61u8 {
        p.at += 2usize
        ret (1u8, true)
    }
    if c == 60u8 && next == 61u8 {
        p.at += 2usize
        ret (3u8, true)
    }
    if c == 62u8 && next == 61u8 {
        p.at += 2usize
        ret (5u8, true)
    }
    if c == 60u8 {
        p.at += 1usize
        ret (2u8, true)
    }
    if c == 62u8 {
        p.at += 1usize
        ret (4u8, true)
    }
    ret (0u8, false)
}

fn add_member(p: *Parser, idx: usize) -> bool {
    if p.s.member_count >= MAX_MEMBERS { ret false }
    p.s.members[p.s.member_count] = u32(idx)
    p.s.member_count += 1usize
    ret true
}

// The set after `of`: `them` or a parenthesised list of `$name` and `$prefix*` entries.
fn string_set(p: *Parser, node: u32) -> bool {
    let first = p.s.member_count
    skip(p)
    let w = peek_word(p)
    if same(w, "them") {
        let consumed = word(p)
        var i = p.rule_first
        while i < p.s.pattern_count {
            if !add_member(p, i) { ret false }
            i += 1usize
        }
    } else if eat(p, 40u8) {
        while true {
            skip(p)
            if !eat(p, 36u8) { ret false }
            let start = p.at
            while p.at < p.src.len && is_ident(p.src[p.at]) { p.at += 1usize }
            if p.at == start { ret false }
            let name: str = p.src[start..p.at]
            if p.at < p.src.len && p.src[p.at] == 42u8 {
                p.at += 1usize
                var i = p.rule_first
                while i < p.s.pattern_count {
                    let pn = p.s.patterns[i].name
                    if pn.len >= name.len && same(pn[0usize..name.len], name) {
                        if !add_member(p, i) { ret false }
                    }
                    i += 1usize
                }
            } else {
                let at = find_pattern(p, name)
                if at < 0i32 { ret false }
                if !add_member(p, usize(at)) { ret false }
            }
            if eat(p, 44u8) { continue }
            if eat(p, 41u8) { break }
            ret false
        }
    } else {
        ret false
    }
    p.s.nodes[usize(node)].a = u32(first)
    p.s.nodes[usize(node)].b = u32(p.s.member_count - first)
    ret true
}

fn parse_primary(p: *Parser, depth: u32) -> (u32, bool) {
    if depth > 64u32 { ret (0u32, false) }
    skip(p)
    if p.at >= p.src.len { ret (0u32, false) }
    let c = p.src[p.at]
    if c == 40u8 {
        p.at += 1usize
        let (inner, ok_inner) = parse_or(p, depth + 1u32)
        if !ok_inner || !eat(p, 41u8) { ret (0u32, false) }
        ret (inner, true)
    }
    if c == 36u8 {
        p.at += 1usize
        let start = p.at
        while p.at < p.src.len && is_ident(p.src[p.at]) { p.at += 1usize }
        if p.at == start { ret (0u32, false) }
        let name: str = p.src[start..p.at]
        let idx = find_pattern(p, name)
        if idx < 0i32 { ret (0u32, false) }
        let w = peek_word(p)
        if same(w, "at") {
            let consumed = word(p)
            let (n, n_ok) = number(p)
            if !n_ok { ret (0u32, false) }
            let (node, made) = new_node(p, N_AT)
            if !made { ret (0u32, false) }
            p.s.nodes[usize(node)].a = u32(idx)
            p.s.nodes[usize(node)].n = n
            ret (node, true)
        }
        let (node, made) = new_node(p, N_STRING)
        if !made { ret (0u32, false) }
        p.s.nodes[usize(node)].a = u32(idx)
        ret (node, true)
    }
    if c == 35u8 {
        p.at += 1usize
        let start = p.at
        while p.at < p.src.len && is_ident(p.src[p.at]) { p.at += 1usize }
        if p.at == start { ret (0u32, false) }
        let name: str = p.src[start..p.at]
        let idx = find_pattern(p, name)
        if idx < 0i32 { ret (0u32, false) }
        let (op, op_ok) = compare_op(p)
        if !op_ok { ret (0u32, false) }
        let (n, n_ok) = number(p)
        if !n_ok { ret (0u32, false) }
        let (node, made) = new_node(p, N_COUNT)
        if !made { ret (0u32, false) }
        p.s.nodes[usize(node)].a = u32(idx)
        p.s.nodes[usize(node)].op = op
        p.s.nodes[usize(node)].n = n
        ret (node, true)
    }
    if c >= 48u8 && c <= 57u8 {
        let (n, n_ok) = number(p)
        if !n_ok { ret (0u32, false) }
        let w = word(p)
        if !same(w, "of") { ret (0u32, false) }
        let (node, made) = new_node(p, N_OF)
        if !made { ret (0u32, false) }
        p.s.nodes[usize(node)].quant = 3u8
        p.s.nodes[usize(node)].n = n
        if !string_set(p, node) { ret (0u32, false) }
        ret (node, true)
    }
    let w = word(p)
    if same(w, "true") {
        let (node, made) = new_node(p, N_TRUE)
        ret (node, made)
    }
    if same(w, "false") {
        let (node, made) = new_node(p, N_FALSE)
        ret (node, made)
    }
    if same(w, "filesize") {
        let (op, op_ok) = compare_op(p)
        if !op_ok { ret (0u32, false) }
        let (n, n_ok) = number(p)
        if !n_ok { ret (0u32, false) }
        let (node, made) = new_node(p, N_FILESIZE)
        if !made { ret (0u32, false) }
        p.s.nodes[usize(node)].op = op
        p.s.nodes[usize(node)].n = n
        ret (node, true)
    }
    if same(w, "any") || same(w, "all") || same(w, "none") {
        let of = word(p)
        if !same(of, "of") { ret (0u32, false) }
        let (node, made) = new_node(p, N_OF)
        if !made { ret (0u32, false) }
        if same(w, "any") {
            p.s.nodes[usize(node)].quant = 0u8
        } else if same(w, "all") {
            p.s.nodes[usize(node)].quant = 1u8
        } else {
            p.s.nodes[usize(node)].quant = 2u8
        }
        if !string_set(p, node) { ret (0u32, false) }
        ret (node, true)
    }
    ret (0u32, false)
}

fn parse_not(p: *Parser, depth: u32) -> (u32, bool) {
    if depth > 64u32 { ret (0u32, false) }
    let w = peek_word(p)
    if same(w, "not") {
        let consumed = word(p)
        let (inner, inner_ok) = parse_not(p, depth + 1u32)
        if !inner_ok { ret (0u32, false) }
        let (node, made) = new_node(p, N_NOT)
        if !made { ret (0u32, false) }
        p.s.nodes[usize(node)].a = inner
        ret (node, true)
    }
    let (node, made) = parse_primary(p, depth)
    ret (node, made)
}

fn parse_and(p: *Parser, depth: u32) -> (u32, bool) {
    let (first, left_ok) = parse_not(p, depth)
    if !left_ok { ret (0u32, false) }
    var left = first
    while true {
        let w = peek_word(p)
        if !same(w, "and") { break }
        let consumed = word(p)
        let (right, right_ok) = parse_not(p, depth)
        if !right_ok { ret (0u32, false) }
        let (node, made) = new_node(p, N_AND)
        if !made { ret (0u32, false) }
        p.s.nodes[usize(node)].a = left
        p.s.nodes[usize(node)].b = right
        left = node
    }
    ret (left, true)
}

fn parse_or(p: *Parser, depth: u32) -> (u32, bool) {
    let (first, left_ok) = parse_and(p, depth)
    if !left_ok { ret (0u32, false) }
    var left = first
    while true {
        let w = peek_word(p)
        if !same(w, "or") { break }
        let consumed = word(p)
        let (right, right_ok) = parse_and(p, depth)
        if !right_ok { ret (0u32, false) }
        let (node, made) = new_node(p, N_OR)
        if !made { ret (0u32, false) }
        p.s.nodes[usize(node)].a = left
        p.s.nodes[usize(node)].b = right
        left = node
    }
    ret (left, true)
}

// A `meta:` value: a quoted string, a number or true/false (checked, not kept).
fn meta_value(p: *Parser) -> bool {
    skip(p)
    if p.at >= p.src.len { ret false }
    if p.src[p.at] == 34u8 {
        p.at += 1usize
        while p.at < p.src.len && p.src[p.at] != 34u8 {
            if p.src[p.at] == 92u8 { p.at += 1usize }
            p.at += 1usize
        }
        if p.at >= p.src.len { ret false }
        p.at += 1usize
        ret true
    }
    if p.src[p.at] >= 48u8 && p.src[p.at] <= 57u8 {
        let (n, n_ok) = number(p)
        ret n_ok
    }
    let w = word(p)
    ret same(w, "true") || same(w, "false")
}

fn parse_rule(p: *Parser) -> err {
    if p.s.rule_count >= MAX_RULES { ret TooMany }
    let name = word(p)
    if name.len == 0usize { ret Syntax }
    var i = 0usize
    while i < p.s.rule_count {
        if same(p.s.rules[i].name, name) { ret Syntax }
        i += 1usize
    }
    if !eat(p, 123u8) { ret Syntax }
    p.rule_first = p.s.pattern_count
    var w = peek_word(p)
    if same(w, "meta") {
        let consumed = word(p)
        if !eat(p, 58u8) { ret Syntax }
        while true {
            w = peek_word(p)
            if w.len == 0usize || same(w, "strings") || same(w, "condition") { break }
            let key = word(p)
            if !eat(p, 61u8) { ret Syntax }
            if !meta_value(p) { ret Syntax }
        }
        w = peek_word(p)
    }
    if same(w, "strings") {
        let consumed = word(p)
        if !eat(p, 58u8) { ret Syntax }
        while true {
            skip(p)
            if p.at < p.src.len && p.src[p.at] == 36u8 {
                p.at += 1usize
                let e = declaration(p)
                if e != ok { ret e }
            } else {
                break
            }
        }
        w = peek_word(p)
    }
    if !same(w, "condition") { ret Syntax }
    let consumed = word(p)
    if !eat(p, 58u8) { ret Syntax }
    let (root, root_ok) = parse_or(p, 0u32)
    if !root_ok { ret Syntax }
    if !eat(p, 125u8) { ret Syntax }
    p.s.rules[p.s.rule_count] = Rule { name: name, first_string: u32(p.rule_first), string_count: u32(p.s.pattern_count - p.rule_first), root: root }
    p.s.rule_count += 1usize
    ret ok
}

// Parses rule text into tables; `Syntax` for anything outside the subset, `TooMany` past a capacity.
fn compile(a: *mem.Arena, source: str) -> (Set, err) {
    var s: Set = zero
    let (rules, e1) = mem.alloc[Rule](a, MAX_RULES)
    if e1 != ok { ret (s, e1) }
    let (patterns, e2) = mem.alloc[Pattern](a, MAX_PATTERNS)
    if e2 != ok { ret (s, e2) }
    let (tokens, e3) = mem.alloc[Token](a, MAX_TOKENS)
    if e3 != ok { ret (s, e3) }
    let (nodes, e4) = mem.alloc[Node](a, MAX_NODES)
    if e4 != ok { ret (s, e4) }
    let (members, e5) = mem.alloc[u32](a, MAX_MEMBERS)
    if e5 != ok { ret (s, e5) }
    s.rules = rules
    s.patterns = patterns
    s.tokens = tokens
    s.nodes = nodes
    s.members = members
    var p = Parser { src: source, at: 0usize, s: s, rule_first: 0usize }
    while true {
        skip(&p)
        if p.at >= p.src.len { break }
        let w = word(&p)
        if !same(w, "rule") { ret (s, Syntax) }
        let e = parse_rule(&p)
        if e != ok { ret (s, e) }
    }
    ret (p.s, ok)
}

// Whether pattern `pi` matches starting exactly at `pos`.
fn tokens_at(s: *const Set, t: usize, end: usize, data: []const u8, pos: usize) -> bool {
    var i = t
    var at = pos
    while i < end {
        let tok = s.tokens[i]
        if tok.kind == 1u8 {
            var gap = tok.min
            while gap <= tok.max {
                if tokens_at(s, i + 1usize, end, data, at + usize(gap)) { ret true }
                gap += 1u32
            }
            ret false
        }
        if at >= data.len { ret false }
        if (data[at] & tok.mask) != tok.value { ret false }
        at += 1usize
        i += 1usize
    }
    ret true
}

fn literal_at(s: *const Set, pat: Pattern, data: []const u8, pos: usize, wide: bool) -> bool {
    var step = 1usize
    if wide { step = 2usize }
    let n = usize(pat.count)
    if pos > data.len || n * step > data.len - pos { ret false }
    var i = 0usize
    while i < n {
        let want = s.tokens[usize(pat.first) + i].value
        let got = data[pos + i * step]
        if pat.nocase {
            if fold(got) != fold(want) { ret false }
        } else if got != want {
            ret false
        }
        if wide && data[pos + i * step + 1usize] != 0u8 { ret false }
        i += 1usize
    }
    if pat.fullword {
        let end = pos + n * step
        if wide {
            if pos >= 2usize && data[pos - 1usize] == 0u8 && is_alnum(data[pos - 2usize]) { ret false }
            if end + 2usize <= data.len && is_alnum(data[end]) && data[end + 1usize] == 0u8 { ret false }
        } else {
            if pos >= 1usize && is_alnum(data[pos - 1usize]) { ret false }
            if end < data.len && is_alnum(data[end]) { ret false }
        }
    }
    ret true
}

fn pattern_at(s: *const Set, pi: usize, data: []const u8, pos: usize) -> bool {
    let pat = s.patterns[pi]
    if pat.hex { ret tokens_at(s, usize(pat.first), usize(pat.first) + usize(pat.count), data, pos) }
    if pat.ascii && literal_at(s, pat, data, pos, false) { ret true }
    if pat.wide && literal_at(s, pat, data, pos, true) { ret true }
    ret false
}

// The number of offsets at which pattern `pi` matches.
fn count_matches(s: *const Set, pi: usize, data: []const u8) -> u32 {
    var n = 0u32
    var pos = 0usize
    while pos < data.len {
        if pattern_at(s, pi, data, pos) { n += 1u32 }
        pos += 1usize
    }
    ret n
}

// The `k`th (from zero) match offset of pattern `pi`.
fn nth_match(s: *const Set, pi: usize, data: []const u8, k: usize) -> (usize, bool) {
    var seen = 0usize
    var pos = 0usize
    while pos < data.len {
        if pattern_at(s, pi, data, pos) {
            if seen == k { ret (pos, true) }
            seen += 1usize
        }
        pos += 1usize
    }
    ret (0usize, false)
}

fn compare(op: u8, x: u64, y: u64) -> bool {
    if op == 0u8 { ret x == y }
    if op == 1u8 { ret x != y }
    if op == 2u8 { ret x < y }
    if op == 3u8 { ret x <= y }
    if op == 4u8 { ret x > y }
    ret x >= y
}

fn eval(s: *const Set, node: u32, data: []const u8, counts: []const u32) -> bool {
    let n = s.nodes[usize(node)]
    if n.kind == N_TRUE { ret true }
    if n.kind == N_FALSE { ret false }
    if n.kind == N_AND { ret eval(s, n.a, data, counts) && eval(s, n.b, data, counts) }
    if n.kind == N_OR { ret eval(s, n.a, data, counts) || eval(s, n.b, data, counts) }
    if n.kind == N_NOT { ret !eval(s, n.a, data, counts) }
    if n.kind == N_STRING { ret counts[usize(n.a)] > 0u32 }
    if n.kind == N_AT {
        if n.n >= u64(data.len) { ret false }
        ret pattern_at(s, usize(n.a), data, usize(n.n))
    }
    if n.kind == N_COUNT { ret compare(n.op, u64(counts[usize(n.a)]), n.n) }
    if n.kind == N_FILESIZE { ret compare(n.op, u64(data.len), n.n) }
    var hit = 0u64
    var i = 0usize
    while i < usize(n.b) {
        if counts[usize(s.members[usize(n.a) + i])] > 0u32 { hit += 1u64 }
        i += 1usize
    }
    if n.quant == 0u8 { ret hit >= 1u64 }
    if n.quant == 1u8 { ret hit == u64(n.b) }
    if n.quant == 2u8 { ret hit == 0u64 }
    ret hit >= n.n
}

// Counts every string's matches into `counts` (one per string, in source order) and sets `matched` per rule.
fn scan(s: *const Set, data: []const u8, counts: []u32, matched: []bool) -> err {
    if counts.len < s.pattern_count || matched.len < s.rule_count { ret TooSmall }
    var i = 0usize
    while i < s.pattern_count {
        counts[i] = count_matches(s, i, data)
        i += 1usize
    }
    i = 0usize
    while i < s.rule_count {
        matched[i] = eval(s, s.rules[i].root, data, counts)
        i += 1usize
    }
    ret ok
}
