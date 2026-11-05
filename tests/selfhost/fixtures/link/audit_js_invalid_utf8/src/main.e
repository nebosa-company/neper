// Typed-array boundary checks driven through `e.js.realm`: explicit view
// lengths are ToIndex-validated without wrapping, options objects are
// type-checked, toLocaleString forwards its arguments to the element method,
// and subarray validates a detached/out-of-bounds receiver. Each check exits
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

fn throws(it: *js.Interp, source: str) -> bool {
    let (v, e) = realm.run(it, source)
    ret e != ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, re) = realm.new_realm(a)
    if re != ok { os.exit(9i32) }
    it.quiet = true
    // 813: an infinite or past-2^53 explicit length is a RangeError, a length
    // whose element-size product would overflow is one too, and NaN is 0.
    if !throws(it, "new Uint8Array(new ArrayBuffer(16), 0, Infinity)") { os.exit(1i32) }
    if !throws(it, "new Float64Array(new ArrayBuffer(16), 0, 2305843009213693952)") { os.exit(1i32) }
    if !check(it, "String(new Uint8Array(new ArrayBuffer(16), 0, NaN).length)", "0") { os.exit(1i32) }
    // 814: a primitive options value is a TypeError; undefined is the absent case.
    if !throws(it, "new ArrayBuffer(8, 5)") { os.exit(2i32) }
    if !throws(it, "new ArrayBuffer(8, null)") { os.exit(2i32) }
    if !check(it, "String(new ArrayBuffer(8, undefined).byteLength)", "8") { os.exit(2i32) }
    if !check(it, "String(new ArrayBuffer(8, {maxByteLength: 16}).maxByteLength)", "16") { os.exit(2i32) }
    // 815: the element toLocaleString sees the locales and options.
    if !check(it, "Number.prototype.toLocaleString = function(l, o) { return String(l) + '|' + String(o && o.style); }; new Uint8Array([1, 2]).toLocaleString('de-DE', {style: 'percent'})", "de-DE|percent,de-DE|percent") { os.exit(3i32) }
    // 816: subarray on a detached view throws.
    if !check(it, "var b = new ArrayBuffer(16, {maxByteLength: 16}); var ta = new Uint8Array(b, 0, 16); b.resize(0); var threw = false; try { ta.subarray(0); } catch (e) { threw = true; } String(threw)", "true") { os.exit(4i32) }
    ret ok
}
