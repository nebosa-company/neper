// `index --json` (D232): the module and its module-scope declarations as symbol records,
// each with its signature, attributes and `///` documentation (D251), and the parameters,
// fields and members nested under a function or type (D258).
use e.mem
const K: i32 = 7i32
/// A pair of halves.
type Pair = struct {
    /// The left half.
    a: i32,
    b: i32,
}
type Colour = enum u8 { Red, Green }
/// A function type's entries are types, not parameters (D550).
type Hook = struct {
    run: fn(*mem.Arena, i32) -> err,
}
error Bad
var counter: i32 = 0i32
/// Adds two numbers.
/// A second line, joined to the first with LF.
fn add(x: i32, y: i32) -> i32 {
    ret x + y
}
extern fn clock() -> i64
/// Documentation sits above the attributes and still attaches.
@test
fn attributed(a: *mem.Arena) -> err {
    if add(1i32, 2i32) == 3i32 { ret ok }
    ret Bad
}
/// A blank line breaks attachment, so M has no documentation.

const M: i32 = 9i32
fn uses(pair: Pair) -> i32 {
    counter = pair.a
    let here = &counter
    let shade = Colour.Red
    let doubled = add(K, M)
    ret doubled
}
