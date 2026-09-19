// Every pointer-bearing field of the returned carrier retains the declared input.
type Views = struct { head: []const u8, tail: []const u8 }

@borrows("source")
fn views(source: []const u8) -> Views {
    let result = Views { head: source, tail: source[1usize..] }
    ret result
}

fn main() {}
