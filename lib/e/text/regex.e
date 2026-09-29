// Regular expressions over UTF-8, with two engines behind one `Regex`. A pattern
// compiles once into an arena. `compile` builds a Pike VM, so a match costs time linear
// in the text times the program, never the exponential blow-up a backtracker pays. Its
// syntax is regular only: literals, `.`, classes `[a-z]` `[^...]` with `\d \w \s` and
// their negations, the anchors `^` `$` `\b` `\B`, the repeats `* + ? {m} {m,} {m,n}`
// each with a lazy `?`, alternation `|`, capturing `(...)`, named `(?<name>...)` or
// `(?P<name>...)` and non-capturing `(?:...)` groups, and the escapes `\n \t \r` and
// `\<punctuation>`. A construct only a backtracker can run is refused with
// `NeedsBacktracking` rather than `InvalidPattern`, so the caller knows to switch.
//
// `compile_backtracking` accepts all of that plus backreferences `\1`..`\9`, `\k<name>`
// and `(?P=name)`; lookahead `(?=...)` `(?!...)`; lookbehind `(?<=...)` `(?<!...)` over
// a fixed number of scalars (alternatives of equal width, as Python requires); atomic
// groups `(?>...)`; and possessive repeats `*+ ++ ?+ {m,n}+`. It runs a backtracking VM
// over the same instructions and answers what Python's `re` answers. A backreference to
// a group that took no part fails; `case_insensitive` folds its comparison too. A repeat
// whose body matched empty stops repeating, as in Python. The work is bounded: a search
// may take `MIN_STEPS` plus `STEPS_PER_BYTE` per byte searched, past which it stops with
// `TooManySteps`, and holds at most `MAX_TRACK` backtrack entries, past which it stops
// with `TooDeep`; `is_match` and `find` then answer no match and `last_error` names the
// cause, while `captures` and `replace_all` return it. The `is_match`, `find`,
// `captures` and `replace_all` below serve both engines.
// ponytail: no recursion `(?R)`, conditionals `(?(1)...)` or inline flags `(?i)`; they
// would be new instructions over the same backtrack stack.
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
// the closure stack, or for the backtracker its stack and one capture row -- is
// allocated by the compile, so `is_match` and `find` allocate nothing; that scratch is
// mutated behind the `*const`, which is why one `Regex` must not be matched from two
// threads at once. `TooComplex` bounds the program at `MAX_INSTS` instructions, a
// repeat count at `MAX_REPEAT` and group nesting at `MAX_DEPTH`.

use e.mem
use e.text.utf8
use e.text.unicode

type Regex = struct { state: *void }
type Match = struct { start: usize, end: usize }
type Captures = struct { whole: Match, groups: []const Match }
type Options = struct { case_insensitive: bool, multiline: bool, dot_matches_newline: bool }
error InvalidPattern
error TooComplex
error NeedsBacktracking
error TooManySteps
error TooDeep

const NONE: usize = 18446744073709551615usize
const NO_NODE: u32 = 4294967295u32
const MAX_INSTS: usize = 16384usize
const MAX_REPEAT: u32 = 1000u32
const MAX_DEPTH: u32 = 64u32
// ponytail: a fixed backtrack stack (768 KB per compiled pattern) caps a greedy `.*` at
// about 16K scalars; a caller-sized stack is the upgrade when subjects grow past that.
const MAX_TRACK: usize = 32768usize
const MIN_STEPS: usize = 1000000usize
const STEPS_PER_BYTE: usize = 1000usize
const MAX_WIDTH: usize = 1048576usize

type Op = enum u8 { Char, Any, Class, Split, Jmp, Save, Bol, Eol, WordB, NotWordB, Done, Backref, Look, LookEnd, Atomic, AtomicEnd, RepStart, RepCheck }
// Char: x is the scalar (folded when case-insensitive). Class: x is the first range, y
// the range count doubled plus the negation bit. Split: x is preferred over y. Jmp: x.
// Save: x is the capture slot. The rest are the backtracker's. Backref: x is the group.
// Look: x is the instruction after its LookEnd, y bit 0 negative, bit 1 behind and the
// width in scalars above them; LookEnd: y the same bits. RepStart: x is the slot that
// keeps where an iteration began; RepCheck: loops to y unless the iteration was empty.
type Inst = struct { op: Op, x: u32, y: u32 }

type Kind = enum u8 { Empty, Char, Any, Class, Bol, Eol, WordB, NotWordB, Group, Concat, Alt, Repeat, Backref, Look, Atomic }
// Char: value is the scalar. Class: value is the first range, min the range count, max
// the negation. Group: value is the capture index or NO_NODE. Repeat: min..max with max
// NO_NODE for unbounded. Backref: value is the group. Look: value is the Look bits, min
// the width. Atomic: first is the body.
type Node = struct { kind: Kind, first: u32, second: u32, value: u32, min: u32, max: u32, lazy: bool }

// `names` holds a (start, length) pair into the pattern per group, length 0 if unnamed.
type Parser = struct { pattern: str, at: usize, nodes: []Node, node_count: usize, ranges: []u32, range_count: usize, groups: u32, depth: u32, options: Options, backtracking: bool, names: []u32 }

// `loops` counts the unbounded repeats given an iteration slot, from `loop_base` on.
type Emitter = struct { insts: []Inst, count: usize, writing: bool, backtracking: bool, loop_base: u32, loops: u32 }

// One thread list of the VM: a program counter per thread and a capture row per thread;
// `seen` marks the counters already in the list for this generation.
type Threads = struct { pcs: []u32, caps: []usize, seen: []u32, gen: u32, count: usize }

// `work` is the backtracker's one capture row, iteration slots after the group slots;
// `track` its stack of (kind, x, y) entries, `depth` deep.
type Program = struct { insts: []Inst, ranges: []u32, groups: usize, slots: usize, options: Options, a: Threads, b: Threads, work: []usize, result: []usize, stack: []usize, backtracking: bool, source: str, names: []const u32, track: []usize, depth: usize, steps: usize, failure: err }

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

// A group name `[A-Za-z_][A-Za-z0-9_]*` followed by `close`, consumed; answers where
// the name starts and its length.
fn parse_name(p: *Parser, close: u32) -> (u32, u32, err) {
    let start = p.at
    while p.at < p.pattern.len && (is_word_byte(p.pattern, p.at)) { p.at += 1usize }
    let length = p.at - start
    if length == 0usize || (p.pattern[start] >= 48u8 && p.pattern[start] <= 57u8) { ret (0u32, 0u32, InvalidPattern) }
    if peek(*p) != close { ret (0u32, 0u32, InvalidPattern) }
    p.at += 1usize
    ret (u32(start), u32(length), ok)
}

// The group named by the pattern bytes at `start`, or NO_NODE.
fn find_name(p: *Parser, start: u32, length: u32) -> u32 {
    let wanted = p.pattern[usize(start)..usize(start + length)]
    var g = 0u32
    while g < p.groups {
        let at = usize(p.names[usize(g) * 2usize])
        let size = p.names[usize(g) * 2usize + 1usize]
        if size == length && mem.eq[u8](p.pattern[at..at + usize(size)], wanted) { ret g + 1u32 }
        g += 1u32
    }
    ret NO_NODE
}

// A new capturing group, named by `length` pattern bytes at `start` unless 0.
fn open_group(p: *Parser, start: u32, length: u32) -> (u32, err) {
    if length > 0u32 && find_name(p, start, length) != NO_NODE { ret (NO_NODE, InvalidPattern) }
    p.names[usize(p.groups) * 2usize] = start
    p.names[usize(p.groups) * 2usize + 1usize] = length
    p.groups += 1u32
    ret (p.groups, ok)
}

fn named_backref(p: *Parser, start: u32, length: u32) -> (u32, err) {
    let group = find_name(p, start, length)
    if group == NO_NODE { ret (NO_NODE, InvalidPattern) }
    let (made, made_error) = node(p, .Backref, NO_NODE, NO_NODE, group)
    ret (made, made_error)
}

// The scalars every match of the subtree spans, and whether that is one fixed number.
fn fixed_width(p: *Parser, at: u32) -> (usize, bool) {
    let n = p.nodes[usize(at)]
    if n.kind == .Char || n.kind == .Any || n.kind == .Class { ret (1usize, true) }
    if n.kind == .Backref { ret (0usize, false) }
    if n.kind == .Group || n.kind == .Atomic {
        let (inner, inner_fixed) = fixed_width(p, n.first)
        ret (inner, inner_fixed)
    }
    if n.kind == .Concat || n.kind == .Alt {
        let (left, left_fixed) = fixed_width(p, n.first)
        let (right, right_fixed) = fixed_width(p, n.second)
        if !left_fixed || !right_fixed { ret (0usize, false) }
        if n.kind == .Alt {
            if left != right { ret (0usize, false) }
            ret (left, true)
        }
        if left + right > MAX_WIDTH { ret (0usize, false) }
        ret (left + right, true)
    }
    if n.kind == .Repeat {
        if n.max != n.min { ret (0usize, false) }
        let (inner, inner_fixed) = fixed_width(p, n.first)
        if !inner_fixed || inner * usize(n.min) > MAX_WIDTH { ret (0usize, false) }
        ret (inner * usize(n.min), true)
    }
    ret (0usize, true)
}

fn parse_escape(p: *Parser) -> (u32, err) {
    if p.at >= p.pattern.len { ret (NO_NODE, InvalidPattern) }
    let escaped = advance(p)
    if escaped >= 49u32 && escaped <= 57u32 {
        if !p.backtracking { ret (NO_NODE, NeedsBacktracking) }
        if escaped - 48u32 > p.groups { ret (NO_NODE, InvalidPattern) }
        let (made, made_error) = node(p, .Backref, NO_NODE, NO_NODE, escaped - 48u32)
        ret (made, made_error)
    }
    if escaped == 107u32 {
        if !p.backtracking { ret (NO_NODE, NeedsBacktracking) }
        if peek(*p) != 60u32 { ret (NO_NODE, InvalidPattern) }
        p.at += 1usize
        let (start, length, name_error) = parse_name(p, 62u32)
        if name_error != ok { ret (NO_NODE, name_error) }
        let (made, made_error) = named_backref(p, start, length)
        ret (made, made_error)
    }
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
        var look = NO_NODE
        var atomic = false
        if peek(*p) == 63u32 {
            p.at += 1usize
            if p.at >= p.pattern.len { ret (NO_NODE, InvalidPattern) }
            let sort = advance(p)
            if sort == 58u32 {
                capture = NO_NODE
            } else if sort == 61u32 || sort == 33u32 {
                look = 0u32
                if sort == 33u32 { look = 1u32 }
            } else if sort == 62u32 {
                atomic = true
            } else if sort == 60u32 && (peek(*p) == 61u32 || peek(*p) == 33u32) {
                look = 2u32
                if advance(p) == 33u32 { look = 3u32 }
            } else if sort == 60u32 || (sort == 80u32 && peek(*p) == 60u32) {
                if sort == 80u32 { p.at += 1usize }
                let (start, length, name_error) = parse_name(p, 62u32)
                if name_error != ok { ret (NO_NODE, name_error) }
                let (group, group_error) = open_group(p, start, length)
                if group_error != ok { ret (NO_NODE, group_error) }
                capture = group
            } else if sort == 80u32 && peek(*p) == 61u32 {
                p.at += 1usize
                if !p.backtracking { ret (NO_NODE, NeedsBacktracking) }
                let (start, length, name_error) = parse_name(p, 41u32)
                if name_error != ok { ret (NO_NODE, name_error) }
                let (made, made_error) = named_backref(p, start, length)
                ret (made, made_error)
            } else {
                ret (NO_NODE, InvalidPattern)
            }
            if (look != NO_NODE || atomic) && !p.backtracking { ret (NO_NODE, NeedsBacktracking) }
        } else {
            let (group, group_error) = open_group(p, 0u32, 0u32)
            if group_error != ok { ret (NO_NODE, group_error) }
            capture = group
        }
        if p.depth >= MAX_DEPTH { ret (NO_NODE, TooComplex) }
        p.depth += 1u32
        let (inner, inner_error) = parse_alt(p)
        if inner_error != ok { ret (NO_NODE, inner_error) }
        p.depth -= 1u32
        if peek(*p) != 41u32 { ret (NO_NODE, InvalidPattern) }
        p.at += 1usize
        if look != NO_NODE {
            var width = 0usize
            if look >= 2u32 {
                let (spans, fixed) = fixed_width(p, inner)
                if !fixed { ret (NO_NODE, InvalidPattern) }
                width = spans
            }
            let (looked, looked_error) = node(p, .Look, inner, NO_NODE, look)
            if looked_error != ok { ret (NO_NODE, looked_error) }
            p.nodes[usize(looked)].min = u32(width)
            ret (looked, ok)
        }
        if atomic {
            let (sealed, sealed_error) = node(p, .Atomic, inner, NO_NODE, 0u32)
            ret (sealed, sealed_error)
        }
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
        var possessive = false
        if peek(*p) == 63u32 {
            lazy = true
            p.at += 1usize
        } else if peek(*p) == 43u32 {
            if !p.backtracking { ret (NO_NODE, NeedsBacktracking) }
            possessive = true
            p.at += 1usize
        }
        let (wrapped, wrapped_error) = node(p, .Repeat, atom, NO_NODE, 0u32)
        if wrapped_error != ok { ret (NO_NODE, wrapped_error) }
        p.nodes[usize(wrapped)].min = min
        p.nodes[usize(wrapped)].max = max
        p.nodes[usize(wrapped)].lazy = lazy
        atom = wrapped
        if possessive {
            let (sealed, sealed_error) = node(p, .Atomic, wrapped, NO_NODE, 0u32)
            if sealed_error != ok { ret (NO_NODE, sealed_error) }
            atom = sealed
        }
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
    if e.backtracking {
        // An iteration that consumed nothing leaves the loop instead of spinning.
        let slot = e.loop_base + e.loops
        e.loops += 1u32
        let (_, start_error) = emit(e, .RepStart, slot, 0u32)
        if start_error != ok { ret start_error }
        try gen_node(e, p, n.first)
        let (_, check_error) = emit(e, .RepCheck, slot, split)
        if check_error != ok { ret check_error }
    } else {
        try gen_node(e, p, n.first)
        let (_, jump_error) = emit(e, .Jmp, split, 0u32)
        if jump_error != ok { ret jump_error }
    }
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
    if n.kind == .Backref {
        let (_, backref_error) = emit(e, .Backref, n.value, 0u32)
        ret backref_error
    }
    if n.kind == .Atomic {
        let (_, atomic_error) = emit(e, .Atomic, 0u32, 0u32)
        if atomic_error != ok { ret atomic_error }
        try gen_node(e, p, n.first)
        let (_, sealed_error) = emit(e, .AtomicEnd, 0u32, 0u32)
        ret sealed_error
    }
    if n.kind == .Look {
        let (look, look_error) = emit(e, .Look, 0u32, n.value | (n.min << 2u32))
        if look_error != ok { ret look_error }
        try gen_node(e, p, n.first)
        let (_, end_error) = emit(e, .LookEnd, 0u32, n.value)
        if end_error != ok { ret end_error }
        patch(e, look, false, u32(e.count))
        ret ok
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

// The Pike VM; a pattern only a backtracker runs is refused with `NeedsBacktracking`.
fn compile(a: *mem.Arena, pattern: str, options: Options) -> (Regex, err) {
    let (r, r_error) = build(a, pattern, options, false)
    ret (r, r_error)
}

// The backtracking engine: the Pike VM's syntax plus backreferences, lookaround, atomic
// groups and possessive repeats, at the cost of time exponential in the worst case,
// which the step budget turns into `TooManySteps`.
fn compile_backtracking(a: *mem.Arena, pattern: str, options: Options) -> (Regex, err) {
    let (r, r_error) = build(a, pattern, options, true)
    ret (r, r_error)
}

fn build(a: *mem.Arena, pattern: str, options: Options, backtracking: bool) -> (Regex, err) {
    if !utf8.validate(pattern) { ret (zero, InvalidPattern) }
    let checkpoint = a.off
    let (nodes, nodes_error) = mem.alloc[Node](a, pattern.len * 2usize + 2usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (ranges, ranges_error) = mem.alloc[u32](a, pattern.len * 5usize + 8usize)
    if ranges_error != ok { ret (zero, ranges_error) }
    // Every group spends at least `(` and `)`, so a pair per two pattern bytes suffices.
    let (names, names_error) = mem.alloc[u32](a, pattern.len + 2usize)
    if names_error != ok { ret (zero, names_error) }
    var p = Parser { pattern: pattern, at: 0usize, nodes: nodes, node_count: 0usize, ranges: ranges, range_count: 0usize, groups: 0u32, depth: 0u32, options: options, backtracking: backtracking, names: names }
    let (root, root_error) = parse_alt(&p)
    if root_error != ok {
        a.off = checkpoint
        ret (zero, root_error)
    }
    if p.at < pattern.len {
        a.off = checkpoint
        ret (zero, InvalidPattern)
    }
    let slots = (usize(p.groups) + 1usize) * 2usize
    var measure = Emitter { insts: zero, count: 0usize, writing: false, backtracking: backtracking, loop_base: u32(slots), loops: 0u32 }
    let measure_error = gen_program(&measure, &p, root)
    if measure_error != ok {
        a.off = checkpoint
        ret (zero, measure_error)
    }
    let (insts, insts_error) = mem.alloc[Inst](a, measure.count)
    if insts_error != ok { ret (zero, insts_error) }
    var writer = Emitter { insts: insts, count: 0usize, writing: true, backtracking: backtracking, loop_base: u32(slots), loops: 0u32 }
    let step_error = gen_program(&writer, &p, root)
    if step_error != ok { ret (zero, step_error) }
    let (source, source_error) = mem.alloc[u8](a, pattern.len)
    if source_error != ok { ret (zero, source_error) }
    mem.copy[u8](source, pattern)
    let (program, program_error) = mem.alloc[Program](a, 1usize)
    if program_error != ok { ret (zero, program_error) }
    var first: Threads = zero
    var second: Threads = zero
    if !backtracking {
        let (made_first, first_error) = threads(a, measure.count, slots)
        if first_error != ok { ret (zero, first_error) }
        let (made_second, second_error) = threads(a, measure.count, slots)
        if second_error != ok { ret (zero, second_error) }
        first = made_first
        second = made_second
    }
    let (work, work_error) = mem.alloc[usize](a, slots + usize(measure.loops))
    if work_error != ok { ret (zero, work_error) }
    let (result, result_error) = mem.alloc[usize](a, slots)
    if result_error != ok { ret (zero, result_error) }
    var stack: []usize = zero
    var track: []usize = zero
    if backtracking {
        let (made_track, track_error) = mem.alloc[usize](a, MAX_TRACK * 3usize)
        if track_error != ok { ret (zero, track_error) }
        track = made_track
    } else {
        let (made_stack, stack_error) = mem.alloc[usize](a, (measure.count * 2usize + 2usize) * 3usize)
        if stack_error != ok { ret (zero, stack_error) }
        stack = made_stack
    }
    program[0usize] = Program { insts: insts, ranges: ranges[..p.range_count], groups: usize(p.groups), slots: slots, options: options, a: first, b: second, work: work, result: result, stack: stack, backtracking: backtracking, source: source, names: names[..usize(p.groups) * 2usize], track: track, depth: 0usize, steps: 0usize, failure: ok }
    ret (Regex { state: mem.cast[*void](&program[0usize]) }, ok)
}

// The group number (1-based, as `$1` and `\1` count) of the group called `name`.
fn group_index(r: *const Regex, name: str) -> (usize, bool) {
    let prog = mem.cast[*Program](r.state)
    var g = 0usize
    while g < prog.groups {
        let at = usize(prog.names[g * 2usize])
        let size = usize(prog.names[g * 2usize + 1usize])
        if size > 0usize && mem.eq[u8](prog.source[at..at + size], name) { ret (g + 1usize, true) }
        g += 1usize
    }
    ret (0usize, false)
}

// What stopped the last `is_match`, `find`, `captures` or `replace_all` on `r`:
// `TooManySteps` or `TooDeep` from the backtracker, `ok` otherwise.
fn last_error(r: *const Regex) -> err {
    let prog = mem.cast[*Program](r.state)
    ret prog.failure
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
    if prog.backtracking { ret bt_search(prog, text, from) }
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

// The backtracker's stack entries, (kind, x, y): an alternative to resume at pc x and
// position y; a capture slot x to restore to y; the mark of an open atomic group; the
// mark of an open lookahead or lookbehind, x the position it began at and, when
// negative, y the instruction to resume at should its body fail.
const T_ALT: usize = 0usize
const T_CAP: usize = 1usize
const T_ATOMIC: usize = 2usize
const T_LOOK: usize = 3usize
const T_NOTLOOK: usize = 4usize

fn bt_push(prog: *Program, kind: usize, x: usize, y: usize) -> bool {
    if prog.depth + 3usize > prog.track.len {
        prog.failure = TooDeep
        ret false
    }
    prog.track[prog.depth] = kind
    prog.track[prog.depth + 1usize] = x
    prog.track[prog.depth + 2usize] = y
    prog.depth += 3usize
    ret true
}

// The innermost open atomic or lookaround mark; every construct inside it has closed
// and removed its own, so the topmost mark is the one being closed.
fn bt_mark(prog: *Program) -> usize {
    var at = prog.depth
    while at > 0usize {
        at -= 3usize
        if prog.track[at] >= T_ATOMIC { ret at }
    }
    ret 0usize
}

// Commits past the mark at `m`: it and every alternative above it go, the capture
// restores stay, so failing back past the construct still undoes its captures.
fn bt_cut(prog: *Program, m: usize) {
    var kept = m
    var at = m + 3usize
    while at < prog.depth {
        if prog.track[at] == T_CAP {
            prog.track[kept] = T_CAP
            prog.track[kept + 1usize] = prog.track[at + 1usize]
            prog.track[kept + 2usize] = prog.track[at + 2usize]
            kept += 3usize
        }
        at += 3usize
    }
    prog.depth = kept
}

// Undoes everything down to and including the mark at `m`.
fn bt_unwind(prog: *Program, m: usize) {
    while prog.depth > m {
        prog.depth -= 3usize
        if prog.track[prog.depth] == T_CAP { prog.work[prog.track[prog.depth + 1usize]] = prog.track[prog.depth + 2usize] }
    }
}

// The position `count` scalars before `pos`, and whether the text reaches back that far.
fn step_back(text: str, pos: usize, count: u32) -> (usize, bool) {
    var at = pos
    var left = count
    while left > 0u32 {
        if at == 0usize { ret (0usize, false) }
        at -= 1usize
        while at > 0usize && (text[at] & 192u8) == 128u8 { at -= 1usize }
        left -= 1u32
    }
    ret (at, true)
}

// Where the text at `pos` stops repeating group `group`, if it does.
fn backref(prog: *Program, text: str, group: u32, pos: usize) -> (usize, bool) {
    let from = prog.work[usize(group) * 2usize]
    let upto = prog.work[usize(group) * 2usize + 1usize]
    if from == NONE || upto == NONE { ret (0usize, false) }
    var i = from
    var j = pos
    while i < upto {
        if j >= text.len { ret (0usize, false) }
        let (want, want_width) = unicode.read_utf8(text, i)
        let (have, have_width) = unicode.read_utf8(text, j)
        if want != have && !(prog.options.case_insensitive && unicode.to_lower_simple(want) == unicode.to_lower_simple(have)) { ret (0usize, false) }
        i += want_width
        j += have_width
    }
    ret (j, true)
}

// Pops to the next alternative and answers where it resumes; false when none is left
// or the budget ran out.
fn bt_fail(prog: *Program) -> (u32, usize, bool) {
    while prog.depth > 0usize {
        if prog.steps == 0usize {
            prog.failure = TooManySteps
            ret (0u32, 0usize, false)
        }
        prog.steps -= 1usize
        prog.depth -= 3usize
        let kind = prog.track[prog.depth]
        let x = prog.track[prog.depth + 1usize]
        let y = prog.track[prog.depth + 2usize]
        if kind == T_ALT { ret (u32(x), y, true) }
        if kind == T_CAP { prog.work[x] = y }
        if kind == T_NOTLOOK { ret (u32(y), x, true) }
    }
    ret (0u32, 0usize, false)
}

// One attempt anchored at `start`: true with the match in `prog.result`; false with
// `prog.failure` set when the budget or the stack ran out.
fn bt_attempt(prog: *Program, text: str, start: usize) -> bool {
    var s = 0usize
    while s < prog.work.len {
        prog.work[s] = NONE
        s += 1usize
    }
    prog.depth = 0usize
    var pc = 0u32
    var pos = start
    while true {
        if prog.steps == 0usize {
            prog.failure = TooManySteps
            ret false
        }
        prog.steps -= 1usize
        let inst = prog.insts[usize(pc)]
        var failed = false
        pc += 1u32
        if inst.op == .Char || inst.op == .Any || inst.op == .Class {
            failed = true
            if pos < text.len {
                let (scalar, width) = unicode.read_utf8(text, pos)
                if consumes(prog, inst, scalar) {
                    pos += width
                    failed = false
                }
            }
        } else if inst.op == .Split {
            if !bt_push(prog, T_ALT, usize(inst.y), pos) { ret false }
            pc = inst.x
        } else if inst.op == .Jmp {
            pc = inst.x
        } else if inst.op == .Save || inst.op == .RepStart {
            if !bt_push(prog, T_CAP, usize(inst.x), prog.work[usize(inst.x)]) { ret false }
            prog.work[usize(inst.x)] = pos
        } else if inst.op == .RepCheck {
            if pos != prog.work[usize(inst.x)] { pc = inst.y }
        } else if inst.op == .Bol || inst.op == .Eol || inst.op == .WordB || inst.op == .NotWordB {
            failed = !holds(prog, inst.op, text, pos)
        } else if inst.op == .Backref {
            let (upto, repeated) = backref(prog, text, inst.x, pos)
            if repeated { pos = upto }
            failed = !repeated
        } else if inst.op == .Atomic {
            if !bt_push(prog, T_ATOMIC, 0usize, 0usize) { ret false }
        } else if inst.op == .AtomicEnd {
            bt_cut(prog, bt_mark(prog))
        } else if inst.op == .Look {
            let negative = (inst.y & 1u32) != 0u32
            var begin = pos
            var reachable = true
            if (inst.y & 2u32) != 0u32 {
                let (back_to, back_ok) = step_back(text, pos, inst.y >> 2u32)
                begin = back_to
                reachable = back_ok
            }
            if !reachable {
                // A lookbehind reaching before the text holds only when negative.
                failed = !negative
                pc = inst.x
            } else {
                var kind = T_LOOK
                if negative { kind = T_NOTLOOK }
                if !bt_push(prog, kind, pos, usize(inst.x)) { ret false }
                pos = begin
            }
        } else if inst.op == .LookEnd {
            let m = bt_mark(prog)
            let saved = prog.track[m + 1usize]
            if (inst.y & 2u32) != 0u32 && pos != saved {
                failed = true
            } else if (inst.y & 1u32) != 0u32 {
                bt_unwind(prog, m)
                failed = true
            } else {
                bt_cut(prog, m)
                pos = saved
            }
        } else {
            mem.copy[usize](prog.result, prog.work[..prog.slots])
            ret true
        }
        if failed {
            let (resume_pc, resume_pos, resumed) = bt_fail(prog)
            if !resumed { ret false }
            pc = resume_pc
            pos = resume_pos
        }
    }
    ret false
}

// The leftmost match from `from`, trying each scalar boundary in turn under one budget.
fn bt_search(prog: *Program, text: str, from: usize) -> bool {
    prog.failure = ok
    prog.steps = MIN_STEPS + STEPS_PER_BYTE * (text.len - from)
    var start = from
    while true {
        if bt_attempt(prog, text, start) { ret true }
        if prog.failure != ok || start >= text.len { break }
        let (_, width) = unicode.read_utf8(text, start)
        start += width
    }
    ret false
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
    let prog = mem.cast[*Program](r.state)
    let (whole, found) = find(r, text, from)
    if !found { ret (zero, false, prog.failure) }
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
    if prog.failure != ok { ret ("", prog.failure) }
    let (out, out_error) = mem.alloc[u8](a, needed)
    if out_error != ok { ret ("", out_error) }
    let written = substitute(prog, out, true, text, replacement)
    ret (out[..written], ok)
}

// The automata behind `compile` as entry points of their own: `nfa_compile` is the
// Thompson construction (the same instruction program), `pike_vm` the thread-list VM
// with capture slots, `dfa_from_nfa` the subset construction over the program with
// the scalar alphabet cut into the classes the pattern's literals and ranges bound,
// `dfa_minimize` Moore partition refinement, `dfa_run` anchored acceptance and
// `dfa_longest` the longest accepted prefix. A DFA state is a set of program counters
// before its empty closure; `^` holds only in the start state's closure, `$` only in
// the closure taken at the text's end, so each state carries two accept bits. The DFA
// refuses (`Unsupported`) what a state cannot decide from one scalar: `\b`, `\B`,
// `multiline` and `case_insensitive`. `TooLarge` caps the states at the caller's limit.
// ponytail: states are deduplicated by a linear scan of bitsets and minimized by Moore
// refinement, both quadratic in the state count; a hashed set table and Hopcroft are
// the upgrade for patterns that build thousands of states.

type Nfa = struct { state: *void }
type Dfa = struct { table: []const u32, points: []const u32, classes: usize, states: usize, start: u32, accept: []const u8 }
error TooLarge
error Unsupported

fn nfa_compile(a: *mem.Arena, pattern: str, options: Options) -> (Nfa, err) {
    let (r, r_error) = compile(a, pattern, options)
    if r_error != ok { ret (zero, r_error) }
    ret (Nfa { state: r.state }, ok)
}

// The instruction count of the program.
fn nfa_size(n: Nfa) -> usize {
    let prog = mem.cast[*Program](n.state)
    ret prog.insts.len
}

// The leftmost match from `from`: `caps[0]` is the whole match and `caps[g]` group g
// (`NONE` bounds for a group that took no part), as many as `caps` holds.
fn pike_vm(n: Nfa, text: str, from: usize, caps: []Match) -> bool {
    if from > text.len { ret false }
    let prog = mem.cast[*Program](n.state)
    if !run(prog, text, from, false) { ret false }
    var g = 0usize
    while g < caps.len && g <= prog.groups {
        caps[g] = Match { start: prog.result[g * 2usize], end: prog.result[g * 2usize + 1usize] }
        g += 1usize
    }
    ret true
}

fn bit_set(bits: []const u64, at: usize) -> bool { ret ((bits[at / 64usize] >> u32(at % 64usize)) & 1u64) == 1u64 }
fn bit_mark(bits: []u64, at: usize) { bits[at / 64usize] |= 1u64 << u32(at % 64usize) }

fn is_consuming(op: Op) -> bool { ret op == .Char || op == .Any || op == .Class }

// The closure of `set` under empty edges in the context (`at_start`, `at_end`): every
// instruction reached is marked in `reach`; answers whether `Done` is among them.
fn dfa_closure(prog: *Program, set: []const u64, at_start: bool, at_end: bool, reach: []u64, stack: []u32) -> bool {
    var w = 0usize
    while w < reach.len {
        reach[w] = 0u64
        w += 1usize
    }
    var sp = 0usize
    var pc = 0usize
    while pc < prog.insts.len {
        if bit_set(set, pc) {
            stack[sp] = u32(pc)
            sp += 1usize
        }
        pc += 1usize
    }
    var done = false
    while sp > 0usize {
        sp -= 1usize
        let here = stack[sp]
        if bit_set(reach, usize(here)) { continue }
        bit_mark(reach, usize(here))
        let inst = prog.insts[usize(here)]
        if inst.op == .Jmp {
            stack[sp] = inst.x
            sp += 1usize
        } else if inst.op == .Split {
            stack[sp] = inst.x
            stack[sp + 1usize] = inst.y
            sp += 2usize
        } else if inst.op == .Save || (inst.op == .Bol && at_start) || (inst.op == .Eol && at_end) {
            stack[sp] = here + 1u32
            sp += 1usize
        } else if inst.op == .Done {
            done = true
        }
    }
    ret done
}

// The sorted distinct boundaries of the scalar classes: 0, every literal and range edge,
// the newline and the end of the scalar space; answers how many points were written.
fn dfa_points(prog: *Program, points: []u32) -> usize {
    var count = 0usize
    points[0] = 0u32
    points[1] = 10u32
    points[2] = 11u32
    points[3] = 1114112u32
    count = 4usize
    var pc = 0usize
    while pc < prog.insts.len {
        let inst = prog.insts[pc]
        if inst.op == .Char {
            points[count] = inst.x
            points[count + 1usize] = inst.x + 1u32
            count += 2usize
        }
        if inst.op == .Class {
            var r = 0u32
            while r < (inst.y >> 1u32) {
                let at = usize(inst.x + r * 2u32)
                points[count] = prog.ranges[at]
                points[count + 1usize] = prog.ranges[at + 1usize] + 1u32
                count += 2usize
                r += 1u32
            }
        }
        pc += 1usize
    }
    var i = 1usize
    while i < count {
        let v = points[i]
        var j = i
        while j > 0usize && points[j - 1usize] > v {
            points[j] = points[j - 1usize]
            j -= 1usize
        }
        points[j] = v
        i += 1usize
    }
    var kept = 1usize
    i = 1usize
    while i < count {
        if points[i] != points[kept - 1usize] {
            points[kept] = points[i]
            kept += 1usize
        }
        i += 1usize
    }
    ret kept
}

// The class of `scalar`: the last point at or below it.
fn dfa_class(d: Dfa, scalar: u32) -> usize {
    var low = 0usize
    var high = d.classes
    while high - low > 1usize {
        let mid = (low + high) / 2usize
        if d.points[mid] <= scalar { low = mid } else { high = mid }
    }
    ret low
}

fn same_set(sets: []const u64, at: usize, words: usize, set: []const u64) -> bool {
    var w = 0usize
    while w < words {
        if sets[at * words + w] != set[w] { ret false }
        w += 1usize
    }
    ret true
}

// Subset construction over the program, at most `max_states` states.
fn dfa_from_nfa(a: *mem.Arena, n: Nfa, max_states: usize) -> (Dfa, err) {
    let prog = mem.cast[*Program](n.state)
    if prog.options.case_insensitive || prog.options.multiline || max_states == 0usize { ret (zero, Unsupported) }
    let count = prog.insts.len
    var pc = 0usize
    while pc < count {
        if prog.insts[pc].op == .WordB || prog.insts[pc].op == .NotWordB { ret (zero, Unsupported) }
        pc += 1usize
    }
    let (points, points_error) = mem.alloc[u32](a, count * 2usize + prog.ranges.len + 4usize)
    if points_error != ok { ret (zero, points_error) }
    let classes = dfa_points(prog, points) - 1usize
    let words = (count + 63usize) / 64usize
    let (sets, sets_error) = mem.alloc[u64](a, max_states * words)
    if sets_error != ok { ret (zero, sets_error) }
    let (table, table_error) = mem.alloc[u32](a, max_states * classes)
    if table_error != ok { ret (zero, table_error) }
    let (accept, accept_error) = mem.alloc[u8](a, max_states)
    if accept_error != ok { ret (zero, accept_error) }
    let (reach, reach_error) = mem.alloc[u64](a, words)
    if reach_error != ok { ret (zero, reach_error) }
    let (next, next_error) = mem.alloc[u64](a, words)
    if next_error != ok { ret (zero, next_error) }
    let (stack, stack_error) = mem.alloc[u32](a, count * 3usize + 1usize)
    if stack_error != ok { ret (zero, stack_error) }
    var w = 0usize
    while w < words {
        sets[w] = 0u64
        w += 1usize
    }
    bit_mark(sets, 0usize)
    var states = 1usize
    var s = 0usize
    while s < states {
        let set = sets[s * words..(s + 1usize) * words]
        var flags = 0u8
        if dfa_closure(prog, set, s == 0usize, true, reach, stack) { flags |= 2u8 }
        if dfa_closure(prog, set, s == 0usize, false, reach, stack) { flags |= 1u8 }
        accept[s] = flags
        var k = 0usize
        while k < classes {
            w = 0usize
            while w < words {
                next[w] = 0u64
                w += 1usize
            }
            pc = 0usize
            while pc < count {
                if bit_set(reach, pc) && is_consuming(prog.insts[pc].op) && consumes(prog, prog.insts[pc], points[k]) { bit_mark(next, pc + 1usize) }
                pc += 1usize
            }
            var t = 0usize
            while t < states && !same_set(sets, t, words, next) { t += 1usize }
            if t == states {
                if states >= max_states { ret (zero, TooLarge) }
                mem.copy[u64](sets[states * words..(states + 1usize) * words], next)
                states += 1usize
            }
            table[s * classes + k] = u32(t)
            k += 1usize
        }
        s += 1usize
    }
    ret (Dfa { table: table[..states * classes], points: points[..classes + 1usize], classes: classes, states: states, start: 0u32, accept: accept[..states] }, ok)
}

// Moore refinement: states split by their accept bits, then by the blocks their
// transitions reach, until a pass splits nothing.
fn dfa_minimize(a: *mem.Arena, d: Dfa) -> (Dfa, err) {
    let n = d.states
    let c = d.classes
    let (block, block_error) = mem.alloc[u32](a, n)
    if block_error != ok { ret (zero, block_error) }
    let (fresh, fresh_error) = mem.alloc[u32](a, n)
    if fresh_error != ok { ret (zero, fresh_error) }
    var s = 0usize
    while s < n {
        block[s] = u32(d.accept[s])
        s += 1usize
    }
    var previous = 0usize
    var blocks = 0usize
    while true {
        blocks = 0usize
        s = 0usize
        while s < n {
            var found = n
            var t = 0usize
            while t < s && found == n {
                var alike = block[t] == block[s]
                var k = 0usize
                while alike && k < c {
                    if block[usize(d.table[t * c + k])] != block[usize(d.table[s * c + k])] { alike = false }
                    k += 1usize
                }
                if alike { found = t }
                t += 1usize
            }
            if found < n {
                fresh[s] = fresh[found]
            } else {
                fresh[s] = u32(blocks)
                blocks += 1usize
            }
            s += 1usize
        }
        mem.copy[u32](block, fresh)
        if blocks == previous { break }
        previous = blocks
    }
    let (table, table_error) = mem.alloc[u32](a, blocks * c)
    if table_error != ok { ret (zero, table_error) }
    let (accept, accept_error) = mem.alloc[u8](a, blocks)
    if accept_error != ok { ret (zero, accept_error) }
    s = 0usize
    while s < n {
        let b = usize(block[s])
        accept[b] = d.accept[s]
        var k = 0usize
        while k < c {
            table[b * c + k] = block[usize(d.table[s * c + k])]
            k += 1usize
        }
        s += 1usize
    }
    ret (Dfa { table: table, points: d.points, classes: c, states: blocks, start: block[usize(d.start)], accept: accept }, ok)
}

// Whether the whole text is accepted.
fn dfa_run(d: Dfa, text: str) -> bool {
    var s = usize(d.start)
    var pos = 0usize
    while pos < text.len {
        let (scalar, width) = unicode.read_utf8(text, pos)
        s = usize(d.table[s * d.classes + dfa_class(d, scalar)])
        pos += width
    }
    ret (d.accept[s] & 2u8) != 0u8
}

// The end of the longest prefix accepted, and whether there is one.
fn dfa_longest(d: Dfa, text: str) -> (usize, bool) {
    var s = usize(d.start)
    var pos = 0usize
    var best = 0usize
    var has = false
    while true {
        var flag = 1u8
        if pos == text.len { flag = 2u8 }
        if (d.accept[s] & flag) != 0u8 {
            best = pos
            has = true
        }
        if pos >= text.len { break }
        let (scalar, width) = unicode.read_utf8(text, pos)
        s = usize(d.table[s * d.classes + dfa_class(d, scalar)])
        pos += width
    }
    ret (best, has)
}
