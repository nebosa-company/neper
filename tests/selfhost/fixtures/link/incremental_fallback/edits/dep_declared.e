// The same module declaring the protocol function the supplied rule stood in for.
type Colour = enum u8 { Red, Green }

fn pick() -> Colour {
    ret .Red
}

fn colour_eq(x: Colour, y: Colour) -> bool {
    ret false
}
