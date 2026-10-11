// Mutation testing over source text, after Stryker: `discover` finds the places a
// program can be made subtly wrong, `apply` makes one such program, `run` hands each
// mutant to the caller's test suite and scores how many the suite caught.
//
// A mutant replaces one span of the source and nothing else. Three families:
//   Operator  `==` `!=` swap; `<` becomes `<=` and `>=`, `<=` becomes `<` and `>`, and
//             `>`, `>=` likewise; `&&` and `||` swap; `+` `-` swap (also `+=` `-=`);
//             a binary `*` becomes `/`.
//   Constant  a decimal integer literal becomes its successor (0 becomes 1), the
//             suffix kept; `true` and `false` swap.
//   Branch    the condition of an `if` becomes `true` and `false`; that of a `while`
//             becomes `false`. The condition is the text up to the last `{` on the
//             line.
// Comments, string and character literals, `->`, `..`, shifts, floats and prefixed
// numbers are skipped. A `-` or `*` after something that cannot end an operand is
// unary or a type and is skipped; a mutant that is nevertheless ill-formed is the
// suite's `Invalid` and does not count against the score.
//
// The suite is the caller's `fn(*Ctx, Mutant, str) -> Verdict`: compile and run the
// tests against the mutated source and say what happened. The score is the share of
// valid mutants (everything but `Invalid`) that were `Killed` or `Timeout`.
// Equivalent mutants (a change no test could observe) are not detected: they show as
// survivors, as they do in every mutation tool.

use e.mem
use e.str

type Kind = enum u8 { Operator, Constant, Branch }
type Verdict = enum u8 { Killed, Survived, Invalid, Timeout }
// The span `source[offset..offset + len]` becomes `replacement`.
type Mutant = struct { kind: Kind, offset: usize, len: usize, replacement: str, line: u32 }
type Score = struct { total: usize, killed: usize, timeout: usize, survived: usize, invalid: usize }
error TooSmall

fn add(out: []Mutant, n: *usize, kind: Kind, offset: usize, len: usize, replacement: str, line: u32) -> err {
    if *n >= out.len { ret TooSmall }
    out[*n] = Mutant { kind: kind, offset: offset, len: len, replacement: replacement, line: line }
    *n += 1usize
    ret ok
}

fn is_word_byte(b: u8) -> bool {
    ret str.is_ascii_alnum(b) || b == 95u8
}

// Could the text before `at` end an operand (so that a `-` or `*` here is binary)?
fn after_operand(source: str, at: usize) -> bool {
    var i = at
    while i > 0usize && (source[i - 1usize] == 32u8 || source[i - 1usize] == 9u8) { i -= 1usize }
    if i == 0usize { ret false }
    let b = source[i - 1usize]
    if b == 41u8 || b == 93u8 { ret true }
    if !is_word_byte(b) { ret false }
    // A word that ends the operand, unless it is a keyword that takes one.
    var start = i
    while start > 0usize && is_word_byte(source[start - 1usize]) { start -= 1usize }
    let word = source[start..i]
    if str.eq(word, "ret") || str.eq(word, "if") || str.eq(word, "while") || str.eq(word, "in") || str.eq(word, "try") { ret false }
    ret true
}

fn line_end(source: str, from: usize) -> usize {
    var e = from
    while e < source.len && source[e] != 10u8 { e += 1usize }
    ret e
}

// The walk behind `discover`; `n` counts the mutants written.
fn scan(a: *mem.Arena, source: str, out: []Mutant, n: *usize) -> err {
    var line = 1u32
    var i = 0usize
    while i < source.len {
        let c = source[i]
        if c == 10u8 {
            line += 1u32
            i += 1usize
            continue
        }
        if c == 47u8 && i + 1usize < source.len && source[i + 1usize] == 47u8 {
            i = line_end(source, i)
            continue
        }
        if c == 34u8 || c == 39u8 {
            i += 1usize
            while i < source.len && source[i] != c && source[i] != 10u8 {
                if source[i] == 92u8 { i += 1usize }
                i += 1usize
            }
            i += 1usize
            continue
        }
        if str.is_ascii_alpha(c) || c == 95u8 {
            var end = i
            while end < source.len && is_word_byte(source[end]) { end += 1usize }
            let word = source[i..end]
            if str.eq(word, "true") { try add(out, n, .Constant, i, 4usize, "false", line) }
            if str.eq(word, "false") { try add(out, n, .Constant, i, 5usize, "true", line) }
            if str.eq(word, "if") || str.eq(word, "while") {
                let eol = line_end(source, end)
                let (brace, found) = str.rfind(source[end..eol], "{")
                if found {
                    var cond_start = end
                    while cond_start < end + brace && source[cond_start] == 32u8 { cond_start += 1usize }
                    var cond_end = end + brace
                    while cond_end > cond_start && source[cond_end - 1usize] == 32u8 { cond_end -= 1usize }
                    if cond_end > cond_start {
                        let cond = source[cond_start..cond_end]
                        if str.eq(word, "if") {
                            if !str.eq(cond, "true") { try add(out, n, .Branch, cond_start, cond.len, "true", line) }
                        }
                        if !str.eq(cond, "false") { try add(out, n, .Branch, cond_start, cond.len, "false", line) }
                    }
                }
            }
            i = end
            continue
        }
        if str.is_ascii_digit(c) {
            var end = i
            while end < source.len && str.is_ascii_digit(source[end]) { end += 1usize }
            let digits_end = end
            var skip = false
            if end + 1usize < source.len && source[end] == 46u8 && str.is_ascii_digit(source[end + 1usize]) { skip = true }
            if i + 1usize == end && c == 48u8 && end < source.len && (source[end] == 120u8 || source[end] == 98u8 || source[end] == 111u8) { skip = true }
            while end < source.len && is_word_byte(source[end]) { end += 1usize }
            if skip {
                // A float or a prefixed literal: past its fraction, exponent and suffix.
                while end < source.len && (is_word_byte(source[end]) || source[end] == 46u8) { end += 1usize }
            } else {
                if digits_end - i <= 18usize {
                    let (value, parse_error) = str.parse_u64(source[i..digits_end])
                    if parse_error == ok {
                        let (builder0, builder_error) = str.builder(a, 24usize)
                        if builder_error != ok { ret builder_error }
                        var b = builder0
                        try str.push_u64(&b, value + 1u64)
                        try add(out, n, .Constant, i, digits_end - i, str.done(&b), line)
                    }
                }
            }
            i = end
            continue
        }
        // Operators.
        let next = if_next(source, i)
        if c == 61u8 && next == 61u8 {
            try add(out, n, .Operator, i, 2usize, "!=", line)
            i += 2usize
            continue
        }
        if c == 33u8 && next == 61u8 {
            try add(out, n, .Operator, i, 2usize, "==", line)
            i += 2usize
            continue
        }
        if c == 38u8 && next == 38u8 {
            try add(out, n, .Operator, i, 2usize, "||", line)
            i += 2usize
            continue
        }
        if c == 124u8 && next == 124u8 {
            try add(out, n, .Operator, i, 2usize, "&&", line)
            i += 2usize
            continue
        }
        if c == 45u8 && next == 62u8 {
            i += 2usize
            continue
        }
        if (c == 60u8 && next == 60u8) || (c == 62u8 && next == 62u8) || (c == 46u8 && next == 46u8) {
            i += 2usize
            continue
        }
        if c == 60u8 || c == 62u8 {
            // `<`, `<=`, `>`, `>=`.
            var width = 1usize
            if next == 61u8 { width = 2usize }
            let less = c == 60u8
            if width == 1usize {
                if less {
                    try add(out, n, .Operator, i, 1usize, "<=", line)
                    try add(out, n, .Operator, i, 1usize, ">=", line)
                } else {
                    try add(out, n, .Operator, i, 1usize, ">=", line)
                    try add(out, n, .Operator, i, 1usize, "<=", line)
                }
            } else {
                if less {
                    try add(out, n, .Operator, i, 2usize, "<", line)
                    try add(out, n, .Operator, i, 2usize, ">", line)
                } else {
                    try add(out, n, .Operator, i, 2usize, ">", line)
                    try add(out, n, .Operator, i, 2usize, "<", line)
                }
            }
            i += width
            continue
        }
        if c == 43u8 {
            if next == 61u8 {
                try add(out, n, .Operator, i, 2usize, "-=", line)
                i += 2usize
                continue
            }
            if after_operand(source, i) { try add(out, n, .Operator, i, 1usize, "-", line) }
            i += 1usize
            continue
        }
        if c == 45u8 {
            if next == 61u8 {
                try add(out, n, .Operator, i, 2usize, "+=", line)
                i += 2usize
                continue
            }
            if after_operand(source, i) { try add(out, n, .Operator, i, 1usize, "+", line) }
            i += 1usize
            continue
        }
        if c == 42u8 {
            if after_operand(source, i) { try add(out, n, .Operator, i, 1usize, "/", line) }
            i += 1usize
            continue
        }
        i += 1usize
    }
    ret ok
}

// Up to `out.len` mutants of `source`, in source order. Numeric replacements are
// built in `a`. `TooSmall` when there are more than fit (the first `out.len` stand and
// the count says how many).
fn discover(a: *mem.Arena, source: str, out: []Mutant) -> (usize, err) {
    var n = 0usize
    let scan_error = scan(a, source, out, &n)
    ret (n, scan_error)
}

fn if_next(source: str, at: usize) -> u8 {
    if at + 1usize < source.len { ret source[at + 1usize] }
    ret 0u8
}

// The program with this one mutation made.
fn apply(a: *mem.Arena, source: str, m: Mutant) -> (str, err) {
    let (builder0, builder_error) = str.builder(a, source.len + m.replacement.len)
    if builder_error != ok { ret ("", builder_error) }
    var b = builder0
    try str.push(&b, source[0usize..m.offset])
    try str.push(&b, m.replacement)
    try str.push(&b, source[m.offset + m.len..])
    ret (str.done(&b), ok)
}

// Run every mutant through `suite`; each mutated source lives only for its call (the
// arena is rewound after it). `verdicts` has an entry per mutant.
fn run[Ctx: type](a: *mem.Arena, source: str, mutants: []const Mutant, ctx: *Ctx, suite: fn(*Ctx, Mutant, str) -> Verdict, verdicts: []Verdict) -> (Score, err) {
    var score: Score = zero
    if verdicts.len < mutants.len { ret (score, TooSmall) }
    var i = 0usize
    while i < mutants.len {
        let mark = mem.mark(a)
        let (mutated, apply_error) = apply(a, source, mutants[i])
        if apply_error != ok { ret (score, apply_error) }
        let verdict = suite(ctx, mutants[i], mutated)
        mem.reset(a, mark)
        verdicts[i] = verdict
        score.total += 1usize
        if verdict == .Killed { score.killed += 1usize }
        if verdict == .Timeout { score.timeout += 1usize }
        if verdict == .Survived { score.survived += 1usize }
        if verdict == .Invalid { score.invalid += 1usize }
        i += 1usize
    }
    ret (score, ok)
}

// Killed-or-timed-out share of the valid mutants, in tenths of a percent (0 to 1000);
// 0 when there are none.
fn score_permille(s: Score) -> u32 {
    let valid = s.killed + s.timeout + s.survived
    if valid == 0usize { ret 0u32 }
    ret u32((s.killed + s.timeout) * 1000usize / valid)
}

// The suite is good enough when the score is at least `threshold` tenths of a percent.
fn meets(s: Score, threshold_permille: u32) -> bool {
    ret score_permille(s) >= threshold_permille
}

fn put(b: *str.Builder, s: str) {
    let discarded = str.push(b, s)
}

fn put_count(b: *str.Builder, n: usize) {
    let discarded = str.push_usize(b, n)
}

// One line per survivor (`survived: line L: old -> new`) and a total line, in `out`.
fn report(source: str, mutants: []const Mutant, verdicts: []const Verdict, s: Score, out: []u8) -> str {
    var holder = mem.arena_from(out)
    let (built, builder_error) = str.builder(&holder, out.len)
    if builder_error != ok { ret "" }
    var b = built
    var i = 0usize
    while i < mutants.len && i < verdicts.len {
        if verdicts[i] == .Survived {
            let m = &mutants[i]
            put(&b, "survived: line ")
            put_count(&b, usize(m.line))
            put(&b, ": ")
            put(&b, source[m.offset..m.offset + m.len])
            put(&b, " -> ")
            put(&b, m.replacement)
            put(&b, "\n")
        }
        i += 1usize
    }
    let permille = score_permille(s)
    put_count(&b, s.total)
    put(&b, " mutants: ")
    put_count(&b, s.killed)
    put(&b, " killed, ")
    put_count(&b, s.timeout)
    put(&b, " timeout, ")
    put_count(&b, s.survived)
    put(&b, " survived, ")
    put_count(&b, s.invalid)
    put(&b, " invalid; score ")
    put_count(&b, usize(permille / 10u32))
    put(&b, ".")
    put_count(&b, usize(permille % 10u32))
    put(&b, "%\n")
    ret str.done(&b)
}
