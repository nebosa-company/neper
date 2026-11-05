// JS early errors: an escaped "use strict" is not a directive (#820), duplicate
// `__proto__` after a shorthand property is rejected (#821), and mixing `??` with
// `||`/`&&` is rejected unless the logical operand is parenthesised (#822).
// Each check has its own exit code.
use e.io
use e.js.realm as realm
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, realm_error) = realm.new_realm(a)
    if realm_error != ok { os.exit(90i32) }
    // #820: the cooked text is "use strict" but the spelling is escaped, so sloppy mode
    // (and `with`) stays valid; a literal directive still enables strict mode.
    let (_, e1) = realm.run(it, "\"use\\x20strict\"; with({}) {}")
    if e1 != ok { os.exit(1i32) }
    let (_, e2) = realm.run(it, "\"use strict\"; with({}) {}")
    if e2 == ok { os.exit(2i32) }
    // #821: a shorthand property must not hide later duplicate __proto__ fields.
    let (_, e3) = realm.run(it, "var x = 1; ({x, __proto__: 1, __proto__: 2})")
    if e3 == ok { os.exit(3i32) }
    let (_, e4) = realm.run(it, "var x = 1; ({x, a: 1, b: 2})")
    if e4 != ok { os.exit(4i32) }
    // #822: mixed forms are rejected; a parenthesised logical operand is accepted.
    let (_, e5) = realm.run(it, "1 ?? 2 || 3")
    if e5 == ok { os.exit(5i32) }
    let (_, e6) = realm.run(it, "1 && 2 ?? 3")
    if e6 == ok { os.exit(6i32) }
    let (_, e7) = realm.run(it, "(1 || 2) ?? 3")
    if e7 != ok { os.exit(7i32) }
    try io.print("audit js parse depth ok")
    ret ok
}

