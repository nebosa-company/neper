// Abandoned generators park their threads on event words inside the realm's arena. A host that resets the arena between
// realms must release them first (`shutdown_generators`), or a later generator whose event lands at the same address wakes
// a stale thread. Each realm here abandons two suspended generators, shuts them down and resets the arena.
use e.js.interp as js
use e.js.realm as realm
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let base = mem.mark(a)
    var round = 0u32
    while round < 80u32 {
        let (it, re) = realm.new_realm(a)
        if re != ok { os.exit(1) }
        it.quiet = true
        let (v, e) = realm.run(it, "function* g() { yield 1; yield 2 } var x = g(); x.next(); var y = g(); y.next(); y.next();")
        if e != ok { os.exit(2) }
        js.shutdown_generators(it)
        if it.gens.len != 0usize { os.exit(3) }
        mem.reset(a, base)
        round += 1u32
    }
    ret ok
}
