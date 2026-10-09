// e.ui.report against a second implementation of its specification (scripts/report_reference.py writes this file from
// scripts/report_fixture_template.e): @@COUNT@@ seeded random reports -- groups of up to three levels, keep-together,
// repeated headers, page breaks before groups, wrapping and growing text with every template function -- must lay out to
// the same page count, the same item count on each page and the same 64-bit hash of every item; and small reports
// are checked item by item against hand-computed pages.
use e.io
use e.mem
use e.os
use e.ui.report as rp

fn fail(code: i32) -> err {
    let _ = io.print("ui report failed at ")
    var digits: [6]u8 = zero
    digits[0] = u8(48i32 + code / 10000i32)
    digits[1] = u8(48i32 + (code / 1000i32) % 10i32)
    digits[2] = u8(48i32 + (code / 100i32) % 10i32)
    digits[3] = u8(48i32 + (code / 10i32) % 10i32)
    digits[4] = u8(48i32 + code % 10i32)
    let _ = io.print(digits[..5])
    let _ = io.print("\n")
    os.exit(code)
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// ---- the canonical dump, hashed on the fly ----

type Hash = struct { h: u64, bytes: u64 }

fn feed(h: *Hash, text: str) {
    var i = 0usize
    while i < text.len {
        h.h = ((h.h ^ u64(text[i])) * 16777619u64) % 4294967296u64
        h.bytes += 1u64
        i += 1usize
    }
}

fn feed_number(h: *Hash, v: f32) {
    var n = u64(v * 100.0 + 0.5)
    let whole = n / 100u64
    let frac = n % 100u64
    var digits: [24]u8 = zero
    var count = 0usize
    var rest = whole
    if rest == 0u64 {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0u64 {
        digits[count] = u8(48u64 + rest % 10u64)
        rest = rest / 10u64
        count += 1usize
    }
    while count > 0usize {
        count -= 1usize
        feed(h, digits[count..count + 1usize])
    }
    feed(h, ".")
    var two: [2]u8 = zero
    two[0] = u8(48u64 + frac / 10u64)
    two[1] = u8(48u64 + frac % 10u64)
    feed(h, two[0..])
}

fn feed_count(h: *Hash, value: usize) {
    var digits: [24]u8 = zero
    var count = 0usize
    var rest = value
    if rest == 0usize {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0usize {
        digits[count] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
        count += 1usize
    }
    while count > 0usize {
        count -= 1usize
        feed(h, digits[count..count + 1usize])
    }
}

fn dump_item(h: *Hash, item: rp.Item) {
    var kind = "T"
    var align = "L"
    if item.kind == .Line { kind = "L" }
    if item.kind == .Rect { kind = "R" }
    if item.kind == .Text {
        if item.align == .Left { align = "Left" }
        if item.align == .Center { align = "Center" }
        if item.align == .Right { align = "Right" }
    }
    feed(h, kind)
    feed(h, " ")
    feed_number(h, item.x)
    feed(h, " ")
    feed_number(h, item.y)
    feed(h, " ")
    feed_number(h, item.width)
    feed(h, " ")
    feed_number(h, item.height)
    feed(h, " ")
    feed(h, align)
    feed(h, " ")
    feed_number(h, item.size)
    feed(h, " ")
    if item.bold { feed(h, "B") } else { feed(h, "N") }
    feed(h, " ")
    feed(h, item.text)
    feed(h, "\n")
}

fn check(a: *mem.Arena, report: *const rp.Report, pages: usize, counts: []const usize, expected: u64) -> i32 {
    let mark = mem.mark(a)
    let pitch = rp.FixedPitch { em: 0.5 }
    let (laid, layout_error) = rp.layout(a, report, rp.fixed_pitch(&pitch))
    if layout_error != ok {
        mem.reset(a, mark)
        ret 1i32
    }
    if laid.pages.len != pages {
        mem.reset(a, mark)
        ret 2i32
    }
    var h = Hash { h: 2166136261u64, bytes: 0u64 }
    var p = 0usize
    while p < laid.pages.len {
        if laid.pages[p].items.len != counts[p] {
            mem.reset(a, mark)
            ret 3i32
        }
        feed(&h, "P ")
        feed_count(&h, laid.pages[p].number)
        feed(&h, "\n")
        var i = 0usize
        while i < laid.pages[p].items.len {
            dump_item(&h, laid.pages[p].items[i])
            i += 1usize
        }
        p += 1usize
    }
    mem.reset(a, mark)
    if h.h + h.bytes * 4294967296u64 != expected { ret 4i32 }
    ret 0i32
}

@@CASES@@

// A small report by hand: a page 100 by 100 with 10 margins, a page header 10 tall, a footer 10 tall, a detail of 20, six
// rows grouped on Kind with a group footer of 10. The content area is 10 + 10 .. 100 - 10 - 10 = 20 .. 80, 60 tall.
fn hand(a: *mem.Arena) -> i32 {
    let pitch = rp.FixedPitch { em: 0.5 }
    let header_els = [1]rp.Element{ rp.Element { kind: .Text, x: 0.0, y: 0.0, width: 80.0, height: 10.0, text: "H [PAGE]/[PAGES]", size: 8.0, bold: false, align: .Left, border: false, grow: false } }
    let footer_els = [1]rp.Element{ rp.Element { kind: .Text, x: 0.0, y: 0.0, width: 80.0, height: 10.0, text: "F", size: 8.0, bold: false, align: .Right, border: false, grow: false } }
    let group_head_els = [1]rp.Element{ rp.Element { kind: .Text, x: 0.0, y: 0.0, width: 80.0, height: 10.0, text: "[Kind]", size: 8.0, bold: true, align: .Left, border: false, grow: false } }
    let detail_els = [1]rp.Element{ rp.Element { kind: .Text, x: 0.0, y: 0.0, width: 80.0, height: 20.0, text: "[Name] [Amount:1]", size: 8.0, bold: false, align: .Left, border: false, grow: true } }
    let group_foot_els = [1]rp.Element{ rp.Element { kind: .Text, x: 0.0, y: 0.0, width: 80.0, height: 10.0, text: "= [SUM(Amount)]", size: 8.0, bold: false, align: .Left, border: false, grow: false } }
    let bands = [5]rp.Band{
        rp.Band { kind: .PageHeader, height: 10.0, elements: header_els[0..], level: 0usize, page_break_before: false },
        rp.Band { kind: .GroupHeader, height: 10.0, elements: group_head_els[0..], level: 0usize, page_break_before: false },
        rp.Band { kind: .Detail, height: 20.0, elements: detail_els[0..], level: 0usize, page_break_before: false },
        rp.Band { kind: .GroupFooter, height: 10.0, elements: group_foot_els[0..], level: 0usize, page_break_before: false },
        rp.Band { kind: .PageFooter, height: 10.0, elements: footer_els[0..], level: 0usize, page_break_before: false },
    }
    let groups = [1]rp.Group{ rp.Group { field: "Kind", keep_together: false, repeat_header: true } }
    let columns = [3]str{ "Kind", "Name", "Amount" }
    let cells = [18]rp.Cell{
        rp.Cell { text: "a", number: 0.0, numeric: false }, rp.Cell { text: "one", number: 0.0, numeric: false }, rp.Cell { text: "1.5", number: 1.5, numeric: true },
        rp.Cell { text: "a", number: 0.0, numeric: false }, rp.Cell { text: "two", number: 0.0, numeric: false }, rp.Cell { text: "2.5", number: 2.5, numeric: true },
        rp.Cell { text: "a", number: 0.0, numeric: false }, rp.Cell { text: "three", number: 0.0, numeric: false }, rp.Cell { text: "3", number: 3.0, numeric: true },
        rp.Cell { text: "b", number: 0.0, numeric: false }, rp.Cell { text: "four", number: 0.0, numeric: false }, rp.Cell { text: "4", number: 4.0, numeric: true },
        rp.Cell { text: "b", number: 0.0, numeric: false }, rp.Cell { text: "five", number: 0.0, numeric: false }, rp.Cell { text: "5", number: 5.0, numeric: true },
        rp.Cell { text: "b", number: 0.0, numeric: false }, rp.Cell { text: "six", number: 0.0, numeric: false }, rp.Cell { text: "6.25", number: 6.25, numeric: true },
    }
    let source = rp.Source { columns: columns[0..], cells: cells[0..], rows: 6usize }
    let report = rp.Report { page_width: 100.0, page_height: 100.0, margin_left: 10.0, margin_top: 10.0, margin_right: 10.0, margin_bottom: 10.0, bands: bands[0..], groups: groups[0..], source: source, sort: true }
    let (laid, layout_error) = rp.layout(a, &report, rp.fixed_pitch(&pitch))
    if layout_error != ok { ret 1i32 }
    // Page 1: header at y 10, group "a" header 20..30, details 30..50 and 50..70; the third detail (70..90) is past the
    // bottom at 80, so page 2 opens with the header, the repeated "a" header (20..30), the detail (30..50) and the
    // group's footer (50..60); "b"'s header and first detail (30 more) do not fit under 80, so page 3 has them
    // and two details, and the last detail goes to page 4 under a repeated "b" header.
    if laid.pages.len != 4usize { ret 2i32 }
    let first = laid.pages[0usize]
    if first.number != 1usize || first.items.len != 5usize { ret 3i32 }
    if first.items[0usize].y != 10.0 || !same(first.items[0usize].text, "H 1/4") || first.items[0usize].x != 10.0 || first.items[0usize].size != 8.0 { ret 4i32 }
    if first.items[1usize].y != 20.0 || !same(first.items[1usize].text, "a") || !first.items[1usize].bold { ret 5i32 }
    if first.items[2usize].y != 30.0 || !same(first.items[2usize].text, "one 1.5") || first.items[2usize].height != 10.0 { ret 6i32 }
    if first.items[3usize].y != 50.0 || !same(first.items[3usize].text, "two 2.5") { ret 7i32 }
    if first.items[4usize].y != 90.0 - 10.0 || !same(first.items[4usize].text, "F") || first.items[4usize].align != .Right { ret 8i32 }
    let second = laid.pages[1usize]
    if second.number != 2usize || !same(second.items[0usize].text, "H 2/4") || !same(second.items[1usize].text, "a") || second.items[1usize].y != 20.0 { ret 9i32 }
    if !same(second.items[2usize].text, "three 3.0") || second.items[2usize].y != 30.0 { ret 10i32 }
    if !same(second.items[3usize].text, "= 7.00") || second.items[3usize].y != 50.0 { ret 11i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    let hand_code = hand(a)
    if hand_code != 0i32 { ret fail(hand_code) }
@@CALLS@@
    try io.print("ui report ok\n")
    ret ok
}
