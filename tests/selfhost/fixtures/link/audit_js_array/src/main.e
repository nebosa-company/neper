// JS Array and Date audit: join stops at a cycle instead of recursing, construction
// keeps every argument, the callback helpers pass stack-backed argument slices, and
// Date.parse rejects ISO timezone offsets outside 00..23 / 00..59. Each check exits
// with its own code.
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, re) = realm.new_realm(a)
    if re != ok { os.exit(9i32) }
    it.quiet = true
    // 799: a self-reference and a nested cycle contribute empty strings, not recursion.
    if !check(it, "var a = []; a[0] = a; String(a.join('-'))", "") { os.exit(1i32) }
    if !check(it, "var b = []; b[0] = [b]; String(b.join())", "") { os.exit(2i32) }
    // 797: callback argument slices carry value, index and the array.
    if !check(it, "[10,20,30].map(function(v, i, arr) { return v + i + (arr.length === 3 ? 0 : 1000) }).join(',')", "10,21,32") { os.exit(3i32) }
    if !check(it, "[1,2,3].reduce(function(acc, v, i, arr) { return acc + v + i + (arr.length === 3 ? 0 : 1000) }, 0)", "9") { os.exit(4i32) }
    // 798: every constructor argument lands (allocation failure is not reachable here).
    if !check(it, "new Array(1,2,3).length + '|' + new Array(1,2,3)[2]", "3|3") { os.exit(5i32) }
    // 803: out-of-range ISO offsets are invalid; in-range offsets still shift the time.
    if !check(it, "String(isNaN(Date.parse('2020-01-01T00:00:00+99:99'))) + '|' + String(isNaN(Date.parse('2020-01-01T00:00:00-00:99')))", "true|true") { os.exit(6i32) }
    if !check(it, "String(Date.parse('2020-01-01T00:00:00+01:00') === Date.parse('2019-12-31T23:00:00Z'))", "true") { os.exit(7i32) }
    // 797: 2000 callback invocations must not leave one arena-allocated argument array each.
    let before = it.a.off
    if !check(it, "var q = []; for (var j = 0; j < 2000; j++) { q.push(j) } var t = 0; q.forEach(function(v) { t += v }); t", "1999000") { os.exit(8i32) }
    let spent = it.a.off - before
    if spent > 350000usize { os.exit(10i32) }
    ret ok
}
