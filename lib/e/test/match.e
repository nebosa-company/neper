// Composable value matchers with Hamcrest-style descriptions, over `e.test`. A matcher
// is plain data: a `Kind` and the operands that kind reads. Matchers compose through
// `inner` (negate, has_item, every, len_is) and `kids` (all_of, any_of), both of which
// borrow caller storage, so nothing allocates. A value is a `Subject`: an integer, a
// float, text, a bool or a list of integers; a matcher given a subject of a kind it
// does not read does not match, and its explanation says so.
//
// `matches` answers; `describe` writes what was expected ("a value greater than 5");
// `explain` writes why a value did not match ("was 3"; a composite names the failing
// part: "item at index 1 was 9"); `message` joins them the way Hamcrest does, and
// `assert_that` fails the running test with that text, built in the caller's buffer
// (text past the buffer is cut, never an error).

use e.mem
use e.str
use e.test

type Subject = union enum u8 { Int: i64, Float: f64, Text: str, Bool: bool, Ints: []const i64 }
type Kind = enum u8 { Anything, EqInt, NeInt, Gt, Ge, Lt, Le, Between, OneOf, EqFloat, Near, EqText, Contains, StartsWith, EndsWith, Len, IsTrue, IsFalse, Not, AllOf, AnyOf, HasItem, Every }
// `lo`/`hi` are the integer operands (`Between`), `real` and `tol` the float ones,
// `text` the text operand, `ints` the `OneOf` set, `kids` the `AllOf`/`AnyOf` parts and
// `inner` the single part of `Not`, `Len`, `HasItem` and `Every`.
type Matcher = struct { kind: Kind, lo: i64, hi: i64, real: f64, tol: f64, text: str, ints: []const i64, kids: []const Matcher, inner: *const Matcher }

fn blank(kind: Kind) -> Matcher {
    ret Matcher { kind: kind, lo: 0i64, hi: 0i64, real: 0.0f64, tol: 0.0f64, text: "", ints: zero, kids: zero, inner: nil }
}

fn anything() -> Matcher { ret blank(.Anything) }

fn int_matcher(kind: Kind, v: i64) -> Matcher {
    var m = blank(kind)
    m.lo = v
    ret m
}

fn eq_int(v: i64) -> Matcher { ret int_matcher(.EqInt, v) }
fn ne_int(v: i64) -> Matcher { ret int_matcher(.NeInt, v) }
fn gt(v: i64) -> Matcher { ret int_matcher(.Gt, v) }
fn ge(v: i64) -> Matcher { ret int_matcher(.Ge, v) }
fn lt(v: i64) -> Matcher { ret int_matcher(.Lt, v) }
fn le(v: i64) -> Matcher { ret int_matcher(.Le, v) }

fn between(lo: i64, hi: i64) -> Matcher {
    var m = blank(.Between)
    m.lo = lo
    m.hi = hi
    ret m
}

fn one_of(values: []const i64) -> Matcher {
    var m = blank(.OneOf)
    m.ints = values
    ret m
}

fn eq_float(v: f64) -> Matcher {
    var m = blank(.EqFloat)
    m.real = v
    ret m
}

// Within `tol` (absolute) of `v`; a NaN is near nothing.
fn near(v: f64, tol: f64) -> Matcher {
    var m = blank(.Near)
    m.real = v
    m.tol = tol
    ret m
}

fn text_matcher(kind: Kind, t: str) -> Matcher {
    var m = blank(kind)
    m.text = t
    ret m
}

fn eq_text(t: str) -> Matcher { ret text_matcher(.EqText, t) }
fn contains(t: str) -> Matcher { ret text_matcher(.Contains, t) }
fn starts_with(t: str) -> Matcher { ret text_matcher(.StartsWith, t) }
fn ends_with(t: str) -> Matcher { ret text_matcher(.EndsWith, t) }
fn is_true() -> Matcher { ret blank(.IsTrue) }
fn is_false() -> Matcher { ret blank(.IsFalse) }

fn inner_matcher(kind: Kind, inner: *const Matcher) -> Matcher {
    var m = blank(kind)
    m.inner = inner
    ret m
}

// The length of a `Text` or the count of `Ints` satisfies `inner`.
fn len_is(inner: *const Matcher) -> Matcher { ret inner_matcher(.Len, inner) }
fn negate(inner: *const Matcher) -> Matcher { ret inner_matcher(.Not, inner) }
// Some item of an `Ints` satisfies `inner`.
fn has_item(inner: *const Matcher) -> Matcher { ret inner_matcher(.HasItem, inner) }
// Every item of an `Ints` satisfies `inner` (vacuously for an empty list).
fn every(inner: *const Matcher) -> Matcher { ret inner_matcher(.Every, inner) }

fn all_of(kids: []const Matcher) -> Matcher {
    var m = blank(.AllOf)
    m.kids = kids
    ret m
}

fn any_of(kids: []const Matcher) -> Matcher {
    var m = blank(.AnyOf)
    m.kids = kids
    ret m
}

fn contains_text(hay: str, needle: str) -> bool {
    if needle.len > hay.len { ret false }
    var at = 0usize
    while at + needle.len <= hay.len {
        var k = 0usize
        while k < needle.len && hay[at + k] == needle[k] { k += 1usize }
        if k == needle.len { ret true }
        at += 1usize
    }
    ret false
}

fn matches(m: *const Matcher, v: Subject) -> bool {
    if m.kind == .Anything { ret true }
    switch v {
    case .Int as n:
        if m.kind == .EqInt { ret n == m.lo }
        if m.kind == .NeInt { ret n != m.lo }
        if m.kind == .Gt { ret n > m.lo }
        if m.kind == .Ge { ret n >= m.lo }
        if m.kind == .Lt { ret n < m.lo }
        if m.kind == .Le { ret n <= m.lo }
        if m.kind == .Between { ret n >= m.lo && n <= m.hi }
        if m.kind == .OneOf {
            var i = 0usize
            while i < m.ints.len {
                if m.ints[i] == n { ret true }
                i += 1usize
            }
            ret false
        }
    case .Float as x:
        if m.kind == .EqFloat { ret x == m.real }
        if m.kind == .Near {
            var gap = x - m.real
            if gap < 0.0f64 { gap = 0.0f64 - gap }
            ret gap <= m.tol
        }
    case .Text as t:
        if m.kind == .EqText { ret str.eq(t, m.text) }
        if m.kind == .Contains { ret contains_text(t, m.text) }
        if m.kind == .StartsWith { ret t.len >= m.text.len && str.eq(t[0usize..m.text.len], m.text) }
        if m.kind == .EndsWith { ret t.len >= m.text.len && str.eq(t[t.len - m.text.len..t.len], m.text) }
        if m.kind == .Len { ret matches(m.inner, Subject{ Int: i64(t.len) }) }
    case .Bool as b:
        if m.kind == .IsTrue { ret b }
        if m.kind == .IsFalse { ret !b }
    case .Ints as items:
        if m.kind == .Len { ret matches(m.inner, Subject{ Int: i64(items.len) }) }
        if m.kind == .HasItem {
            var i = 0usize
            while i < items.len {
                if matches(m.inner, Subject{ Int: items[i] }) { ret true }
                i += 1usize
            }
            ret false
        }
        if m.kind == .Every {
            var i = 0usize
            while i < items.len {
                if !matches(m.inner, Subject{ Int: items[i] }) { ret false }
                i += 1usize
            }
            ret true
        }
    }
    // Composition applies to every subject.
    if m.kind == .Not { ret !matches(m.inner, v) }
    if m.kind == .AllOf {
        var i = 0usize
        while i < m.kids.len {
            if !matches(&m.kids[i], v) { ret false }
            i += 1usize
        }
        ret true
    }
    if m.kind == .AnyOf {
        var i = 0usize
        while i < m.kids.len {
            if matches(&m.kids[i], v) { ret true }
            i += 1usize
        }
        ret false
    }
    ret false
}

// Text writing is best-effort into the caller's buffer: a push the buffer cannot hold
// is dropped, so a description longer than the buffer is cut.
fn put(b: *str.Builder, s: str) {
    let discarded = str.push(b, s)
}

fn put_int(b: *str.Builder, n: i64) {
    let discarded = str.push_i64(b, n)
}

fn put_quoted(b: *str.Builder, s: str) {
    put(b, "\"")
    put(b, s)
    put(b, "\"")
}

fn put_ints(b: *str.Builder, items: []const i64) {
    put(b, "[")
    var i = 0usize
    while i < items.len {
        if i != 0usize { put(b, ", ") }
        put_int(b, items[i])
        i += 1usize
    }
    put(b, "]")
}

fn put_show(b: *str.Builder, v: Subject) {
    switch v {
    case .Int as n:
        put_int(b, n)
    case .Float as x:
        let discarded = str.push_f64(b, x)
    case .Text as t:
        put_quoted(b, t)
    case .Bool as flag:
        if flag { put(b, "true") } else { put(b, "false") }
    case .Ints as items:
        put_ints(b, items)
    }
}

fn put_describe(b: *str.Builder, m: *const Matcher) {
    if m.kind == .Anything { put(b, "anything") }
    if m.kind == .EqInt {
        put(b, "equal to ")
        put_int(b, m.lo)
    }
    if m.kind == .NeInt {
        put(b, "not equal to ")
        put_int(b, m.lo)
    }
    if m.kind == .Gt {
        put(b, "greater than ")
        put_int(b, m.lo)
    }
    if m.kind == .Ge {
        put(b, "at least ")
        put_int(b, m.lo)
    }
    if m.kind == .Lt {
        put(b, "less than ")
        put_int(b, m.lo)
    }
    if m.kind == .Le {
        put(b, "at most ")
        put_int(b, m.lo)
    }
    if m.kind == .Between {
        put(b, "between ")
        put_int(b, m.lo)
        put(b, " and ")
        put_int(b, m.hi)
    }
    if m.kind == .OneOf {
        put(b, "one of ")
        put_ints(b, m.ints)
    }
    if m.kind == .EqFloat {
        put(b, "equal to ")
        let discarded = str.push_f64(b, m.real)
    }
    if m.kind == .Near {
        put(b, "within ")
        let tol_discarded = str.push_f64(b, m.tol)
        put(b, " of ")
        let real_discarded = str.push_f64(b, m.real)
    }
    if m.kind == .EqText {
        put(b, "equal to ")
        put_quoted(b, m.text)
    }
    if m.kind == .Contains {
        put(b, "containing ")
        put_quoted(b, m.text)
    }
    if m.kind == .StartsWith {
        put(b, "starting with ")
        put_quoted(b, m.text)
    }
    if m.kind == .EndsWith {
        put(b, "ending with ")
        put_quoted(b, m.text)
    }
    if m.kind == .IsTrue { put(b, "true") }
    if m.kind == .IsFalse { put(b, "false") }
    if m.kind == .Len {
        put(b, "length ")
        put_describe(b, m.inner)
    }
    if m.kind == .Not {
        put(b, "not (")
        put_describe(b, m.inner)
        put(b, ")")
    }
    if m.kind == .HasItem {
        put(b, "an item ")
        put_describe(b, m.inner)
    }
    if m.kind == .Every {
        put(b, "every item ")
        put_describe(b, m.inner)
    }
    if m.kind == .AllOf || m.kind == .AnyOf {
        if m.kind == .AllOf { put(b, "all of (") } else { put(b, "any of (") }
        var i = 0usize
        while i < m.kids.len {
            if i != 0usize {
                if m.kind == .AllOf { put(b, " and ") } else { put(b, " or ") }
            }
            put_describe(b, &m.kids[i])
            i += 1usize
        }
        put(b, ")")
    }
}

// Why `v` does not satisfy `m`; nothing useful is written when it does.
fn put_explain(b: *str.Builder, m: *const Matcher, v: Subject) {
    var handled = false
    switch v {
    case .Text as t:
        if m.kind == .Len {
            put(b, "length ")
            put_explain(b, m.inner, Subject{ Int: i64(t.len) })
            handled = true
        }
    case .Ints as items:
        if m.kind == .Len {
            put(b, "length ")
            put_explain(b, m.inner, Subject{ Int: i64(items.len) })
            handled = true
        }
        if m.kind == .HasItem {
            put(b, "no item matched in ")
            put_ints(b, items)
            handled = true
        }
        if m.kind == .Every {
            var i = 0usize
            while i < items.len && !handled {
                if !matches(m.inner, Subject{ Int: items[i] }) {
                    put(b, "item at index ")
                    put_int(b, i64(i))
                    put(b, " ")
                    put_explain(b, m.inner, Subject{ Int: items[i] })
                    handled = true
                }
                i += 1usize
            }
        }
    default:
        handled = false
    }
    if !handled && m.kind == .AllOf {
        var i = 0usize
        while i < m.kids.len && !handled {
            if !matches(&m.kids[i], v) {
                put_explain(b, &m.kids[i], v)
                handled = true
            }
            i += 1usize
        }
    }
    if !handled && m.kind == .AnyOf {
        put(b, "none matched: ")
        var i = 0usize
        while i < m.kids.len {
            if i != 0usize { put(b, "; ") }
            put_explain(b, &m.kids[i], v)
            i += 1usize
        }
        handled = true
    }
    if !handled {
        put(b, "was ")
        put_show(b, v)
    }
}

fn describe(m: *const Matcher, out: []u8) -> str {
    var holder = mem.arena_from(out)
    let (built, builder_error) = str.builder(&holder, out.len)
    if builder_error != ok { ret "" }
    var b = built
    put_describe(&b, m)
    ret str.done(&b)
}

fn explain(m: *const Matcher, v: Subject, out: []u8) -> str {
    var holder = mem.arena_from(out)
    let (built, builder_error) = str.builder(&holder, out.len)
    if builder_error != ok { ret "" }
    var b = built
    put_explain(&b, m, v)
    ret str.done(&b)
}

// `expected: <describe>` and, on the next line, `     but: <explain>`.
fn message(m: *const Matcher, v: Subject, out: []u8) -> str {
    var holder = mem.arena_from(out)
    let (built, builder_error) = str.builder(&holder, out.len)
    if builder_error != ok { ret "" }
    var b = built
    put(&b, "expected: ")
    put_describe(&b, m)
    put(&b, "\n     but: ")
    put_explain(&b, m, v)
    ret str.done(&b)
}

// `ok` when `v` matches; otherwise fails the running test with `message` built in `buf`.
fn assert_that(v: Subject, m: *const Matcher, buf: []u8) -> err {
    if matches(m, v) { ret ok }
    ret test.fail(message(m, v, buf))
}
