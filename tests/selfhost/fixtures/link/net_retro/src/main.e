// `e.net.retro`: Gemini request and response headers and gemtext lines, Gopher request lines and menu items, and
// Finger query lines, against cases written out from the three protocol texts (gemini spec 0.16, RFC 1436,
// RFC 1288). Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.net.retro as retro

fn text_of(buf: []const u8, n: usize) -> str {
    ret buf[0..n]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buf: [1100]u8 = zero
    // Gemini request.
    let (n1, e1) = retro.gemini_request(buf[0..], "gemini://example.org/")
    if e1 != ok || !str.eq(text_of(buf[0..], n1), "gemini://example.org/\r\n") { os.exit(1) }
    var long: [1100]u8 = zero
    var i = 0usize
    while i < 1025usize {
        long[i] = 97u8
        i += 1usize
    }
    let (n2, e2) = retro.gemini_request(buf[0..], long[0..1025])
    if e2 != retro.TooLong { os.exit(2) }
    let (n3, e3) = retro.gemini_request(buf[0..], long[0..1024])
    if e3 != ok || n3 != 1026usize { os.exit(3) }
    let (n4, e4) = retro.gemini_request(buf[0..], "gemini://x/\n")
    if e4 != retro.BadHeader { os.exit(4) }
    // Gemini responses.
    let (r1, re1) = retro.gemini_response("20 text/gemini; charset=utf-8\r\n# Hi\r\n")
    if re1 != ok || r1.status != 20u8 || !str.eq(r1.meta, "text/gemini; charset=utf-8") { os.exit(5) }
    if r1.body_at != 31usize { os.exit(6) }
    let (r2, re2) = retro.gemini_response("31 gemini://new.example/\r\n")
    if re2 != ok || r2.status != 31u8 || !str.eq(r2.meta, "gemini://new.example/") { os.exit(7) }
    let (r3, re3) = retro.gemini_response("51 Not found\r\n")
    if re3 != ok || r3.status != 51u8 || !str.eq(r3.meta, "Not found") { os.exit(8) }
    let (r4, re4) = retro.gemini_response("10 \r\n")
    if re4 != ok || r4.status != 10u8 || r4.meta.len != 0usize { os.exit(9) }
    let (r5, re5) = retro.gemini_response("2x oops\r\n")
    if re5 != retro.BadHeader { os.exit(10) }
    let (r6, re6) = retro.gemini_response("20 text/gemini no line end")
    if re6 != retro.BadHeader { os.exit(11) }
    // Gemtext lines.
    if retro.gemini_line_kind("=> gemini://a/ A", false) != retro.LINE_LINK { os.exit(12) }
    if retro.gemini_line_kind("# One", false) != retro.LINE_HEADING1 { os.exit(13) }
    if retro.gemini_line_kind("## Two", false) != retro.LINE_HEADING2 { os.exit(14) }
    if retro.gemini_line_kind("### Three", false) != retro.LINE_HEADING3 { os.exit(15) }
    if retro.gemini_line_kind("* item", false) != retro.LINE_LIST { os.exit(16) }
    if retro.gemini_line_kind("*no space", false) != retro.LINE_TEXT { os.exit(17) }
    if retro.gemini_line_kind("> quote", false) != retro.LINE_QUOTE { os.exit(18) }
    if retro.gemini_line_kind("```alt text", false) != retro.LINE_PRE_TOGGLE { os.exit(19) }
    if retro.gemini_line_kind("# not a heading", true) != retro.LINE_TEXT { os.exit(20) }
    if retro.gemini_line_kind("```", true) != retro.LINE_PRE_TOGGLE { os.exit(21) }
    if retro.gemini_line_kind("plain", false) != retro.LINE_TEXT { os.exit(22) }
    let (url, label) = retro.gemini_link("=>  gemini://a.example/x\t Label here")
    if !str.eq(url, "gemini://a.example/x") || !str.eq(label, "Label here") { os.exit(23) }
    let (url2, label2) = retro.gemini_link("=> gemini://b.example")
    if !str.eq(url2, "gemini://b.example") || label2.len != 0usize { os.exit(24) }
    // Gopher.
    let (g1, ge1) = retro.gopher_request(buf[0..], "/files", "", false)
    if ge1 != ok || !str.eq(text_of(buf[0..], g1), "/files\r\n") { os.exit(25) }
    let (g2, ge2) = retro.gopher_request(buf[0..], "/search", "neper lang", true)
    if ge2 != ok || !str.eq(text_of(buf[0..], g2), "/search\tneper lang\r\n") { os.exit(26) }
    let (g3, ge3) = retro.gopher_request(buf[0..], "", "", false)
    if ge3 != ok || g3 != 2usize { os.exit(27) }
    let (m1, me1) = retro.gopher_item("0About\t/about.txt\texample.org\t70")
    if me1 != ok || m1.kind != 48u8 || !str.eq(m1.display, "About") || !str.eq(m1.selector, "/about.txt") { os.exit(28) }
    if !str.eq(m1.host, "example.org") || m1.port != 70usize { os.exit(29) }
    let (m2, me2) = retro.gopher_item("1Sub menu\t/sub\th.example\t7070\t+")
    if me2 != ok || m2.kind != 49u8 || !str.eq(m2.display, "Sub menu") || m2.port != 7070usize { os.exit(30) }
    let (m3, me3) = retro.gopher_item("iJust text\t\t\t0")
    if me3 != ok || m3.kind != 105u8 || m3.selector.len != 0usize || m3.host.len != 0usize || m3.port != 0usize { os.exit(31) }
    let (m4, me4) = retro.gopher_item("1noTabs")
    if me4 != retro.BadItem { os.exit(32) }
    if !retro.gopher_is_end(".") || retro.gopher_is_end("..") || retro.gopher_is_end("") { os.exit(33) }
    // Finger.
    let (f1, fe1) = retro.finger_request(buf[0..], "alice", false)
    if fe1 != ok || !str.eq(text_of(buf[0..], f1), "alice\r\n") { os.exit(34) }
    let (f2, fe2) = retro.finger_request(buf[0..], "alice", true)
    if fe2 != ok || !str.eq(text_of(buf[0..], f2), "/W alice\r\n") { os.exit(35) }
    let (f3, fe3) = retro.finger_request(buf[0..], "", true)
    if fe3 != ok || !str.eq(text_of(buf[0..], f3), "/W\r\n") { os.exit(36) }
    let (f4, fe4) = retro.finger_request(buf[0..], "", false)
    if fe4 != ok || f4 != 2usize { os.exit(37) }
    let (f5, fe5) = retro.finger_request(buf[0..], "bob\r\nroot", false)
    if fe5 != retro.BadHeader { os.exit(38) }
    let (user, host) = retro.finger_target("bob@host.example")
    if !str.eq(user, "bob") || !str.eq(host, "host.example") { os.exit(39) }
    let (user2, host2) = retro.finger_target("carol")
    if !str.eq(user2, "carol") || host2.len != 0usize { os.exit(40) }
    let (user3, host3) = retro.finger_target("a@b@c")
    if !str.eq(user3, "a@b") || !str.eq(host3, "c") { os.exit(41) }
    ret ok
}
