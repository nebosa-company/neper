// An unknown type name within two edits of a type in scope (D485, H09): the
// diagnostic sits on the name, names the nearest type and offers it as a `maybe`
// fix over the token, as an unknown value name has since D445.
type Colour = enum u8 { Red, Green }

fn shade() -> Colour {
    let c: Colr = .Red
    ret c
}

fn main() -> i32 {
    if shade() == .Red { ret 0i32 }
    ret 1i32
}
