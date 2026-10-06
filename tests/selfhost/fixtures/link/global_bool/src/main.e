// A module-scope `var` of type `bool` carries its initialiser's folded bit: `true`
// is stored as 1 and `false` as 0, the way an integer global stores its value, so a
// read before any assignment sees the declared value and not a zero fill (D2136).
var enabled: bool = true
var disabled: bool = false

fn main() -> i64 {
    if !enabled { ret 1i64 }
    if disabled { ret 2i64 }
    enabled = false
    disabled = true
    if enabled { ret 3i64 }
    if !disabled { ret 4i64 }
    ret 0i64
}
