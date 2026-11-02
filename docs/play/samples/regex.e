// e.text.regex is a Pike VM: no backtracking blow-up, leftmost-first matches.

use e.io
use e.mem
use e.text.regex

fn main(a: *mem.Arena, args: []str) -> err {
    let r = try regex.compile(a, "[a-z]+@[a-z]+\\.com", zero)
    let text: str = "write to ada@example.com or grace@navy.com today"

    var from: usize = 0
    var more = true
    while more {
        let (m, found) = regex.find(&r, text, from)
        if !found {
            more = false
            continue
        }
        try io.printf["match at {}..{}\n"](m.start, m.end)
        from = m.end
    }

    let hidden = try regex.replace_all(a, &r, text, "<hidden>")
    try io.printf["{}\n"](hidden)
    ret ok
}
