// `e.fmt.pdf.write`: a one-page document and a two-page report (a bold heading with escapes, a wrapped paragraph
// with accents and a euro sign and a forced break, a table with a shaded header and wrapped cells, rectangles, lines,
// a polyline, a polygon and a circle) compared byte for byte with an independent writer that measures with
// reportlab's Helvetica metrics, read back through `e.fmt.pdf.pages`, text widths against reportlab, and the state
// errors. pypdf (strict) and pdfminer accepted the files when the generator ran. Written by
// scripts/gen_pdf_write_test.py. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.pdf as pdf
use e.fmt.pdf.write as w

fn same(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var (m, m_error) = w.document(a, 1usize, 4096usize, 200.0, 100.0, "")
    if m_error != ok { os.exit(1) }
    if w.begin_page(&m) != ok { os.exit(2) }
    if w.put_text(&m, 10.0, 50.0, 12.0, .Regular, w.rgb(0u8, 0u8, 0u8), "Hi") != ok { os.exit(3) }
    if w.end_page(&m) != ok { os.exit(4) }
    let (mini, mini_error) = w.finish(a, &m)
    if mini_error != ok { os.exit(5) }
    if mini.len != 842usize || !same(mini, "%PDF-1.4\x0a%\xe2\xe3\xcf\xd3\x0a1 0 obj\x0a<< /Type /Catalog /Pages 2 0 R >>\x0aendobj\x0a2 0 obj\x0a<< /Type /Pages /Count 1 /Kids [6 0 R] >>\x0aendobj\x0a3 0 obj\x0a<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\x0aendobj\x0a4 0 obj\x0a<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>\x0aendobj\x0a5 0 obj\x0a<< /Producer (Neper e.fmt.pdf.write) >>\x0aendobj\x0a6 0 obj\x0a<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100 ] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents 7 0 R >>\x0aendobj\x0a7 0 obj\x0a<< /Length 46 >>\x0astream\x0aq 0 0 0 rg BT /F1 12 Tf 10 50 Td (Hi) Tj ET Q\x0aendstream\x0aendobj\x0axref\x0a0 8\x0a0000000000 65535 f \x0a0000000015 00000 n \x0a0000000064 00000 n \x0a0000000121 00000 n \x0a0000000218 00000 n \x0a0000000320 00000 n \x0a0000000375 00000 n \x0a0000000512 00000 n \x0atrailer\x0a<< /Size 8 /Root 1 0 R /Info 5 0 R >>\x0astartxref\x0a607\x0a%%EOF\x0a") { os.exit(6) }
    let (mini_pages, mini_read) = pdf.pages(a, mini)
    if mini_read != ok || mini_pages.len != 1usize || !str.contains(mini_pages[0], "Hi") { os.exit(7) }
    var (d, d_error) = w.document(a, 4usize, 65536usize, 595.0, 842.0, "Quarterly report \xe2\x80\x93 Q3 caf\xc3\xa9")
    if d_error != ok { os.exit(8) }
    if w.begin_page(&d) != ok { os.exit(9) }
    if w.put_text(&d, 72.0, 90.0, 18.0, .Bold, w.rgb(0u8, 0u8, 0u8), "Quarterly report (Q3) \\ done") != ok { os.exit(10) }
    let (para6_next, para6_lines, para6_error) = w.put_paragraph(&d, 72.0, 120.0, 300.0, 11.0, 14.0, .Regular, w.rgb(0u8, 0u8, 0u8), "The quick brown fox jumps over the lazy dog, then the caf\xc3\xa9 menu lists r\xc3\xa9sum\xc3\xa9 pasta for \xe2\x82\xac12.50 and a second line.\x0aA new paragraph after a forced break keeps wrapping at word boundaries so that long text lands on several lines of the same column.")
    if para6_error != ok || para6_lines != 5usize || para6_next != 190.0 { os.exit(11) }
    let table8_widths = [3]f64{ 120.0, 60.0, 110.0 }
    let table8_r0 = [3]str{ "Item", "Qty", "Notes" }
    let table8_r1 = [3]str{ "Apple pie", "12", "baked fresh every morning in the old oven" }
    let table8_r2 = [3]str{ "Caf\xc3\xa9 au lait", "3", "" }
    let table8_r3 = [2]str{ "Totals", "15" }
    let table8_rows = [4][]const str{ table8_r0[0..], table8_r1[0..], table8_r2[0..], table8_r3[0..] }
    let (table8_bottom, table8_error) = w.put_table(&d, 72.0, 200.0, table8_widths[0..], table8_rows[0..], 10.0, 12.0, 4.0, true, w.rgb(0u8, 0u8, 0u8), w.rgb(128u8, 128u8, 128u8))
    if table8_error != ok || table8_bottom != 304.0 { os.exit(12) }
    if w.fill_rect(&d, 72.0, 324.0, 120.0, 30.0, w.rgb(0u8, 64u8, 192u8)) != ok { os.exit(13) }
    if w.stroke_rect(&d, 210.0, 324.0, 120.0, 30.0, 1.5, w.rgb(255u8, 0u8, 0u8)) != ok { os.exit(14) }
    if w.draw_line(&d, 72.0, 374.0, 330.0, 374.0, 0.75, w.rgb(128u8, 128u8, 128u8)) != ok { os.exit(15) }
    let xs13 = [4]f64{ 72.0, 120.0, 170.0, 230.0 }
    let ys13 = [4]f64{ 404.0, 384.0, 414.0, 394.0 }
    if w.draw_path(&d, xs13[0..], ys13[0..], false, 2.0, w.rgb(255u8, 0u8, 0u8)) != ok { os.exit(16) }
    let xs14 = [3]f64{ 260.0, 330.0, 295.0 }
    let ys14 = [3]f64{ 414.0, 414.0, 384.0 }
    if w.draw_path(&d, xs14[0..], ys14[0..], true, 1.0, w.rgb(0u8, 64u8, 192u8)) != ok { os.exit(17) }
    if w.fill_circle(&d, 400.0, 404.0, 25.0, w.rgb(255u8, 0u8, 0u8)) != ok { os.exit(18) }
    if w.end_page(&d) != ok { os.exit(19) }
    if w.begin_page(&d) != ok { os.exit(20) }
    if w.put_text(&d, 72.0, 72.0, 10.0, .Regular, w.rgb(128u8, 128u8, 128u8), "Page two") != ok { os.exit(21) }
    if w.end_page(&d) != ok { os.exit(22) }
    let (bytes, bytes_error) = w.finish(a, &d)
    if bytes_error != ok { os.exit(23) }
    if bytes.len != 3549usize || !same(bytes, "%PDF-1.4\x0a%\xe2\xe3\xcf\xd3\x0a1 0 obj\x0a<< /Type /Catalog /Pages 2 0 R >>\x0aendobj\x0a2 0 obj\x0a<< /Type /Pages /Count 2 /Kids [6 0 R 8 0 R] >>\x0aendobj\x0a3 0 obj\x0a<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\x0aendobj\x0a4 0 obj\x0a<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>\x0aendobj\x0a5 0 obj\x0a<< /Title <FEFF0051007500610072007400650072006C00790020007200650070006F0072007400202013002000510033002000630061006600E9> /Producer (Neper e.fmt.pdf.write) >>\x0aendobj\x0a6 0 obj\x0a<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842 ] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents 7 0 R >>\x0aendobj\x0a7 0 obj\x0a<< /Length 2333 >>\x0astream\x0aq 0 0 0 rg BT /F2 18 Tf 72 752 Td (Quarterly report \\(Q3\\) \\\\ done) Tj ET Q\x0aq 0 0 0 rg BT /F1 11 Tf 72 722 Td (The quick brown fox jumps over the lazy dog, then the caf\\351) Tj ET Q\x0aq 0 0 0 rg BT /F1 11 Tf 72 708 Td (menu lists r\\351sum\\351 pasta for \\20012.50 and a second line.) Tj ET Q\x0aq 0 0 0 rg BT /F1 11 Tf 72 694 Td (A new paragraph after a forced break keeps wrapping at) Tj ET Q\x0aq 0 0 0 rg BT /F1 11 Tf 72 680 Td (word boundaries so that long text lands on several lines of) Tj ET Q\x0aq 0 0 0 rg BT /F1 11 Tf 72 666 Td (the same column.) Tj ET Q\x0aq 0.9333 0.9333 0.9333 rg 72 622 120 20 re f Q\x0aq 0.502 0.502 0.502 RG 0.5 w 72 622 120 20 re S Q\x0aq 0 0 0 rg BT /F2 10 Tf 76 628 Td (Item) Tj ET Q\x0aq 0.9333 0.9333 0.9333 rg 192 622 60 20 re f Q\x0aq 0.502 0.502 0.502 RG 0.5 w 192 622 60 20 re S Q\x0aq 0 0 0 rg BT /F2 10 Tf 196 628 Td (Qty) Tj ET Q\x0aq 0.9333 0.9333 0.9333 rg 252 622 110 20 re f Q\x0aq 0.502 0.502 0.502 RG 0.5 w 252 622 110 20 re S Q\x0aq 0 0 0 rg BT /F2 10 Tf 256 628 Td (Notes) Tj ET Q\x0aq 0.502 0.502 0.502 RG 0.5 w 72 578 120 44 re S Q\x0aq 0 0 0 rg BT /F1 10 Tf 76 608 Td (Apple pie) Tj ET Q\x0aq 0.502 0.502 0.502 RG 0.5 w 192 578 60 44 re S Q\x0aq 0 0 0 rg BT /F1 10 Tf 196 608 Td (12) Tj ET Q\x0aq 0.502 0.502 0.502 RG 0.5 w 252 578 110 44 re S Q\x0aq 0 0 0 rg BT /F1 10 Tf 256 608 Td (baked fresh every) Tj ET Q\x0aq 0 0 0 rg BT /F1 10 Tf 256 596 Td (morning in the old) Tj ET Q\x0aq 0 0 0 rg BT /F1 10 Tf 256 584 Td (oven) Tj ET Q\x0aq 0.502 0.502 0.502 RG 0.5 w 72 558 120 20 re S Q\x0aq 0 0 0 rg BT /F1 10 Tf 76 564 Td (Caf\\351 au lait) Tj ET Q\x0aq 0.502 0.502 0.502 RG 0.5 w 192 558 60 20 re S Q\x0aq 0 0 0 rg BT /F1 10 Tf 196 564 Td (3) Tj ET Q\x0aq 0.502 0.502 0.502 RG 0.5 w 252 558 110 20 re S Q\x0aq 0.502 0.502 0.502 RG 0.5 w 72 538 120 20 re S Q\x0aq 0 0 0 rg BT /F1 10 Tf 76 544 Td (Totals) Tj ET Q\x0aq 0.502 0.502 0.502 RG 0.5 w 192 538 60 20 re S Q\x0aq 0 0 0 rg BT /F1 10 Tf 196 544 Td (15) Tj ET Q\x0aq 0.502 0.502 0.502 RG 0.5 w 252 538 110 20 re S Q\x0aq 0 0.251 0.7529 rg 72 488 120 30 re f Q\x0aq 1 0 0 RG 1.5 w 210 488 120 30 re S Q\x0aq 0.502 0.502 0.502 RG 0.75 w 72 468 m 330 468 l S Q\x0aq 1 0 0 RG 2 w 72 438 m 120 458 l 170 428 l 230 448 l S Q\x0aq 0 0.251 0.7529 rg 260 428 m 330 428 l 295 458 l h f Q\x0aq 1 0 0 rg 425 438 m 425 451.81 413.81 463 400 463 c 386.19 463 375 451.81 375 438 c 375 424.19 386.19 413 400 413 c 413.81 413 425 424.19 425 438 c f Q\x0aendstream\x0aendobj\x0a8 0 obj\x0a<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842 ] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents 9 0 R >>\x0aendobj\x0a9 0 obj\x0a<< /Length 65 >>\x0astream\x0aq 0.502 0.502 0.502 rg BT /F1 10 Tf 72 770 Td (Page two) Tj ET Q\x0aendstream\x0aendobj\x0axref\x0a0 10\x0a0000000000 65535 f \x0a0000000015 00000 n \x0a0000000064 00000 n \x0a0000000127 00000 n \x0a0000000224 00000 n \x0a0000000326 00000 n \x0a0000000499 00000 n \x0a0000000636 00000 n \x0a0000003020 00000 n \x0a0000003157 00000 n \x0atrailer\x0a<< /Size 10 /Root 1 0 R /Info 5 0 R >>\x0astartxref\x0a3271\x0a%%EOF\x0a") { os.exit(24) }
    let (read_pages, read_error) = pdf.pages(a, bytes)
    if read_error != ok || read_pages.len != 2usize { os.exit(25) }
    if !str.contains(read_pages[0], "Apple pie") || !str.contains(read_pages[0], "A new paragraph after a forced break") || !str.contains(read_pages[1], "Page two") { os.exit(26) }
    let (tw_27, tw_error_27) = w.text_width("Hello, World", 12.0, .Regular)
    if tw_error_27 != ok || tw_27 < 65.3399 || tw_27 > 65.3401 { os.exit(27) }
    let (tw_28, tw_error_28) = w.text_width("Hello, World", 12.0, .Bold)
    if tw_error_28 != ok || tw_28 < 70.0079 || tw_28 > 70.00810000000001 { os.exit(28) }
    let (tw_29, tw_error_29) = w.text_width("Wijg\xc3\xa9 \xe2\x82\xac", 10.0, .Bold)
    if tw_error_29 != ok || tw_29 < 35.009899999999995 || tw_29 > 35.0101 { os.exit(29) }
    var (e, e_error) = w.document(a, 1usize, 256usize, 200.0, 100.0, "")
    if e_error != ok { os.exit(30) }
    if w.put_text(&e, 1.0, 1.0, 10.0, .Regular, w.black(), "x") != w.NoPage { os.exit(31) }
    if w.end_page(&e) != w.NoPage { os.exit(32) }
    let (f1, f1_error) = w.finish(a, &e)
    if f1_error != w.NoPage { os.exit(33) }
    if w.begin_page(&e) != ok { os.exit(34) }
    if w.begin_page(&e) != w.PageOpen { os.exit(35) }
    if w.put_text(&e, 1.0, 1.0, 10.0, .Regular, w.black(), "\xe6\x97\xa5") != w.Unsupported { os.exit(36) }
    if w.put_text(&e, 1.0, 1.0, 10.0, .Regular, w.black(), "a\nb") != w.Invalid { os.exit(37) }
    if w.put_text(&e, 1.0, 1.0, 0.0, .Regular, w.black(), "a") != w.Invalid { os.exit(38) }
    if w.fill_rect(&e, 1.0, 1.0, 0.0, 5.0, w.black()) != w.Invalid { os.exit(39) }
    let (f2, f2_error) = w.finish(a, &e)
    if f2_error != w.PageOpen { os.exit(40) }
    let (e_next, e_lines, e_pe) = w.put_paragraph(&e, 1.0, 20.0, 10.0, 10.0, 12.0, .Regular, w.black(), "a long text that will not fit into so small a region of page content bytes at all, no matter how it is wrapped, because the page store holds two hundred and fifty-six bytes")
    if e_pe != w.TooLarge { os.exit(41) }
    if e_lines != 0usize { os.exit(42) }
    let (e2, e2_error) = w.document(a, 1usize, 4096usize, 200.0, 100.0, "")
    if e2_error != ok { os.exit(43) }
    var e3 = e2
    if w.begin_page(&e3) != ok || w.end_page(&e3) != ok || w.begin_page(&e3) != w.TooLarge { os.exit(44) }
    let (e4, e4_error) = w.document(a, 1usize, 4096usize, 0.0, 100.0, "")
    if e4_error != w.Invalid { os.exit(45) }
    ret ok
}
