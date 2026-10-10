// Container query evaluation (L040), after Vaper's `css/container_query.dart`: a condition tree of `and`, `or`, `not`, an
// unknown leaf and size features (`width`, `height`, `aspect-ratio`, `orientation`) evaluated three-valued, Kleene
// style, against a container whose width or height may not be known. A query matches only when it is definitely true;
// an unknown (a feature the container does not size, an aspect ratio over a zero height, a condition the parser could
// not read) stays unknown through `not` and through `and` or `or` unless the other branch decides.
//
// An equality feature uses the half-pixel tolerance `@media (width: ...)` uses, and a relative one of a thousandth for
// float ratios.

use e.math

type Tri = enum u8 { False, True, Unknown }

type CondKind = enum u8 { And, Or, Not, Unknown, Feature }

type FeatureKind = enum u8 { Width, Height, AspectRatio, OrientationPortrait, OrientationLandscape }

type Op = enum u8 { Lt, Le, Gt, Ge, Eq }

// `parts` holds the operands of `And`/`Or` and the one operand of `Not`; `feature`, `op` and `value` the leaf.
type Condition = struct { kind: CondKind, parts: []const Condition, feature: FeatureKind, op: Op, value: f64 }

// A container's size: a dimension that is not known is absent.
type Size = struct { has_width: bool, width: f64, has_height: bool, height: f64 }

fn unknown_condition() -> Condition {
    ret Condition { kind: .Unknown, parts: zero, feature: .Width, op: .Eq, value: 0.0f64 }
}

fn compare(c: Condition, actual: f64) -> bool {
    switch c.op {
    case .Lt:
        ret actual < c.value
    case .Le:
        ret actual <= c.value
    case .Gt:
        ret actual > c.value
    case .Ge:
        ret actual >= c.value
    case .Eq:
        if math.abs[f64](actual - c.value) < 0.5f64 { ret true }
        ret c.value != 0.0f64 && math.abs[f64](actual / c.value - 1.0f64) < 0.001f64
    }
}

fn tri(b: bool) -> Tri {
    if b { ret .True }
    ret .False
}

fn evaluate(c: Condition, size: Size) -> Tri {
    switch c.kind {
    case .And:
        var unknown = false
        var at = 0usize
        while at < c.parts.len {
            let v = evaluate(c.parts[at], size)
            if v == .False { ret .False }
            if v == .Unknown { unknown = true }
            at += 1usize
        }
        if unknown { ret .Unknown }
        ret .True
    case .Or:
        var unknown = false
        var at = 0usize
        while at < c.parts.len {
            let v = evaluate(c.parts[at], size)
            if v == .True { ret .True }
            if v == .Unknown { unknown = true }
            at += 1usize
        }
        if unknown { ret .Unknown }
        ret .False
    case .Not:
        if c.parts.len == 0usize { ret .Unknown }
        let v = evaluate(c.parts[0], size)
        if v == .Unknown { ret .Unknown }
        ret tri(v == .False)
    case .Unknown:
        ret .Unknown
    case .Feature:
        switch c.feature {
        case .Width:
            if !size.has_width { ret .Unknown }
            ret tri(compare(c, size.width))
        case .Height:
            if !size.has_height { ret .Unknown }
            ret tri(compare(c, size.height))
        case .AspectRatio:
            if !size.has_width || !size.has_height { ret .Unknown }
            if size.height <= 0.0f64 { ret .Unknown }
            ret tri(compare(c, size.width / size.height))
        case .OrientationPortrait:
            if !size.has_width || !size.has_height { ret .Unknown }
            ret tri(size.height >= size.width)
        case .OrientationLandscape:
            if !size.has_width || !size.has_height { ret .Unknown }
            ret tri(size.width > size.height)
        }
    }
}

// Whether the condition reads the block axis (height, aspect ratio or orientation), so the container needs `size`.
fn uses_block_axis(c: Condition) -> bool {
    switch c.kind {
    case .And, .Or, .Not:
        var at = 0usize
        while at < c.parts.len {
            if uses_block_axis(c.parts[at]) { ret true }
            at += 1usize
        }
        ret false
    case .Unknown:
        ret false
    case .Feature:
        ret c.feature != .Width
    }
}

// A query matches when its condition is definitely true.
fn matches(c: Condition, size: Size) -> bool { ret evaluate(c, size) == .True }
