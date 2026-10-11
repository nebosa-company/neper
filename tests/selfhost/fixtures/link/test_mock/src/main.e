// `e.test.mock`: scripted expectations with argument matchers over a three-method
// "payment gateway" double. Sections: the default exactly-once expectation and its
// report when called twice, an argument that fails its matcher (the report names the
// argument and the matcher's explanation), a missing call, `times` with a returns list
// (the last value repeating), a stub that tolerates any number of calls including
// none, ordered expectations called out of order, the spy log and call counts, the
// table-full and bad-index refusals, and `assert_verified` leaving the report in
// `e.test.current`. The report texts are exact and hand-checked. Every check has its
// own exit code.
use e.os
use e.mem
use e.str
use e.test
use e.test.match as match
use e.test.mock as mock

const CHARGE: u32 = 1u32
const REFUND: u32 = 2u32
const AUDIT: u32 = 3u32

fn report_is(m: *const mock.Mock, want: str) -> bool {
    var buf: [512]u8 = zero
    let (text, verify_error) = mock.verify(m, buf[0..])
    if verify_error != mock.Unmet { ret false }
    ret str.eq(text, want)
}

fn clean(m: *const mock.Mock) -> bool {
    var buf: [64]u8 = zero
    let (text, verify_error) = mock.verify(m, buf[0..])
    ret verify_error == ok && text.len == 0usize
}

fn charge_once(m: *mock.Mock) -> usize {
    let (idx, expect_error) = mock.expect(m, CHARGE, "charge")
    if expect_error != ok { ret 99usize }
    if mock.with_arg(m, idx, 0usize, match.eq_int(100i64)) != ok { ret 99usize }
    if mock.returns(m, idx, 7i64) != ok { ret 99usize }
    ret idx
}

fn checks_basic() -> i32 {
    var exps: [8]mock.Expectation = zero
    var calls: [16]mock.Call = zero
    var m = mock.mock(exps[0..], calls[0..])
    let _ = charge_once(&m)
    var args: [2]i64 = zero
    args[0] = 100i64
    args[1] = 7i64
    let (value, call_error) = mock.call(&m, CHARGE, args[0..])
    if call_error != ok || value != 7i64 { ret 10i32 }
    if !clean(&m) { ret 11i32 }
    // The second call exceeds the default exactly-once bound.
    let (_, again_error) = mock.call(&m, CHARGE, args[0..])
    if again_error != mock.Unexpected { ret 12i32 }
    if !report_is(&m, "unexpected call: charge(100, 7)\n  wanted: charge(equal to 100) (1 of 1 calls used)\n") { ret 13i32 }
    ret 0i32
}

fn checks_arguments() -> i32 {
    var exps: [8]mock.Expectation = zero
    var calls: [16]mock.Call = zero
    var m = mock.mock(exps[0..], calls[0..])
    let _ = charge_once(&m)
    var args: [1]i64 = zero
    args[0] = 50i64
    let (_, call_error) = mock.call(&m, CHARGE, args[0..])
    if call_error != mock.Unexpected { ret 20i32 }
    let want = "unexpected call: charge(50)\n  wanted: charge(equal to 100) (0 of 1 calls used)\n    argument 0 was 50\nmissing call: charge(equal to 100) expected at least 1 time(s), called 0\n"
    if !report_is(&m, want) { ret 21i32 }
    // An unrelated method is unexpected with no `wanted` lines of its own.
    let (_, other_error) = mock.call(&m, REFUND, zero)
    if other_error != mock.Unexpected { ret 22i32 }
    ret 0i32
}

fn checks_times() -> i32 {
    var exps: [8]mock.Expectation = zero
    var calls: [16]mock.Call = zero
    var m = mock.mock(exps[0..], calls[0..])
    let (idx, expect_error) = mock.expect(&m, REFUND, "refund")
    if expect_error != ok { ret 30i32 }
    var scripted: [2]i64 = zero
    scripted[0] = 10i64
    scripted[1] = 20i64
    if mock.returns_list(&m, idx, scripted[0..]) != ok { ret 31i32 }
    if mock.times(&m, idx, 2u32, 3u32) != ok { ret 32i32 }
    var one: [1]i64 = zero
    one[0] = 1i64
    let (v1, e1) = mock.call(&m, REFUND, one[0..])
    if e1 != ok || v1 != 10i64 { ret 33i32 }
    if clean(&m) { ret 34i32 }
    let (v2, e2) = mock.call(&m, REFUND, one[0..])
    if e2 != ok || v2 != 20i64 { ret 35i32 }
    if !clean(&m) { ret 36i32 }
    let (v3, e3) = mock.call(&m, REFUND, one[0..])
    if e3 != ok || v3 != 20i64 { ret 37i32 }
    let (_, e4) = mock.call(&m, REFUND, one[0..])
    if e4 != mock.Unexpected { ret 38i32 }
    if mock.call_count(&m, REFUND) != 4usize || mock.call_count(&m, CHARGE) != 0usize { ret 39i32 }
    ret 0i32
}

fn checks_stub_and_missing() -> i32 {
    var exps: [8]mock.Expectation = zero
    var calls: [16]mock.Call = zero
    var m = mock.mock(exps[0..], calls[0..])
    let (_, allow_error) = mock.allow(&m, AUDIT, "audit", 42i64)
    if allow_error != ok { ret 40i32 }
    if !clean(&m) { ret 41i32 }
    var i = 0usize
    while i < 5usize {
        let (v, e) = mock.call(&m, AUDIT, zero)
        if e != ok || v != 42i64 { ret 42i32 }
        i += 1usize
    }
    if !clean(&m) { ret 43i32 }
    if mock.call_count(&m, AUDIT) != 5usize { ret 44i32 }
    // An expectation never met is reported by name and bound.
    var more: [8]mock.Expectation = zero
    var more_calls: [4]mock.Call = zero
    var n = mock.mock(more[0..], more_calls[0..])
    let (idx, expect_error) = mock.expect(&n, REFUND, "refund")
    if expect_error != ok { ret 45i32 }
    if mock.with_arg(&n, idx, 0usize, match.gt(5i64)) != ok { ret 46i32 }
    if mock.times(&n, idx, 3u32, 5u32) != ok { ret 47i32 }
    if !report_is(&n, "missing call: refund(greater than 5) expected at least 3 time(s), called 0\n") { ret 48i32 }
    ret 0i32
}

fn checks_order() -> i32 {
    var exps: [8]mock.Expectation = zero
    var calls: [16]mock.Call = zero
    var m = mock.mock(exps[0..], calls[0..])
    let (audit_idx, audit_error) = mock.expect(&m, AUDIT, "audit")
    if audit_error != ok { ret 50i32 }
    let (charge_idx, charge_error) = mock.expect(&m, CHARGE, "charge")
    if charge_error != ok { ret 51i32 }
    if mock.in_order(&m, audit_idx) != ok || mock.in_order(&m, charge_idx) != ok { ret 52i32 }
    var args: [1]i64 = zero
    args[0] = 5i64
    // charge before audit: answered, but out of order.
    let (_, early) = mock.call(&m, CHARGE, args[0..])
    if early != mock.Order { ret 53i32 }
    let (_, audited) = mock.call(&m, AUDIT, zero)
    if audited != ok { ret 54i32 }
    if !report_is(&m, "call out of order: charge(5) came before an earlier expected call was met\n") { ret 55i32 }
    // In order is clean.
    var exps2: [8]mock.Expectation = zero
    var calls2: [16]mock.Call = zero
    var n = mock.mock(exps2[0..], calls2[0..])
    let (a2, ae) = mock.expect(&n, AUDIT, "audit")
    let (c2, ce) = mock.expect(&n, CHARGE, "charge")
    if ae != ok || ce != ok { ret 56i32 }
    if mock.in_order(&n, a2) != ok || mock.in_order(&n, c2) != ok { ret 57i32 }
    let (_, first) = mock.call(&n, AUDIT, zero)
    let (_, second) = mock.call(&n, CHARGE, args[0..])
    if first != ok || second != ok || !clean(&n) { ret 58i32 }
    ret 0i32
}

fn checks_spy_and_limits() -> i32 {
    var exps: [2]mock.Expectation = zero
    var calls: [2]mock.Call = zero
    var m = mock.mock(exps[0..], calls[0..])
    let (_, a) = mock.expect(&m, CHARGE, "charge")
    let (_, b) = mock.expect(&m, REFUND, "refund")
    if a != ok || b != ok { ret 60i32 }
    let (_, full) = mock.expect(&m, AUDIT, "audit")
    if full != mock.Full { ret 61i32 }
    if mock.with_arg(&m, 5usize, 0usize, match.anything()) != mock.BadIndex { ret 62i32 }
    if mock.with_arg(&m, 0usize, 4usize, match.anything()) != mock.BadIndex { ret 63i32 }
    var args: [3]i64 = zero
    args[0] = 1i64
    args[1] = 2i64
    args[2] = 3i64
    let (_, c1) = mock.call(&m, CHARGE, args[0..])
    let (_, c2) = mock.call(&m, REFUND, args[0..2usize])
    let (_, c3) = mock.call(&m, REFUND, zero)
    if c1 != ok || c2 != ok || c3 != mock.Full { ret 64i32 }
    // The spy log keeps arguments and the expectation each call matched.
    if m.calls[0].nargs != 3usize || m.calls[0].args[2] != 3i64 || m.calls[0].matched != 0i64 { ret 65i32 }
    if m.calls[1].nargs != 2usize || m.calls[1].matched != 1i64 { ret 66i32 }
    ret 0i32
}

fn checks_assert() -> i32 {
    var exps: [4]mock.Expectation = zero
    var calls: [4]mock.Call = zero
    var m = mock.mock(exps[0..], calls[0..])
    var buf: [256]u8 = zero
    if mock.assert_verified(&m, buf[0..]) != ok { ret 70i32 }
    let (_, e) = mock.expect(&m, AUDIT, "audit")
    if e != ok { ret 71i32 }
    if mock.assert_verified(&m, buf[0..]) != test.Failed { ret 72i32 }
    if !str.eq(test.current.message, "missing call: audit() expected at least 1 time(s), called 0\n") { ret 73i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var code = checks_basic()
    if code == 0i32 { code = checks_arguments() }
    if code == 0i32 { code = checks_times() }
    if code == 0i32 { code = checks_stub_and_missing() }
    if code == 0i32 { code = checks_order() }
    if code == 0i32 { code = checks_spy_and_limits() }
    if code == 0i32 { code = checks_assert() }
    if code != 0i32 { os.exit(code) }
    ret ok
}
