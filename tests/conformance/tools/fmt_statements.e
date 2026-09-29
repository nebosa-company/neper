// `fmt` refuses what does not parse (T006): the grammar ends a statement at its line,
// so two on one line are the parser's E-SYNTAX-9999 at the second, and no layout is
// written -- inline braces or not.
fn main() {
    var a = 1usize
    var b = 2usize
    a = 3usize b = 4usize
    if a == b { a = 1usize b = 2usize }
}
