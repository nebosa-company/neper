// JS string and RegExp audit: named replacement keeps a literal U+0001 distinct from
// its own expansion slots, the substring searches compare UTF-16 code units so a lone
// surrogate matches one half of a pair, fromCharCode/fromCodePoint convert every
// argument, and a RegExp over a long subject converts through the cached unit path.
// Each check exits with its own code.
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
    // 809: a literal U+0001 in the replacement is copied, not taken for the slot of
    // the first named capture.
    if !check(it, "var r = /(?<a>A)(?<b>B)/; 'AB'.replace(r, '$<b>\\u0001$<a>')", "B\x01A") { os.exit(1i32) }
    // 811: indexOf finds a lone surrogate inside a surrogate pair (units 0 and 1).
    if !check(it, "var p = String.fromCharCode(0xD83D, 0xDE00); String(p.indexOf(String.fromCharCode(0xD83D))) + '|' + String(p.indexOf(String.fromCharCode(0xDE00)))", "0|1") { os.exit(2i32) }
    // 811: startsWith/endsWith compare code units at the pair boundary.
    if !check(it, "var p = String.fromCharCode(0xD83D, 0xDE00); String(p.startsWith(String.fromCharCode(0xD83D))) + String(p.endsWith(String.fromCharCode(0xDE00)))", "truetrue") { os.exit(3i32) }
    // 811: splitting at the low half of a pair leaves the high half in the first part.
    if !check(it, "var p = 'a' + String.fromCharCode(0xD83D, 0xDE00) + 'b'; var q = p.split(String.fromCharCode(0xDE00)); String(q.length) + '|' + String(q[0].charCodeAt(1))", "2|55357") { os.exit(4i32) }
    // 812: every argument is converted, not only the first 64.
    if !check(it, "String.fromCharCode(65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65).length", "70") { os.exit(5i32) }
    if !check(it, "String.fromCodePoint(65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65,65).length", "65") { os.exit(6i32) }
    // 810: the unit conversion of a long subject (the cache path) still matches a
    // supplementary scalar; an allocation failure now reaches the caller instead of
    // compiling an empty pattern.
    if !check(it, "var r = new RegExp(String.fromCharCode(0xD83C, 0xDF89)); String(r.test('x'.repeat(130) + String.fromCharCode(0xD83C, 0xDF89)))", "true") { os.exit(7i32) }
    // A pattern that does not match must stay a pattern: if a unit conversion failed and
    // reported an empty source, this would compile the empty (always-matching) pattern.
    if !check(it, "String(new RegExp('a').test('b'))", "false") { os.exit(8i32) }
    ret ok
}
