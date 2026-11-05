// `e.js.b_misc` and `e.js.b_json` audit: AggregateError is constructor-only, JSON.parse keeps an
// escaped lone surrogate as a code unit (round-tripping through JSON.stringify), and
// Object.groupBy runs its callback as the iterator advances and closes the iterator when the
// callback throws.
use e.js.interp as js
use e.js.realm as realm
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, re) = realm.new_realm(a)
    if re != ok { os.exit(1i32) }
    it.quiet = true
    // 805: calling AggregateError without `new` is a TypeError.
    let (agg, agge) = realm.run(it, "var agg_ok = false; try { AggregateError([]) } catch (e) { agg_ok = e instanceof TypeError } agg_ok")
    if agge != ok || !js.to_boolean(agg) { os.exit(1i32) }
    // 804: JSON.parse preserves an escaped lone high surrogate; stringify escapes it back.
    let (surrogate, surrogate_error) = realm.run(it, "var s = JSON.parse('\"\\\\uD800\"'); s.length === 1 && s.charCodeAt(0) === 55296 && JSON.stringify(s) === '\"\\\\ud800\"'")
    if surrogate_error != ok || !js.to_boolean(surrogate) { os.exit(2i32) }
    // 806: the callback runs between generator resumptions, and a throwing callback closes the
    // iterator.
    let order = "var order_log = []; function* g() { order_log.push('y1'); yield 1; order_log.push('y2'); yield 2 } Object.groupBy(g(), function (v) { order_log.push('cb' + v); return 'k' }); var order_ok = order_log.join(',') === 'y1,cb1,y2,cb2'; var closed = false; var it2 = { [Symbol.iterator]: function () { return this }, next: function () { this.n = (this.n || 0) + 1; return { value: this.n, done: this.n > 2 } }, return: function () { closed = true; return {} } }; var threw = false; try { Object.groupBy(it2, function () { throw new Error('x') }) } catch (e) { threw = true } order_ok && threw && closed"
    let (grouped, grouped_error) = realm.run(it, order)
    if grouped_error != ok || !js.to_boolean(grouped) { os.exit(3i32) }
    ret ok
}
