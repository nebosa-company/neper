// `e.asset` over this fixture's `project.yaml` (D777): three declared files -- one
// with a flow attribute mapping, one with a nested one and a quoted name, one empty
// -- sorted by logical name into the registry with their bytes, media types (the
// default where none is declared), SHA-256 and attributes; lookups by index and by
// name, a missing name and a missing attribute answer false.

use e.asset
use e.io
use e.mem
use e.os

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn digest_is(actual: [32]u8, expected: [32]u8) -> bool {
    var i = 0usize
    while i < 32usize {
        if actual[i] != expected[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    if asset.count() != 3usize { os.exit(1i32) }
    // Sorted: "bytes/all@1x" < "bytes/empty" < "text/hello".
    let (first, first_found) = asset.at(0usize)
    if !first_found || !same(first.name, "bytes/all@1x") || !same(first.media_type, "application/octet-stream") { os.exit(2i32) }
    if first.bytes.len != 256usize || first.bytes[0] != 0u8 || first.bytes[255] != 255u8 || first.bytes[34] != 34u8 || first.bytes[92] != 92u8 { os.exit(3i32) }
    if !digest_is(first.sha256, [32]u8{ 64u8, 175u8, 242u8, 233u8, 210u8, 216u8, 146u8, 46u8, 71u8, 175u8, 212u8, 100u8, 142u8, 105u8, 103u8, 73u8, 113u8, 88u8, 120u8, 95u8, 189u8, 29u8, 168u8, 112u8, 231u8, 17u8, 2u8, 102u8, 191u8, 148u8, 72u8, 128u8 }) { os.exit(4i32) }
    if first.attributes.len != 2usize || !same(first.attributes[0].name, "base") || !same(first.attributes[0].value, "bytes/all") || !same(first.attributes[1].name, "scale") || !same(first.attributes[1].value, "1") { os.exit(5i32) }
    let (second, second_found) = asset.at(1usize)
    if !second_found || !same(second.name, "bytes/empty") || second.bytes.len != 0usize || second.attributes.len != 0usize { os.exit(6i32) }
    if !digest_is(second.sha256, [32]u8{ 227u8, 176u8, 196u8, 66u8, 152u8, 252u8, 28u8, 20u8, 154u8, 251u8, 244u8, 200u8, 153u8, 111u8, 185u8, 36u8, 39u8, 174u8, 65u8, 228u8, 100u8, 155u8, 147u8, 76u8, 164u8, 149u8, 153u8, 27u8, 120u8, 82u8, 184u8, 85u8 }) { os.exit(7i32) }
    let (third, third_found) = asset.at(2usize)
    if !third_found || !same(third.name, "text/hello") || !same(third.media_type, "text/plain") { os.exit(8i32) }
    if !same(third.bytes, "hello, \"assets\"\\n\n") { os.exit(9i32) }
    if !digest_is(third.sha256, [32]u8{ 48u8, 212u8, 40u8, 190u8, 62u8, 143u8, 2u8, 169u8, 229u8, 110u8, 125u8, 35u8, 99u8, 164u8, 33u8, 235u8, 15u8, 136u8, 51u8, 130u8, 33u8, 109u8, 240u8, 198u8, 201u8, 195u8, 78u8, 99u8, 157u8, 122u8, 201u8, 176u8 }) { os.exit(10i32) }
    if third.attributes.len != 3usize { os.exit(11i32) }
    let (theme, has_theme) = asset.attribute(third, "theme")
    if !has_theme || !same(theme, "any") { os.exit(12i32) }
    let (locale, has_locale) = asset.attribute(third, "locale")
    if !has_locale || locale.len != 0usize { os.exit(13i32) }
    let (_, has_scale) = asset.attribute(third, "scale")
    if has_scale { os.exit(14i32) }
    let (_, past) = asset.at(3usize)
    if past { os.exit(15i32) }
    // By name.
    let (named, named_found) = asset.get("text/hello")
    if !named_found || !same(named.media_type, "text/plain") || named.bytes.len != third.bytes.len { os.exit(16i32) }
    let (_, missing) = asset.get("text/missing")
    if missing { os.exit(17i32) }
    let (_, prefix) = asset.get("text/hell")
    if prefix { os.exit(18i32) }
    // The slices are the executable's: two lookups answer the same bytes.
    let (again, _) = asset.get("bytes/all@1x")
    if again.bytes.len != first.bytes.len || again.bytes[100] != 100u8 { os.exit(19i32) }

    try io.print("asset ok\n")
    ret ok
}
