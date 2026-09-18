type Token = resource struct { value: usize }
type Choice = union enum u8 { Empty, Some: Token }

// A tagged union containing an affine payload is affine as a whole (D612).
fn run() {
    let token = Token { value: 1usize }
    let choice = Choice { Some: token }
    let moved = choice
    let old_tag = choice.tag
}
