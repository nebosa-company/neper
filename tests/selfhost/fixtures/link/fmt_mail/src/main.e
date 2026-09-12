// `e.fmt.mail`: addresses in every form the header allows, a list split outside quotes
// and comments, formatting with quoting where needed, dates with numeric and named
// zones against Python's email.utils, a message read into headers and a body reader,
// encoded words in B and Q with UTF-8 and Latin-1 and the whitespace between two of
// them dropped, and the refusals. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.mail as mail

fn main(a: *mem.Arena, args: []str) -> err {
    let (a1, e1) = mail.parse_address(a, "Ada Lovelace <ada@example.com>")
    if e1 != ok || !str.eq(a1.name, "Ada Lovelace") || !str.eq(a1.address, "ada@example.com") { os.exit(1) }
    let (a2, e2) = mail.parse_address(a, "\"Lovelace, Ada\" <ada@example.com>")
    if e2 != ok || !str.eq(a2.name, "Lovelace, Ada") { os.exit(2) }
    let (a3, e3) = mail.parse_address(a, " bob@example.org (Bob) ")
    if e3 != ok || a3.name.len != 0usize || !str.eq(a3.address, "bob@example.org") { os.exit(3) }
    let (a4, e4) = mail.parse_address(a, "\"Q\\\"uote\" <q@x.y>")
    if e4 != ok || !str.eq(a4.name, "Q\"uote") { os.exit(4) }
    let (bad1, e5) = mail.parse_address(a, "no at sign")
    if e5 != mail.InvalidAddress { os.exit(5) }
    let (bad2, e6) = mail.parse_address(a, "Name <unclosed@x.y")
    if e6 != mail.InvalidAddress { os.exit(6) }
    let (list, e7) = mail.parse_address_list(a, "Ada <ada@example.com>, \"Bob, Jr\" <bob@example.org>,(a, comment) carol@example.net")
    if e7 != ok || list.len != 3usize || !str.eq(list[1].name, "Bob, Jr") || !str.eq(list[2].address, "carol@example.net") { os.exit(7) }
    let (empty, e8) = mail.parse_address_list(a, "")
    if e8 != ok || empty.len != 0usize { os.exit(8) }
    let (f1, e9) = mail.format_address(a, mail.Address { name: "Ada Lovelace", address: "ada@example.com" })
    if e9 != ok || !str.eq(f1, "Ada Lovelace <ada@example.com>") { os.exit(9) }
    let (f2, e10) = mail.format_address(a, mail.Address { name: "Lovelace, Ada", address: "ada@example.com" })
    if e10 != ok || !str.eq(f2, "\"Lovelace, Ada\" <ada@example.com>") { os.exit(10) }
    let (f3, e11) = mail.format_address(a, mail.Address { name: "", address: "x@y.z" })
    if e11 != ok || !str.eq(f3, "x@y.z") { os.exit(11) }
    let (f4, e12) = mail.format_address(a, mail.Address { name: "N", address: "bad address" })
    if e12 != mail.InvalidAddress { os.exit(12) }
    // Dates.
    let (d1, e13) = mail.parse_date("Tue, 12 Sep 2026 15:04:05 +0200")
    if e13 != ok || d1.instant != 1789218245i64 || d1.offset_minutes != 120i16 { os.exit(13) }
    let (d2, e14) = mail.parse_date("1 Jan 2000 00:00 GMT")
    if e14 != ok || d2.instant != 946684800i64 || d2.offset_minutes != 0i16 { os.exit(14) }
    let (d3, e15) = mail.parse_date("Fri, 13 Sep 2026 07:30:00 EST")
    if e15 != ok || d3.instant != 1789302600i64 || d3.offset_minutes != -300i16 { os.exit(15) }
    let (d4, e16) = mail.parse_date("31 Feb 2026 10:00:00 +0000")
    if e16 != mail.InvalidDate { os.exit(16) }
    let (d5, e17) = mail.parse_date("12 Sep 2026 15:04")
    if e17 != mail.InvalidDate { os.exit(17) }
    // A message.
    let raw = "From: Ada <ada@example.com>\r\nSubject: =?utf-8?B?R3LDvMOfZQ==?=\r\n  =?ISO-8859-1?Q?_caf=E9?=\r\nContent-Type: text/plain\r\n\r\nhello body\r\nline two\r\n"
    var source_state = io.SliceReader { data: raw, off: 0usize }
    let (message, e18) = mail.read_message(a, io.slice_reader(&source_state), 4096usize)
    if e18 != ok || message.headers.len != 3usize { os.exit(18) }
    if !str.eq(message.headers[0].name, "From") || !str.eq(message.headers[2].value, "text/plain") { os.exit(19) }
    var body = message.body
    var out: [64]u8 = zero
    var filled = 0usize
    while true {
        let (count, read_error) = io.read(&body, out[filled..])
        if read_error == io.End { break }
        if read_error != ok { os.exit(20) }
        filled += count
    }
    if !str.eq(out[..filled], "hello body\r\nline two\r\n") { os.exit(21) }
    let (subject, e19) = mail.decode_header(a, message.headers[1].value, 256usize)
    if e19 != ok || !str.eq(subject, "Gr\xc3\xbc\xc3\x9fe caf\xc3\xa9") { os.exit(22) }
    let (plain, e20) = mail.decode_header(a, "plain subject", 256usize)
    if e20 != ok || !str.eq(plain, "plain subject") { os.exit(23) }
    let (mixed, e21) = mail.decode_header(a, "a =?utf-8?Q?b=3Dc?= d =?x-unknown?B?QQ==?=", 256usize)
    if e21 != ok || !str.eq(mixed, "a b=c d =?x-unknown?B?QQ==?=") { os.exit(24) }
    let (capped, e22) = mail.decode_header(a, "=?utf-8?B?R3LDvMOfZQ==?=", 3usize)
    if e22 != mail.TooLarge { os.exit(25) }
    var small_state = io.SliceReader { data: raw, off: 0usize }
    let (small, e23) = mail.read_message(a, io.slice_reader(&small_state), 40usize)
    if e23 != mail.TooLarge { os.exit(26) }
    var bad_state = io.SliceReader { data: "no colon here\r\n\r\nbody", off: 0usize }
    let (bad_message, e24) = mail.read_message(a, io.slice_reader(&bad_state), 4096usize)
    if e24 != mail.InvalidMessage { os.exit(27) }
    ret ok
}
