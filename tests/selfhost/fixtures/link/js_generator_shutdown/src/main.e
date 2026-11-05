// Abandoned generators park their threads on event words inside the realm's arena. A host that resets the arena between
// realms must release them first (`shutdown_generators`), or a later generator whose event lands at the same address wakes
// a stale thread. Each realm here abandons two suspended generators, shuts them down and resets the arena.
use e.js.interp as js
use e.js.lex
use e.js.realm as realm
use e.mem
use e.os
use e.str

// The reported line of the first token spelled `want_text`, or 0 when it never appears.
fn token_line(a: *mem.Arena, src: str, want_text: str) -> u32 {
    var lx = lex.new_lexer(a, src)
    while true {
        let (t, e) = lex.next_token(&lx)
        if e != ok { ret 0u32 }
        if t.kind == lex.T_EOF { ret 0u32 }
        if str.eq(t.text, want_text) { ret t.line }
    }
    ret 0u32
}

// A fresh realm with `source` run in it: the script's completion value and error.
fn run_fresh(a: *mem.Arena, source: str) -> (js.Value, err) {
    let (it, re) = realm.new_realm(a)
    if re != ok { ret (js.undefv(), re) }
    it.quiet = true
    let (v, e) = realm.run(it, source)
    ret (v, e)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 827: a RegExp literal uses the realm intrinsic, not the reassignable global binding.
    let (rx_value, rx_error) = run_fresh(a, "globalThis.RegExp = null; (/x/).test('x')")
    if rx_error != ok || !js.to_boolean(rx_value) { os.exit(10i32) }
    // 824: a proxy getPrototypeOf trap reporting the object itself cannot create a cycle.
    let (cycle_value, cycle_error) = run_fresh(a, "var o = {}; var p = new Proxy({}, { getPrototypeOf: function () { return o } }); var threw = false; try { Object.setPrototypeOf(o, p) } catch (e) { threw = e instanceof TypeError } threw")
    if cycle_error != ok || !js.to_boolean(cycle_value) { os.exit(11i32) }
    // 823: object rest excludes every explicit key, not only the first 64.
    let (kb, kb_error) = str.builder(a, 2048usize)
    if kb_error != ok { os.exit(12i32) }
    var kbv = kb
    try str.push(&kbv, "var o = {}; for (var i = 0; i < 70; i++) { o['k' + i] = i } var {")
    var kk = 0usize
    while kk < 65usize {
        if kk != 0usize { try str.push(&kbv, ",") }
        try str.push(&kbv, "k")
        try str.push_u64(&kbv, u64(kk))
        kk += 1usize
    }
    try str.push(&kbv, ", ...rest} = o; Object.keys(rest).length === 5 && rest.k65 === 65 && rest.k64 === undefined")
    let (rest_value, rest_error) = run_fresh(a, str.done(&kbv))
    if rest_error != ok || !js.to_boolean(rest_value) { os.exit(12i32) }
    // 825: closing a for-await over a sync iterator needs an object from return().
    let (ait, aie) = realm.new_realm(a)
    if aie != ok { os.exit(13i32) }
    ait.quiet = true
    let (_, for_await_error) = realm.run(ait, "var settled = false; var got_type_error = false; var bad = { [Symbol.iterator]: function () { return this }, next: function () { return { value: 1, done: false } }, return: function () { return 5 } }; (async function () { try { for await (var x of bad) { break } } catch (e) { got_type_error = e instanceof TypeError } settled = true })();")
    if for_await_error != ok { os.exit(13i32) }
    if js.run_jobs(ait) != ok { os.exit(13i32) }
    let (closed_value, closed_error) = realm.run(ait, "settled && got_type_error")
    if closed_error != ok || !js.to_boolean(closed_value) { os.exit(13i32) }
    // 826: one strings array per tagged-template call site and realm.
    let (cache_value, cache_error) = run_fresh(a, "var seen = null; var same = true; function tag(s) { if (seen === null) { seen = s } else { same = same && (s === seen) } return s } function f() { return tag`a` } f(); f(); same")
    if cache_error != ok || !js.to_boolean(cache_value) { os.exit(14i32) }
    // 836: CRLF inside a block comment is one line terminator; the token after it is line 3.
    let crlf_comment = "/* a\r\nb */\nzzz"
    if token_line(a, crlf_comment, "zzz") != 3u32 { os.exit(8i32) }
    // 837: CR, LS and PS in a substitution, plus a nested template holding LF: the token after
    // the template is line 6.
    let template = "`x${a\rb\xe2\x80\xa8c\xe2\x80\xa9d`y\nz`e}f`\nafter"
    if token_line(a, template, "after") != 6u32 { os.exit(9i32) }
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
