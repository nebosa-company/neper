use e.mem
use e.os
use token

// A declared resource (D348): acquired, owed, released on every exit; a struct
// holding two, closed field by field; a borrowed token read but never released.
type Held = struct { first: token.Token, second: token.Token, label: str }

fn use_both(a: *mem.Arena) -> err {
    let first = try token.acquire(a)
    let (second, second_error) = token.acquire(a)
    if second_error != ok {
        let dropped = token.release(first)
        ret second_error
    }
    var held = Held { first: first, second: second, label: "pair" }
    let first_released = token.release(held.first)
    let second_released = token.release(held.second)
    if first_released != ok { ret first_released }
    ret second_released
}

fn peek(t: token.Token) -> usize {
    ret token.value(t)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let t = try token.acquire(a)
    defer let _ = token.release(t)
    if peek(t) != 1usize { ret os.Failed }
    try use_both(a)
    ret ok
}
