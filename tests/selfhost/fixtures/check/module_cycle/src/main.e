// `b` imports `main` back: E-MODULE-0002 at the module whose `use` closes the cycle (D215).
use b

fn main() { b.f() }
