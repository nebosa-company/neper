// Abandoned generators park their threads on event words inside the realm's arena. A host that resets the arena between
// realms must release them first (`shutdown_generators`), or a later generator whose event lands at the same address wakes
// a stale thread. Each realm here abandons two suspended generators, shuts them down and resets the arena.
use e.js.interp as js
use e.js.lex
use e.js.realm as realm
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // U+0378 is unassigned, while nearby U+0377 is an assigned Greek letter.
    if lex.id_start_cp(888u32) || lex.id_part_cp(888u32) || !lex.id_start_cp(887u32) || !lex.id_part_cp(887u32) { os.exit(4i32) }
    let base = mem.mark(a)
    var round = 0u32
    while round < 80u32 {
        let (it, re) = realm.new_realm(a)
        if re != ok { os.exit(1) }
        it.quiet = true
        // A continuation byte is not an IdentifierStart or IdentifierPart by itself.
        let (bad_start, bad_start_error) = realm.run(it, "\x80 = 1")
        if bad_start_error == ok { os.exit(5) }
        let (bad_part, bad_part_error) = realm.run(it, "name\x80 = 1")
        if bad_part_error == ok { os.exit(6) }
        let (greek, greek_error) = realm.run(it, "\xCE\xB1 = 1")
        if greek_error != ok { os.exit(7) }
        let (v, e) = realm.run(it, "function* g() { yield 1; yield 2 } var x = g(); x.next(); var y = g(); y.next(); y.next();")
        if e != ok { os.exit(2) }
        js.shutdown_generators(it)
        if it.gens.len != 0usize { os.exit(3) }
        mem.reset(a, base)
        round += 1u32
    }
    ret ok
}
