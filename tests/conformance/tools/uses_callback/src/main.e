// A function taken as a value (D511, H17): `twice` is bound to a local and passed
// as an argument, and called only through `apply`'s parameter. Its uses are the two
// sites where its name is a value; the call through `f` is counted as one indirect
// call no name can trace; a rename plan rewrites both sites and the declaration.
use e.os

fn twice(n: usize) -> usize {
    ret n + n
}

fn apply(f: fn(usize) -> usize, n: usize) -> usize {
    ret f(n)
}

fn main() -> err {
    let step = twice
    os.exit(i32(apply(step, 3usize) + apply(twice, 1usize)))
    ret ok
}
