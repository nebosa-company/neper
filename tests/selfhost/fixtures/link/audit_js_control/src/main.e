// Control/collection/atomics boundary checks through `e.js.realm`:
// Promise.allSettled's two per-input handlers share one already-called guard,
// Map/Set storage stays consistent, and Atomics.load/store take the same hub
// lock as the read-modify-write operations. Each check exits with its own code.
use e.js.interp as js
use e.js.realm as realm
use e.mem
use e.os
use e.str

fn check(it: *js.Interp, source: str, want: str) -> bool {
    let (v, e) = realm.run(it, source)
    if e != ok { ret false }
    let (s, se) = js.to_string(it, v)
    if se != ok { ret false }
    ret str.eq(s, want)
}

fn throws(it: *js.Interp, source: str) -> bool {
    let (v, e) = realm.run(it, source)
    ret e != ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, re) = realm.new_realm(a)
    if re != ok { os.exit(9i32) }
    it.quiet = true
    // 802: the first settlement of an input wins even when the thenable calls
    // both handlers (they share one guard). The result is read after the
    // microtask queue has run.
    let setup = "function C(ex) { var self = this; ex(function(v) { self.result = v; }, function(e) { self.reason = e; }); } C.resolve = function() { return { then: function(res, rej) { res('first'); rej('second'); } }; }; var c = Promise.allSettled.call(C, [1]);"
    let (sv, se) = realm.run(it, setup)
    if se != ok { os.exit(1i32) }
    let (logged, lge) = realm.run(it, "String(c.result[0].status) + ':' + String(c.result[0].value)")
    if lge != ok { os.exit(1i32) }
    let (text, te) = js.to_string(it, logged)
    if te != ok || !str.eq(text, "fulfilled:first") { os.exit(1i32) }
    // 801: Map and Set still behave after construction and failed lookups;
    // the allocation-failure rollback is not reachable through the public API.
    if !check(it, "(function() { var m = new Map(); m.set('a', 1); m.set('b', 2); m.set('a', 3); return String(m.get('a')) + ':' + String(m.size); })()", "3:2") { os.exit(2i32) }
    if !check(it, "(function() { var s = new Set([1, 2, 2, 3]); return String(s.size) + ':' + String(s.has(2)) + ':' + String(s.has(9)); })()", "3:true:false") { os.exit(2i32) }
    // 800: Atomics.load/store round-trip on a shared integer array. Indivisibility
    // against a concurrent agent is not observable in this single realm; the lock
    // is pinned by inspection.
    if !check(it, "(function() { var b = new SharedArrayBuffer(16); var a = new Int32Array(b); Atomics.store(a, 0, 41); Atomics.add(a, 0, 1); return String(Atomics.load(a, 0)); })()", "42") { os.exit(3i32) }
    if !check(it, "(function() { var b = new SharedArrayBuffer(8); var a = new BigInt64Array(b); Atomics.store(a, 0, 7n); return String(Atomics.load(a, 0)); })()", "7") { os.exit(3i32) }
    ret ok
}
