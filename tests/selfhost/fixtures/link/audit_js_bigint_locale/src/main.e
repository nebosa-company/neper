// `e.js.intl` BCP 47 gaps, driven through `e.js.realm`: a 4-letter primary language
// subtag and an extlang must parse and canonicalize, a duplicate Unicode keyword is
// invalid rather than silently dropped, and the registered grandfathered tags map to
// their preferred values. Each check has its own exit code.
use e.js.interp as js
use e.js.realm as realm
use e.mem
use e.os
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, realm_error) = realm.new_realm(a)
    if realm_error != ok { os.exit(1i32) }
    it.quiet = true
    // #833: selectRange applies the range rule, not the end value's category alone.
    let (range, range_error) = realm.run(it, "new Intl.PluralRules('en', { type: 'ordinal' }).selectRange(1, 2)")
    if range_error != ok { os.exit(13i32) }
    let (range_text, range_text_error) = js.to_string(it, range)
    if range_text_error != ok || !str.eq(range_text, "other") { os.exit(14i32) }
    let (same, same_error) = realm.run(it, "new Intl.PluralRules('en', { type: 'ordinal' }).selectRange(2, 2)")
    if same_error != ok { os.exit(15i32) }
    let (same_text, same_text_error) = js.to_string(it, same)
    if same_text_error != ok || !str.eq(same_text, "two") { os.exit(15i32) }
    // #834: an iterable's iterator method is fetched and called exactly once.
    let (once, once_error) = realm.run(it, "var calls = 0; var iterable = {}; iterable[Symbol.iterator] = function () { calls++; var n = 0; return { next: function () { n++; return n <= 2 ? { value: 'a' + n, done: false } : { value: undefined, done: true }; } }; }; new Intl.ListFormat('en').format(iterable) + '|' + calls")
    if once_error != ok { os.exit(16i32) }
    let (once_text, once_text_error) = js.to_string(it, once)
    if once_text_error != ok || !str.eq(once_text, "a1 and a2|1") { os.exit(17i32) }
    // #829: RFC 5646 allows a 4-letter primary language subtag.
    let (four, four_error) = realm.run(it, "Intl.getCanonicalLocales('Gbcd')[0]")
    if four_error != ok { os.exit(2i32) }
    let (four_text, four_text_error) = js.to_string(it, four)
    if four_text_error != ok || !str.eq(four_text, "gbcd") { os.exit(3i32) }
    // #829: a 2-3 letter language may carry extlangs (zh-cmn).
    let (extlang, extlang_error) = realm.run(it, "Intl.getCanonicalLocales('zh-cmn')[0]")
    if extlang_error != ok { os.exit(4i32) }
    let (extlang_text, extlang_text_error) = js.to_string(it, extlang)
    if extlang_text_error != ok || extlang_text.len < 2usize || extlang_text[0usize] != 122u8 || extlang_text[1usize] != 104u8 { os.exit(5i32) }
    // #830: a duplicate u-extension key is malformed and must be rejected.
    let (_, duplicate_error) = realm.run(it, "Intl.getCanonicalLocales('en-u-ca-gregory-ca-islamic')")
    if duplicate_error == ok { os.exit(6i32) }
    // #831: grandfathered tags are accepted and canonicalized to their preferred values.
    let (klingon, klingon_error) = realm.run(it, "Intl.getCanonicalLocales('i-klingon')[0]")
    if klingon_error != ok { os.exit(7i32) }
    let (klingon_text, klingon_text_error) = js.to_string(it, klingon)
    if klingon_text_error != ok || !str.eq(klingon_text, "tlh") { os.exit(8i32) }
    let (oxendict, oxendict_error) = realm.run(it, "Intl.getCanonicalLocales('en-GB-oed')[0]")
    if oxendict_error != ok { os.exit(9i32) }
    let (oxendict_text, oxendict_text_error) = js.to_string(it, oxendict)
    if oxendict_text_error != ok || !str.eq(oxendict_text, "en-GB-oxendict") { os.exit(10i32) }
    let (guoyu, guoyu_error) = realm.run(it, "Intl.getCanonicalLocales('zh-guoyu')[0]")
    if guoyu_error != ok { os.exit(11i32) }
    let (guoyu_text, guoyu_text_error) = js.to_string(it, guoyu)
    if guoyu_text_error != ok || !str.eq(guoyu_text, "zh") { os.exit(12i32) }
    ret ok
}
