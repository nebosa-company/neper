// A type without a declared `eq` (D494, H14): `main`'s `same[dep.Colour]` takes the
// supplied rule, and the day this module declares `colour_eq` the instance must be
// rebuilt to select it -- the absence is an edge.
type Colour = enum u8 { Red, Green }

fn pick() -> Colour {
    ret .Red
}
