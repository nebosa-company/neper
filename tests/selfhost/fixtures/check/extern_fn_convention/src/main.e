// A struct by value is where the C convention and neper's part (D1676), so there a
// function's convention is its type's: a neper `fn` taking a `Key` is not an
// `extern fn(Key)`, and C calling it through one would pass the bits it reads as an address.
type Key = struct { k: i64 }
type Callback = extern fn(Key) -> i64

fn own(k: Key) -> i64 { ret k.k }

fn main() -> err {
    let f: Callback = own
    if f(Key { k: 1i64 }) == 0i64 { ret ok }
    ret ok
}
