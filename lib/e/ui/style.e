// Style values for the UI tree: plain immutable structs a caller builds from
// `defaults()` and hands to layout and paint. `validate` is the single guard --
// every length finite and, for padding and the size bounds, non-negative; a
// margin may be negative; a `Px` minimum never above a `Px` maximum; opacity in
// `[0, 1]`; the background brush as `paint.validate` sees it. There is no
// cascade, selector or inheritance: a style is what its fields say.

use e.gfx.paint

type Length = union enum u8 { Auto, Px: f32, Percent: f32, Flex: f32 }
type EdgeLengths = struct { left: Length, top: Length, right: Length, bottom: Length }
type Display = enum u8 { Flex, Grid, Stack, None }
type Position = enum u8 { Flow, Absolute }
type Overflow = enum u8 { Visible, Clip, Scroll }
type Style = struct { display: Display, position: Position, width: Length, height: Length, min_width: Length, min_height: Length, max_width: Length, max_height: Length, margin: EdgeLengths, padding: EdgeLengths, background: paint.Brush, opacity: f32, overflow: Overflow }
error Invalid

fn finite(v: f32) -> bool {
    ret v - v == 0.0
}

// A length's number when it has one; `Auto` answers zero and true.
fn amount(l: Length) -> (f32, bool) {
    switch l {
    case .Auto:
        ret (0.0, true)
    case .Px as v:
        ret (v, finite(v))
    case .Percent as v:
        ret (v, finite(v))
    case .Flex as v:
        ret (v, finite(v))
    }
    ret (0.0, false)
}

fn length_ok(l: Length, allow_negative: bool) -> bool {
    let (v, fin) = amount(l)
    if !fin { ret false }
    if !allow_negative && v < 0.0 { ret false }
    ret true
}

fn edges_ok(e: EdgeLengths, allow_negative: bool) -> bool {
    ret length_ok(e.left, allow_negative) && length_ok(e.top, allow_negative) && length_ok(e.right, allow_negative) && length_ok(e.bottom, allow_negative)
}

fn px_of(l: Length) -> (f32, bool) {
    switch l {
    case .Px as v:
        ret (v, true)
    case .Auto:
        ret (0.0, false)
    case .Percent as v:
        ret (v, false)
    case .Flex as v:
        ret (v, false)
    }
    ret (0.0, false)
}

fn defaults() -> Style {
    let none = Length { Px: 0.0 }
    let auto: Length = .Auto
    ret Style {
        display: .Flex,
        position: .Flow,
        width: auto,
        height: auto,
        min_width: auto,
        min_height: auto,
        max_width: auto,
        max_height: auto,
        margin: EdgeLengths { left: none, top: none, right: none, bottom: none },
        padding: EdgeLengths { left: none, top: none, right: none, bottom: none },
        background: paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, 0.0) },
        opacity: 1.0,
        overflow: .Visible,
    }
}

fn validate(value: *const Style) -> err {
    if !length_ok(value.width, false) || !length_ok(value.height, false) { ret Invalid }
    if !length_ok(value.min_width, false) || !length_ok(value.min_height, false) { ret Invalid }
    if !length_ok(value.max_width, false) || !length_ok(value.max_height, false) { ret Invalid }
    if !edges_ok(value.margin, true) || !edges_ok(value.padding, false) { ret Invalid }
    let (min_w, has_min_w) = px_of(value.min_width)
    let (max_w, has_max_w) = px_of(value.max_width)
    if has_min_w && has_max_w && min_w > max_w { ret Invalid }
    let (min_h, has_min_h) = px_of(value.min_height)
    let (max_h, has_max_h) = px_of(value.max_height)
    if has_min_h && has_max_h && min_h > max_h { ret Invalid }
    if !finite(value.opacity) || value.opacity < 0.0 || value.opacity > 1.0 { ret Invalid }
    if paint.validate(&value.background) != ok { ret Invalid }
    ret ok
}
