use e.io
use e.mem
use e.text.regex

fn main(a: *mem.Arena, args: []str) -> err {
    let plain = regex.Options { case_insensitive: false, multiline: false, dot_matches_newline: false }

    // A doubled word, "the the": a backreference, so only the backtracker takes it.
    let pattern = "\\b(\\w+) \\1\\b"
    let (_, refused) = regex.compile(a, pattern, plain)
    if refused == regex.NeedsBacktracking {
        try io.printf["compile: {}\n"]("needs the backtracker")
    }
    let doubled = try regex.compile_backtracking(a, pattern, plain)
    let text = "it was the the best of times"
    let (hit, found) = regex.find(&doubled, text, 0usize)
    if found {
        let word: str = text[hit.start..hit.end]
        try io.printf["doubled word at {}..{}: {}\n"](hit.start, hit.end, word)
    }

    // A price not preceded by "-": lookbehind, lookahead and a named group.
    let price = try regex.compile_backtracking(a, "(?<!-)\\$(?<amount>\\d+)(?=\\.\\d\\d)", plain)
    let line = "refund -$15.00, charge $42.50"
    let (c, matched, capture_error) = regex.captures(a, &price, line, 0usize)
    if capture_error != ok { ret capture_error }
    let (amount, named) = regex.group_index(&price, "amount")
    if matched && named {
        let g = c.groups[amount - 1usize]
        let digits: str = line[g.start..g.end]
        try io.printf["charged amount: {}\n"](digits)
    }

    // Swap "last, first" with the ordinary replace_all; it works on either engine.
    let swap = try regex.compile_backtracking(a, "(\\w+), (\\w+)", plain)
    let swapped = try regex.replace_all(a, &swap, "Lovelace, Ada; Hopper, Grace", "$2 $1")
    try io.printf["{}\n"](swapped)

    // A pattern that backtracks exponentially stops on its step budget instead of hanging.
    let evil = try regex.compile_backtracking(a, "(a+)+$", plain)
    let subject = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab"
    if !regex.is_match(&evil, subject) && regex.last_error(&evil) == regex.TooManySteps {
        try io.printf["(a+)+$: gave up after its step budget\n"]()
    }
    ret ok
}
