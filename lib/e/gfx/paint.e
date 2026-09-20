// Colors and brushes with nothing that rasterises. A `Color` is linear-light RGBA in
// `0..1`, straight alpha unless it came through `premultiply`; `srgb8` applies the
// sRGB transfer (the 0.04045 knee and the 2.4 power) to the three channels and scales
// alpha, so an 8-bit sRGB pixel becomes the linear value compositing wants. `validate`
// is the one check a brush gets: every channel in `0..1`, gradient stops borrowed, at
// least one, offsets in `0..1` and non-decreasing, a radial radius non-negative.

use e.gfx.geometry

type Color = struct { red: f32, green: f32, blue: f32, alpha: f32 }
type Blend = enum u8 { SourceOver, Source, DestinationOver, Multiply, Screen, Overlay, Darken, Lighten }
type StrokeCap = enum u8 { Butt, Round, Square }
type StrokeJoin = enum u8 { Miter, Round, Bevel }
type Stroke = struct { width: f32, cap: StrokeCap, join: StrokeJoin, miter_limit: f32 }
type Stop = struct { offset: f32, color: Color }
type Brush = union enum u8 { Solid: Color, Linear: LinearGradient, Radial: RadialGradient }
type LinearGradient = struct { start: geometry.Point, end: geometry.Point, stops: []const Stop }
type RadialGradient = struct { center: geometry.Point, radius: f32, stops: []const Stop }
error Invalid

fn rgba(red: f32, green: f32, blue: f32, alpha: f32) -> Color {
    ret Color { red: red, green: green, blue: blue, alpha: alpha }
}

// The sRGB electro-optical transfer: linear below the knee, a 2.4 power above it.
fn linear_of(byte: u8) -> f32 {
    let c = f32(byte) / 255.0
    if c <= 0.04045 { ret c / 12.92 }
    ret pow24((c + 0.055) / 1.055)
}

// x^2.4 as x^2 * x^0.4, the fractional power by Newton on y^5 = x^2 from 1, which
// walks down to the root -- plain arithmetic, no transcendental library behind a colour.
fn pow24(x: f32) -> f32 {
    if x <= 0.0 { ret 0.0 }
    let square = x * x
    var y: f32 = 1.0
    var i = 0usize
    while i < 40usize {
        let y4 = y * y * y * y
        y = y - (y4 * y - square) / (5.0 * y4)
        i += 1usize
    }
    ret square * y
}

fn srgb8(red: u8, green: u8, blue: u8, alpha: u8) -> Color {
    ret Color { red: linear_of(red), green: linear_of(green), blue: linear_of(blue), alpha: f32(alpha) / 255.0 }
}

fn premultiply(color: Color) -> Color {
    ret Color { red: color.red * color.alpha, green: color.green * color.alpha, blue: color.blue * color.alpha, alpha: color.alpha }
}

fn unit(v: f32) -> bool {
    ret v >= 0.0 && v <= 1.0
}

fn color_ok(c: Color) -> bool {
    ret unit(c.red) && unit(c.green) && unit(c.blue) && unit(c.alpha)
}

fn stops_ok(stops: []const Stop) -> bool {
    if stops.len == 0usize { ret false }
    var previous: f32 = 0.0
    var i = 0usize
    while i < stops.len {
        if !unit(stops[i].offset) || stops[i].offset < previous || !color_ok(stops[i].color) { ret false }
        previous = stops[i].offset
        i += 1usize
    }
    ret true
}

fn validate(brush: *const Brush) -> err {
    switch *brush {
    case .Solid as color:
        if !color_ok(color) { ret Invalid }
    case .Linear as linear:
        if !stops_ok(linear.stops) { ret Invalid }
        if linear.start.x != linear.start.x || linear.end.x != linear.end.x { ret Invalid }
    case .Radial as radial:
        if !stops_ok(radial.stops) || radial.radius < 0.0 { ret Invalid }
    }
    ret ok
}
