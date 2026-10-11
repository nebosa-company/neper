// Mocks, stubs and spies in the shape of gomock and testify's mock, over caller
// storage. Neper has no runtime reflection, so a double is a table, not a generated
// type: a call is a method number (the caller's own enum or constant) and up to
// `MAX_ARGS` integer arguments, a test double's method body is one `call`, and what it
// returns is the scripted value. Argument checks are `e.test.match` matchers.
//
// An `Expectation` says which method, what each argument must satisfy, how many
// times (default exactly once, `times` widens it), what to return (a value, or a
// list consumed one per call with the last repeating), and optionally its place in
// an ordered chain. `call` takes the first expectation of that method whose
// arguments match and whose upper bound is not reached; a call nothing takes is
// answered `Unexpected`, and one made before an earlier ordered expectation has met
// its minimum is answered `Order` (and counted, so `verify` names it once). A stub
// is an expectation with no argument matchers and no bounds (`allow`). Every call is
// logged, which is the spy: `call_count`, and `calls` for the arguments.
//
// `verify` is the single diagnostic producer: unexpected calls with every
// expectation of that method and the first argument that differed, out-of-order
// calls with the expectation they overtook, and expectations short of their
// minimum, all in the caller's buffer.

use e.mem
use e.str
use e.test
use e.test.match as match

const MAX_ARGS: usize = 4usize
const UNBOUNDED: u32 = 0xffffffffu32
const NO_MATCH: i64 = -1i64

type Expectation = struct { method: u32, name: str, args: [4]match.Matcher, nargs: usize, ret_value: i64, rets: []const i64, min: u32, max: u32, seq: u32, called: u32 }
type Call = struct { method: u32, nargs: usize, args: [4]i64, matched: i64, late: bool }
type Mock = struct { expectations: []Expectation, count: usize, calls: []Call, logged: usize, chain: u32 }
error Full
error Unexpected
error Order
error Unmet
error BadIndex

fn mock(expectations: []Expectation, calls: []Call) -> Mock {
    ret Mock { expectations: expectations, count: 0usize, calls: calls, logged: 0usize, chain: 0u32 }
}

// A new expectation of `method`, shown as `name` in diagnostics: exactly one call,
// any arguments, returning 0. Answers its index.
fn expect(m: *Mock, method: u32, name: str) -> (usize, err) {
    if m.count >= m.expectations.len { ret (0usize, Full) }
    var e: Expectation = zero
    e.method = method
    e.name = name
    var k = 0usize
    while k < MAX_ARGS {
        e.args[k] = match.anything()
        k += 1usize
    }
    e.min = 1u32
    e.max = 1u32
    let index = m.count
    m.expectations[index] = e
    m.count += 1usize
    ret (index, ok)
}

// A stub: any arguments, any number of calls (including none), returning `value`.
fn allow(m: *Mock, method: u32, name: str, value: i64) -> (usize, err) {
    let (index, expect_error) = expect(m, method, name)
    if expect_error != ok { ret (0usize, expect_error) }
    m.expectations[index].min = 0u32
    m.expectations[index].max = UNBOUNDED
    m.expectations[index].ret_value = value
    ret (index, ok)
}

fn with_arg(m: *Mock, index: usize, pos: usize, matcher: match.Matcher) -> err {
    if index >= m.count || pos >= MAX_ARGS { ret BadIndex }
    m.expectations[index].args[pos] = matcher
    if pos + 1usize > m.expectations[index].nargs { m.expectations[index].nargs = pos + 1usize }
    ret ok
}

fn returns(m: *Mock, index: usize, value: i64) -> err {
    if index >= m.count { ret BadIndex }
    m.expectations[index].ret_value = value
    ret ok
}

// The n-th call returns `values[n]`; the last repeats. Borrowed, not copied.
fn returns_list(m: *Mock, index: usize, values: []const i64) -> err {
    if index >= m.count { ret BadIndex }
    m.expectations[index].rets = values
    ret ok
}

// At least `min`, at most `max` (`UNBOUNDED` for no limit) calls.
fn times(m: *Mock, index: usize, min: u32, max: u32) -> err {
    if index >= m.count { ret BadIndex }
    m.expectations[index].min = min
    m.expectations[index].max = max
    ret ok
}

// Place the expectation next in the ordered chain: it may be called only once every
// expectation placed before it has met its minimum.
fn in_order(m: *Mock, index: usize) -> err {
    if index >= m.count { ret BadIndex }
    m.chain += 1u32
    m.expectations[index].seq = m.chain
    ret ok
}

// Every argument position the call has satisfies its matcher; positions beyond the
// call's arguments need a matcher that accepts anything.
fn accepts(e: *const Expectation, args: []const i64) -> bool {
    var k = 0usize
    while k < MAX_ARGS {
        if k < args.len {
            if !match.matches(&e.args[k], match.Subject{ Int: args[k] }) { ret false }
        } else {
            if e.args[k].kind != .Anything { ret false }
        }
        k += 1usize
    }
    ret true
}

// Every expectation placed before `index` in the ordered chain has met its minimum.
fn prior_met(m: *const Mock, index: usize) -> bool {
    let seq = m.expectations[index].seq
    if seq == 0u32 { ret true }
    var i = 0usize
    while i < m.count {
        let e = &m.expectations[i]
        if e.seq != 0u32 && e.seq < seq && e.called < e.min { ret false }
        i += 1usize
    }
    ret true
}

fn scripted(e: *const Expectation) -> i64 {
    if e.rets.len == 0usize { ret e.ret_value }
    var at = usize(e.called)
    if at >= e.rets.len { at = e.rets.len - 1usize }
    ret e.rets[at]
}

// The double's method body: record the call and answer the scripted value.
fn call(m: *Mock, method: u32, args: []const i64) -> (i64, err) {
    if m.logged >= m.calls.len { ret (0i64, Full) }
    var record: Call = zero
    record.method = method
    record.matched = NO_MATCH
    var k = 0usize
    while k < MAX_ARGS && k < args.len {
        record.args[k] = args[k]
        record.nargs = k + 1usize
        k += 1usize
    }
    var chosen = NO_MATCH
    var i = 0usize
    while i < m.count && chosen == NO_MATCH {
        let e = &m.expectations[i]
        if e.method == method && e.called < e.max && accepts(e, args) { chosen = i64(i) }
        i += 1usize
    }
    let slot = m.logged
    m.logged += 1usize
    if chosen == NO_MATCH {
        m.calls[slot] = record
        ret (0i64, Unexpected)
    }
    let index = usize(chosen)
    record.matched = chosen
    let late = !prior_met(m, index)
    record.late = late
    m.calls[slot] = record
    let value = scripted(&m.expectations[index])
    m.expectations[index].called += 1u32
    if late { ret (value, Order) }
    ret (value, ok)
}

fn call_count(m: *const Mock, method: u32) -> usize {
    var n = 0usize
    var i = 0usize
    while i < m.logged {
        if m.calls[i].method == method { n += 1usize }
        i += 1usize
    }
    ret n
}

fn put(b: *str.Builder, s: str) {
    let discarded = str.push(b, s)
}

fn put_usize(b: *str.Builder, n: usize) {
    let discarded = str.push_usize(b, n)
}

// `name(arg, arg)` of a recorded call.
fn put_call(b: *str.Builder, name: str, c: *const Call) {
    put(b, name)
    put(b, "(")
    var k = 0usize
    while k < c.nargs {
        if k != 0usize { put(b, ", ") }
        let discarded = str.push_i64(b, c.args[k])
        k += 1usize
    }
    put(b, ")")
}

// `name(expected, expected)` of an expectation, up to its last constrained position.
fn put_expectation(b: *str.Builder, e: *const Expectation) {
    put(b, e.name)
    put(b, "(")
    var k = 0usize
    while k < e.nargs {
        if k != 0usize { put(b, ", ") }
        match.put_describe(b, &e.args[k])
        k += 1usize
    }
    put(b, ")")
}

fn name_of(m: *const Mock, method: u32) -> str {
    var i = 0usize
    while i < m.count {
        if m.expectations[i].method == method { ret m.expectations[i].name }
        i += 1usize
    }
    ret "method"
}

// The first argument of `c` that `e` rejects, as ` (argument N was V: <why>)`.
fn put_difference(b: *str.Builder, e: *const Expectation, c: *const Call) {
    var k = 0usize
    var shown = false
    while k < MAX_ARGS && !shown {
        if k < c.nargs {
            let subject = match.Subject{ Int: c.args[k] }
            if !match.matches(&e.args[k], subject) {
                put(b, "    argument ")
                put_usize(b, k)
                put(b, " ")
                match.put_explain(b, &e.args[k], subject)
                put(b, "\n")
                shown = true
            }
        }
        k += 1usize
    }
}

// The report for everything that went wrong with this mock, or `ok` and an empty text.
// A report longer than `out` is cut.
fn verify(m: *const Mock, out: []u8) -> (str, err) {
    var holder = mem.arena_from(out)
    let (built, builder_error) = str.builder(&holder, out.len)
    if builder_error != ok { ret ("", Unmet) }
    var b = built
    var bad = false
    var i = 0usize
    while i < m.logged {
        let c = &m.calls[i]
        if c.matched == NO_MATCH {
            bad = true
            put(&b, "unexpected call: ")
            put_call(&b, name_of(m, c.method), c)
            put(&b, "\n")
            var j = 0usize
            while j < m.count {
                let e = &m.expectations[j]
                if e.method == c.method {
                    put(&b, "  wanted: ")
                    put_expectation(&b, e)
                    put(&b, " (")
                    put_usize(&b, usize(e.called))
                    put(&b, " of ")
                    put_usize(&b, usize(e.max))
                    put(&b, " calls used)\n")
                    put_difference(&b, e, c)
                }
                j += 1usize
            }
        } else {
            if c.late {
                bad = true
                put(&b, "call out of order: ")
                put_call(&b, name_of(m, c.method), c)
                put(&b, " came before an earlier expected call was met\n")
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < m.count {
        let e = &m.expectations[i]
        if e.called < e.min {
            bad = true
            put(&b, "missing call: ")
            put_expectation(&b, e)
            put(&b, " expected at least ")
            put_usize(&b, usize(e.min))
            put(&b, " time(s), called ")
            put_usize(&b, usize(e.called))
            put(&b, "\n")
        }
        i += 1usize
    }
    let report = str.done(&b)
    if bad { ret (report, Unmet) }
    ret ("", ok)
}

// `ok` when `verify` is clean; otherwise fails the running test with its report.
fn assert_verified(m: *const Mock, buf: []u8) -> err {
    let (report, verify_error) = verify(m, buf)
    if verify_error == ok { ret ok }
    ret test.fail(report)
}
