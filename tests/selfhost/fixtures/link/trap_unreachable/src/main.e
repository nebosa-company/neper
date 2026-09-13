// `unreachable()`, section 11's one always-on builtin: a call that traps with kind
// `unreachable` and the optional `str` literal as its values, and that the checker
// counts as diverging -- `classify` ends in it rather than in a `ret`. The last argument
// picks the form: `message` reaches the literal form, `bare` the empty one, and anything
// else exits 0 through the ordinary path.
use e.mem
use e.str

fn classify(n: usize) -> u8 {
    if n < 3usize { ret u8(n) }
    unreachable("n past the table")
}

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    if str.eq(mode, "message") {
        let v = classify(args.len + 5usize)
        if v == 9u8 { ret ok }
    }
    if str.eq(mode, "bare") {
        unreachable()
    }
    let small = classify(args.len - 1usize)
    if small != 1u8 { ret ok }
    ret ok
}
