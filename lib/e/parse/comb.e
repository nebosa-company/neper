// A parser-combinator kit over a caller's string: a parser is a function
// `fn(*Cx, usize) -> (usize, bool)` that reads `cx.src` from an offset and answers the
// offset after what it matched, or `false` (nom's `IResult` with the rest implied by the
// offset). Nothing is copied: a match is the byte range `[start, end)` of the input.
//
// Failure keeps the furthest offset any primitive failed at, and the label of the
// first failure there, in the context (`cx.furthest`, `cx.expected`): the error offset
// of a failed alternative is where the input stopped being parseable, not where the last
// alternative began, which is what `nom::error::VerboseError` and parsy's `furthest` give.
//
// Structure is recorded by `node`, which appends an `Event { kind, start, end }` to the
// caller's event buffer after the events of its children (post-order, so an expression
// grammar produces reverse-Polish order). Every combinator that backtracks restores the
// event count, so a branch that was abandoned leaves no events. The buffer filling is a
// parse failure with `cx.overflow` set.
//
// Combinators: `lit`, `byte_range`, `one_of`, `none_of`, `any_byte`, `take_while`,
// `take_while1`, `eof`; `seq2`, `seq3`, `choice2`, `choice3`, `choice4`, `many0`,
// `many1`, `opt`, `delimited`, `preceded`, `terminated`, `separated0`, `separated1`,
// `count`, `peek`, `not`, `chainl1`, `chainr1`; and `node` and `label`. Left recursion
// and memoisation are not provided: write the loop with `chainl1` or `many0`.

type Event = struct { kind: u32, start: usize, end: usize }
type Cx = struct { src: str, furthest: usize, expected: str, noted: bool, events: []Event, count: usize, overflow: bool }

// A fresh context over `src` with `events` as the event buffer.
fn context(src: str, events: []Event) -> Cx {
    ret Cx { src: src, furthest: 0usize, expected: "", noted: false, events: events, count: 0usize, overflow: false }
}

// Forget every outcome and event so one context parses again.
fn reset(cx: *Cx) {
    cx.furthest = 0usize
    cx.expected = ""
    cx.noted = false
    cx.count = 0usize
    cx.overflow = false
}

// Record a failure at `off`: the furthest one wins, the first at that offset keeps its label.
fn note(cx: *Cx, off: usize, expected: str) {
    if !cx.noted || off > cx.furthest {
        cx.furthest = off
        cx.expected = expected
        cx.noted = true
    }
}

// One-based line and column of byte offset `off` in `src` (a column counts bytes).
fn line_col(src: str, off: usize) -> (usize, usize) {
    var line = 1usize
    var col = 1usize
    var i = 0usize
    while i < off && i < src.len {
        if src[i] == 10u8 {
            line += 1usize
            col = 1usize
        } else {
            col += 1usize
        }
        i += 1usize
    }
    ret (line, col)
}

// The literal bytes `s`.
fn lit(cx: *Cx, off: usize, s: str) -> (usize, bool) {
    if off + s.len > cx.src.len {
        note(cx, off, s)
        ret (off, false)
    }
    var i = 0usize
    while i < s.len {
        if cx.src[off + i] != s[i] {
            note(cx, off, s)
            ret (off, false)
        }
        i += 1usize
    }
    ret (off + s.len, true)
}

fn byte_range(cx: *Cx, off: usize, lo: u8, hi: u8, name: str) -> (usize, bool) {
    if off < cx.src.len && cx.src[off] >= lo && cx.src[off] <= hi { ret (off + 1usize, true) }
    note(cx, off, name)
    ret (off, false)
}

fn one_of(cx: *Cx, off: usize, set: str, name: str) -> (usize, bool) {
    if off < cx.src.len {
        var i = 0usize
        while i < set.len {
            if set[i] == cx.src[off] { ret (off + 1usize, true) }
            i += 1usize
        }
    }
    note(cx, off, name)
    ret (off, false)
}

fn none_of(cx: *Cx, off: usize, set: str, name: str) -> (usize, bool) {
    if off >= cx.src.len {
        note(cx, off, name)
        ret (off, false)
    }
    var i = 0usize
    while i < set.len {
        if set[i] == cx.src[off] {
            note(cx, off, name)
            ret (off, false)
        }
        i += 1usize
    }
    ret (off + 1usize, true)
}

fn any_byte(cx: *Cx, off: usize) -> (usize, bool) {
    if off < cx.src.len { ret (off + 1usize, true) }
    note(cx, off, "any byte")
    ret (off, false)
}

// Zero or more bytes satisfying `pred`; never fails.
fn take_while(cx: *Cx, off: usize, pred: fn(u8) -> bool) -> (usize, bool) {
    var i = off
    while i < cx.src.len && pred(cx.src[i]) { i += 1usize }
    ret (i, true)
}

fn take_while1(cx: *Cx, off: usize, pred: fn(u8) -> bool, name: str) -> (usize, bool) {
    var i = off
    while i < cx.src.len && pred(cx.src[i]) { i += 1usize }
    if i == off {
        note(cx, off, name)
        ret (off, false)
    }
    ret (i, true)
}

fn eof(cx: *Cx, off: usize) -> (usize, bool) {
    if off == cx.src.len { ret (off, true) }
    note(cx, off, "end of input")
    ret (off, false)
}

fn seq2(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool), q: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (a, good_a) = p(cx, off)
    if !good_a {
        cx.count = mark
        ret (off, false)
    }
    let (b, good_b) = q(cx, a)
    if !good_b {
        cx.count = mark
        ret (off, false)
    }
    ret (b, true)
}

fn seq3(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool), q: fn(*Cx, usize) -> (usize, bool), r: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (a, good_a) = p(cx, off)
    if !good_a {
        cx.count = mark
        ret (off, false)
    }
    let (b, good_b) = q(cx, a)
    if !good_b {
        cx.count = mark
        ret (off, false)
    }
    let (c, good_c) = r(cx, b)
    if !good_c {
        cx.count = mark
        ret (off, false)
    }
    ret (c, true)
}

fn choice2(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool), q: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (a, good_a) = p(cx, off)
    if good_a { ret (a, true) }
    cx.count = mark
    let (b, good_b) = q(cx, off)
    if good_b { ret (b, true) }
    cx.count = mark
    ret (off, false)
}

fn choice3(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool), q: fn(*Cx, usize) -> (usize, bool), r: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (a, good_a) = p(cx, off)
    if good_a { ret (a, true) }
    cx.count = mark
    let (b, good_b) = q(cx, off)
    if good_b { ret (b, true) }
    cx.count = mark
    let (c, good_c) = r(cx, off)
    if good_c { ret (c, true) }
    cx.count = mark
    ret (off, false)
}

fn choice4(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool), q: fn(*Cx, usize) -> (usize, bool), r: fn(*Cx, usize) -> (usize, bool), s: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (a, good_a) = p(cx, off)
    if good_a { ret (a, true) }
    cx.count = mark
    let (b, good_b) = q(cx, off)
    if good_b { ret (b, true) }
    cx.count = mark
    let (c, good_c) = r(cx, off)
    if good_c { ret (c, true) }
    cx.count = mark
    let (d, good_d) = s(cx, off)
    if good_d { ret (d, true) }
    cx.count = mark
    ret (off, false)
}

// Zero or more `p`; stops at the first failure or at an iteration that consumed nothing.
fn many0(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    var cur = off
    while true {
        let mark = cx.count
        let (next, good) = p(cx, cur)
        if !good {
            cx.count = mark
            break
        }
        if next == cur { break }
        cur = next
    }
    ret (cur, true)
}

fn many1(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (first, good) = p(cx, off)
    if !good {
        cx.count = mark
        ret (off, false)
    }
    let (rest, more) = many0(cx, first, p)
    ret (rest, true)
}

fn opt(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (next, good) = p(cx, off)
    if good { ret (next, true) }
    cx.count = mark
    ret (off, true)
}

// `open inner close`, keeping the events of all three.
fn delimited(cx: *Cx, off: usize, open: fn(*Cx, usize) -> (usize, bool), inner: fn(*Cx, usize) -> (usize, bool), close: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let (next, good) = seq3(cx, off, open, inner, close)
    ret (next, good)
}

fn preceded(cx: *Cx, off: usize, first: fn(*Cx, usize) -> (usize, bool), second: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let (next, good) = seq2(cx, off, first, second)
    ret (next, good)
}

fn terminated(cx: *Cx, off: usize, first: fn(*Cx, usize) -> (usize, bool), second: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let (next, good) = seq2(cx, off, first, second)
    ret (next, good)
}

// `item (sep item)*`; an empty list is a success consuming nothing, a trailing separator
// is left unconsumed.
fn separated0(cx: *Cx, off: usize, item: fn(*Cx, usize) -> (usize, bool), sep: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (first, good) = item(cx, off)
    if !good {
        cx.count = mark
        ret (off, true)
    }
    var cur = first
    while true {
        let loop_mark = cx.count
        let (after_sep, good_sep) = sep(cx, cur)
        if !good_sep {
            cx.count = loop_mark
            break
        }
        let (after_item, good_item) = item(cx, after_sep)
        if !good_item {
            cx.count = loop_mark
            break
        }
        cur = after_item
    }
    ret (cur, true)
}

fn separated1(cx: *Cx, off: usize, item: fn(*Cx, usize) -> (usize, bool), sep: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (first, good) = item(cx, off)
    if !good {
        cx.count = mark
        ret (off, false)
    }
    let (next, more) = separated0(cx, off, item, sep)
    ret (next, true)
}

// Exactly `n` repeats of `p`.
fn count(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool), n: usize) -> (usize, bool) {
    let mark = cx.count
    var cur = off
    var i = 0usize
    while i < n {
        let (next, good) = p(cx, cur)
        if !good {
            cx.count = mark
            ret (off, false)
        }
        cur = next
        i += 1usize
    }
    ret (cur, true)
}

// `p` without consuming: success keeps the offset and drops p's events.
fn peek(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (next, good) = p(cx, off)
    cx.count = mark
    ret (off, good)
}

// Negative lookahead: succeeds, consuming nothing, exactly when `p` fails.
fn not(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool), name: str) -> (usize, bool) {
    let mark = cx.count
    let (next, good) = p(cx, off)
    cx.count = mark
    if good {
        note(cx, off, name)
        ret (off, false)
    }
    ret (off, true)
}

// Run `p`; on success append one event spanning what it matched, after p's own.
fn node(cx: *Cx, off: usize, kind: u32, p: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    let mark = cx.count
    let (next, good) = p(cx, off)
    if !good {
        cx.count = mark
        ret (off, false)
    }
    if cx.count >= cx.events.len {
        cx.overflow = true
        cx.count = mark
        note(cx, off, "event buffer space")
        ret (off, false)
    }
    cx.events[cx.count] = Event { kind: kind, start: off, end: next }
    cx.count += 1usize
    ret (next, true)
}

// Name what was expected when `p` fails at its own start and nothing further was seen.
fn label(cx: *Cx, off: usize, p: fn(*Cx, usize) -> (usize, bool), name: str) -> (usize, bool) {
    let (next, good) = p(cx, off)
    if good { ret (next, true) }
    if !cx.noted || cx.furthest <= off {
        cx.furthest = off
        cx.expected = name
        cx.noted = true
    }
    ret (off, false)
}

// `operand (op operand)*`, left associative; each application appends one event of `kind`
// spanning the operator, after both operands' events.
fn chainl1(cx: *Cx, off: usize, operand: fn(*Cx, usize) -> (usize, bool), op: fn(*Cx, usize) -> (usize, bool), kind: u32) -> (usize, bool) {
    let mark = cx.count
    let (first, good) = operand(cx, off)
    if !good {
        cx.count = mark
        ret (off, false)
    }
    var cur = first
    while true {
        let loop_mark = cx.count
        let (after_op, good_op) = op(cx, cur)
        if !good_op {
            cx.count = loop_mark
            break
        }
        let (after_rhs, good_rhs) = operand(cx, after_op)
        if !good_rhs {
            cx.count = loop_mark
            break
        }
        if cx.count >= cx.events.len {
            cx.overflow = true
            cx.count = mark
            note(cx, cur, "event buffer space")
            ret (off, false)
        }
        cx.events[cx.count] = Event { kind: kind, start: cur, end: after_op }
        cx.count += 1usize
        cur = after_rhs
    }
    ret (cur, true)
}

// `operand (op chainr1)?`, right associative.
fn chainr1(cx: *Cx, off: usize, operand: fn(*Cx, usize) -> (usize, bool), op: fn(*Cx, usize) -> (usize, bool), kind: u32) -> (usize, bool) {
    let mark = cx.count
    let (first, good) = operand(cx, off)
    if !good {
        cx.count = mark
        ret (off, false)
    }
    let after_first = cx.count
    let (after_op, good_op) = op(cx, first)
    if !good_op {
        cx.count = after_first
        ret (first, true)
    }
    let (after_rhs, good_rhs) = chainr1(cx, after_op, operand, op, kind)
    if !good_rhs {
        cx.count = after_first
        ret (first, true)
    }
    if cx.count >= cx.events.len {
        cx.overflow = true
        cx.count = mark
        note(cx, first, "event buffer space")
        ret (off, false)
    }
    cx.events[cx.count] = Event { kind: kind, start: first, end: after_op }
    cx.count += 1usize
    ret (after_rhs, true)
}

// Parse the whole input: `p` and then the end. The answer is the offset reached and
// whether it was all consumed; on `false`, `cx.furthest` and `cx.expected` say where
// and why.
fn parse_all(cx: *Cx, p: fn(*Cx, usize) -> (usize, bool)) -> (usize, bool) {
    reset(cx)
    let (next, good) = p(cx, 0usize)
    if !good { ret (next, false) }
    if next != cx.src.len {
        note(cx, next, "end of input")
        ret (next, false)
    }
    ret (next, true)
}
