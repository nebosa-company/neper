// Assertions. Each answers `ok` or `Failed` and nothing else: discovery, isolation and
// reporting belong to `neper test`, which is what the fence says and what the dependency list
// enforces -- nothing here can print. The message is what `neper test` will show for a failed
// assertion once the trap protocol carries it (spec 11); until then it is accepted and the
// error is the whole report, which is honest about what this module can do on its own.
//
// The plan lets this module use `e.math`, `e.meta` and `e.str`, and it uses none of them yet:
// `near` wants only a sign test, and `eq` wants only the comparison the language supplies.

error Failed

fn assert(cond: bool, msg: str) -> err {
    if cond { ret ok }
    ret Failed
}

// Equality is the type's own: section 9 rule 4 supplies `eq` for every scalar, slice, array
// and aggregate that does not declare one, and a type that does is compared the way it asked.
// `T.eq` is that protocol; `==` is the operator, which the language keeps to the scalars.
fn eq[T: type](a: T, b: T, msg: str) -> err {
    if T.eq(a, b) { ret ok }
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
    ret Failed
}

fn fail(msg: str) -> err {
    ret Failed
}
