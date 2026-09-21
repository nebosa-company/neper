// `e.text.casing`: identifiers split at separators and case boundaries
// (`HTTPServer` is two words, `version2Beta` two), convert between the five
// conventions, slugs fold punctuation runs to one hyphen with none at the
// ends, and title case capitalises every word but the small ones except at
// either end. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.casing

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn converts(name: str, style: casing.Style, want: str) -> bool {
    var out: [64]u8 = zero
    var bounds: [32]usize = zero
    let (got, convert_error) = casing.convert(name, style, out[..], bounds[..])
    ret convert_error == ok && same(got, want)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: word splitting.
    var bounds: [16]usize = zero
    let (count, split_error) = casing.words("HTTPServerError2xx", bounds[..])
    if split_error != ok || count != 3usize { os.exit(1i32) }
    if bounds[0usize] != 0usize || bounds[1usize] != 4usize || bounds[2usize] != 4usize || bounds[3usize] != 10usize || bounds[4usize] != 10usize || bounds[5usize] != 18usize { os.exit(1i32) }
    let (count2, split2_error) = casing.words("  hello--world_again fooBar ", bounds[..])
    if split2_error != ok || count2 != 5usize || bounds[6usize] != 21usize || bounds[7usize] != 24usize || bounds[9usize] != 27usize { os.exit(1i32) }
    let (_, room) = casing.words("a b c", bounds[..4usize])
    if room != casing.TooSmall { os.exit(1i32) }
    let (none, none_error) = casing.words("---", bounds[..])
    if none_error != ok || none != 0usize { os.exit(1i32) }

    // 2: conversions.
    if !converts("fooBarBaz", .Snake, "foo_bar_baz") || !converts("fooBarBaz", .Kebab, "foo-bar-baz") { os.exit(2i32) }
    if !converts("fooBarBaz", .Pascal, "FooBarBaz") || !converts("fooBarBaz", .Screaming, "FOO_BAR_BAZ") { os.exit(2i32) }
    if !converts("foo_bar_baz", .Camel, "fooBarBaz") || !converts("FOO_BAR_BAZ", .Camel, "fooBarBaz") { os.exit(2i32) }
    if !converts("HTTPServer", .Snake, "http_server") || !converts("XMLHttpRequest", .Kebab, "xml-http-request") { os.exit(2i32) }
    if !converts("version2Beta", .Snake, "version2_beta") || !converts("  hello--world ", .Pascal, "HelloWorld") { os.exit(2i32) }
    if !converts("ABC", .Camel, "abc") || !converts("ABC", .Pascal, "Abc") || !converts("", .Snake, "") { os.exit(2i32) }
    var small: [4]u8 = zero
    let (_, convert_room) = casing.convert("fooBar", .Snake, small[..], bounds[..])
    if convert_room != casing.TooSmall { os.exit(2i32) }

    // 3: slugs.
    var out: [64]u8 = zero
    let (s1, s1_error) = casing.slug("Hello, World!  Neper 2026", out[..])
    if s1_error != ok || !same(s1, "hello-world-neper-2026") { os.exit(3i32) }
    let (s2, s2_error) = casing.slug("--a--", out[..])
    if s2_error != ok || !same(s2, "a") { os.exit(3i32) }
    let (s3, s3_error) = casing.slug("", out[..])
    if s3_error != ok || s3.len != 0usize { os.exit(3i32) }
    let (_, s_room) = casing.slug("abc", out[..2usize])
    if s_room != casing.TooSmall { os.exit(3i32) }

    // 4: titles.
    let (t1, t1_error) = casing.title("the lord of the rings", out[..])
    if t1_error != ok || !same(t1, "The Lord of the Rings") { os.exit(4i32) }
    let (t2, t2_error) = casing.title("WAR AND PEACE", out[..])
    if t2_error != ok || !same(t2, "War and Peace") { os.exit(4i32) }
    let (t3, t3_error) = casing.title("to be or not to be", out[..])
    if t3_error != ok || !same(t3, "To Be or Not to Be") { os.exit(4i32) }
    let (t4, t4_error) = casing.title("what to do", out[..])
    if t4_error != ok || !same(t4, "What to Do") { os.exit(4i32) }
    let (t5, t5_error) = casing.title("a  tale (of) two cities", out[..])
    if t5_error != ok || !same(t5, "A  Tale (Of) Two Cities") { os.exit(4i32) }

    try io.print("text casing ok\n")
    ret ok
}
