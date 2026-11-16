// Input that nests a hundred thousand levels deep is refused with an error by each recursive site of the JavaScript engine, not by
// a stack overflow: the parser (brackets), the evaluator (a long left-associative chain), JSON.stringify and Array.prototype.flat.
// A shallow input of the same shape still works.
use e.io
use e.js.realm as realm
use e.mem
use e.os
use e.str

fn run_ok(a: *mem.Arena, source: str) -> bool {
    let (it, realm_error) = realm.new_realm(a)
    if realm_error != ok { os.exit(90i32) }
    let (_, e) = realm.run(it, source)
    ret e == ok
}

fn repeat(a: *mem.Arena, piece: str, count: usize) -> str {
    let (b0, be) = str.builder(a, piece.len * count + 8usize)
    if be != ok { os.exit(91i32) }
    var b = b0
    var i = 0usize
    while i < count {
        if str.push(&b, piece) != ok { os.exit(92i32) }
        i += 1usize
    }
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let deep = 100000usize
    // the parser: nested parentheses
    let (open_deep, oe) = str.concat(a, repeat(a, "(", deep), "1")
    if oe != ok { os.exit(93i32) }
    let (parens_deep, pe) = str.concat(a, open_deep, repeat(a, ")", deep))
    if pe != ok { os.exit(93i32) }
    if run_ok(a, parens_deep) { os.exit(1i32) }
    let (open_few, ofe) = str.concat(a, repeat(a, "(", 100usize), "1")
    if ofe != ok { os.exit(93i32) }
    let (parens_few, pfe) = str.concat(a, open_few, repeat(a, ")", 100usize))
    if pfe != ok { os.exit(93i32) }
    if !run_ok(a, parens_few) { os.exit(2i32) }

    // the evaluator: 1+1+...+1
    let (chain_deep, cde) = str.concat(a, repeat(a, "1+", deep), "1")
    if cde != ok { os.exit(94i32) }
    if run_ok(a, chain_deep) { os.exit(3i32) }
    // a chain the parser accepts but the evaluator refuses: 1400 deep is past its limit, not past the stack
    let (chain_mid, cme) = str.concat(a, repeat(a, "1+", 1400usize), "1")
    if cme != ok { os.exit(94i32) }
    if run_ok(a, chain_mid) { os.exit(9i32) }
    let (chain_few, cfe) = str.concat(a, repeat(a, "1+", 200usize), "1")
    if cfe != ok { os.exit(94i32) }
    if !run_ok(a, chain_few) { os.exit(4i32) }

    // JSON.stringify and flat over arrays nested by a loop
    if run_ok(a, "var a = []; for (var i = 0; i < 100000; i++) { a = [a]; } JSON.stringify(a)") { os.exit(5i32) }
    if !run_ok(a, "var a = []; for (var i = 0; i < 100; i++) { a = [a]; } JSON.stringify(a)") { os.exit(6i32) }
    if run_ok(a, "var a = [1]; for (var i = 0; i < 100000; i++) { a = [a]; } a.flat(Infinity)") { os.exit(7i32) }
    if !run_ok(a, "var a = [1]; for (var i = 0; i < 100; i++) { a = [a]; } a.flat(Infinity)") { os.exit(8i32) }
    try io.print("js depth guards ok")
    ret ok
}
