// Assertions. Each answers `ok` or `Failed` and nothing else: discovery, isolation and
// reporting belong to `neper test`, which is what the fence says and what the dependency list
// enforces -- nothing here can print. A failed assertion's message goes in `current`, the
// running test's record (spec 13, Report), which the synthesized root reads after the test
// and `neper test` reports as the record's `message` (T005).
//
// The plan lets this module use `e.math`, `e.meta` and `e.str`, and it uses none of them yet:
// `near` wants only a sign test, and `eq` wants only the comparison the language supplies.

error Failed

// The running test's record: the message of the assertion that failed it. Spec 13 has the
// root point a `*Record` here before each test; a test is a process of its own (D240), so
// the record is this one slot, read by the root after the test returns. Outside a test root
// nothing reads it. The library's one hidden state, as the spec allows.
type Record = struct { message: str }

var current: Record = zero

fn assert(cond: bool, msg: str) -> err {
    if cond { ret ok }
    current.message = msg
    ret Failed
}

// Equality is the type's own: section 9 rule 4 supplies `eq` for every scalar, slice, array
// and aggregate that does not declare one, and a type that does is compared the way it asked.
// `T.eq` is that protocol; `==` is the operator, which the language keeps to the scalars.
fn eq[T: type](a: T, b: T, msg: str) -> err {
    if T.eq(a, b) { ret ok }
    current.message = msg
    ret Failed
}

// Close enough by either tolerance: within `abs` of each other, or within `rel` of the larger
// magnitude. A NaN on either side is near nothing, which the comparisons say on their own. The
// magnitudes are taken inline because the fence is the whole surface and admits no helper.
fn near(a: f64, b: f64, abs: f64, rel: f64, msg: str) -> err {
    var gap = a - b
    if gap < 0.0f64 { gap = -gap }
    if gap <= abs { ret ok }
    var scale = a
    if scale < 0.0f64 { scale = -scale }
    var other = b
    if other < 0.0f64 { other = -other }
    if other > scale { scale = other }
    if gap <= rel * scale { ret ok }
    current.message = msg
    ret Failed
}

fn fail(msg: str) -> err {
    current.message = msg
    ret Failed
}
