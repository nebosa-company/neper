// Regular expressions over UTF-8: a pattern compiles once into an arena and runs as a
// Pike VM, so a match costs time linear in the text times the program, never the
// exponential blow-up a backtracker pays. The accepted syntax is regular only:
// literals, `.`, classes `[a-z]` `[^...]` with `\d \w \s` and their negations, the
// anchors `^` `$` `\b` `\B`, the repeats `* + ? {m} {m,} {m,n}` each with a lazy `?`,
// alternation `|`, capturing `(...)` and non-capturing `(?:...)` groups, and the
// escapes `\n \t \r` and `\<punctuation>`. No backreferences, recursion or lookaround.
//
// Positions are byte offsets. Text is read scalar by scalar with `unicode.read_utf8`, a
// malformed sequence standing as U+FFFD over one byte, so `.` never splits a character.
// `\d \w \s \b` are ASCII, as they are in most engines; `case_insensitive` folds both
// sides with `unicode.to_lower_simple`. `multiline` makes `^` and `$` match at a `\n`;
// `dot_matches_newline` lets `.` take one.
//
// The match is the leftmost one, and among those the one a backtracker would find first
// (greedy repeats prefer more, lazy fewer, alternation prefers the left branch). A group
// that did not take part answers `NONE` for both bounds. `replace_all` expands `$0`..`$9`
// to the whole match and its groups and `$$` to a dollar; an empty match right after a
// previous match is skipped, so `x*` over "xa" gives "-a-", not "--a-".
//
// Everything the VM needs -- two thread lists, their capture rows, the visit marks and
// the closure stack -- is allocated by `compile`, so `is_match` and `find` allocate
// nothing; that scratch is mutated behind the `*const`, which is why one `Regex` must not
// be matched from two threads at once. `TooComplex` bounds the program at `MAX_INSTS`
// instructions, a repeat count at `MAX_REPEAT` and group nesting at `MAX_DEPTH`.

use e.mem
use e.text.utf8
use e.text.unicode

type Regex = struct { state: *void }
type Match = struct { start: usize, end: usize }
type Captures = struct { whole: Match, groups: []const Match }
type Options = struct { case_insensitive: bool, multiline: bool, dot_matches_newline: bool }
error InvalidPattern
error TooComplex

const NONE: usize = 18446744073709551615usize
const NO_NODE: u32 = 4294967295u32
const MAX_INSTS: usize = 16384usize
const MAX_REPEAT: u32 = 1000u32
const MAX_DEPTH: u32 = 64u32

type Op = enum u8 { Char, Any, Class, Split, Jmp, Save, Bol, Eol, WordB, NotWordB, Done }
// Char: x is the scalar (folded when case-insensitive). Class: x is the first range, y
// the range count doubled plus the negation bit. Split: x is preferred over y. Jmp: x.
// Save: x is the capture slot.
type Inst = struct { op: Op, x: u32, y: u32 }

type Kind = enum u8 { Empty, Char, Any, Class, Bol, Eol, WordB, NotWordB, Group, Concat, Alt, Repeat }
// Char: value is the scalar. Class: value is the first range, min the range count, max
// the negation. Group: value is the capture index or NO_NODE. Repeat: min..max with max
// NO_NODE for unbounded.
type Node = struct { kind: Kind, first: u32, second: u32, value: u32, min: u32, max: u32, lazy: bool }

type Parser = struct {
    pattern: str,
    at: usize,
    nodes: []Node,
    node_count: usize,
    ranges: []u32,
    range_count: usize,
    groups: u32,
    depth: u32,
    options: Options,
}

type Emitter = struct { insts: []Inst, count: usize, writing: bool }

// One thread list of the VM: a program counter per thread and a capture row per thread;
// `seen` marks the counters already in the list for this generation.
type Threads = struct { pcs: []u32, caps: []usize, seen: []u32, gen: u32, count: usize }

type Program = struct {
    insts: []Inst,
    ranges: []u32,
    groups: usize,
    slots: usize,
    options: Options,
    a: Threads,
    b: Threads,
    work: []usize,
    result: []usize,
    stack: []usize,
}

fn node(p: *Parser, kind: Kind, first: u32, second: u32, value: u32) -> (u32, err) {
    if p.node_count >= p.nodes.len { ret (NO_NODE, TooComplex) }
    let at = p.node_count
    p.nodes[at] = Node { kind: kind, first: first, second: second, value: value, min: 0u32, max: 0u32, lazy: false }
    p.node_count += 1usize
    ret (u32(at), ok)
}

fn add_range(p: *Parser, lo: u32, hi: u32) -> err {
    if p.range_count + 2usize > p.ranges.len { ret TooComplex }
    p.ranges[p.range_count] = lo
    p.ranges[p.range_count + 1usize] = hi
    p.range_count += 2usize
    ret ok
}

fn peek(p: Parser) -> u32 {
    if p.at >= p.pattern.len { ret NO_NODE }
    let (scalar, _) = unicode.read_utf8(p.pattern, p.at)
    ret scalar
}

fn advance(p: *Parser) -> u32 {
    let (scalar, width) = unicode.read_utf8(p.pattern, p.at)
    p.at += width
    ret scalar
}

// The ranges of `\d`, `\w`, `\s` (`positive`) or of their negations, appended.
fn add_shorthand(p: *Parser, letter: u32, positive: bool) -> err {
    if letter == 100u32 {
        if positive { ret add_range(p, 48u32, 57u32) }
        try add_range(p, 0u32, 47u32)
        ret add_range(p, 58u32, 1114111u32)
    }
    if letter == 119u32 {
        if positive {
            try add_range(p, 48u32, 57u32)
            try add_range(p, 65u32, 90u32)
            try add_range(p, 95u32, 95u32)
            ret add_range(p, 97u32, 122u32)
        }
        try add_range(p, 0u32, 47u32)
        try add_range(p, 58u32, 64u32)
        try add_range(p, 91u32, 94u32)
        try add_range(p, 96u32, 96u32)
        ret add_range(p, 123u32, 1114111u32)
    }
    if positive {
        try add_range(p, 9u32, 13u32)
        ret add_range(p, 32u32, 32u32)
    }
    try add_range(p, 0u32, 8u32)
    try add_range(p, 14u32, 31u32)
    ret add_range(p, 33u32, 1114111u32)
}

fn is_shorthand(scalar: u32) -> bool {
    ret scalar == 100u32 || scalar == 119u32 || scalar == 115u32 || scalar == 68u32 || scalar == 87u32 || scalar == 83u32
}

// The scalar an escape other than a shorthand or anchor stands for.
fn escape_scalar(scalar: u32) -> (u32, err) {
    if scalar == 110u32 { ret (10u32, ok) }
    if scalar == 116u32 { ret (9u32, ok) }
    if scalar == 114u32 { ret (13u32, ok) }
    let alnum = (scalar >= 48u32 && scalar <= 57u32) || (scalar >= 65u32 && scalar <= 90u32) || (scalar >= 97u32 && scalar <= 122u32)
    if alnum || scalar >= 128u32 { ret (0u32, InvalidPattern) }
    ret (scalar, ok)
}

// A class node over the ranges appended since `start`.
fn class_node(p: *Parser, start: usize, negated: bool) -> (u32, err) {
    let (at, at_error) = node(p, .Class, NO_NODE, NO_NODE, u32(start))
    if at_error != ok { ret (NO_NODE, at_error) }
    p.nodes[usize(at)].min = u32((p.range_count - start) / 2usize)
    if negated { p.nodes[usize(at)].max = 1u32 }
    ret (at, ok)
}

// After the `[`: an optional `^`, then items to the closing `]`, a `]` first being literal.
fn parse_class(p: *Parser) -> (u32, err) {
    var negated = false
    if peek(*p) == 94u32 {
        negated = true
        p.at += 1usize
    }
    let start = p.range_count
    var first = true
    while true {
        if p.at >= p.pattern.len { ret (NO_NODE, InvalidPattern) }
        var lo = advance(p)
        if lo == 93u32 && !first { break }
        first = false
        if lo == 92u32 {
            if p.at >= p.pattern.len { ret (NO_NODE, InvalidPattern) }
            let escaped = advance(p)
            if is_shorthand(escaped) {
                let positive = escaped >= 97u32
                var letter = escaped
                if !positive { letter = escaped + 32u32 }
                let step_error = add_shorthand(p, letter, positive)
                if step_error != ok { ret (zero, step_error) }
                continue
            }
            let (scalar, scalar_error) = escape_scalar(escaped)
            if scalar_error != ok { ret (NO_NODE, scalar_error) }
            lo = scalar
        }
        var hi = lo
        if peek(*p) == 45u32 && p.at + 1usize < p.pattern.len && p.pattern[p.at + 1usize] != 93u8 {
            p.at += 1usize
            hi = advance(p)
            if hi == 92u32 {
                if p.at >= p.pattern.len { ret (NO_NODE, InvalidPattern) }
                let (scalar, scalar_error) = escape_scalar(advance(p))
                if scalar_error != ok { ret (NO_NODE, scalar_error) }
                hi = scalar
            }
            if hi < lo { ret (NO_NODE, InvalidPattern) }
        }
        let step_error = add_range(p, lo, hi)
        if step_error != ok { ret (zero, step_error) }
    }
    let (made, made_error) = class_node(p, start, negated)
    ret (made, made_error)
}

fn parse_escape(p: *Parser) -> (u32, err) {
    if p.at >= p.pattern.len { ret (NO_NODE, InvalidPattern) }
    let escaped = advance(p)
    if escaped == 98u32 {
        let (made, made_error) = node(p, .WordB, NO_NODE, NO_NODE, 0u32)
        ret (made, made_error)
    }
    if escaped == 66u32 {
        let (made, made_error) = node(p, .NotWordB, NO_NODE, NO_NODE, 0u32)
        ret (made, made_error)
    }
    if is_shorthand(escaped) {
        let positive = escaped >= 97u32
        var letter = escaped
        if !positive { letter = escaped + 32u32 }
        let start = p.range_count
        let step_error = add_shorthand(p, letter, true)
        if step_error != ok { ret (zero, step_error) }
        let (made, made_error) = class_node(p, start, !positive)
        ret (made, made_error)
    }
    let (scalar, scalar_error) = escape_scalar(escaped)
    if scalar_error != ok { ret (NO_NODE, scalar_error) }
    let (made, made_error) = node(p, .Char, NO_NODE, NO_NODE, scalar)
    ret (made, made_error)
}

fn parse_atom(p: *Parser) -> (u32, err) {
    let scalar = advance(p)
    if scalar == 40u32 {
        var capture = NO_NODE
        if peek(*p) == 63u32 {
            p.at += 1usize
            if peek(*p) != 58u32 { ret (NO_NODE, InvalidPattern) }
            p.at += 1usize
        } else {
            p.groups += 1u32
            capture = p.groups
        }
        if p.depth >= MAX_DEPTH { ret (NO_NODE, TooComplex) }
        p.depth += 1u32
        let (inner, inner_error) = parse_alt(p)
        if inner_error != ok { ret (NO_NODE, inner_error) }
        p.depth -= 1u32
        if peek(*p) != 41u32 { ret (NO_NODE, InvalidPattern) }
        p.at += 1usize
        let (made, made_error) = node(p, .Group, inner, NO_NODE, capture)
        ret (made, made_error)
    }
    if scalar == 91u32 {
        let (class_at, class_error) = parse_class(p)
        ret (class_at, class_error)
    }
    if scalar == 92u32 {
        let (escape_at, escape_error) = parse_escape(p)
        ret (escape_at, escape_error)
    }
    if scalar == 46u32 {
        let (made, made_error) = node(p, .Any, NO_NODE, NO_NODE, 0u32)
        ret (made, made_error)
    }
    if scalar == 94u32 {
        let (made, made_error) = node(p, .Bol, NO_NODE, NO_NODE, 0u32)
        ret (made, made_error)
    }
    if scalar == 36u32 {
        let (made, made_error) = node(p, .Eol, NO_NODE, NO_NODE, 0u32)
        ret (made, made_error)
    }
    if scalar == 41u32 || scalar == 42u32 || scalar == 43u32 || scalar == 63u32 || scalar == 123u32 || scalar == 124u32 { ret (NO_NODE, InvalidPattern) }
    var value = scalar
    if p.options.case_insensitive { value = unicode.to_lower_simple(scalar) }
    let (made, made_error) = node(p, .Char, NO_NODE, NO_NODE, value)
    ret (made, made_error)
}

fn parse_number(p: *Parser) -> (u32, bool) {
    var value = 0u32
    var any = false
    while peek(*p) >= 48u32 && peek(*p) <= 57u32 {
        value = value * 10u32 + (advance(p) - 48u32)
        if value > MAX_REPEAT { value = MAX_REPEAT + 1u32 }
        any = true
    }
    ret (value, any)
}

// `{m}`, `{m,}` or `{m,n}` after the brace; answers min and max, NO_NODE for unbounded.
fn parse_brace(p: *Parser) -> (u32, u32, err) {
    let (min, has_min) = parse_number(p)
    if !has_min { ret (0u32, 0u32, InvalidPattern) }
    var max = min
    if peek(*p) == 44u32 {
        p.at += 1usize
        let (bound, has_bound) = parse_number(p)
        max = NO_NODE
        if has_bound { max = bound }
    }
    if peek(*p) != 125u32 { ret (0u32, 0u32, InvalidPattern) }
    p.at += 1usize
    if min > MAX_REPEAT || (max != NO_NODE && max > MAX_REPEAT) { ret (0u32, 0u32, TooComplex) }
    if max != NO_NODE && max < min { ret (0u32, 0u32, InvalidPattern) }
    ret (min, max, ok)
}

fn parse_repeat(p: *Parser) -> (u32, err) {
    let (first_atom, atom_error) = parse_atom(p)
    if atom_error != ok { ret (NO_NODE, atom_error) }
    var atom = first_atom
    while true {
        let suffix = peek(*p)
        var min = 0u32
        var max = 0u32
        if suffix == 42u32 {
            max = NO_NODE
            p.at += 1usize
        } else if suffix == 43u32 {
            min = 1u32
            max = NO_NODE
            p.at += 1usize
        } else if suffix == 63u32 {
            max = 1u32
            p.at += 1usize
        } else if suffix == 123u32 {
            p.at += 1usize
            let (lo, hi, brace_error) = parse_brace(p)
            if brace_error != ok { ret (NO_NODE, brace_error) }
            min = lo
            max = hi
        } else {
            break
        }
        var lazy = false
        if peek(*p) == 63u32 {
            lazy = true
            p.at += 1usize
        }
        let (wrapped, wrapped_error) = node(p, .Repeat, atom, NO_NODE, 0u32)
        if wrapped_error != ok { ret (NO_NODE, wrapped_error) }
        p.nodes[usize(wrapped)].min = min
        p.nodes[usize(wrapped)].max = max
        p.nodes[usize(wrapped)].lazy = lazy
        atom = wrapped
    }
    ret (atom, ok)
}

fn parse_concat(p: *Parser) -> (u32, err) {
    let (empty, head_error) = node(p, .Empty, NO_NODE, NO_NODE, 0u32)
    if head_error != ok { ret (NO_NODE, head_error) }
    var head = empty
    while p.at < p.pattern.len && peek(*p) != 124u32 && peek(*p) != 41u32 {
        let (item, item_error) = parse_repeat(p)
        if item_error != ok { ret (NO_NODE, item_error) }
        let (joined, joined_error) = node(p, .Concat, head, item, 0u32)
        if joined_error != ok { ret (NO_NODE, joined_error) }
        head = joined
    }
    ret (head, ok)
}

fn parse_alt(p: *Parser) -> (u32, err) {
    let (first_branch, left_error) = parse_concat(p)
    if left_error != ok { ret (NO_NODE, left_error) }
    var left = first_branch
    while peek(*p) == 124u32 {
        p.at += 1usize
        let (right, right_error) = parse_concat(p)
        if right_error != ok { ret (NO_NODE, right_error) }
        let (either, either_error) = node(p, .Alt, left, right, 0u32)
        if either_error != ok { ret (NO_NODE, either_error) }
        left = either
    }
    ret (left, ok)
}

fn emit(e: *Emitter, op: Op, x: u32, y: u32) -> (u32, err) {
    if e.count >= MAX_INSTS { ret (0u32, TooComplex) }
    if e.writing { e.insts[e.count] = Inst { op: op, x: x, y: y } }
    e.count += 1usize
    ret (u32(e.count - 1usize), ok)
}

fn patch(e: *Emitter, at: u32, second: bool, to: u32) {
    if !e.writing { ret }
    if second {
        e.insts[usize(at)].y = to
    } else {
        e.insts[usize(at)].x = to
    }
}

// `remaining` optional copies of `child`, each guarded by a split to the common end.
fn gen_optional(e: *Emitter, p: *Parser, child: u32, remaining: u32, lazy: bool) -> err {
    if remaining == 0u32 { ret ok }
    let (split, split_error) = emit(e, .Split, 0u32, 0u32)
    if split_error != ok { ret split_error }
    patch(e, split, lazy, u32(e.count))
    try gen_node(e, p, child)
    try gen_optional(e, p, child, remaining - 1u32, lazy)
    patch(e, split, !lazy, u32(e.count))
    ret ok
}

fn gen_repeat(e: *Emitter, p: *Parser, at: u32) -> err {
    let n = p.nodes[usize(at)]
    var copies = 0u32
    while copies < n.min {
        try gen_node(e, p, n.first)
        copies += 1u32
    }
    if n.max != NO_NODE { ret gen_optional(e, p, n.first, n.max - n.min, n.lazy) }
    let (split, split_error) = emit(e, .Split, 0u32, 0u32)
    if split_error != ok { ret split_error }
    patch(e, split, n.lazy, u32(e.count))
    try gen_node(e, p, n.first)
    let (_, jump_error) = emit(e, .Jmp, split, 0u32)
    if jump_error != ok { ret jump_error }
    patch(e, split, !n.lazy, u32(e.count))
    ret ok
}

fn gen_node(e: *Emitter, p: *Parser, at: u32) -> err {
    let n = p.nodes[usize(at)]
    if n.kind == .Empty { ret ok }
    if n.kind == .Char {
        let (_, char_error) = emit(e, .Char, n.value, 0u32)
        ret char_error
    }
    if n.kind == .Any {
        let (_, any_error) = emit(e, .Any, 0u32, 0u32)
        ret any_error
    }
    if n.kind == .Class {
        let (_, class_error) = emit(e, .Class, n.value, n.min * 2u32 + n.max)
        ret class_error
    }
    if n.kind == .Bol || n.kind == .Eol || n.kind == .WordB || n.kind == .NotWordB {
        var op: Op = .Bol
        if n.kind == .Eol { op = .Eol }
        if n.kind == .WordB { op = .WordB }
        if n.kind == .NotWordB { op = .NotWordB }
        let (_, assert_error) = emit(e, op, 0u32, 0u32)
        ret assert_error
    }
    if n.kind == .Group {
        if n.value == NO_NODE { ret gen_node(e, p, n.first) }
        let (_, open_error) = emit(e, .Save, n.value * 2u32, 0u32)
        if open_error != ok { ret open_error }
        try gen_node(e, p, n.first)
        let (_, close_error) = emit(e, .Save, n.value * 2u32 + 1u32, 0u32)
        ret close_error
    }
    if n.kind == .Concat {
        try gen_node(e, p, n.first)
        ret gen_node(e, p, n.second)
    }
    if n.kind == .Alt {
        let (split, split_error) = emit(e, .Split, 0u32, 0u32)
        if split_error != ok { ret split_error }
        patch(e, split, false, u32(e.count))
        try gen_node(e, p, n.first)
        let (jump, jump_error) = emit(e, .Jmp, 0u32, 0u32)
        if jump_error != ok { ret jump_error }
        patch(e, split, true, u32(e.count))
        try gen_node(e, p, n.second)
        patch(e, jump, false, u32(e.count))
        ret ok
    }
    ret gen_repeat(e, p, at)
}

// The whole program: `Save 0`, the pattern, `Save 1`, `Done`.
fn gen_program(e: *Emitter, p: *Parser, root: u32) -> err {
    let (_, open_error) = emit(e, .Save, 0u32, 0u32)
    if open_error != ok { ret open_error }
    try gen_node(e, p, root)
    let (_, close_error) = emit(e, .Save, 1u32, 0u32)
    if close_error != ok { ret close_error }
    let (_, done_error) = emit(e, .Done, 0u32, 0u32)
    ret done_error
}

fn threads(a: *mem.Arena, insts: usize, slots: usize) -> (Threads, err) {
    let (pcs, pcs_error) = mem.alloc[u32](a, insts)
    if pcs_error != ok { ret (zero, pcs_error) }
    let (caps, caps_error) = mem.alloc[usize](a, insts * slots)
    if caps_error != ok { ret (zero, caps_error) }
    let (seen, seen_error) = mem.alloc[u32](a, insts)
    if seen_error != ok { ret (zero, seen_error) }
    var at = 0usize
    while at < insts {
        seen[at] = 0u32
        at += 1usize
    }
    ret (Threads { pcs: pcs, caps: caps, seen: seen, gen: 0u32, count: 0usize }, ok)
}

fn compile(a: *mem.Arena, pattern: str, options: Options) -> (Regex, err) {
    if !utf8.validate(pattern) { ret (zero, InvalidPattern) }
    let checkpoint = a.off
    let (nodes, nodes_error) = mem.alloc[Node](a, pattern.len * 2usize + 2usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (ranges, ranges_error) = mem.alloc[u32](a, pattern.len * 5usize + 8usize)
    if ranges_error != ok { ret (zero, ranges_error) }
    var p = Parser { pattern: pattern, at: 0usize, nodes: nodes, node_count: 0usize, ranges: ranges, range_count: 0usize, groups: 0u32, depth: 0u32, options: options }
    let (root, root_error) = parse_alt(&p)
    if root_error != ok {
        a.off = checkpoint
        ret (zero, root_error)
    }
    if p.at < pattern.len {
        a.off = checkpoint
        ret (zero, InvalidPattern)
    }
    var measure: Emitter = zero
    let measure_error = gen_program(&measure, &p, root)
    if measure_error != ok {
        a.off = checkpoint
        ret (zero, measure_error)
    }
    let (insts, insts_error) = mem.alloc[Inst](a, measure.count)
    if insts_error != ok { ret (zero, insts_error) }
    var writer = Emitter { insts: insts, count: 0usize, writing: true }
    let step_error = gen_program(&writer, &p, root)
    if step_error != ok { ret (zero, step_error) }
    let slots = (usize(p.groups) + 1usize) * 2usize
    let (program, program_error) = mem.alloc[Program](a, 1usize)
    if program_error != ok { ret (zero, program_error) }
    let (first, first_error) = threads(a, measure.count, slots)
    if first_error != ok { ret (zero, first_error) }
    let (second, second_error) = threads(a, measure.count, slots)
    if second_error != ok { ret (zero, second_error) }
    let (work, work_error) = mem.alloc[usize](a, slots)
    if work_error != ok { ret (zero, work_error) }
    let (result, result_error) = mem.alloc[usize](a, slots)
    if result_error != ok { ret (zero, result_error) }
    let (stack, stack_error) = mem.alloc[usize](a, (measure.count * 2usize + 2usize) * 3usize)
    if stack_error != ok { ret (zero, stack_error) }
    program[0usize] = Program { insts: insts, ranges: ranges[..p.range_count], groups: usize(p.groups), slots: slots, options: options, a: first, b: second, work: work, result: result, stack: stack }
    ret (Regex { state: mem.cast[*void](&program[0usize]) }, ok)
}

fn is_word_byte(text: str, at: usize) -> bool {
    if at >= text.len { ret false }
    let b = text[at]
    ret (b >= 48u8 && b <= 57u8) || (b >= 65u8 && b <= 90u8) || b == 95u8 || (b >= 97u8 && b <= 122u8)
}

fn holds(prog: *Program, op: Op, text: str, pos: usize) -> bool {
    if op == .Bol { ret pos == 0usize || (prog.options.multiline && text[pos - 1usize] == 10u8) }
    if op == .Eol { ret pos == text.len || (prog.options.multiline && text[pos] == 10u8) }
    var boundary = false
    if pos == 0usize {
        boundary = is_word_byte(text, 0usize)
    } else {
        boundary = is_word_byte(text, pos - 1usize) != is_word_byte(text, pos)
    }
    if op == .WordB { ret boundary }
    ret !boundary
}

fn in_ranges(prog: *Program, first: u32, count: u32, scalar: u32) -> bool {
    var i = 0u32
    while i < count {
        let at = usize(first + i * 2u32)
        if scalar >= prog.ranges[at] && scalar <= prog.ranges[at + 1usize] { ret true }
        i += 1u32
    }
    ret false
}

fn consumes(prog: *Program, inst: Inst, scalar: u32) -> bool {
    if inst.op == .Char {
        if scalar == inst.x { ret true }
        ret prog.options.case_insensitive && unicode.to_lower_simple(scalar) == inst.x
    }
    if inst.op == .Any { ret scalar != 10u32 || prog.options.dot_matches_newline }
    if inst.op != .Class { ret false }
    let count = inst.y >> 1u32
    var inside = in_ranges(prog, inst.x, count, scalar)
    if !inside && prog.options.case_insensitive {
        inside = in_ranges(prog, inst.x, count, unicode.to_lower_simple(scalar)) || in_ranges(prog, inst.x, count, unicode.to_upper_simple(scalar))
    }
    if (inst.y & 1u32) != 0u32 { ret !inside }
    ret inside
}

fn clear(t: *Threads) {
    t.count = 0usize
    // Wraps after 2**32 runs, when a stale mark could equal a fresh generation once.
    t.gen = t.gen +% 1u32
}

// Follows every empty edge from `pc` at `pos`, appending each consuming or final
// instruction reached to `t` once, in priority order, with the captures `prog.work`
// carries at that point; a `Save` sets a slot for its subtree and restores it after.
fn add_thread(prog: *Program, t: *Threads, pc: u32, pos: usize, text: str) {
    let slots = prog.slots
    var sp = 0usize
    prog.stack[0] = usize(pc)
    prog.stack[1] = NONE
    prog.stack[2] = 0usize
    sp = 3usize
    while sp > 0usize {
        sp -= 3usize
        let here = u32(prog.stack[sp])
        let slot = prog.stack[sp + 1usize]
        if slot != NONE {
            prog.work[slot] = prog.stack[sp + 2usize]
            continue
        }
        if t.seen[usize(here)] == t.gen { continue }
        t.seen[usize(here)] = t.gen
        let inst = prog.insts[usize(here)]
        if inst.op == .Jmp {
            prog.stack[sp] = usize(inst.x)
            prog.stack[sp + 1usize] = NONE
            sp += 3usize
        } else if inst.op == .Split {
            prog.stack[sp] = usize(inst.y)
            prog.stack[sp + 1usize] = NONE
            prog.stack[sp + 3usize] = usize(inst.x)
            prog.stack[sp + 4usize] = NONE
            sp += 6usize
        } else if inst.op == .Save {
            prog.stack[sp] = 0usize
            prog.stack[sp + 1usize] = usize(inst.x)
            prog.stack[sp + 2usize] = prog.work[usize(inst.x)]
            prog.stack[sp + 3usize] = usize(here + 1u32)
            prog.stack[sp + 4usize] = NONE
            sp += 6usize
            prog.work[usize(inst.x)] = pos
        } else if inst.op == .Bol || inst.op == .Eol || inst.op == .WordB || inst.op == .NotWordB {
            if holds(prog, inst.op, text, pos) {
                prog.stack[sp] = usize(here + 1u32)
                prog.stack[sp + 1usize] = NONE
                sp += 3usize
            }
        } else {
            t.pcs[t.count] = here
            mem.copy[usize](t.caps[t.count * slots..(t.count + 1usize) * slots], prog.work)
            t.count += 1usize
        }
    }
}

// The Pike VM over `text` from `from`: the leftmost match, in `prog.result` when it
// answers true. `first` stops at the first `Done` reached, enough for `is_match`.
fn run(prog: *Program, text: str, from: usize, first: bool) -> bool {
    let slots = prog.slots
    var cur = &prog.a
    var nxt = &prog.b
    clear(cur)
    clear(nxt)
    var matched = false
    var pos = from
    while true {
        if !matched {
            var s = 0usize
            while s < slots {
                prog.work[s] = NONE
                s += 1usize
            }
            add_thread(prog, cur, 0u32, pos, text)
        }
        if cur.count == 0usize && matched { break }
        var scalar = 0u32
        var width = 0usize
        if pos < text.len {
            let (read, read_width) = unicode.read_utf8(text, pos)
            scalar = read
            width = read_width
        }
        clear(nxt)
        var i = 0usize
        while i < cur.count {
            let pc = cur.pcs[i]
            let inst = prog.insts[usize(pc)]
            if inst.op == .Done {
                mem.copy[usize](prog.result, cur.caps[i * slots..(i + 1usize) * slots])
                matched = true
                if first { ret true }
                break
            }
            if pos < text.len && consumes(prog, inst, scalar) {
                mem.copy[usize](prog.work, cur.caps[i * slots..(i + 1usize) * slots])
                add_thread(prog, nxt, pc + 1u32, pos + width, text)
            }
            i += 1usize
        }
        let swap = cur
        cur = nxt
        nxt = swap
        if pos >= text.len { break }
        pos += width
    }
    ret matched
}

fn is_match(r: *const Regex, text: str) -> bool {
    let prog = mem.cast[*Program](r.state)
    ret run(prog, text, 0usize, true)
}

fn find(r: *const Regex, text: str, from: usize) -> (Match, bool) {
    if from > text.len { ret (zero, false) }
    let prog = mem.cast[*Program](r.state)
    if !run(prog, text, from, false) { ret (zero, false) }
    ret (Match { start: prog.result[0], end: prog.result[1] }, true)
}

fn captures(a: *mem.Arena, r: *const Regex, text: str, from: usize) -> (Captures, bool, err) {
    let (whole, found) = find(r, text, from)
    if !found { ret (zero, false, ok) }
    let prog = mem.cast[*Program](r.state)
    let (groups, groups_error) = mem.alloc[Match](a, prog.groups)
    if groups_error != ok { ret (zero, false, groups_error) }
    var g = 0usize
    while g < prog.groups {
        groups[g] = Match { start: prog.result[(g + 1usize) * 2usize], end: prog.result[(g + 1usize) * 2usize + 1usize] }
        g += 1usize
    }
    ret (Captures { whole: whole, groups: groups }, true, ok)
}

// Appends `replacement` with `$0`..`$9` and `$$` expanded from the last match in
// `prog.result`; writes only when `writing`, and answers the new length either way.
fn expand(prog: *Program, out: []u8, at: usize, writing: bool, replacement: str, text: str) -> usize {
    var used = at
    var i = 0usize
    while i < replacement.len {
        let b = replacement[i]
        if b == 36u8 && i + 1usize < replacement.len {
            let next = replacement[i + 1usize]
            if next == 36u8 {
                if writing { out[used] = 36u8 }
                used += 1usize
                i += 2usize
                continue
            }
            if next >= 48u8 && next <= 57u8 {
                let group = usize(next - 48u8)
                if group <= prog.groups {
                    let start = prog.result[group * 2usize]
                    let end = prog.result[group * 2usize + 1usize]
                    if start != NONE && end != NONE {
                        if writing { mem.copy[u8](out[used..used + (end - start)], text[start..end]) }
                        used += end - start
                    }
                }
                i += 2usize
                continue
            }
        }
        if writing { out[used] = b }
        used += 1usize
        i += 1usize
    }
    ret used
}

// One pass over the matches: the output length when `out` is empty, the output itself
// otherwise.
fn substitute(prog: *Program, out: []u8, writing: bool, text: str, replacement: str) -> usize {
    var used = 0usize
    var pos = 0usize
    var last_end = NONE
    while pos <= text.len {
        if !run(prog, text, pos, false) { break }
        let start = prog.result[0]
        let end = prog.result[1]
        if start == end && start == last_end {
            if start >= text.len { break }
            let (_, width) = unicode.read_utf8(text, start)
            if writing { mem.copy[u8](out[used..used + (start + width - pos)], text[pos..start + width]) }
            used += start + width - pos
            pos = start + width
            continue
        }
        if writing { mem.copy[u8](out[used..used + (start - pos)], text[pos..start]) }
        used += start - pos
        used = expand(prog, out, used, writing, replacement, text)
        last_end = end
        if start == end {
            if start >= text.len {
                pos = start
                break
            }
            let (_, width) = unicode.read_utf8(text, start)
            if writing { mem.copy[u8](out[used..used + width], text[start..start + width]) }
            used += width
            pos = start + width
        } else {
            pos = end
        }
    }
    if pos < text.len {
        if writing { mem.copy[u8](out[used..used + (text.len - pos)], text[pos..]) }
        used += text.len - pos
    }
    ret used
}

fn replace_all(a: *mem.Arena, r: *const Regex, text: str, replacement: str) -> (str, err) {
    let prog = mem.cast[*Program](r.state)
    var none: []u8 = zero
    let needed = substitute(prog, none, false, text, replacement)
    let (out, out_error) = mem.alloc[u8](a, needed)
    if out_error != ok { ret ("", out_error) }
    let written = substitute(prog, out, true, text, replacement)
    ret (out[..written], ok)
}
