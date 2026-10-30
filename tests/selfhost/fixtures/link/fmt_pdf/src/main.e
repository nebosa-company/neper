// `e.fmt.pdf`: PDFs written by reference.py -- plain and zlib-compressed streams, a nested page tree stored
// out of order, a contents array, a literal string with escapes, a hex string, TJ kerning and T* -- read back
// page by page, and the refusals for bytes that are no PDF and for a PDF with no pages.
// Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.pdf as pdf

fn issue_78_core_check(a: *mem.Arena) -> u8 {
    let (_, _, huge_number) = pdf.number_at("9999999999", 0usize, 10usize)
    if huge_number { ret 1u8 }
    let (bounded_number, _, bounded_ok) = pdf.number_at("999999999", 0usize, 9usize)
    if !bounded_ok || bounded_number != 999999999usize { ret 2u8 }
    let malformed_object = "9999999999 0 obj\n<<>>\nendobj\n1 0 obj\n<<>>\nendobj\n"
    let (malformed_table, malformed_count, malformed_error) = pdf.objects(a, malformed_object)
    if malformed_error != ok || malformed_count != 1usize || malformed_table[0usize].number != 1usize { ret 23u8 }

    let (kid_builder0, kid_builder_error) = str.builder(a, 0usize)
    if kid_builder_error != ok { ret 3u8 }
    var kid_builder = kid_builder0
    if str.push(&kid_builder, "/Kids [") != ok { ret 4u8 }
    var page_at = 0usize
    while page_at < 300usize {
        if str.push(&kid_builder, "1 0 R ") != ok { ret 5u8 }
        page_at += 1usize
    }
    if str.push(&kid_builder, "]") != ok { ret 6u8 }
    let kid_data = str.done(&kid_builder)
    var kid_refs: [512]usize = zero
    if pdf.refs_in_array(kid_data, 0usize, kid_data.len, "Kids", kid_refs[0usize..]) != 300usize { ret 7u8 }

    // Exercise `walk` itself, not just the reference scanner: a flat /Pages node
    // with 300 children must keep all of them in page order.
    let (tree_builder0, tree_builder_error) = str.builder(a, 0usize)
    if tree_builder_error != ok { ret 17u8 }
    var tree_builder = tree_builder0
    if str.push(&tree_builder, "/Type /Pages /Kids [") != ok { ret 18u8 }
    page_at = 0usize
    while page_at < 300usize {
        if str.push_usize(&tree_builder, page_at + 2usize) != ok || str.push(&tree_builder, " 0 R ") != ok { ret 19u8 }
        page_at += 1usize
    }
    if str.push(&tree_builder, "]") != ok { ret 20u8 }
    let tree_root_end = tree_builder.len
    if str.push(&tree_builder, "/Type /Page") != ok { ret 21u8 }
    let tree_data = str.done(&tree_builder)
    var tree_objects: [301]pdf.Object = zero
    tree_objects[0usize].number = 1usize
    tree_objects[0usize].start = 0usize
    tree_objects[0usize].end = tree_root_end
    page_at = 0usize
    while page_at < 300usize {
        let object_at = page_at + 1usize
        tree_objects[object_at].number = page_at + 2usize
        tree_objects[object_at].start = tree_root_end
        tree_objects[object_at].end = tree_data.len
        page_at += 1usize
    }
    var walked_pages: [512]usize = zero
    let (walked_count, walked_error) = pdf.walk(a, tree_data, tree_objects[0usize..], 301usize, 1usize, walked_pages[0usize..])
    if walked_error != ok || walked_count != 300usize || walked_pages[0usize] != 2usize || walked_pages[299usize] != 301usize { ret 22u8 }

    var cid_widths: [4]u16 = zero
    let cid_data = "[-1 [500] 0 [70000]]"
    let cid_count = pdf.read_cid_widths(cid_data, 0usize, cid_data.len, cid_widths[0usize..])
    if cid_count != 1usize || cid_widths[0usize] != 65000u16 { ret 8u8 }
    let cid_font_data = "/Type /Font /Subtype /Type0 /DescendantFonts [2 0 R] /DW 70000 /W [0 [500]]"
    let cid_tail_at = pdf.find(cid_font_data, "/DW", 0usize, cid_font_data.len)
    var cid_objects: [2]pdf.Object = zero
    cid_objects[0usize].number = 1usize
    cid_objects[0usize].start = 0usize
    cid_objects[0usize].end = cid_tail_at
    cid_objects[1usize].number = 2usize
    cid_objects[1usize].start = cid_tail_at
    cid_objects[1usize].end = cid_font_data.len
    var cid_font_painter: pdf.Painter = zero
    cid_font_painter.data = cid_font_data
    cid_font_painter.table = cid_objects[0usize..]
    cid_font_painter.count = 2usize
    let (cid_font_index, cid_font_error) = pdf.load_font(a, &cid_font_painter, 1usize)
    if cid_font_error != ok || cid_font_index != 0usize || cid_font_painter.fonts[0usize].default_width != 65000usize { ret 24u8 }

    var cmap_font: pdf.FontInfo = zero
    var cmap_codes: [4]u16 = zero
    var cmap_unis: [4]str = zero
    let cmap_data = "1 beginbfchar <0003> <00660069> endbfchar 1 beginbfrange <0001> <0002> [<00660069> <0066006C>] endbfrange"
    let (cmap_count, cmap_error) = pdf.read_cmap(a, cmap_data, &cmap_font, cmap_codes[0usize..], cmap_unis[0usize..])
    if cmap_error != ok || cmap_count != 3usize || !str.eq(cmap_unis[0usize], "fi") || !str.eq(cmap_unis[1usize], "fi") || !str.eq(cmap_unis[2usize], "fl") { ret 9u8 }
    if !cmap_font.two_byte { ret 16u8 }
    cmap_font.codes = cmap_codes[0usize..cmap_count]
    cmap_font.unis = cmap_unis[0usize..cmap_count]
    cmap_font.mapped = cmap_count
    var cmap_painter: pdf.Painter = zero
    cmap_painter.fonts[0usize] = cmap_font
    cmap_painter.font_n = 1usize
    cmap_painter.cur_font = 0usize
    let (mapped, mapped_error) = pdf.text_run(a, "<000100020003> Tj", &cmap_painter)
    if mapped_error != ok { ret 10u8 }
    if mapped.len != 6usize { ret 14u8 }
    if mapped[0usize] != 102u8 || mapped[1usize] != 105u8 || mapped[2usize] != 102u8 || mapped[3usize] != 108u8 || mapped[4usize] != 102u8 || mapped[5usize] != 105u8 { ret 15u8 }

    // A ToUnicode destination can contain many UTF-16 units. Its UTF-8 output
    // must not be shortened by either text extraction or the painting buffer.
    var long_font: pdf.FontInfo = zero
    var long_codes: [1]u16 = zero
    var long_unis: [1]str = zero
    let long_cmap = "1 beginbfchar <04> <D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00> endbfchar"
    let (long_count, long_error) = pdf.read_cmap(a, long_cmap, &long_font, long_codes[0usize..], long_unis[0usize..])
    if long_error != ok || long_count != 1usize || long_unis[0usize].len != 80usize { ret 25u8 }
    long_font.codes = long_codes[0usize..long_count]
    long_font.unis = long_unis[0usize..long_count]
    long_font.mapped = long_count
    var long_text_painter: pdf.Painter = zero
    long_text_painter.fonts[0usize] = long_font
    long_text_painter.font_n = 1usize
    long_text_painter.cur_font = 0usize
    let (long_text, long_text_error) = pdf.text_run(a, "<04> Tj", &long_text_painter)
    if long_text_error != ok || long_text.len != 80usize { ret 26u8 }
    var long_shapes: [1]pdf.Shape = zero
    var long_paint_painter: pdf.Painter = zero
    long_paint_painter.out = long_shapes[0usize..]
    long_paint_painter.fonts[0usize] = long_font
    long_paint_painter.font_n = 1usize
    long_paint_painter.cur_font = 0usize
    long_paint_painter.scale_x = 1.0f64
    long_paint_painter.scale_y = 1.0f64
    long_paint_painter.font_size = 1.0f64
    long_paint_painter.text_scale = 1.0f64
    let long_raw: [1]u8 = [1]u8{ 4u8 }
    pdf.paint_run(a, &long_paint_painter, long_raw[0usize..])
    if long_paint_painter.n != 1usize || long_shapes[0usize].text.len != 80usize { ret 27u8 }

    // An explicit empty ToUnicode destination suppresses the glyph; it is not
    // the same as an unmapped source code, which falls back to Latin-1.
    var empty_font: pdf.FontInfo = zero
    var empty_codes: [1]u16 = zero
    var empty_unis: [1]str = zero
    let empty_cmap = "1 beginbfchar <41> <> endbfchar"
    let (empty_count, empty_error) = pdf.read_cmap(a, empty_cmap, &empty_font, empty_codes[0usize..], empty_unis[0usize..])
    if empty_error != ok || empty_count != 1usize || empty_unis[0usize].len != 0usize { ret 30u8 }
    empty_font.codes = empty_codes[0usize..empty_count]
    empty_font.unis = empty_unis[0usize..empty_count]
    empty_font.mapped = empty_count
    var empty_painter: pdf.Painter = zero
    empty_painter.fonts[0usize] = empty_font
    empty_painter.font_n = 1usize
    empty_painter.cur_font = 0usize
    let (empty_text, empty_text_error) = pdf.text_run(a, "(A) Tj", &empty_painter)
    if empty_text_error != ok || empty_text.len != 0usize { ret 31u8 }

    // `Tf` loads this font after text_run has sized its initial output buffer.
    // The loaded mapping must still grow the buffer before `(a)` is committed.
    let dynamic_data = "/Font << /F1 1 0 R >> /Type /Font /ToUnicode 2 0 R <<>>\nstream\n1 beginbfchar <61> <D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00 D83DDE00> endbfchar\nendstream"
    let dynamic_font_at = pdf.find(dynamic_data, "/Type /Font", 0usize, dynamic_data.len)
    let dynamic_cmap_at = pdf.find(dynamic_data, "<<>>", dynamic_font_at, dynamic_data.len)
    var dynamic_objects: [2]pdf.Object = zero
    dynamic_objects[0usize].number = 1usize
    dynamic_objects[0usize].start = dynamic_font_at
    dynamic_objects[0usize].end = dynamic_cmap_at
    dynamic_objects[1usize].number = 2usize
    dynamic_objects[1usize].start = dynamic_cmap_at
    dynamic_objects[1usize].end = dynamic_data.len
    var dynamic_painter: pdf.Painter = zero
    dynamic_painter.data = dynamic_data
    dynamic_painter.table = dynamic_objects[0usize..]
    dynamic_painter.count = 2usize
    dynamic_painter.res_s = 0usize
    dynamic_painter.res_e = dynamic_font_at
    let (dynamic_text, dynamic_text_error) = pdf.text_run(a, "/F1 1 Tf(a)Tj", &dynamic_painter)
    if dynamic_text_error != ok || dynamic_text.len != 80usize { ret 29u8 }

    let (shown, shown_error) = pdf.text_of(a, "BT /P <</MCID 0>> BDC /Span <</ActualText (fi)>> BDC (shown) Tj ET")
    if shown_error != ok || !str.eq(shown, "shown") { ret 11u8 }
    let (literal_dict, literal_dict_error) = pdf.text_of(a, "BT /Span <</ActualText (ignored >> (junk) Tj)>> BDC (shown) Tj ET")
    if literal_dict_error != ok || !str.eq(literal_dict, "shown") { ret 28u8 }

    var image_painter: pdf.Painter = zero
    image_painter.data = "<< /Width 999999999 /Height 999999999 >>"
    let (_, giant_image) = pdf.decode_image(a, &image_painter, 0usize, image_painter.data.len)
    if giant_image { ret 12u8 }
    image_painter.data = "<< /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Predictor 12 /Colors 999999999 /Columns 999999999 /Length 1 >>\nstream\nx\nendstream"
    let (_, giant_row) = pdf.decode_image(a, &image_painter, 0usize, image_painter.data.len)
    if giant_row { ret 13u8 }
    ret 0u8
}

// Run before the regular fixture consumes its shared arena. The exact buffer is
// reset immediately after the count, so the 65,537-entry cap stays covered
// without retaining a megabyte of generated test text.
fn issue_78_cmap_limit_check(a: *mem.Arena) -> u8 {
    let before = mem.mark(a)
    let prefix = "1 beginbfchar "
    let entry = "<0> <0> "
    let suffix = "endbfchar"
    let total = prefix.len + 65537usize * entry.len + suffix.len
    let (data, data_error) = mem.alloc[u8](a, total)
    if data_error != ok {
        mem.reset(a, before)
        ret 1u8
    }
    var at = 0usize
    mem.copy[u8](data[at..at + prefix.len], prefix)
    at += prefix.len
    var entry_at = 0usize
    while entry_at < 65537usize {
        mem.copy[u8](data[at..at + entry.len], entry)
        at += entry.len
        entry_at += 1usize
    }
    mem.copy[u8](data[at..at + suffix.len], suffix)
    let (_, limit_error) = pdf.cmap_entry_count(data)
    mem.reset(a, before)
    if limit_error != pdf.TooLarge { ret 2u8 }
    ret 0u8
}

// Follow-up regressions for the remaining #78 reader findings. Keep these
// generated inputs small enough to exercise the parser without checked-in PDFs.
fn issue_78_remaining_check(a: *mem.Arena) -> u8 {
    // A decimal TJ adjustment is a number, not its digits with the point removed.
    let (fractional, fractional_error) = pdf.text_of(a, "[(Wor) -2.31 (ld)] TJ")
    if fractional_error != ok || !str.eq(fractional, "World") { ret 1u8 }
    let (word_gap, word_gap_error) = pdf.text_of(a, "[(A) -200.5 (B)] TJ")
    if word_gap_error != ok || !str.eq(word_gap, "A B") { ret 2u8 }

    // x-only moves start a new independently positioned word, while a nonzero
    // y operand still starts a text line.
    let (x_moves, x_moves_error) = pdf.text_of(a, "(one) Tj 30 0 Td (two) Tj 1 0 0 1 40 0 Tm (three) Tj")
    if x_moves_error != ok || !str.eq(x_moves, "one two three") { ret 3u8 }

    // Legacy metadata and CMap parsing must not combine a high surrogate with
    // an arbitrary next unit.
    let (orphan, _, _, orphan_ok) = pdf.hex_value("<D8000041>", 0usize, 10usize)
    if !orphan_ok || orphan != 65533u32 { ret 4u8 }
    let legacy = "/Title <FEFFD8000041>"
    let title = pdf.string_after(a, legacy, 0usize, legacy.len, "Title")
    if title.len != 4usize || title[0usize] != 239u8 || title[1usize] != 191u8 || title[2usize] != 189u8 || title[3usize] != 65u8 { ret 5u8 }
    let (cmap_orphan, _, cmap_orphan_ok) = pdf.hex_text(a, "<D8000041>", 0usize, 10usize, 0u32)
    if !cmap_orphan_ok || cmap_orphan.len != 4usize || cmap_orphan[0usize] != 239u8 || cmap_orphan[1usize] != 191u8 || cmap_orphan[2usize] != 189u8 || cmap_orphan[3usize] != 65u8 { ret 38u8 }
    let (_, _, unterminated_at, unterminated_ok) = pdf.hex_value("<D800", 0usize, 5usize)
    if unterminated_ok || unterminated_at != 5usize { ret 39u8 }

    // A ninth q spills beyond the inline slots. Its matching Q must restore the
    // eighth scale after an inner transformation, rather than popping it (256).
    let (state_builder0, state_builder_error) = str.builder(a, 0usize)
    if state_builder_error != ok { ret 6u8 }
    var state_builder = state_builder0
    var state_at = 0usize
    while state_at < 8usize {
        if str.push(&state_builder, "q 2 0 0 2 0 0 cm ") != ok { ret 7u8 }
        state_at += 1usize
    }
    if str.push(&state_builder, "q 2 0 0 2 0 0 cm Q 0 0 1 1 re f") != ok { ret 8u8 }
    var state_shapes: [1]pdf.Shape = zero
    var state_painter = pdf.paint_start(state_shapes[0usize..])
    let state_error = pdf.paint_content(a, &state_painter, str.done(&state_builder))
    if state_error != ok || state_painter.n != 1usize || state_shapes[0usize].x1 != 256.0f64 { ret 9u8 }

    // Resources and MediaBox inherit strictly through this page's Parent chain.
    let inherited = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 3 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Resources << /Font << /F1 7 0 R >> >> /MediaBox [0 0 111 222] >>\nendobj\n3 0 obj\n<< /Type /Pages /Kids [4 0 R] /Resources << /Font << /F1 5 0 R >> >> /MediaBox [0 0 300 400] >>\nendobj\n4 0 obj\n<< /Type /Page /Parent 3 0 R /Contents 6 0 R >>\nendobj\n5 0 obj\n<< /Type /Font /ToUnicode 8 0 R >>\nendobj\n6 0 obj\n<<>>\nstream\nBT /F1 12 Tf (A) Tj ET\nendstream\nendobj\n7 0 obj\n<< /Type /Font /ToUnicode 9 0 R >>\nendobj\n8 0 obj\n<<>>\nstream\n1 beginbfchar <41> <005A> endbfchar\nendstream\nendobj\n9 0 obj\n<<>>\nstream\n1 beginbfchar <41> <0058> endbfchar\nendstream\nendobj\n"
    let (inherited_pages, inherited_error) = pdf.pages(a, inherited)
    if inherited_error != ok || inherited_pages.len != 1usize || !str.eq(inherited_pages[0usize], "Z") { ret 10u8 }
    let (inherited_painting, inherited_painting_error) = pdf.page_painting(a, inherited, 0usize)
    if inherited_painting_error != ok || inherited_painting.width != 300.0f64 || inherited_painting.height != 400.0f64 { ret 11u8 }

    // More than the old 64 /Contents references are all joined in source order.
    let (contents_builder0, contents_builder_error) = str.builder(a, 0usize)
    if contents_builder_error != ok { ret 12u8 }
    var contents_builder = contents_builder0
    if str.push(&contents_builder, "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents [") != ok { ret 13u8 }
    var contents_at = 0usize
    while contents_at < 65usize {
        if str.push_usize(&contents_builder, contents_at + 4usize) != ok || str.push(&contents_builder, " 0 R ") != ok { ret 14u8 }
        contents_at += 1usize
    }
    if str.push(&contents_builder, "] >>\nendobj\n") != ok { ret 15u8 }
    contents_at = 0usize
    while contents_at < 65usize {
        if str.push_usize(&contents_builder, contents_at + 4usize) != ok || str.push(&contents_builder, " 0 obj\n<<>>\nstream\n(x) Tj\nendstream\nendobj\n") != ok { ret 16u8 }
        contents_at += 1usize
    }
    let (many_contents, many_contents_error) = pdf.pages(a, str.done(&contents_builder))
    if many_contents_error != ok || many_contents.len != 1usize || many_contents[0usize].len != 129usize { ret 17u8 }

    // The former 1,024-entry ToUnicode allocation grows to the exact CMap size.
    let loaded_cmap = "/Type /Font /ToUnicode 2 0 R <<>>\nstream\n1 beginbfrange <0000> <0400> <0041> endbfrange\nendstream"
    let cmap_stream_at = pdf.find(loaded_cmap, "<<>>", 0usize, loaded_cmap.len)
    var loaded_cmap_objects: [2]pdf.Object = zero
    loaded_cmap_objects[0usize].number = 1usize
    loaded_cmap_objects[0usize].start = 0usize
    loaded_cmap_objects[0usize].end = cmap_stream_at
    loaded_cmap_objects[1usize].number = 2usize
    loaded_cmap_objects[1usize].start = cmap_stream_at
    loaded_cmap_objects[1usize].end = loaded_cmap.len
    var loaded_cmap_painter: pdf.Painter = zero
    loaded_cmap_painter.data = loaded_cmap
    loaded_cmap_painter.table = loaded_cmap_objects[0usize..]
    loaded_cmap_painter.count = 2usize
    let (loaded_cmap_font, loaded_cmap_error) = pdf.load_font(a, &loaded_cmap_painter, 1usize)
    if loaded_cmap_error != ok || loaded_cmap_font != 0usize || loaded_cmap_painter.fonts[0usize].mapped != 1025usize { ret 18u8 }

    // Object and stream boundaries are reported, never returned as a partial document.
    let (object_builder0, object_builder_error) = str.builder(a, 0usize)
    if object_builder_error != ok { ret 19u8 }
    var object_builder = object_builder0
    var object_at = 0usize
    while object_at < 4097usize {
        if str.push_usize(&object_builder, object_at + 1usize) != ok || str.push(&object_builder, " 0 obj\n<<>>\nendobj\n") != ok { ret 20u8 }
        object_at += 1usize
    }
    let (_, _, object_limit_error) = pdf.objects(a, str.done(&object_builder))
    if object_limit_error != pdf.TooLarge { ret 21u8 }
    let cap_stream = "<<>>\nstream\nfour\nendstream"
    let (capped, capped_error) = pdf.stream_capped(a, cap_stream, 0usize, cap_stream.len, 3usize)
    if capped_error != pdf.TooLarge || capped.len != 0usize { ret 22u8 }
    let flate_cap_stream = "<< /Filter /FlateDecode >>\nstream\n\x78\x9c\x4b\xcb\x2f\x2d\x02\x00\x04\x45\x01\xbd\nendstream"
    let (_, flate_cap_error) = pdf.stream_capped(a, flate_cap_stream, 0usize, flate_cap_stream.len, 3usize)
    if flate_cap_error != pdf.TooLarge { ret 41u8 }
    let invalid_a85_stream = "<< /Filter /ASCII85Decode >>\nstream\nv\nendstream"
    let (_, invalid_a85_error) = pdf.stream_capped(a, invalid_a85_stream, 0usize, invalid_a85_stream.len, 8usize)
    if invalid_a85_error != pdf.InvalidAscii85 { ret 40u8 }

    // Each page gets a fresh eight-slot font cache; the ninth distinct font must
    // still apply its shared ToUnicode map instead of falling back to Latin-1.
    let (font_pages_builder0, font_pages_builder_error) = str.builder(a, 0usize)
    if font_pages_builder_error != ok { ret 28u8 }
    var font_pages_builder = font_pages_builder0
    if str.push(&font_pages_builder, "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [") != ok { ret 29u8 }
    var font_page_at = 0usize
    while font_page_at < 9usize {
        if str.push_usize(&font_pages_builder, font_page_at + 3usize) != ok || str.push(&font_pages_builder, " 0 R ") != ok { ret 30u8 }
        font_page_at += 1usize
    }
    if str.push(&font_pages_builder, "] >>\nendobj\n") != ok { ret 31u8 }
    font_page_at = 0usize
    while font_page_at < 9usize {
        if str.push_usize(&font_pages_builder, font_page_at + 3usize) != ok || str.push(&font_pages_builder, " 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 ") != ok || str.push_usize(&font_pages_builder, font_page_at + 12usize) != ok || str.push(&font_pages_builder, " 0 R >> >> /Contents ") != ok || str.push_usize(&font_pages_builder, font_page_at + 22usize) != ok || str.push(&font_pages_builder, " 0 R >>\nendobj\n") != ok { ret 32u8 }
        font_page_at += 1usize
    }
    font_page_at = 0usize
    while font_page_at < 9usize {
        if str.push_usize(&font_pages_builder, font_page_at + 12usize) != ok || str.push(&font_pages_builder, " 0 obj\n<< /Type /Font /ToUnicode 21 0 R >>\nendobj\n") != ok { ret 33u8 }
        font_page_at += 1usize
    }
    if str.push(&font_pages_builder, "21 0 obj\n<<>>\nstream\n1 beginbfchar <41> <005A> endbfchar\nendstream\nendobj\n") != ok { ret 34u8 }
    font_page_at = 0usize
    while font_page_at < 9usize {
        if str.push_usize(&font_pages_builder, font_page_at + 22usize) != ok || str.push(&font_pages_builder, " 0 obj\n<<>>\nstream\nBT /F1 12 Tf (A) Tj ET\nendstream\nendobj\n") != ok { ret 35u8 }
        font_page_at += 1usize
    }
    let (font_pages, font_pages_error) = pdf.pages(a, str.done(&font_pages_builder))
    if font_pages_error != ok || font_pages.len != 9usize { ret 36u8 }
    font_page_at = 0usize
    while font_page_at < font_pages.len {
        if !str.eq(font_pages[font_page_at], "Z") { ret 37u8 }
        font_page_at += 1usize
    }

    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    let cmap_limit_check = issue_78_cmap_limit_check(a)
    if cmap_limit_check != 0u8 { os.exit(96i32 + i32(cmap_limit_check)) }
    let plain: [964]u8 = [964]u8{ 37, 80, 68, 70, 45, 49, 46, 52, 10, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 67, 97, 116, 97, 108, 111, 103, 32, 47, 80, 97, 103, 101, 115, 32, 50, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 32, 47, 75, 105, 100, 115, 32, 91, 51, 32, 48, 32, 82, 32, 53, 32, 48, 32, 82, 93, 32, 47, 67, 111, 117, 110, 116, 32, 50, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 32, 47, 80, 97, 114, 101, 110, 116, 32, 50, 32, 48, 32, 82, 32, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 52, 32, 48, 32, 82, 32, 47, 82, 101, 115, 111, 117, 114, 99, 101, 115, 32, 60, 60, 32, 47, 70, 111, 110, 116, 32, 60, 60, 32, 47, 70, 49, 32, 55, 32, 48, 32, 82, 32, 62, 62, 32, 62, 62, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 48, 32, 48, 32, 54, 49, 50, 32, 55, 57, 50, 93, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 76, 101, 110, 103, 116, 104, 32, 49, 51, 54, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 66, 84, 32, 47, 70, 49, 32, 49, 50, 32, 84, 102, 32, 55, 50, 32, 55, 48, 48, 32, 84, 100, 32, 40, 72, 101, 108, 108, 111, 44, 32, 80, 68, 70, 32, 119, 111, 114, 108, 100, 41, 32, 84, 106, 32, 48, 32, 45, 49, 52, 32, 84, 100, 32, 91, 40, 78, 101, 112, 101, 114, 41, 32, 45, 51, 50, 48, 32, 40, 112, 104, 111, 110, 101, 41, 32, 50, 48, 32, 40, 33, 41, 93, 32, 84, 74, 32, 48, 32, 45, 49, 52, 32, 84, 100, 32, 40, 97, 32, 92, 40, 112, 97, 114, 101, 110, 92, 41, 32, 97, 110, 100, 32, 92, 49, 48, 49, 32, 97, 110, 100, 32, 99, 97, 102, 92, 51, 53, 49, 41, 32, 84, 106, 32, 69, 84, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 53, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 32, 47, 80, 97, 114, 101, 110, 116, 32, 50, 32, 48, 32, 82, 32, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 54, 32, 48, 32, 82, 32, 47, 82, 101, 115, 111, 117, 114, 99, 101, 115, 32, 60, 60, 32, 47, 70, 111, 110, 116, 32, 60, 60, 32, 47, 70, 49, 32, 55, 32, 48, 32, 82, 32, 62, 62, 32, 62, 62, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 48, 32, 48, 32, 54, 49, 50, 32, 55, 57, 50, 93, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 54, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 76, 101, 110, 103, 116, 104, 32, 54, 49, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 66, 84, 32, 47, 70, 49, 32, 49, 50, 32, 84, 102, 32, 55, 50, 32, 55, 48, 48, 32, 84, 100, 32, 60, 52, 56, 54, 53, 54, 99, 54, 99, 54, 102, 62, 32, 84, 106, 32, 84, 42, 32, 40, 115, 101, 99, 111, 110, 100, 32, 108, 105, 110, 101, 41, 32, 84, 106, 32, 69, 84, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 55, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 84, 121, 112, 101, 49, 32, 47, 66, 97, 115, 101, 70, 111, 110, 116, 32, 47, 72, 101, 108, 118, 101, 116, 105, 99, 97, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 120, 114, 101, 102, 10, 48, 32, 56, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 32, 54, 53, 53, 51, 53, 32, 102, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 57, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 53, 56, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 49, 50, 49, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 50, 52, 55, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 52, 51, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 53, 54, 48, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 54, 55, 49, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 116, 114, 97, 105, 108, 101, 114, 10, 60, 60, 32, 47, 83, 105, 122, 101, 32, 56, 32, 47, 82, 111, 111, 116, 32, 49, 32, 48, 32, 82, 32, 62, 62, 10, 115, 116, 97, 114, 116, 120, 114, 101, 102, 10, 55, 52, 49, 10, 37, 37, 69, 79, 70, 10 }
    let nested: [834]u8 = [834]u8{ 37, 80, 68, 70, 45, 49, 46, 52, 10, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 67, 97, 116, 97, 108, 111, 103, 32, 47, 80, 97, 103, 101, 115, 32, 50, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 32, 47, 75, 105, 100, 115, 32, 91, 56, 32, 48, 32, 82, 32, 51, 32, 48, 32, 82, 93, 32, 47, 67, 111, 117, 110, 116, 32, 50, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 32, 47, 80, 97, 114, 101, 110, 116, 32, 50, 32, 48, 32, 82, 32, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 52, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 76, 101, 110, 103, 116, 104, 32, 54, 49, 32, 47, 70, 105, 108, 116, 101, 114, 32, 47, 70, 108, 97, 116, 101, 68, 101, 99, 111, 100, 101, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 120, 156, 115, 10, 81, 208, 119, 51, 84, 48, 52, 82, 8, 73, 83, 48, 55, 82, 48, 55, 48, 80, 8, 73, 81, 208, 112, 206, 207, 45, 40, 74, 45, 46, 78, 77, 81, 40, 46, 41, 74, 77, 204, 85, 40, 73, 173, 40, 209, 84, 8, 201, 82, 112, 13, 1, 0, 122, 174, 15, 128, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 56, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 32, 47, 80, 97, 114, 101, 110, 116, 32, 50, 32, 48, 32, 82, 32, 47, 75, 105, 100, 115, 32, 91, 57, 32, 48, 32, 82, 93, 32, 47, 67, 111, 117, 110, 116, 32, 49, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 57, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 32, 47, 80, 97, 114, 101, 110, 116, 32, 56, 32, 48, 32, 82, 32, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 49, 48, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 48, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 76, 101, 110, 103, 116, 104, 32, 52, 55, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 66, 84, 32, 47, 70, 49, 32, 49, 50, 32, 84, 102, 32, 55, 50, 32, 55, 48, 48, 32, 84, 100, 32, 40, 84, 114, 101, 101, 32, 111, 114, 100, 101, 114, 32, 102, 105, 114, 115, 116, 41, 32, 84, 106, 32, 69, 84, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 120, 114, 101, 102, 10, 48, 32, 49, 49, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 32, 54, 53, 53, 51, 53, 32, 102, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 57, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 53, 56, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 49, 50, 49, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 49, 56, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 51, 49, 54, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 51, 56, 55, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 52, 53, 49, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 116, 114, 97, 105, 108, 101, 114, 10, 60, 60, 32, 47, 83, 105, 122, 101, 32, 49, 49, 32, 47, 82, 111, 111, 116, 32, 49, 32, 48, 32, 82, 32, 62, 62, 10, 115, 116, 97, 114, 116, 120, 114, 101, 102, 10, 53, 52, 57, 10, 37, 37, 69, 79, 70, 10 }
    let array: [532]u8 = [532]u8{ 37, 80, 68, 70, 45, 49, 46, 52, 10, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 67, 97, 116, 97, 108, 111, 103, 32, 47, 80, 97, 103, 101, 115, 32, 50, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 32, 47, 75, 105, 100, 115, 32, 91, 51, 32, 48, 32, 82, 93, 32, 47, 67, 111, 117, 110, 116, 32, 49, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 32, 47, 80, 97, 114, 101, 110, 116, 32, 50, 32, 48, 32, 82, 32, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 91, 52, 32, 48, 32, 82, 32, 53, 32, 48, 32, 82, 93, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 76, 101, 110, 103, 116, 104, 32, 51, 49, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 66, 84, 32, 55, 50, 32, 55, 48, 48, 32, 84, 100, 32, 40, 102, 105, 114, 115, 116, 32, 112, 97, 114, 116, 41, 32, 84, 106, 32, 69, 84, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 53, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 76, 101, 110, 103, 116, 104, 32, 51, 50, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 66, 84, 32, 55, 50, 32, 54, 48, 48, 32, 84, 100, 32, 40, 115, 101, 99, 111, 110, 100, 32, 112, 97, 114, 116, 41, 32, 84, 106, 32, 69, 84, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 120, 114, 101, 102, 10, 48, 32, 54, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 32, 54, 53, 53, 51, 53, 32, 102, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 57, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 53, 56, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 49, 49, 53, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 49, 56, 54, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 50, 54, 55, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 116, 114, 97, 105, 108, 101, 114, 10, 60, 60, 32, 47, 83, 105, 122, 101, 32, 54, 32, 47, 82, 111, 111, 116, 32, 49, 32, 48, 32, 82, 32, 62, 62, 10, 115, 116, 97, 114, 116, 120, 114, 101, 102, 10, 51, 52, 57, 10, 37, 37, 69, 79, 70, 10 }
    let (p, p_error) = pdf.pages(a, plain[0..])
    if p_error != ok { os.exit(1) }
    if p.len != 2usize { os.exit(2) }
    if !str.eq(p[0], "Hello, PDF world\nNeper phone!\na (paren) and A and caf\xc3\xa9") { os.exit(3) }
    if !str.eq(p[1], "Hello\nsecond line") { os.exit(4) }
    let (n, n_error) = pdf.pages(a, nested[0..])
    if n_error != ok { os.exit(5) }
    if n.len != 2usize { os.exit(6) }
    if !str.eq(n[0], "Tree order first") { os.exit(7) }
    if !str.eq(n[1], "Compressed stream text") { os.exit(8) }
    let (r, r_error) = pdf.pages(a, array[0..])
    if r_error != ok { os.exit(9) }
    if r.len != 1usize || !str.eq(r[0], "first part\nsecond part") { os.exit(10) }
    // A stream's declared bytes may contain PDF keywords as literal text. They must not
    // end the object or stream before the real markers after the declared length.
    let keywords = r#"%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 41 >>
stream
BT (before endobj endstream after) Tj ET
endstream
endobj
"#
    let (keyword_pages, keyword_error) = pdf.pages(a, keywords)
    if keyword_error != ok || keyword_pages.len != 1usize { os.exit(54) }
    if !str.eq(keyword_pages[0usize], "before endobj endstream after") { os.exit(55) }
    // Names may spell structural keywords. They must neither truncate an object nor
    // be taken for the start or end of a stream.
    let named_endobj = r#"%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /endobj /ignored /Type /Page /Parent 2 0 R /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 16 >>
stream
BT (name) Tj ET
endstream
endobj
"#
    let (endobj_pages, endobj_error) = pdf.pages(a, named_endobj)
    if endobj_error != ok || endobj_pages.len != 1usize { os.exit(56) }
    if !str.eq(endobj_pages[0usize], "name") { os.exit(57) }
    let named_stream = r#"%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /stream /ignored /Type /Page /Parent 2 0 R /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 16 >>
stream
BT (name) Tj ET
endstream
endobj
"#
    let (stream_pages, stream_error) = pdf.pages(a, named_stream)
    if stream_error != ok || stream_pages.len != 1usize { os.exit(58) }
    if !str.eq(stream_pages[0usize], "name") { os.exit(59) }
    let named_endstream = r#"%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>
endobj
4 0 obj
<< >>
stream
/endstream noop
BT (name) Tj ET
endstream
endobj
"#
    let (endstream_pages, endstream_error) = pdf.pages(a, named_endstream)
    if endstream_error != ok || endstream_pages.len != 1usize { os.exit(60) }
    if !str.eq(endstream_pages[0usize], "name") { os.exit(61) }
    let painted: [494]u8 = [494]u8{ 37, 80, 68, 70, 45, 49, 46, 52, 10, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 67, 97, 116, 97, 108, 111, 103, 32, 47, 80, 97, 103, 101, 115, 32, 50, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 32, 47, 75, 105, 100, 115, 32, 91, 51, 32, 48, 32, 82, 93, 32, 47, 67, 111, 117, 110, 116, 32, 49, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 48, 32, 48, 32, 52, 48, 48, 32, 56, 48, 48, 93, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 32, 47, 80, 97, 114, 101, 110, 116, 32, 50, 32, 48, 32, 82, 32, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 52, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 76, 101, 110, 103, 116, 104, 32, 50, 49, 48, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 113, 32, 49, 32, 48, 32, 48, 32, 114, 103, 32, 49, 48, 48, 32, 54, 48, 48, 32, 50, 48, 48, 32, 53, 48, 32, 114, 101, 32, 102, 32, 81, 10, 48, 32, 48, 32, 49, 32, 82, 71, 32, 51, 32, 119, 32, 49, 48, 48, 32, 53, 48, 48, 32, 109, 32, 51, 48, 48, 32, 53, 48, 48, 32, 108, 32, 83, 10, 66, 84, 32, 47, 70, 49, 32, 49, 56, 32, 84, 102, 32, 55, 50, 32, 55, 48, 48, 32, 84, 100, 32, 40, 72, 101, 108, 108, 111, 41, 32, 84, 106, 32, 69, 84, 10, 113, 32, 48, 46, 53, 32, 48, 32, 48, 32, 48, 46, 53, 32, 49, 48, 32, 50, 48, 32, 99, 109, 32, 48, 46, 53, 32, 103, 32, 48, 32, 48, 32, 52, 48, 32, 52, 48, 32, 114, 101, 32, 102, 32, 81, 10, 66, 84, 32, 47, 70, 49, 32, 49, 48, 32, 84, 102, 32, 48, 32, 48, 32, 48, 32, 49, 32, 107, 32, 53, 48, 32, 52, 48, 48, 32, 84, 100, 32, 91, 40, 84, 101, 97, 41, 32, 45, 51, 48, 48, 32, 40, 98, 97, 103, 115, 41, 93, 32, 84, 74, 32, 69, 84, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 116, 114, 97, 105, 108, 101, 114, 10, 60, 60, 32, 47, 82, 111, 111, 116, 32, 49, 32, 48, 32, 82, 32, 62, 62, 10, 37, 37, 69, 79, 70, 10 }
    let junk: [20]u8 = [20]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }
    let (j, j_error) = pdf.pages(a, junk[0..])
    if j_error != pdf.NotPdf { os.exit(11) }
    let empty = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n"
    let (e, e_error) = pdf.pages(a, empty)
    if e_error != pdf.NoPages { os.exit(12) }
    // (C152) A page painted: shapes with their colours, a `cm` scale and offset, a kern as a word space.
    let (painting, painting_error) = pdf.page_painting(a, painted[0..], 0usize)
    if painting_error != ok { os.exit(13) }
    if painting.width != 400.0f64 || painting.height != 800.0f64 || painting.shapes.len != 5usize { os.exit(14) }
    let s0 = painting.shapes[0]
    if s0.kind != pdf.SHAPE_FILL || s0.x0 != 100.0f64 || s0.y0 != 600.0f64 || s0.x1 != 300.0f64 || s0.y1 != 650.0f64 || s0.red != 1.0f64 || s0.green != 0.0f64 || s0.blue != 0.0f64 { os.exit(15) }
    let s1 = painting.shapes[1]
    if s1.kind != pdf.SHAPE_LINE || s1.x0 != 100.0f64 || s1.y0 != 500.0f64 || s1.x1 != 300.0f64 || s1.y1 != 500.0f64 || s1.width != 3.0f64 || s1.blue != 1.0f64 || s1.red != 0.0f64 { os.exit(16) }
    let s2 = painting.shapes[2]
    if s2.kind != pdf.SHAPE_TEXT || !str.eq(s2.text, "Hello") || s2.x0 != 72.0f64 || s2.y0 != 700.0f64 || s2.size != 18.0f64 || s2.red != 0.0f64 { os.exit(17) }
    let s3 = painting.shapes[3]
    if s3.kind != pdf.SHAPE_FILL || s3.x0 != 10.0f64 || s3.y0 != 20.0f64 || s3.x1 != 30.0f64 || s3.y1 != 40.0f64 || s3.red != 0.5f64 { os.exit(18) }
    let s4 = painting.shapes[4]
    if s4.kind != pdf.SHAPE_TEXT || !str.eq(s4.text, "Tea bags") { os.exit(19) }
    if s4.x0 != 50.0f64 || s4.y0 != 400.0f64 { os.exit(21) }
    if s4.size != 10.0f64 { os.exit(22) }
    if s4.red != 0.0f64 || s4.green != 0.0f64 || s4.blue != 0.0f64 { os.exit(23) }
    let (no_page, no_page_error) = pdf.page_painting(a, painted[0..], 1usize)
    if no_page_error != pdf.NoPages { os.exit(20) }
    let img_pdf: [1809]u8 = [1809]u8{ 37, 80, 68, 70, 45, 49, 46, 52, 10, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 67, 97, 116, 97, 108, 111, 103, 32, 47, 80, 97, 103, 101, 115, 32, 50, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 32, 47, 75, 105, 100, 115, 32, 91, 51, 32, 48, 32, 82, 93, 32, 47, 67, 111, 117, 110, 116, 32, 49, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 48, 32, 48, 32, 50, 48, 48, 32, 50, 48, 48, 93, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 32, 47, 80, 97, 114, 101, 110, 116, 32, 50, 32, 48, 32, 82, 32, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 52, 32, 48, 32, 82, 32, 47, 82, 101, 115, 111, 117, 114, 99, 101, 115, 32, 60, 60, 32, 47, 88, 79, 98, 106, 101, 99, 116, 32, 60, 60, 32, 47, 73, 109, 49, 32, 53, 32, 48, 32, 82, 32, 47, 73, 109, 50, 32, 54, 32, 48, 32, 82, 32, 47, 73, 109, 51, 32, 55, 32, 48, 32, 82, 32, 47, 70, 109, 49, 32, 56, 32, 48, 32, 82, 32, 62, 62, 32, 62, 62, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 32, 47, 76, 101, 110, 103, 116, 104, 32, 49, 49, 52, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 113, 32, 49, 48, 48, 32, 48, 32, 48, 32, 49, 48, 48, 32, 49, 48, 32, 50, 48, 32, 99, 109, 32, 47, 73, 109, 49, 32, 68, 111, 32, 81, 10, 113, 32, 54, 48, 32, 48, 32, 48, 32, 52, 48, 32, 49, 51, 48, 32, 49, 53, 48, 32, 99, 109, 32, 47, 73, 109, 50, 32, 68, 111, 32, 81, 10, 113, 32, 49, 54, 32, 48, 32, 48, 32, 52, 32, 49, 48, 32, 49, 53, 48, 32, 99, 109, 32, 48, 32, 48, 32, 49, 32, 114, 103, 32, 47, 73, 109, 51, 32, 68, 111, 32, 81, 10, 47, 70, 109, 49, 32, 68, 111, 10, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 53, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 88, 79, 98, 106, 101, 99, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 73, 109, 97, 103, 101, 32, 47, 87, 105, 100, 116, 104, 32, 56, 32, 47, 72, 101, 105, 103, 104, 116, 32, 56, 32, 47, 67, 111, 108, 111, 114, 83, 112, 97, 99, 101, 32, 47, 68, 101, 118, 105, 99, 101, 82, 71, 66, 32, 47, 66, 105, 116, 115, 80, 101, 114, 67, 111, 109, 112, 111, 110, 101, 110, 116, 32, 56, 32, 47, 70, 105, 108, 116, 101, 114, 32, 47, 68, 67, 84, 68, 101, 99, 111, 100, 101, 32, 47, 76, 101, 110, 103, 116, 104, 32, 54, 51, 53, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 255, 219, 0, 67, 0, 2, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2, 2, 2, 2, 2, 4, 3, 2, 2, 2, 2, 5, 4, 4, 3, 4, 6, 5, 6, 6, 6, 5, 6, 6, 6, 7, 9, 8, 6, 7, 9, 7, 6, 6, 8, 11, 8, 9, 10, 10, 10, 10, 10, 6, 8, 11, 12, 11, 10, 12, 9, 10, 10, 10, 255, 219, 0, 67, 1, 2, 2, 2, 2, 2, 2, 5, 3, 3, 5, 10, 7, 6, 7, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 255, 192, 0, 17, 8, 0, 8, 0, 8, 3, 1, 34, 0, 2, 17, 1, 3, 17, 1, 255, 196, 0, 31, 0, 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 255, 196, 0, 181, 16, 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125, 1, 2, 3, 0, 4, 17, 5, 18, 33, 49, 65, 6, 19, 81, 97, 7, 34, 113, 20, 50, 129, 145, 161, 8, 35, 66, 177, 193, 21, 82, 209, 240, 36, 51, 98, 114, 130, 9, 10, 22, 23, 24, 25, 26, 37, 38, 39, 40, 41, 42, 52, 53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116, 117, 118, 119, 120, 121, 122, 131, 132, 133, 134, 135, 136, 137, 138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198, 199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 255, 196, 0, 31, 1, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 255, 196, 0, 181, 17, 0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119, 0, 1, 2, 3, 17, 4, 5, 33, 49, 6, 18, 65, 81, 7, 97, 113, 19, 34, 50, 129, 8, 20, 66, 145, 161, 177, 193, 9, 35, 51, 82, 240, 21, 98, 114, 209, 10, 22, 36, 52, 225, 37, 241, 23, 24, 25, 26, 38, 39, 40, 41, 42, 53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116, 117, 118, 119, 120, 121, 122, 130, 131, 132, 133, 134, 135, 136, 137, 138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198, 199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 226, 227, 228, 229, 230, 231, 232, 233, 234, 242, 243, 244, 245, 246, 247, 248, 249, 250, 255, 218, 0, 12, 3, 1, 0, 2, 17, 3, 17, 0, 63, 0, 249, 110, 138, 40, 175, 231, 243, 253, 68, 63, 255, 217, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 54, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 88, 79, 98, 106, 101, 99, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 73, 109, 97, 103, 101, 32, 47, 87, 105, 100, 116, 104, 32, 54, 32, 47, 72, 101, 105, 103, 104, 116, 32, 52, 32, 47, 67, 111, 108, 111, 114, 83, 112, 97, 99, 101, 32, 47, 68, 101, 118, 105, 99, 101, 82, 71, 66, 32, 47, 66, 105, 116, 115, 80, 101, 114, 67, 111, 109, 112, 111, 110, 101, 110, 116, 32, 56, 32, 47, 70, 105, 108, 116, 101, 114, 32, 47, 70, 108, 97, 116, 101, 68, 101, 99, 111, 100, 101, 32, 47, 68, 101, 99, 111, 100, 101, 80, 97, 114, 109, 115, 32, 60, 60, 32, 47, 80, 114, 101, 100, 105, 99, 116, 111, 114, 32, 49, 53, 32, 47, 67, 111, 108, 111, 114, 115, 32, 51, 32, 47, 66, 105, 116, 115, 80, 101, 114, 67, 111, 109, 112, 111, 110, 101, 110, 116, 32, 56, 32, 47, 67, 111, 108, 117, 109, 110, 115, 32, 54, 32, 62, 62, 32, 47, 76, 101, 110, 103, 116, 104, 32, 51, 52, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 120, 156, 99, 100, 96, 16, 212, 96, 102, 64, 70, 44, 236, 54, 12, 236, 204, 34, 200, 8, 46, 164, 1, 71, 200, 66, 54, 16, 4, 0, 147, 244, 4, 93, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 55, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 88, 79, 98, 106, 101, 99, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 73, 109, 97, 103, 101, 32, 47, 87, 105, 100, 116, 104, 32, 56, 32, 47, 72, 101, 105, 103, 104, 116, 32, 50, 32, 47, 73, 109, 97, 103, 101, 77, 97, 115, 107, 32, 116, 114, 117, 101, 32, 47, 66, 105, 116, 115, 80, 101, 114, 67, 111, 109, 112, 111, 110, 101, 110, 116, 32, 49, 32, 47, 76, 101, 110, 103, 116, 104, 32, 50, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 170, 240, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 56, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 88, 79, 98, 106, 101, 99, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 70, 111, 114, 109, 32, 47, 66, 66, 111, 120, 32, 91, 48, 32, 48, 32, 50, 48, 48, 32, 50, 48, 48, 93, 32, 47, 76, 101, 110, 103, 116, 104, 32, 50, 54, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 48, 32, 49, 32, 48, 32, 114, 103, 32, 49, 53, 48, 32, 49, 48, 32, 51, 48, 32, 51, 48, 32, 114, 101, 32, 102, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 116, 114, 97, 105, 108, 101, 114, 10, 60, 60, 32, 47, 82, 111, 111, 116, 32, 49, 32, 48, 32, 82, 32, 62, 62, 10, 37, 37, 69, 79, 70, 10 }
    let font_pdf: [1368]u8 = [1368]u8{ 37, 80, 68, 70, 45, 49, 46, 52, 10, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 67, 97, 116, 97, 108, 111, 103, 32, 47, 80, 97, 103, 101, 115, 32, 50, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 32, 47, 75, 105, 100, 115, 32, 91, 51, 32, 48, 32, 82, 93, 32, 47, 67, 111, 117, 110, 116, 32, 49, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 48, 32, 48, 32, 50, 48, 48, 32, 50, 48, 48, 93, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 32, 47, 80, 97, 114, 101, 110, 116, 32, 50, 32, 48, 32, 82, 32, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 52, 32, 48, 32, 82, 32, 47, 82, 101, 115, 111, 117, 114, 99, 101, 115, 32, 60, 60, 32, 47, 70, 111, 110, 116, 32, 60, 60, 32, 47, 70, 49, 32, 53, 32, 48, 32, 82, 32, 47, 70, 50, 32, 54, 32, 48, 32, 82, 32, 47, 70, 51, 32, 57, 32, 48, 32, 82, 32, 62, 62, 32, 62, 62, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 32, 47, 76, 101, 110, 103, 116, 104, 32, 49, 50, 49, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 66, 84, 32, 47, 70, 49, 32, 49, 48, 32, 84, 102, 32, 49, 48, 32, 49, 48, 48, 32, 84, 100, 32, 40, 65, 66, 67, 41, 32, 84, 106, 32, 69, 84, 10, 66, 84, 32, 47, 70, 50, 32, 49, 50, 32, 84, 102, 32, 49, 48, 32, 53, 48, 32, 84, 100, 32, 60, 48, 48, 48, 49, 48, 48, 48, 50, 48, 48, 48, 51, 48, 48, 48, 52, 48, 48, 48, 53, 62, 32, 84, 106, 32, 69, 84, 10, 66, 84, 32, 47, 70, 51, 32, 49, 48, 32, 84, 102, 32, 49, 48, 32, 50, 48, 32, 84, 100, 32, 60, 48, 49, 48, 49, 62, 32, 84, 106, 32, 69, 84, 10, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 53, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 84, 121, 112, 101, 49, 32, 47, 66, 97, 115, 101, 70, 111, 110, 116, 32, 47, 72, 101, 108, 118, 101, 116, 105, 99, 97, 32, 47, 70, 105, 114, 115, 116, 67, 104, 97, 114, 32, 54, 53, 32, 47, 76, 97, 115, 116, 67, 104, 97, 114, 32, 54, 55, 32, 47, 87, 105, 100, 116, 104, 115, 32, 91, 55, 48, 48, 32, 54, 48, 48, 32, 53, 48, 48, 93, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 54, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 84, 121, 112, 101, 48, 32, 47, 66, 97, 115, 101, 70, 111, 110, 116, 32, 47, 67, 105, 100, 32, 47, 69, 110, 99, 111, 100, 105, 110, 103, 32, 47, 73, 100, 101, 110, 116, 105, 116, 121, 45, 72, 32, 47, 68, 101, 115, 99, 101, 110, 100, 97, 110, 116, 70, 111, 110, 116, 115, 32, 91, 55, 32, 48, 32, 82, 93, 32, 47, 84, 111, 85, 110, 105, 99, 111, 100, 101, 32, 56, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 55, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 67, 73, 68, 70, 111, 110, 116, 84, 121, 112, 101, 50, 32, 47, 66, 97, 115, 101, 70, 111, 110, 116, 32, 47, 67, 105, 100, 32, 47, 68, 87, 32, 49, 48, 48, 48, 32, 47, 87, 32, 91, 49, 32, 91, 52, 48, 48, 32, 53, 48, 48, 93, 32, 51, 32, 53, 32, 50, 53, 48, 93, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 56, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 32, 47, 76, 101, 110, 103, 116, 104, 32, 50, 50, 57, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 47, 67, 73, 68, 73, 110, 105, 116, 32, 47, 80, 114, 111, 99, 83, 101, 116, 32, 102, 105, 110, 100, 114, 101, 115, 111, 117, 114, 99, 101, 32, 98, 101, 103, 105, 110, 32, 49, 50, 32, 100, 105, 99, 116, 32, 98, 101, 103, 105, 110, 32, 98, 101, 103, 105, 110, 99, 109, 97, 112, 10, 49, 32, 98, 101, 103, 105, 110, 99, 111, 100, 101, 115, 112, 97, 99, 101, 114, 97, 110, 103, 101, 32, 60, 48, 48, 48, 48, 62, 32, 60, 70, 70, 70, 70, 62, 32, 101, 110, 100, 99, 111, 100, 101, 115, 112, 97, 99, 101, 114, 97, 110, 103, 101, 10, 50, 32, 98, 101, 103, 105, 110, 98, 102, 99, 104, 97, 114, 32, 60, 48, 48, 48, 49, 62, 32, 60, 48, 48, 52, 56, 62, 32, 60, 48, 48, 48, 50, 62, 32, 60, 48, 48, 54, 57, 62, 32, 101, 110, 100, 98, 102, 99, 104, 97, 114, 10, 49, 32, 98, 101, 103, 105, 110, 98, 102, 114, 97, 110, 103, 101, 32, 60, 48, 48, 48, 51, 62, 32, 60, 48, 48, 48, 53, 62, 32, 60, 48, 48, 52, 49, 62, 32, 101, 110, 100, 98, 102, 114, 97, 110, 103, 101, 10, 101, 110, 100, 99, 109, 97, 112, 32, 101, 110, 100, 32, 101, 110, 100, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 57, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 84, 114, 117, 101, 84, 121, 112, 101, 32, 47, 66, 97, 115, 101, 70, 111, 110, 116, 32, 47, 83, 117, 98, 32, 47, 70, 105, 114, 115, 116, 67, 104, 97, 114, 32, 49, 32, 47, 76, 97, 115, 116, 67, 104, 97, 114, 32, 49, 32, 47, 87, 105, 100, 116, 104, 115, 32, 91, 54, 48, 48, 93, 32, 47, 84, 111, 85, 110, 105, 99, 111, 100, 101, 32, 49, 48, 32, 48, 32, 82, 32, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 48, 32, 48, 32, 111, 98, 106, 10, 60, 60, 32, 32, 47, 76, 101, 110, 103, 116, 104, 32, 57, 51, 32, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 49, 32, 98, 101, 103, 105, 110, 99, 111, 100, 101, 115, 112, 97, 99, 101, 114, 97, 110, 103, 101, 32, 60, 48, 48, 62, 32, 60, 70, 70, 62, 32, 101, 110, 100, 99, 111, 100, 101, 115, 112, 97, 99, 101, 114, 97, 110, 103, 101, 10, 49, 32, 98, 101, 103, 105, 110, 98, 102, 99, 104, 97, 114, 32, 60, 48, 49, 62, 32, 60, 48, 48, 53, 65, 62, 32, 101, 110, 100, 98, 102, 99, 104, 97, 114, 10, 101, 110, 100, 99, 109, 97, 112, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 116, 114, 97, 105, 108, 101, 114, 10, 60, 60, 32, 47, 82, 111, 111, 116, 32, 49, 32, 48, 32, 82, 32, 62, 62, 10, 37, 37, 69, 79, 70, 10 }
    let ttf_pdf: [6567]u8 = [6567]u8{ 37, 80, 68, 70, 45, 49, 46, 51, 10, 37, 147, 140, 139, 158, 32, 82, 101, 112, 111, 114, 116, 76, 97, 98, 32, 71, 101, 110, 101, 114, 97, 116, 101, 100, 32, 80, 68, 70, 32, 100, 111, 99, 117, 109, 101, 110, 116, 32, 40, 111, 112, 101, 110, 115, 111, 117, 114, 99, 101, 41, 10, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 70, 49, 32, 50, 32, 48, 32, 82, 32, 47, 70, 50, 43, 48, 32, 55, 32, 48, 32, 82, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 66, 97, 115, 101, 70, 111, 110, 116, 32, 47, 72, 101, 108, 118, 101, 116, 105, 99, 97, 32, 47, 69, 110, 99, 111, 100, 105, 110, 103, 32, 47, 87, 105, 110, 65, 110, 115, 105, 69, 110, 99, 111, 100, 105, 110, 103, 32, 47, 78, 97, 109, 101, 32, 47, 70, 49, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 84, 121, 112, 101, 49, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 49, 49, 32, 48, 32, 82, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 32, 48, 32, 48, 32, 53, 57, 53, 46, 50, 55, 53, 54, 32, 56, 52, 49, 46, 56, 56, 57, 56, 32, 93, 32, 47, 80, 97, 114, 101, 110, 116, 32, 49, 48, 32, 48, 32, 82, 32, 47, 82, 101, 115, 111, 117, 114, 99, 101, 115, 32, 60, 60, 10, 47, 70, 111, 110, 116, 32, 49, 32, 48, 32, 82, 32, 47, 80, 114, 111, 99, 83, 101, 116, 32, 91, 32, 47, 80, 68, 70, 32, 47, 84, 101, 120, 116, 32, 47, 73, 109, 97, 103, 101, 66, 32, 47, 73, 109, 97, 103, 101, 67, 32, 47, 73, 109, 97, 103, 101, 73, 32, 93, 10, 62, 62, 32, 47, 82, 111, 116, 97, 116, 101, 32, 48, 32, 47, 84, 114, 97, 110, 115, 32, 60, 60, 10, 10, 62, 62, 32, 10, 32, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 76, 101, 110, 103, 116, 104, 32, 49, 56, 55, 51, 10, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 47, 67, 73, 68, 73, 110, 105, 116, 32, 47, 80, 114, 111, 99, 83, 101, 116, 32, 102, 105, 110, 100, 114, 101, 115, 111, 117, 114, 99, 101, 32, 98, 101, 103, 105, 110, 10, 49, 50, 32, 100, 105, 99, 116, 32, 98, 101, 103, 105, 110, 10, 98, 101, 103, 105, 110, 99, 109, 97, 112, 10, 47, 67, 73, 68, 83, 121, 115, 116, 101, 109, 73, 110, 102, 111, 10, 60, 60, 32, 47, 82, 101, 103, 105, 115, 116, 114, 121, 32, 40, 65, 65, 65, 65, 65, 65, 43, 65, 114, 105, 97, 108, 77, 84, 41, 10, 47, 79, 114, 100, 101, 114, 105, 110, 103, 32, 40, 65, 65, 65, 65, 65, 65, 43, 65, 114, 105, 97, 108, 77, 84, 41, 10, 47, 83, 117, 112, 112, 108, 101, 109, 101, 110, 116, 32, 48, 10, 62, 62, 32, 100, 101, 102, 10, 47, 67, 77, 97, 112, 78, 97, 109, 101, 32, 47, 65, 65, 65, 65, 65, 65, 43, 65, 114, 105, 97, 108, 77, 84, 32, 100, 101, 102, 10, 47, 67, 77, 97, 112, 84, 121, 112, 101, 32, 50, 32, 100, 101, 102, 10, 49, 32, 98, 101, 103, 105, 110, 99, 111, 100, 101, 115, 112, 97, 99, 101, 114, 97, 110, 103, 101, 10, 60, 48, 48, 62, 32, 60, 55, 70, 62, 10, 101, 110, 100, 99, 111, 100, 101, 115, 112, 97, 99, 101, 114, 97, 110, 103, 101, 10, 49, 50, 56, 32, 98, 101, 103, 105, 110, 98, 102, 99, 104, 97, 114, 10, 60, 48, 48, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 49, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 50, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 51, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 52, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 53, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 54, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 55, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 56, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 57, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 65, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 66, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 67, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 68, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 69, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 48, 70, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 48, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 49, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 50, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 51, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 52, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 53, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 54, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 55, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 56, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 57, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 65, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 66, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 67, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 68, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 69, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 49, 70, 62, 32, 60, 48, 48, 48, 48, 62, 10, 60, 50, 48, 62, 32, 60, 48, 48, 50, 48, 62, 10, 60, 50, 49, 62, 32, 60, 48, 48, 50, 49, 62, 10, 60, 50, 50, 62, 32, 60, 48, 48, 50, 50, 62, 10, 60, 50, 51, 62, 32, 60, 48, 48, 50, 51, 62, 10, 60, 50, 52, 62, 32, 60, 48, 48, 50, 52, 62, 10, 60, 50, 53, 62, 32, 60, 48, 48, 50, 53, 62, 10, 60, 50, 54, 62, 32, 60, 48, 48, 50, 54, 62, 10, 60, 50, 55, 62, 32, 60, 48, 48, 50, 55, 62, 10, 60, 50, 56, 62, 32, 60, 48, 48, 50, 56, 62, 10, 60, 50, 57, 62, 32, 60, 48, 48, 50, 57, 62, 10, 60, 50, 65, 62, 32, 60, 48, 48, 50, 65, 62, 10, 60, 50, 66, 62, 32, 60, 48, 48, 50, 66, 62, 10, 60, 50, 67, 62, 32, 60, 48, 48, 50, 67, 62, 10, 60, 50, 68, 62, 32, 60, 48, 48, 50, 68, 62, 10, 60, 50, 69, 62, 32, 60, 48, 48, 50, 69, 62, 10, 60, 50, 70, 62, 32, 60, 48, 48, 50, 70, 62, 10, 60, 51, 48, 62, 32, 60, 48, 48, 51, 48, 62, 10, 60, 51, 49, 62, 32, 60, 48, 48, 51, 49, 62, 10, 60, 51, 50, 62, 32, 60, 48, 48, 51, 50, 62, 10, 60, 51, 51, 62, 32, 60, 48, 48, 51, 51, 62, 10, 60, 51, 52, 62, 32, 60, 48, 48, 51, 52, 62, 10, 60, 51, 53, 62, 32, 60, 48, 48, 51, 53, 62, 10, 60, 51, 54, 62, 32, 60, 48, 48, 51, 54, 62, 10, 60, 51, 55, 62, 32, 60, 48, 48, 51, 55, 62, 10, 60, 51, 56, 62, 32, 60, 48, 48, 51, 56, 62, 10, 60, 51, 57, 62, 32, 60, 48, 48, 51, 57, 62, 10, 60, 51, 65, 62, 32, 60, 48, 48, 51, 65, 62, 10, 60, 51, 66, 62, 32, 60, 48, 48, 51, 66, 62, 10, 60, 51, 67, 62, 32, 60, 48, 48, 51, 67, 62, 10, 60, 51, 68, 62, 32, 60, 48, 48, 51, 68, 62, 10, 60, 51, 69, 62, 32, 60, 48, 48, 51, 69, 62, 10, 60, 51, 70, 62, 32, 60, 48, 48, 51, 70, 62, 10, 60, 52, 48, 62, 32, 60, 48, 48, 52, 48, 62, 10, 60, 52, 49, 62, 32, 60, 48, 48, 52, 49, 62, 10, 60, 52, 50, 62, 32, 60, 48, 48, 52, 50, 62, 10, 60, 52, 51, 62, 32, 60, 48, 48, 52, 51, 62, 10, 60, 52, 52, 62, 32, 60, 48, 48, 52, 52, 62, 10, 60, 52, 53, 62, 32, 60, 48, 48, 52, 53, 62, 10, 60, 52, 54, 62, 32, 60, 48, 48, 52, 54, 62, 10, 60, 52, 55, 62, 32, 60, 48, 48, 52, 55, 62, 10, 60, 52, 56, 62, 32, 60, 48, 48, 52, 56, 62, 10, 60, 52, 57, 62, 32, 60, 48, 48, 52, 57, 62, 10, 60, 52, 65, 62, 32, 60, 48, 48, 52, 65, 62, 10, 60, 52, 66, 62, 32, 60, 48, 48, 52, 66, 62, 10, 60, 52, 67, 62, 32, 60, 48, 48, 52, 67, 62, 10, 60, 52, 68, 62, 32, 60, 48, 48, 52, 68, 62, 10, 60, 52, 69, 62, 32, 60, 48, 48, 52, 69, 62, 10, 60, 52, 70, 62, 32, 60, 48, 48, 52, 70, 62, 10, 60, 53, 48, 62, 32, 60, 48, 48, 53, 48, 62, 10, 60, 53, 49, 62, 32, 60, 48, 48, 53, 49, 62, 10, 60, 53, 50, 62, 32, 60, 48, 48, 53, 50, 62, 10, 60, 53, 51, 62, 32, 60, 48, 48, 53, 51, 62, 10, 60, 53, 52, 62, 32, 60, 48, 48, 53, 52, 62, 10, 60, 53, 53, 62, 32, 60, 48, 48, 53, 53, 62, 10, 60, 53, 54, 62, 32, 60, 48, 48, 53, 54, 62, 10, 60, 53, 55, 62, 32, 60, 48, 48, 53, 55, 62, 10, 60, 53, 56, 62, 32, 60, 48, 48, 53, 56, 62, 10, 60, 53, 57, 62, 32, 60, 48, 48, 53, 57, 62, 10, 60, 53, 65, 62, 32, 60, 48, 48, 53, 65, 62, 10, 60, 53, 66, 62, 32, 60, 48, 48, 53, 66, 62, 10, 60, 53, 67, 62, 32, 60, 48, 48, 53, 67, 62, 10, 60, 53, 68, 62, 32, 60, 48, 48, 53, 68, 62, 10, 60, 53, 69, 62, 32, 60, 48, 48, 53, 69, 62, 10, 60, 53, 70, 62, 32, 60, 48, 48, 53, 70, 62, 10, 60, 54, 48, 62, 32, 60, 48, 48, 54, 48, 62, 10, 60, 54, 49, 62, 32, 60, 48, 48, 54, 49, 62, 10, 60, 54, 50, 62, 32, 60, 48, 48, 54, 50, 62, 10, 60, 54, 51, 62, 32, 60, 48, 48, 54, 51, 62, 10, 60, 54, 52, 62, 32, 60, 48, 48, 54, 52, 62, 10, 60, 54, 53, 62, 32, 60, 48, 48, 54, 53, 62, 10, 60, 54, 54, 62, 32, 60, 48, 48, 54, 54, 62, 10, 60, 54, 55, 62, 32, 60, 48, 48, 54, 55, 62, 10, 60, 54, 56, 62, 32, 60, 48, 48, 54, 56, 62, 10, 60, 54, 57, 62, 32, 60, 48, 48, 54, 57, 62, 10, 60, 54, 65, 62, 32, 60, 48, 48, 54, 65, 62, 10, 60, 54, 66, 62, 32, 60, 48, 48, 54, 66, 62, 10, 60, 54, 67, 62, 32, 60, 48, 48, 54, 67, 62, 10, 60, 54, 68, 62, 32, 60, 48, 48, 54, 68, 62, 10, 60, 54, 69, 62, 32, 60, 48, 48, 54, 69, 62, 10, 60, 54, 70, 62, 32, 60, 48, 48, 54, 70, 62, 10, 60, 55, 48, 62, 32, 60, 48, 48, 55, 48, 62, 10, 60, 55, 49, 62, 32, 60, 48, 48, 55, 49, 62, 10, 60, 55, 50, 62, 32, 60, 48, 48, 55, 50, 62, 10, 60, 55, 51, 62, 32, 60, 48, 48, 55, 51, 62, 10, 60, 55, 52, 62, 32, 60, 48, 48, 55, 52, 62, 10, 60, 55, 53, 62, 32, 60, 48, 48, 55, 53, 62, 10, 60, 55, 54, 62, 32, 60, 48, 48, 55, 54, 62, 10, 60, 55, 55, 62, 32, 60, 48, 48, 55, 55, 62, 10, 60, 55, 56, 62, 32, 60, 48, 48, 55, 56, 62, 10, 60, 55, 57, 62, 32, 60, 48, 48, 55, 57, 62, 10, 60, 55, 65, 62, 32, 60, 48, 48, 55, 65, 62, 10, 60, 55, 66, 62, 32, 60, 48, 48, 55, 66, 62, 10, 60, 55, 67, 62, 32, 60, 48, 48, 55, 67, 62, 10, 60, 55, 68, 62, 32, 60, 48, 48, 55, 68, 62, 10, 60, 55, 69, 62, 32, 60, 48, 48, 55, 69, 62, 10, 60, 55, 70, 62, 32, 60, 48, 48, 55, 70, 62, 10, 101, 110, 100, 98, 102, 99, 104, 97, 114, 10, 101, 110, 100, 99, 109, 97, 112, 10, 67, 77, 97, 112, 78, 97, 109, 101, 32, 99, 117, 114, 114, 101, 110, 116, 100, 105, 99, 116, 32, 47, 67, 77, 97, 112, 32, 100, 101, 102, 105, 110, 101, 114, 101, 115, 111, 117, 114, 99, 101, 32, 112, 111, 112, 10, 101, 110, 100, 10, 101, 110, 100, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 53, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 76, 101, 110, 103, 116, 104, 32, 50, 49, 53, 50, 32, 47, 76, 101, 110, 103, 116, 104, 49, 32, 50, 49, 53, 50, 10, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 0, 1, 0, 0, 0, 10, 0, 128, 0, 3, 0, 32, 79, 83, 47, 50, 106, 230, 126, 0, 0, 0, 0, 172, 0, 0, 0, 96, 99, 109, 97, 112, 0, 163, 1, 50, 0, 0, 1, 12, 0, 0, 1, 22, 103, 108, 121, 102, 186, 137, 45, 17, 0, 0, 2, 36, 0, 0, 2, 104, 104, 101, 97, 100, 250, 203, 144, 29, 0, 0, 4, 140, 0, 0, 0, 54, 104, 104, 101, 97, 18, 51, 8, 212, 0, 0, 4, 196, 0, 0, 0, 36, 104, 109, 116, 120, 41, 145, 4, 34, 0, 0, 4, 232, 0, 0, 0, 44, 108, 111, 99, 97, 2, 184, 3, 110, 0, 0, 5, 20, 0, 0, 0, 24, 109, 97, 120, 112, 0, 84, 3, 130, 0, 0, 5, 44, 0, 0, 0, 32, 110, 97, 109, 101, 73, 210, 88, 132, 0, 0, 5, 76, 0, 0, 2, 250, 112, 111, 115, 116, 255, 42, 0, 150, 0, 0, 8, 72, 0, 0, 0, 32, 0, 3, 3, 136, 1, 144, 0, 5, 0, 8, 5, 154, 5, 51, 0, 0, 1, 27, 5, 154, 5, 51, 0, 0, 3, 209, 0, 102, 2, 18, 8, 5, 2, 11, 6, 4, 2, 2, 2, 2, 2, 4, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 84, 77, 67, 32, 0, 64, 0, 32, 0, 119, 5, 211, 254, 81, 1, 51, 7, 62, 1, 178, 0, 0, 0, 1, 0, 0, 0, 0, 4, 38, 5, 187, 0, 0, 0, 32, 0, 21, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 12, 0, 6, 1, 10, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 4, 0, 5, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 164, 0, 0, 5, 34, 5, 186, 0, 11, 0, 0, 51, 17, 51, 17, 33, 17, 51, 17, 35, 17, 33, 17, 164, 194, 2, 250, 194, 194, 253, 6, 5, 186, 253, 166, 2, 90, 250, 70, 2, 179, 253, 77, 0, 0, 0, 2, 0, 70, 255, 232, 3, 223, 5, 186, 0, 17, 0, 29, 0, 0, 33, 53, 6, 35, 34, 38, 38, 53, 52, 18, 54, 51, 50, 22, 23, 17, 51, 17, 1, 20, 22, 51, 50, 54, 53, 52, 38, 35, 34, 6, 3, 56, 101, 196, 127, 213, 117, 106, 212, 131, 96, 150, 47, 179, 253, 32, 172, 117, 118, 165, 168, 123, 120, 161, 134, 158, 140, 251, 163, 159, 1, 3, 138, 81, 65, 2, 14, 250, 70, 2, 18, 204, 202, 193, 198, 218, 204, 196, 0, 0, 0, 2, 0, 75, 255, 232, 4, 30, 4, 62, 0, 21, 0, 29, 0, 0, 1, 23, 6, 6, 35, 34, 0, 17, 16, 0, 51, 50, 0, 17, 20, 7, 33, 22, 22, 51, 50, 54, 1, 33, 38, 39, 38, 35, 34, 6, 3, 94, 186, 44, 238, 185, 233, 254, 239, 1, 20, 220, 213, 1, 14, 1, 252, 232, 10, 178, 133, 99, 140, 253, 218, 2, 81, 12, 56, 86, 137, 124, 169, 1, 86, 23, 163, 180, 1, 31, 1, 3, 1, 12, 1, 40, 254, 222, 254, 249, 16, 32, 175, 186, 104, 1, 149, 134, 67, 104, 166, 0, 0, 1, 0, 19, 0, 0, 2, 128, 5, 211, 0, 23, 0, 0, 51, 17, 35, 53, 51, 53, 52, 55, 54, 54, 51, 50, 23, 7, 38, 35, 34, 6, 21, 21, 51, 21, 35, 17, 178, 159, 159, 19, 26, 131, 118, 76, 92, 27, 56, 50, 82, 68, 207, 207, 3, 154, 140, 113, 107, 52, 70, 87, 18, 157, 10, 70, 96, 98, 140, 252, 102, 0, 0, 2, 0, 136, 0, 0, 1, 60, 5, 186, 0, 3, 0, 7, 0, 0, 19, 53, 51, 21, 3, 17, 51, 17, 136, 180, 180, 180, 4, 235, 207, 207, 251, 21, 4, 38, 251, 218, 0, 0, 0, 1, 0, 131, 0, 0, 1, 55, 5, 186, 0, 3, 0, 0, 51, 17, 51, 17, 131, 180, 5, 186, 250, 70, 0, 2, 0, 68, 255, 232, 4, 39, 4, 62, 0, 13, 0, 25, 0, 0, 19, 16, 55, 54, 51, 50, 0, 21, 20, 6, 6, 35, 34, 0, 19, 20, 22, 51, 50, 54, 53, 52, 38, 35, 34, 6, 68, 164, 137, 197, 219, 1, 22, 123, 235, 139, 223, 254, 237, 185, 178, 135, 134, 178, 179, 133, 135, 178, 2, 19, 1, 39, 142, 118, 254, 225, 253, 205, 235, 130, 1, 30, 1, 13, 204, 203, 204, 209, 197, 203, 202, 0, 0, 1, 0, 133, 0, 0, 2, 198, 4, 62, 0, 17, 0, 0, 51, 17, 51, 21, 54, 54, 51, 50, 23, 7, 38, 35, 34, 6, 7, 6, 21, 17, 133, 162, 62, 105, 63, 91, 94, 62, 66, 66, 59, 94, 20, 30, 4, 38, 161, 113, 72, 58, 167, 39, 71, 63, 96, 114, 253, 212, 0, 1, 0, 6, 0, 0, 5, 183, 4, 38, 0, 18, 0, 0, 33, 1, 51, 19, 23, 54, 55, 19, 51, 19, 23, 55, 19, 51, 1, 35, 3, 39, 3, 1, 75, 254, 187, 186, 169, 63, 4, 51, 169, 185, 159, 53, 61, 182, 175, 254, 180, 187, 169, 41, 215, 4, 38, 253, 155, 228, 17, 202, 2, 110, 253, 152, 203, 205, 2, 102, 251, 218, 2, 124, 181, 252, 207, 0, 0, 0, 0, 1, 0, 0, 0, 7, 15, 92, 84, 67, 40, 205, 95, 15, 60, 245, 8, 27, 8, 0, 0, 0, 0, 0, 162, 227, 39, 42, 0, 0, 0, 0, 230, 5, 14, 225, 250, 175, 253, 103, 16, 0, 8, 81, 0, 0, 0, 9, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 7, 62, 254, 78, 0, 67, 16, 0, 250, 175, 250, 122, 16, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 6, 0, 1, 0, 2, 57, 0, 0, 5, 199, 0, 164, 4, 115, 0, 70, 4, 115, 0, 75, 2, 57, 0, 19, 1, 199, 0, 136, 1, 199, 0, 131, 4, 115, 0, 68, 2, 170, 0, 133, 5, 199, 0, 6, 0, 0, 0, 0, 0, 0, 0, 24, 0, 72, 0, 126, 0, 162, 0, 182, 0, 194, 0, 238, 1, 12, 1, 52, 0, 1, 0, 0, 0, 11, 2, 181, 0, 60, 0, 202, 0, 7, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 2, 0, 0, 0, 7, 0, 90, 0, 3, 0, 1, 4, 9, 0, 0, 2, 30, 0, 0, 0, 3, 0, 1, 4, 9, 0, 1, 0, 10, 2, 30, 0, 3, 0, 1, 4, 9, 0, 2, 0, 14, 2, 40, 0, 3, 0, 1, 4, 9, 0, 3, 0, 68, 2, 54, 0, 3, 0, 1, 4, 9, 0, 4, 0, 10, 2, 30, 0, 3, 0, 1, 4, 9, 0, 5, 0, 24, 2, 122, 0, 3, 0, 1, 4, 9, 0, 6, 0, 14, 2, 146, 0, 169, 0, 32, 0, 50, 0, 48, 0, 50, 0, 54, 0, 32, 0, 84, 0, 104, 0, 101, 0, 32, 0, 77, 0, 111, 0, 110, 0, 111, 0, 116, 0, 121, 0, 112, 0, 101, 0, 32, 0, 67, 0, 111, 0, 114, 0, 112, 0, 111, 0, 114, 0, 97, 0, 116, 0, 105, 0, 111, 0, 110, 0, 46, 0, 32, 0, 65, 0, 108, 0, 108, 0, 32, 0, 82, 0, 105, 0, 103, 0, 104, 0, 116, 0, 115, 0, 32, 0, 82, 0, 101, 0, 115, 0, 101, 0, 114, 0, 118, 0, 101, 0, 100, 0, 46, 0, 32, 0, 13, 0, 10, 0, 13, 0, 10, 0, 72, 0, 101, 0, 98, 0, 114, 0, 101, 0, 119, 0, 32, 0, 79, 0, 112, 0, 101, 0, 110, 0, 84, 0, 121, 0, 112, 0, 101, 0, 32, 0, 76, 0, 97, 0, 121, 0, 111, 0, 117, 0, 116, 0, 32, 0, 108, 0, 111, 0, 103, 0, 105, 0, 99, 0, 32, 0, 99, 0, 111, 0, 112, 0, 121, 0, 114, 0, 105, 0, 103, 0, 104, 0, 116, 0, 32, 0, 169, 0, 32, 0, 50, 0, 48, 0, 48, 0, 51, 0, 32, 0, 38, 0, 32, 0, 50, 0, 48, 0, 48, 0, 55, 0, 44, 0, 32, 0, 82, 0, 97, 0, 108, 0, 112, 0, 104, 0, 32, 0, 72, 0, 97, 0, 110, 0, 99, 0, 111, 0, 99, 0, 107, 0, 32, 0, 38, 0, 32, 0, 74, 0, 111, 0, 104, 0, 110, 0, 32, 0, 72, 0, 117, 0, 100, 0, 115, 0, 111, 0, 110, 0, 46, 0, 32, 0, 84, 0, 104, 0, 105, 0, 115, 0, 32, 0, 108, 0, 97, 0, 121, 0, 111, 0, 117, 0, 116, 0, 32, 0, 108, 0, 111, 0, 103, 0, 105, 0, 99, 0, 32, 0, 102, 0, 111, 0, 114, 0, 32, 0, 66, 0, 105, 0, 98, 0, 108, 0, 105, 0, 99, 0, 97, 0, 108, 0, 32, 0, 72, 0, 101, 0, 98, 0, 114, 0, 101, 0, 119, 0, 32, 0, 105, 0, 115, 0, 32, 0, 111, 0, 112, 0, 101, 0, 110, 0, 32, 0, 115, 0, 111, 0, 117, 0, 114, 0, 99, 0, 101, 0, 32, 0, 115, 0, 111, 0, 102, 0, 116, 0, 119, 0, 97, 0, 114, 0, 101, 0, 32, 0, 117, 0, 110, 0, 100, 0, 101, 0, 114, 0, 32, 0, 116, 0, 104, 0, 101, 0, 32, 0, 77, 0, 73, 0, 84, 0, 32, 0, 76, 0, 105, 0, 99, 0, 101, 0, 110, 0, 115, 0, 101, 0, 59, 0, 32, 0, 115, 0, 101, 0, 101, 0, 32, 0, 101, 0, 109, 0, 98, 0, 101, 0, 100, 0, 100, 0, 101, 0, 100, 0, 32, 0, 108, 0, 105, 0, 99, 0, 101, 0, 110, 0, 115, 0, 101, 0, 32, 0, 100, 0, 101, 0, 115, 0, 99, 0, 114, 0, 105, 0, 112, 0, 116, 0, 105, 0, 111, 0, 110, 0, 32, 0, 102, 0, 111, 0, 114, 0, 32, 0, 100, 0, 101, 0, 116, 0, 97, 0, 105, 0, 108, 0, 115, 0, 46, 0, 65, 0, 114, 0, 105, 0, 97, 0, 108, 0, 82, 0, 101, 0, 103, 0, 117, 0, 108, 0, 97, 0, 114, 0, 77, 0, 111, 0, 110, 0, 111, 0, 116, 0, 121, 0, 112, 0, 101, 0, 58, 0, 65, 0, 114, 0, 105, 0, 97, 0, 108, 0, 32, 0, 82, 0, 101, 0, 103, 0, 117, 0, 108, 0, 97, 0, 114, 0, 32, 0, 40, 0, 77, 0, 105, 0, 99, 0, 114, 0, 111, 0, 115, 0, 111, 0, 102, 0, 116, 0, 41, 0, 86, 0, 101, 0, 114, 0, 115, 0, 105, 0, 111, 0, 110, 0, 32, 0, 55, 0, 46, 0, 48, 0, 54, 0, 65, 0, 114, 0, 105, 0, 97, 0, 108, 0, 77, 0, 84, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 255, 39, 0, 150, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 54, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 65, 115, 99, 101, 110, 116, 32, 55, 50, 56, 46, 48, 50, 55, 51, 32, 47, 67, 97, 112, 72, 101, 105, 103, 104, 116, 32, 55, 49, 54, 46, 51, 48, 56, 54, 32, 47, 68, 101, 115, 99, 101, 110, 116, 32, 45, 50, 49, 48, 46, 52, 52, 57, 50, 32, 47, 70, 108, 97, 103, 115, 32, 52, 32, 47, 70, 111, 110, 116, 66, 66, 111, 120, 32, 91, 32, 45, 54, 54, 52, 46, 53, 53, 48, 56, 32, 45, 51, 50, 52, 46, 55, 48, 55, 32, 50, 48, 48, 48, 32, 49, 48, 51, 57, 46, 53, 53, 49, 32, 93, 32, 47, 70, 111, 110, 116, 70, 105, 108, 101, 50, 32, 53, 32, 48, 32, 82, 32, 10, 32, 32, 47, 70, 111, 110, 116, 78, 97, 109, 101, 32, 47, 65, 65, 65, 65, 65, 65, 43, 65, 114, 105, 97, 108, 77, 84, 32, 47, 73, 116, 97, 108, 105, 99, 65, 110, 103, 108, 101, 32, 48, 32, 47, 77, 105, 115, 115, 105, 110, 103, 87, 105, 100, 116, 104, 32, 55, 53, 48, 32, 47, 83, 116, 101, 109, 86, 32, 56, 55, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 68, 101, 115, 99, 114, 105, 112, 116, 111, 114, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 55, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 66, 97, 115, 101, 70, 111, 110, 116, 32, 47, 65, 65, 65, 65, 65, 65, 43, 65, 114, 105, 97, 108, 77, 84, 32, 47, 70, 105, 114, 115, 116, 67, 104, 97, 114, 32, 48, 32, 47, 70, 111, 110, 116, 68, 101, 115, 99, 114, 105, 112, 116, 111, 114, 32, 54, 32, 48, 32, 82, 32, 47, 76, 97, 115, 116, 67, 104, 97, 114, 32, 49, 50, 55, 32, 47, 78, 97, 109, 101, 32, 47, 70, 50, 43, 48, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 84, 114, 117, 101, 84, 121, 112, 101, 32, 10, 32, 32, 47, 84, 111, 85, 110, 105, 99, 111, 100, 101, 32, 52, 32, 48, 32, 82, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 32, 47, 87, 105, 100, 116, 104, 115, 32, 91, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 50, 55, 55, 46, 56, 51, 50, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 50, 50, 46, 49, 54, 56, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 10, 32, 32, 53, 53, 54, 46, 49, 53, 50, 51, 32, 53, 53, 54, 46, 49, 53, 50, 51, 32, 50, 55, 55, 46, 56, 51, 50, 32, 55, 53, 48, 32, 55, 53, 48, 32, 50, 50, 50, 46, 49, 54, 56, 32, 55, 53, 48, 32, 55, 53, 48, 32, 50, 50, 50, 46, 49, 54, 56, 32, 55, 53, 48, 32, 10, 32, 32, 55, 53, 48, 32, 53, 53, 54, 46, 49, 53, 50, 51, 32, 55, 53, 48, 32, 55, 53, 48, 32, 51, 51, 51, 46, 48, 48, 55, 56, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 50, 50, 46, 49, 54, 56, 32, 10, 32, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 55, 53, 48, 32, 93, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 56, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 80, 97, 103, 101, 77, 111, 100, 101, 32, 47, 85, 115, 101, 78, 111, 110, 101, 32, 47, 80, 97, 103, 101, 115, 32, 49, 48, 32, 48, 32, 82, 32, 47, 84, 121, 112, 101, 32, 47, 67, 97, 116, 97, 108, 111, 103, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 57, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 65, 117, 116, 104, 111, 114, 32, 40, 97, 110, 111, 110, 121, 109, 111, 117, 115, 41, 32, 47, 67, 114, 101, 97, 116, 105, 111, 110, 68, 97, 116, 101, 32, 40, 68, 58, 50, 48, 48, 48, 48, 49, 48, 49, 48, 48, 48, 48, 48, 48, 43, 48, 48, 39, 48, 48, 39, 41, 32, 47, 67, 114, 101, 97, 116, 111, 114, 32, 40, 97, 110, 111, 110, 121, 109, 111, 117, 115, 41, 32, 47, 75, 101, 121, 119, 111, 114, 100, 115, 32, 40, 41, 32, 47, 77, 111, 100, 68, 97, 116, 101, 32, 40, 68, 58, 50, 48, 48, 48, 48, 49, 48, 49, 48, 48, 48, 48, 48, 48, 43, 48, 48, 39, 48, 48, 39, 41, 32, 47, 80, 114, 111, 100, 117, 99, 101, 114, 32, 40, 82, 101, 112, 111, 114, 116, 76, 97, 98, 32, 80, 68, 70, 32, 76, 105, 98, 114, 97, 114, 121, 32, 45, 32, 92, 40, 111, 112, 101, 110, 115, 111, 117, 114, 99, 101, 92, 41, 41, 32, 10, 32, 32, 47, 83, 117, 98, 106, 101, 99, 116, 32, 40, 117, 110, 115, 112, 101, 99, 105, 102, 105, 101, 100, 41, 32, 47, 84, 105, 116, 108, 101, 32, 40, 117, 110, 116, 105, 116, 108, 101, 100, 41, 32, 47, 84, 114, 97, 112, 112, 101, 100, 32, 47, 70, 97, 108, 115, 101, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 48, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 67, 111, 117, 110, 116, 32, 49, 32, 47, 75, 105, 100, 115, 32, 91, 32, 51, 32, 48, 32, 82, 32, 93, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 76, 101, 110, 103, 116, 104, 32, 49, 48, 57, 10, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 49, 32, 48, 32, 48, 32, 49, 32, 48, 32, 48, 32, 99, 109, 32, 32, 66, 84, 32, 47, 70, 49, 32, 49, 50, 32, 84, 102, 32, 49, 52, 46, 52, 32, 84, 76, 32, 69, 84, 10, 66, 84, 32, 49, 32, 48, 32, 48, 32, 49, 32, 55, 50, 32, 55, 48, 48, 32, 84, 109, 32, 47, 70, 50, 43, 48, 32, 49, 50, 32, 84, 102, 32, 49, 52, 46, 52, 32, 84, 76, 32, 40, 72, 101, 108, 108, 111, 32, 102, 105, 32, 119, 111, 114, 108, 100, 41, 32, 84, 106, 32, 84, 42, 32, 69, 84, 10, 32, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 120, 114, 101, 102, 10, 48, 32, 49, 50, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 32, 54, 53, 53, 51, 53, 32, 102, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 54, 49, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 49, 48, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 50, 49, 49, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 52, 49, 54, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 50, 51, 52, 48, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 52, 53, 53, 55, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 52, 56, 48, 49, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 53, 53, 54, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 53, 54, 51, 51, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 53, 56, 57, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 53, 57, 53, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 116, 114, 97, 105, 108, 101, 114, 10, 60, 60, 10, 47, 73, 68, 32, 10, 91, 60, 49, 99, 49, 55, 56, 49, 57, 56, 102, 98, 100, 102, 97, 53, 49, 98, 50, 53, 57, 57, 53, 100, 56, 57, 100, 52, 49, 48, 50, 48, 52, 51, 62, 60, 49, 99, 49, 55, 56, 49, 57, 56, 102, 98, 100, 102, 97, 53, 49, 98, 50, 53, 57, 57, 53, 100, 56, 57, 100, 52, 49, 48, 50, 48, 52, 51, 62, 93, 10, 37, 32, 82, 101, 112, 111, 114, 116, 76, 97, 98, 32, 103, 101, 110, 101, 114, 97, 116, 101, 100, 32, 80, 68, 70, 32, 100, 111, 99, 117, 109, 101, 110, 116, 32, 45, 45, 32, 100, 105, 103, 101, 115, 116, 32, 40, 111, 112, 101, 110, 115, 111, 117, 114, 99, 101, 41, 10, 10, 47, 73, 110, 102, 111, 32, 57, 32, 48, 32, 82, 10, 47, 82, 111, 111, 116, 32, 56, 32, 48, 32, 82, 10, 47, 83, 105, 122, 101, 32, 49, 50, 10, 62, 62, 10, 115, 116, 97, 114, 116, 120, 114, 101, 102, 10, 54, 49, 49, 52, 10, 37, 37, 69, 79, 70, 10 }
    let out_pdf: [2632]u8 = [2632]u8{ 37, 80, 68, 70, 45, 49, 46, 51, 10, 37, 147, 140, 139, 158, 32, 82, 101, 112, 111, 114, 116, 76, 97, 98, 32, 71, 101, 110, 101, 114, 97, 116, 101, 100, 32, 80, 68, 70, 32, 100, 111, 99, 117, 109, 101, 110, 116, 32, 40, 111, 112, 101, 110, 115, 111, 117, 114, 99, 101, 41, 10, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 70, 49, 32, 50, 32, 48, 32, 82, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 66, 97, 115, 101, 70, 111, 110, 116, 32, 47, 72, 101, 108, 118, 101, 116, 105, 99, 97, 32, 47, 69, 110, 99, 111, 100, 105, 110, 103, 32, 47, 87, 105, 110, 65, 110, 115, 105, 69, 110, 99, 111, 100, 105, 110, 103, 32, 47, 78, 97, 109, 101, 32, 47, 70, 49, 32, 47, 83, 117, 98, 116, 121, 112, 101, 32, 47, 84, 121, 112, 101, 49, 32, 47, 84, 121, 112, 101, 32, 47, 70, 111, 110, 116, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 49, 52, 32, 48, 32, 82, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 32, 48, 32, 48, 32, 53, 57, 53, 46, 50, 55, 53, 54, 32, 56, 52, 49, 46, 56, 56, 57, 56, 32, 93, 32, 47, 80, 97, 114, 101, 110, 116, 32, 49, 51, 32, 48, 32, 82, 32, 47, 82, 101, 115, 111, 117, 114, 99, 101, 115, 32, 60, 60, 10, 47, 70, 111, 110, 116, 32, 49, 32, 48, 32, 82, 32, 47, 80, 114, 111, 99, 83, 101, 116, 32, 91, 32, 47, 80, 68, 70, 32, 47, 84, 101, 120, 116, 32, 47, 73, 109, 97, 103, 101, 66, 32, 47, 73, 109, 97, 103, 101, 67, 32, 47, 73, 109, 97, 103, 101, 73, 32, 93, 10, 62, 62, 32, 47, 82, 111, 116, 97, 116, 101, 32, 48, 32, 47, 84, 114, 97, 110, 115, 32, 60, 60, 10, 10, 62, 62, 32, 10, 32, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 49, 53, 32, 48, 32, 82, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 32, 48, 32, 48, 32, 53, 57, 53, 46, 50, 55, 53, 54, 32, 56, 52, 49, 46, 56, 56, 57, 56, 32, 93, 32, 47, 80, 97, 114, 101, 110, 116, 32, 49, 51, 32, 48, 32, 82, 32, 47, 82, 101, 115, 111, 117, 114, 99, 101, 115, 32, 60, 60, 10, 47, 70, 111, 110, 116, 32, 49, 32, 48, 32, 82, 32, 47, 80, 114, 111, 99, 83, 101, 116, 32, 91, 32, 47, 80, 68, 70, 32, 47, 84, 101, 120, 116, 32, 47, 73, 109, 97, 103, 101, 66, 32, 47, 73, 109, 97, 103, 101, 67, 32, 47, 73, 109, 97, 103, 101, 73, 32, 93, 10, 62, 62, 32, 47, 82, 111, 116, 97, 116, 101, 32, 48, 32, 47, 84, 114, 97, 110, 115, 32, 60, 60, 10, 10, 62, 62, 32, 10, 32, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 53, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 67, 111, 110, 116, 101, 110, 116, 115, 32, 49, 54, 32, 48, 32, 82, 32, 47, 77, 101, 100, 105, 97, 66, 111, 120, 32, 91, 32, 48, 32, 48, 32, 53, 57, 53, 46, 50, 55, 53, 54, 32, 56, 52, 49, 46, 56, 56, 57, 56, 32, 93, 32, 47, 80, 97, 114, 101, 110, 116, 32, 49, 51, 32, 48, 32, 82, 32, 47, 82, 101, 115, 111, 117, 114, 99, 101, 115, 32, 60, 60, 10, 47, 70, 111, 110, 116, 32, 49, 32, 48, 32, 82, 32, 47, 80, 114, 111, 99, 83, 101, 116, 32, 91, 32, 47, 80, 68, 70, 32, 47, 84, 101, 120, 116, 32, 47, 73, 109, 97, 103, 101, 66, 32, 47, 73, 109, 97, 103, 101, 67, 32, 47, 73, 109, 97, 103, 101, 73, 32, 93, 10, 62, 62, 32, 47, 82, 111, 116, 97, 116, 101, 32, 48, 32, 47, 84, 114, 97, 110, 115, 32, 60, 60, 10, 10, 62, 62, 32, 10, 32, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 54, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 79, 117, 116, 108, 105, 110, 101, 115, 32, 56, 32, 48, 32, 82, 32, 47, 80, 97, 103, 101, 77, 111, 100, 101, 32, 47, 85, 115, 101, 78, 111, 110, 101, 32, 47, 80, 97, 103, 101, 115, 32, 49, 51, 32, 48, 32, 82, 32, 47, 84, 121, 112, 101, 32, 47, 67, 97, 116, 97, 108, 111, 103, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 55, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 65, 117, 116, 104, 111, 114, 32, 40, 97, 110, 111, 110, 121, 109, 111, 117, 115, 41, 32, 47, 67, 114, 101, 97, 116, 105, 111, 110, 68, 97, 116, 101, 32, 40, 68, 58, 50, 48, 48, 48, 48, 49, 48, 49, 48, 48, 48, 48, 48, 48, 43, 48, 48, 39, 48, 48, 39, 41, 32, 47, 67, 114, 101, 97, 116, 111, 114, 32, 40, 97, 110, 111, 110, 121, 109, 111, 117, 115, 41, 32, 47, 75, 101, 121, 119, 111, 114, 100, 115, 32, 40, 41, 32, 47, 77, 111, 100, 68, 97, 116, 101, 32, 40, 68, 58, 50, 48, 48, 48, 48, 49, 48, 49, 48, 48, 48, 48, 48, 48, 43, 48, 48, 39, 48, 48, 39, 41, 32, 47, 80, 114, 111, 100, 117, 99, 101, 114, 32, 40, 82, 101, 112, 111, 114, 116, 76, 97, 98, 32, 80, 68, 70, 32, 76, 105, 98, 114, 97, 114, 121, 32, 45, 32, 92, 40, 111, 112, 101, 110, 115, 111, 117, 114, 99, 101, 92, 41, 41, 32, 10, 32, 32, 47, 83, 117, 98, 106, 101, 99, 116, 32, 40, 117, 110, 115, 112, 101, 99, 105, 102, 105, 101, 100, 41, 32, 47, 84, 105, 116, 108, 101, 32, 40, 117, 110, 116, 105, 116, 108, 101, 100, 41, 32, 47, 84, 114, 97, 112, 112, 101, 100, 32, 47, 70, 97, 108, 115, 101, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 56, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 67, 111, 117, 110, 116, 32, 53, 32, 47, 70, 105, 114, 115, 116, 32, 57, 32, 48, 32, 82, 32, 47, 76, 97, 115, 116, 32, 49, 50, 32, 48, 32, 82, 32, 47, 84, 121, 112, 101, 32, 47, 79, 117, 116, 108, 105, 110, 101, 115, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 57, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 68, 101, 115, 116, 32, 91, 32, 51, 32, 48, 32, 82, 32, 47, 70, 105, 116, 32, 93, 32, 47, 78, 101, 120, 116, 32, 49, 48, 32, 48, 32, 82, 32, 47, 80, 97, 114, 101, 110, 116, 32, 56, 32, 48, 32, 82, 32, 47, 84, 105, 116, 108, 101, 32, 40, 73, 110, 116, 114, 111, 41, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 48, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 67, 111, 117, 110, 116, 32, 49, 32, 47, 68, 101, 115, 116, 32, 91, 32, 52, 32, 48, 32, 82, 32, 47, 70, 105, 116, 32, 93, 32, 47, 70, 105, 114, 115, 116, 32, 49, 49, 32, 48, 32, 82, 32, 47, 76, 97, 115, 116, 32, 49, 49, 32, 48, 32, 82, 32, 47, 78, 101, 120, 116, 32, 49, 50, 32, 48, 32, 82, 32, 47, 80, 97, 114, 101, 110, 116, 32, 56, 32, 48, 32, 82, 32, 10, 32, 32, 47, 80, 114, 101, 118, 32, 57, 32, 48, 32, 82, 32, 47, 84, 105, 116, 108, 101, 32, 40, 77, 101, 116, 104, 111, 100, 41, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 49, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 68, 101, 115, 116, 32, 91, 32, 52, 32, 48, 32, 82, 32, 47, 70, 105, 116, 32, 93, 32, 47, 80, 97, 114, 101, 110, 116, 32, 49, 48, 32, 48, 32, 82, 32, 47, 84, 105, 116, 108, 101, 32, 40, 68, 101, 116, 97, 105, 108, 115, 41, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 50, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 68, 101, 115, 116, 32, 91, 32, 53, 32, 48, 32, 82, 32, 47, 70, 105, 116, 32, 93, 32, 47, 80, 97, 114, 101, 110, 116, 32, 56, 32, 48, 32, 82, 32, 47, 80, 114, 101, 118, 32, 49, 48, 32, 48, 32, 82, 32, 47, 84, 105, 116, 108, 101, 32, 40, 82, 101, 115, 117, 108, 116, 41, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 51, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 67, 111, 117, 110, 116, 32, 51, 32, 47, 75, 105, 100, 115, 32, 91, 32, 51, 32, 48, 32, 82, 32, 52, 32, 48, 32, 82, 32, 53, 32, 48, 32, 82, 32, 93, 32, 47, 84, 121, 112, 101, 32, 47, 80, 97, 103, 101, 115, 10, 62, 62, 10, 101, 110, 100, 111, 98, 106, 10, 49, 52, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 76, 101, 110, 103, 116, 104, 32, 56, 49, 10, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 49, 32, 48, 32, 48, 32, 49, 32, 48, 32, 48, 32, 99, 109, 32, 32, 66, 84, 32, 47, 70, 49, 32, 49, 50, 32, 84, 102, 32, 49, 52, 46, 52, 32, 84, 76, 32, 69, 84, 10, 66, 84, 32, 49, 32, 48, 32, 48, 32, 49, 32, 55, 50, 32, 55, 48, 48, 32, 84, 109, 32, 40, 80, 97, 103, 101, 32, 49, 41, 32, 84, 106, 32, 84, 42, 32, 69, 84, 10, 32, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 49, 53, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 76, 101, 110, 103, 116, 104, 32, 56, 49, 10, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 49, 32, 48, 32, 48, 32, 49, 32, 48, 32, 48, 32, 99, 109, 32, 32, 66, 84, 32, 47, 70, 49, 32, 49, 50, 32, 84, 102, 32, 49, 52, 46, 52, 32, 84, 76, 32, 69, 84, 10, 66, 84, 32, 49, 32, 48, 32, 48, 32, 49, 32, 55, 50, 32, 55, 48, 48, 32, 84, 109, 32, 40, 80, 97, 103, 101, 32, 50, 41, 32, 84, 106, 32, 84, 42, 32, 69, 84, 10, 32, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 49, 54, 32, 48, 32, 111, 98, 106, 10, 60, 60, 10, 47, 76, 101, 110, 103, 116, 104, 32, 56, 49, 10, 62, 62, 10, 115, 116, 114, 101, 97, 109, 10, 49, 32, 48, 32, 48, 32, 49, 32, 48, 32, 48, 32, 99, 109, 32, 32, 66, 84, 32, 47, 70, 49, 32, 49, 50, 32, 84, 102, 32, 49, 52, 46, 52, 32, 84, 76, 32, 69, 84, 10, 66, 84, 32, 49, 32, 48, 32, 48, 32, 49, 32, 55, 50, 32, 55, 48, 48, 32, 84, 109, 32, 40, 80, 97, 103, 101, 32, 51, 41, 32, 84, 106, 32, 84, 42, 32, 69, 84, 10, 32, 10, 101, 110, 100, 115, 116, 114, 101, 97, 109, 10, 101, 110, 100, 111, 98, 106, 10, 120, 114, 101, 102, 10, 48, 32, 49, 55, 10, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 32, 54, 53, 53, 51, 53, 32, 102, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 54, 49, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 48, 57, 50, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 49, 57, 57, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 52, 48, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 54, 48, 57, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 56, 49, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 48, 56, 57, 57, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 49, 54, 48, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 50, 51, 50, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 51, 49, 54, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 52, 53, 51, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 53, 50, 56, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 54, 49, 52, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 54, 56, 54, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 56, 49, 55, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 48, 48, 48, 48, 48, 48, 49, 57, 52, 56, 32, 48, 48, 48, 48, 48, 32, 110, 32, 10, 116, 114, 97, 105, 108, 101, 114, 10, 60, 60, 10, 47, 73, 68, 32, 10, 91, 60, 49, 99, 49, 55, 56, 49, 57, 56, 102, 98, 100, 102, 97, 53, 49, 98, 50, 53, 57, 57, 53, 100, 56, 57, 100, 52, 49, 48, 50, 48, 52, 51, 62, 60, 49, 99, 49, 55, 56, 49, 57, 56, 102, 98, 100, 102, 97, 53, 49, 98, 50, 53, 57, 57, 53, 100, 56, 57, 100, 52, 49, 48, 50, 48, 52, 51, 62, 93, 10, 37, 32, 82, 101, 112, 111, 114, 116, 76, 97, 98, 32, 103, 101, 110, 101, 114, 97, 116, 101, 100, 32, 80, 68, 70, 32, 100, 111, 99, 117, 109, 101, 110, 116, 32, 45, 45, 32, 100, 105, 103, 101, 115, 116, 32, 40, 111, 112, 101, 110, 115, 111, 117, 114, 99, 101, 41, 10, 10, 47, 73, 110, 102, 111, 32, 55, 32, 48, 32, 82, 10, 47, 82, 111, 111, 116, 32, 54, 32, 48, 32, 82, 10, 47, 83, 105, 122, 101, 32, 49, 55, 10, 62, 62, 10, 115, 116, 97, 114, 116, 120, 114, 101, 102, 10, 50, 48, 55, 57, 10, 37, 37, 69, 79, 70, 10 }
    // (D4800) Images: a DCT block, Flate samples under the PNG predictors, a stencil and a form, in paint order.
    let (pic, pic_error) = pdf.page_painting(a, img_pdf[0..], 0usize)
    if pic_error != ok { os.exit(24) }
    if pic.shapes.len != 4usize || pic.images.len != 3usize { os.exit(25) }
    if pic.shapes[0].kind != pdf.SHAPE_IMAGE || pic.shapes[0].x0 != 10.0f64 || pic.shapes[0].y0 != 20.0f64 || pic.shapes[0].x1 != 110.0f64 || pic.shapes[0].y1 != 120.0f64 || pic.shapes[0].size != 0.0f64 { os.exit(26) }
    if pic.shapes[1].kind != pdf.SHAPE_IMAGE || pic.shapes[1].x0 != 130.0f64 || pic.shapes[1].x1 != 190.0f64 || pic.shapes[1].y1 != 190.0f64 || pic.shapes[1].size != 1.0f64 { os.exit(27) }
    if pic.shapes[3].kind != pdf.SHAPE_FILL || pic.shapes[3].x0 != 150.0f64 || pic.shapes[3].y1 != 40.0f64 || pic.shapes[3].green != 1.0f64 || pic.shapes[3].red != 0.0f64 { os.exit(28) }
    let jpg = pic.images[0]
    if jpg.width != 8u32 || jpg.height != 8u32 { os.exit(29) }
    var jc = 0usize
    while jc < 64usize {
        let jr = i32(jpg.pixels[jc * 4usize]) - 200i32
        let jg = i32(jpg.pixels[jc * 4usize + 1usize]) - 40i32
        let jb = i32(jpg.pixels[jc * 4usize + 2usize]) - 30i32
        if jr > 12i32 || jr < -12i32 || jg > 12i32 || jg < -12i32 || jb > 12i32 || jb < -12i32 { os.exit(30) }
        jc += 1usize
    }
    let flat = pic.images[1]
    if flat.width != 6u32 || flat.height != 4u32 { os.exit(31) }
    var fy = 0usize
    while fy < 4usize {
        var fx = 0usize
        while fx < 6usize {
            let at = (fy * 6usize + fx) * 4usize
            if usize(flat.pixels[at]) != (fx * 40usize + fy * 7usize) % 256usize { os.exit(32) }
            if usize(flat.pixels[at + 1usize]) != (fy * 60usize + fx * 3usize) % 256usize { os.exit(33) }
            if usize(flat.pixels[at + 2usize]) != (fx * fy * 20usize + 17usize) % 256usize { os.exit(34) }
            if flat.pixels[at + 3usize] != 255u8 { os.exit(35) }
            fx += 1usize
        }
        fy += 1usize
    }
    let stencil = pic.images[2]
    if stencil.width != 8u32 || stencil.height != 2u32 { os.exit(36) }
    // Row 0 is 10101010 (a 0 bit paints), row 1 is 11110000.
    if stencil.pixels[3usize] != 0u8 || stencil.pixels[7usize] != 255u8 || stencil.pixels[(8usize + 3usize) * 4usize + 3usize] != 0u8 || stencil.pixels[(8usize + 4usize) * 4usize + 3usize] != 255u8 { os.exit(37) }
    // (D4800) Fonts: /Widths and a Type0 font's /W set the advance, /ToUnicode maps codes to letters.
    let (words, words_error) = pdf.pages(a, font_pdf[0..])
    if words_error != ok || words.len != 1usize { os.exit(38) }
    if !str.eq(words[0], "ABC\nHiABC\nZZ") { os.exit(39) }
    let (lettered, lettered_error) = pdf.page_painting(a, font_pdf[0..], 0usize)
    if lettered_error != ok || lettered.shapes.len != 3usize { os.exit(40) }
    if !str.eq(lettered.shapes[0].text, "ABC") || lettered.shapes[0].x1 != 28.0f64 { os.exit(41) }
    if !str.eq(lettered.shapes[1].text, "HiABC") || lettered.shapes[1].x0 != 10.0f64 { os.exit(42) }
    if lettered.shapes[1].x1 < 29.79f64 || lettered.shapes[1].x1 > 29.81f64 { os.exit(43) }
    if !str.eq(lettered.shapes[2].text, "ZZ") || lettered.shapes[2].x1 != 22.0f64 { os.exit(44) }
    // An embedded TrueType subset from reportlab: its text, and an advance from the font's own widths (11723 units
    // of 2048 at 12 pt for "Hello fi world", from fontTools' hmtx).
    let (faced, faced_error) = pdf.pages(a, ttf_pdf[0..])
    if faced_error != ok || faced.len != 1usize || !str.eq(faced[0], "Hello fi world") { os.exit(45) }
    let (faced_paint, faced_paint_error) = pdf.page_painting(a, ttf_pdf[0..], 0usize)
    if faced_paint_error != ok || faced_paint.shapes.len != 1usize { os.exit(46) }
    let advance = faced_paint.shapes[0].x1 - faced_paint.shapes[0].x0
    if advance < 68.5f64 || advance > 68.9f64 { os.exit(47) }
    // (D4800) The outline: reportlab bookmarks, one nested.
    let (marks, marks_error) = pdf.outline(a, out_pdf[0..])
    if marks_error != ok || marks.len != 4usize { os.exit(48) }
    if !str.eq(marks[0].title, "Intro") || marks[0].page != 0usize || marks[0].level != 0usize { os.exit(49) }
    if !str.eq(marks[1].title, "Method") || marks[1].page != 1usize || marks[1].level != 0usize { os.exit(50) }
    if !str.eq(marks[2].title, "Details") || marks[2].page != 1usize || marks[2].level != 1usize { os.exit(51) }
    if !str.eq(marks[3].title, "Result") || marks[3].page != 2usize || marks[3].level != 0usize { os.exit(52) }
    let (none, none_error) = pdf.outline(a, painted[0..])
    if none_error != ok || none.len != 0usize { os.exit(53) }
    let core_check = issue_78_core_check(a)
    if core_check != 0u8 { os.exit(62i32 + i32(core_check)) }
    let remaining_check = issue_78_remaining_check(a)
    if remaining_check != 0u8 { os.exit(100i32 + i32(remaining_check)) }
    ret ok
}
