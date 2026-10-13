// Document (D2237): the app behind the Document icon, a viewer after Google Docs, Drive and a code viewer
// -- a list of files (a Markdown file, a text file, a PDF, a Word document, a PowerPoint deck, and source in
// Neper, Python, C, JavaScript, SQL, Rust, Go and Java); a Markdown file shows its headings, bullets and
// code; a text file shows its lines; source is shown with line numbers and SYNTAX HIGHLIGHTING (keywords,
// types, strings, numbers and comments in their own colours) for its language; a PDF and a Word document
// are pages you turn; a deck is slides you step through. Dark ground, cream pages and amber, like the
// other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the
// bottom leaves the app.
// ponytail: the files are SAMPLE documents written into the app (no file is opened from storage), the PDF,
// Word and PowerPoint pages are drawn by hand to look like what those formats hold (there is no PDF or
// Office parser yet), and the highlighter is one rule set with a keyword list for each of eight languages
// (the 30 leading languages of the TIOBE index are queued). Real readers for PDF, DOCX, PPTX and
// Markdown, opening files from Files and Mail, search, and highlighting for the rest of the languages are
// queued as C123's remainder, C142.
use e.mem
use e.os
use e.io
use e.fmt.png
use e.fmt.jpeg
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use ui
use vaultfs
use e.fmt.ooxml as ooxml
use e.fmt.odf as odf
use e.fmt.pdf as pdf
use e.fmt.html as html
use e.fmt.zip as zip
use e.text.highlight as hl

const NONE: usize = 99usize
const FILES: usize = 13usize
const LIST_SCREEN: usize = 0usize
const VIEW_SCREEN: usize = 1usize
const DISK_SCREEN: usize = 7usize
const FIND_SCREEN: usize = 8usize
const OUTLINE_SCREEN: usize = 9usize
const MD: usize = 0usize
const TXT: usize = 1usize
const CODE: usize = 2usize
const PDF: usize = 3usize
const DOCX: usize = 4usize
const PPTX: usize = 5usize
// A spreadsheet (C172): its first sheet's cells, a row a line with tabs between the cells, drawn as a grid.
const SHEET: usize = 6usize
// A PDF drawn page by page from its content streams (C152), with its text lines one tap away.
const PDFPAGE: usize = 7usize
// A Word document with styled lines and pictures (D4805), and a deck drawn from its shapes.
const WORD: usize = 8usize
const SLIDES: usize = 9usize

type State = struct {
    // A file handed over by Files (C125): its name and text, shown as entry FILES of the list.
    hand_name: [24]u8,
    hand_name_len: usize,
    hand_text: [16384]u8,
    hand_len: usize,
    // How the handed file is shown (MD, TXT or CODE) and, for code, which sample's highlighter rules it uses.
    hand_kind: usize,
    hand_lang: usize,
    // The language the table-driven highlighter (e.text.highlight) picked by extension, and its classes per byte.
    hand_hl: usize,
    hand_has_hl: bool,
    hand_classes: [16384]u8,
    // The files found on the device's disk (up to eight, names of 24 bytes), the text being searched for, and the
    // text size step (0 small, 1 normal, 2 large).
    disk_names: [192]u8,
    disk_len: [8]usize,
    disk_total: usize,
    find: ui.Field,
    // The path of an open zip archive (C150), so its entries can be extracted: empty when the file is not one.
    zip_path: [64]u8,
    zip_path_len: usize,
    // (C152) A text file over what the viewer holds is read a window at a time from the disk: its path and size, the
    // window shown, where each window starts (at a line) and the pages before it, and whether another follows.
    // (C152) An open PDF: its path (to be painted from), its page count, and whether the text lines are shown instead.
    pdf_path: [64]u8,
    pdf_path_len: usize,
    pdf_pages: usize,
    pdf_text: bool,
    pdf_said: usize,
    // (D4801) The painted page's images as textures (uploaded once per page; `pdf_tex_page` is the page + 1 they
    // belong to), the page zoom step (0 fit, 1 1.5x, 2 2x, 3 3x) and the pan in dp (at most 0 up and left).
    pdf_tex: [6]scene.TextureId,
    pdf_tex_w: [6]f32,
    pdf_tex_h: [6]f32,
    // A Word picture's width in dp (from its extent; 0 when the part gave none).
    pic_dp_w: [6]f32,
    pdf_tex_n: usize,
    pdf_tex_page: usize,
    pz: usize,
    pan_x: f32,
    pan_y: f32,
    // A finger down on the page: where it went down (a drag pans a zoomed page).
    drag_on: bool,
    drag_x: f32,
    drag_y: f32,
    // The word Find highlights on the painted page (set when a Find found it) and how many runs carried it.
    hl_on: bool,
    // (D4805) A Word file or a deck drawn from its package again each frame: its path; for Word, each text line's
    // style (0 body, 1 title or heading 1, 2 heading 2, 3 deeper headings, 9 a picture's first line, 8 its others).
    office_path: [64]u8,
    office_path_len: usize,
    deck_slides: usize,
    line_style: [512]u8,
    // The outline: up to eleven bookmarks (title bytes, depth, page).
    ol_n: usize,
    ol_text: [440]u8,
    ol_len: [11]usize,
    ol_page: [11]usize,
    ol_level: [11]usize,
    big_path: [64]u8,
    big_path_len: usize,
    big_size: usize,
    big_chunk: usize,
    big_starts: [64]usize,
    big_base: [64]usize,
    big_more: bool,
    zoom: usize,
    screen: usize,
    open: usize,
    page: usize,
    hits: ui.Hits,
}

// (C123) Append `line` and a newline to the handed file's text (up to its 2000 bytes); the new length.
fn add_line(s: *State, at: usize, line: str) -> usize {
    var n = at
    var i = 0usize
    while i < line.len && n < 16383usize {
        s.hand_text[n] = line[i]
        n += 1usize
        i += 1usize
    }
    if n < 16383usize {
        s.hand_text[n] = 10u8
        n += 1usize
    }
    ret n
}

// The text of a Word document (a paragraph a line, a list item after "- ") or a PowerPoint deck ("Slide n" and
// its paragraphs) into the handed file's text, through e.fmt.ooxml; the length, 0 when it did not read.
fn deck_of(a: *mem.Arena, is_odf: bool, raw: []const u8) -> ([]ooxml.Slide, err) {
    if is_odf {
        let (found, found_error) = odf.slides(a, raw)
        ret (found, found_error)
    }
    let (found, found_error) = ooxml.slides(a, raw)
    ret (found, found_error)
}

fn text_of_file(a: *mem.Arena, is_odf: bool, raw: []const u8) -> ([]ooxml.Paragraph, err) {
    if is_odf {
        let (found, found_error) = odf.paragraphs(a, raw)
        ret (found, found_error)
    }
    let (found, found_error) = ooxml.paragraphs(a, raw)
    ret (found, found_error)
}

fn office_text(a: *mem.Arena, s: *State, is_deck: bool, is_odf: bool, raw: []const u8) -> usize {
    var n = 0usize
    if is_deck {
        let (slides, slides_error) = deck_of(a, is_odf, raw)
        if slides_error != ok { ret 0usize }
        s.deck_slides = slides.len
        var i = 0usize
        while i < slides.len {
            n = add_line(s, n, ui.join(a, "Slide ", ui.number(a, i + 1usize), ""))
            var j = 0usize
            while j < slides[i].paragraphs.len {
                n = add_line(s, n, ui.join(a, "  ", slides[i].paragraphs[j], ""))
                j += 1usize
            }
            i += 1usize
        }
    } else {
        let (paragraphs, paragraphs_error) = text_of_file(a, is_odf, raw)
        if paragraphs_error != ok { ret 0usize }
        // (C152) A Word document's tables are grids set between the paragraphs outside them: the cells' paragraphs
        // are left out of the text and each table's rows follow the paragraph it came after, tabs between cells.
        var flags: []bool = zero
        var grids: []ooxml.Grid = zero
        if !is_odf {
            let (found_flags, flags_error) = ooxml.cell_flags(a, raw)
            let (found_grids, grids_error) = ooxml.tables(a, raw)
            if flags_error == ok && grids_error == ok && found_flags.len == paragraphs.len {
                flags = found_flags
                grids = found_grids
            }
        }
        // (D4805) Each line's style (Title and Heading n from the paragraph's style) and the lines a picture reserves.
        var pictures: []ooxml.Picture = zero
        if !is_odf {
            let (found_pictures, pictures_error) = ooxml.pictures(a, raw)
            if pictures_error == ok { pictures = found_pictures }
        }
        var line_no = 0usize
        var next_table = 0usize
        var body_count = 0usize
        var i = 0usize
        while i < paragraphs.len {
            var p = 0usize
            while p < pictures.len {
                if pictures[p].paragraph == i && line_no + 4usize < 512usize {
                    s.line_style[line_no] = 9u8
                    n = add_line(s, n, ui.number(a, p))
                    line_no += 1usize
                    var pad = 0usize
                    while pad < 3usize {
                        s.line_style[line_no] = 8u8
                        n = add_line(s, n, "")
                        line_no += 1usize
                        pad += 1usize
                    }
                }
                p += 1usize
            }
            let in_cell = i < flags.len && flags[i]
            if !in_cell {
                while next_table < grids.len && grids[next_table].after <= body_count {
                    n = add_grid(s, n, grids[next_table])
                    line_no += grids[next_table].rows
                    next_table += 1usize
                }
                if line_no < 512usize {
                    var style = 0u8
                    let name = paragraphs[i].style
                    if ui.same(name, "Title") || ui.same(name, "Heading1") { style = 1u8 }
                    if ui.same(name, "Heading2") { style = 2u8 }
                    if ui.same(name, "Heading3") || ui.same(name, "Heading4") || ui.same(name, "Subtitle") { style = 3u8 }
                    s.line_style[line_no] = style
                }
                if paragraphs[i].list {
                    n = add_line(s, n, ui.join(a, "- ", paragraphs[i].text, ""))
                } else {
                    n = add_line(s, n, paragraphs[i].text)
                }
                line_no += 1usize
                body_count += 1usize
            }
            i += 1usize
        }
        while next_table < grids.len {
            n = add_grid(s, n, grids[next_table])
            line_no += grids[next_table].rows
            next_table += 1usize
        }
        if pictures.len > 0usize {
            ui.say("document word pictures ")
            ui.say_num(pictures.len)
            ui.say("\n")
        }
        if grids.len > 0usize {
            ui.say("document tables ")
            ui.say_num(grids.len)
            ui.say("\n")
        }
    }
    ret n
}

// The first sheet of a spreadsheet (C172) as text: a row a line, the cells separated by tabs (a tab or newline inside
// a cell is a space), through e.fmt.ooxml.sheet_grid; the length, 0 when it did not read or has no cell.
fn xlsx_text(a: *mem.Arena, s: *State, raw: []const u8) -> usize {
    let (grid, grid_error) = ooxml.sheet_grid(a, raw, 1usize)
    if grid_error != ok || grid.rows == 0usize || grid.columns == 0usize { ret 0usize }
    ret add_grid(s, 0usize, grid)
}

// A grid's rows as lines of the handed text from `at`, cells separated by tabs (a tab or newline inside a cell is a
// space); the new length. A table of a Word document goes in the same way (C152).
fn add_grid(s: *State, at: usize, grid: ooxml.Grid) -> usize {
    var n = at
    var row = 0usize
    while row < grid.rows {
        var column = 0usize
        while column < grid.columns {
            if column > 0usize && n < 16383usize {
                s.hand_text[n] = 9u8
                n += 1usize
            }
            let cell = grid.cells[row * grid.columns + column]
            var i = 0usize
            while i < cell.len && n < 16383usize {
                var c = cell[i]
                if c == 9u8 || c == 10u8 || c == 13u8 { c = 32u8 }
                s.hand_text[n] = c
                n += 1usize
                i += 1usize
            }
            column += 1usize
        }
        if n < 16383usize {
            s.hand_text[n] = 10u8
            n += 1usize
        }
        row += 1usize
    }
    ret n
}

// The contents of a zip archive (C150): its name, then each entry as "name  size" ("name/" for a directory), one per
// line; the length, 0 when it did not open.
fn zip_text(a: *mem.Arena, s: *State, raw: []const u8) -> usize {
    let (archive, open_error) = ooxml.open_package(a, raw)
    if open_error != ok { ret 0usize }
    var ar = archive
    let listed = zip.entries(&ar)
    var n = add_line(s, 0usize, ui.join(a, ui.number(a, listed.len), " entries", ""))
    var i = 0usize
    while i < listed.len {
        if listed[i].directory {
            n = add_line(s, n, listed[i].name)
        } else {
            n = add_line(s, n, ui.join(a, ui.join(a, listed[i].name, "  ", ""), ui.number(a, usize(listed[i].size)), " bytes"))
        }
        i += 1usize
    }
    ret n
}

// The text of a PDF (a "Page n" heading and its lines for each page) into the handed file's text, through
// e.fmt.pdf; the length, 0 when it did not read.
fn pdf_text(a: *mem.Arena, s: *State, raw: []const u8) -> usize {
    let (found, pages_error) = pdf.pages(a, raw)
    if pages_error != ok { ret 0usize }
    s.pdf_pages = found.len
    // (D4801) The bookmarks (the first eleven), a new document's zoom and pan, and the old page's textures forgotten.
    s.ol_n = 0usize
    s.pz = 0usize
    s.pan_x = 0.0
    s.pan_y = 0.0
    s.hl_on = false
    s.pdf_tex_page = 0usize
    let (marks, marks_error) = pdf.outline(a, raw)
    if marks_error == ok {
        var m = 0usize
        while m < marks.len && s.ol_n < 11usize {
            var len = marks[m].title.len
            if len > 40usize { len = 40usize }
            var b = 0usize
            while b < len {
                s.ol_text[s.ol_n * 40usize + b] = marks[m].title[b]
                b += 1usize
            }
            s.ol_len[s.ol_n] = len
            s.ol_page[s.ol_n] = marks[m].page
            s.ol_level[s.ol_n] = marks[m].level
            s.ol_n += 1usize
            m += 1usize
        }
    }
    var n = 0usize
    var i = 0usize
    while i < found.len {
        n = add_line(s, n, ui.join(a, "Page ", ui.number(a, i + 1usize), ""))
        // The page's lines.
        var start = 0usize
        var at = 0usize
        while at <= found[i].len {
            if at == found[i].len || found[i][at] == 10u8 {
                n = add_line(s, n, ui.join(a, "  ", found[i][start..at], ""))
                start = at + 1usize
            }
            at += 1usize
        }
        i += 1usize
    }
    ret n
}

fn ends_with(whole: str, suffix: str) -> bool {
    if whole.len < suffix.len { ret false }
    var i = 0usize
    while i < suffix.len {
        if whole[whole.len - suffix.len + i] != suffix[i] { ret false }
        i += 1usize
    }
    ret true
}

// (C152) The window `k` of a big text file into the handed text: from where window k starts, up to 12000 bytes ending
// after the last line that fits; where window k + 1 starts is noted. False when there is no such window.
const BIG_WINDOW: usize = 12000usize

fn load_chunk(a: *mem.Arena, s: *State, k: usize) -> bool {
    if k >= 63usize { ret false }
    let path = ui.text_of(a, s.big_path[0usize..], s.big_path_len)
    let offset = s.big_starts[k]
    if offset >= s.big_size { ret false }
    var want = s.big_size - offset
    if want > BIG_WINDOW { want = BIG_WINDOW }
    let (got, read_ok) = vaultfs.read_from(path, offset, mem.address_of(&s.hand_text[0usize]), want)
    if !read_ok || got == 0usize { ret false }
    var cut = got
    if offset + got < s.big_size {
        var i = got
        while i > 0usize && s.hand_text[i - 1usize] != 10u8 { i -= 1usize }
        if i > 0usize { cut = i }
    }
    s.hand_len = cut
    s.big_starts[k + 1usize] = offset + cut
    s.big_more = offset + cut < s.big_size
    s.big_chunk = k
    if s.hand_has_hl {
        let classified = hl.classify(s.hand_hl, ui.text_of(a, s.hand_text[0usize..], s.hand_len), s.hand_classes[0usize..])
    }
    ret true
}

// (C152) The file name a `#!` first line stands for, by its interpreter, so the highlighter's extension table picks
// the language: `#!/usr/bin/env python3` and `#!/bin/python` are Python, `node`, the shells, `perl`, `ruby`, `php` and
// `lua` likewise. Empty when the text has no such line or the interpreter is not one of those.
fn shebang_name(content_text: str) -> str {
    if content_text.len < 3usize || content_text[0usize] != 35u8 || content_text[1usize] != 33u8 { ret "" }
    var end = 2usize
    while end < content_text.len && content_text[end] != 10u8 && content_text[end] != 13u8 { end += 1usize }
    let line = content_text[2usize..end]
    // The words of the line.
    var word_start = 0usize
    var first = ""
    var second = ""
    var words = 0usize
    var i = 0usize
    while i <= line.len {
        if i == line.len || line[i] == 32u8 || line[i] == 9u8 {
            if i > word_start {
                let word = line[word_start..i]
                if words == 0usize { first = word }
                if words == 1usize || (words == 2usize && second.len > 0usize && second[0usize] == 45u8) { second = word }
                words += 1usize
            }
            word_start = i + 1usize
        }
        i += 1usize
    }
    // The interpreter: the base name of the first word, or the word after `env` (and its options).
    var base = first
    var j = first.len
    while j > 0usize && first[j - 1usize] != 47u8 { j -= 1usize }
    base = first[j..first.len]
    if ui.same(base, "env") && second.len > 0usize { base = second }
    if base.len >= 6usize && ui.same(base[0usize..6usize], "python") { ret "x.py" }
    if ui.same(base, "node") || ui.same(base, "nodejs") { ret "x.js" }
    if ui.same(base, "sh") || ui.same(base, "bash") || ui.same(base, "zsh") || ui.same(base, "dash") || ui.same(base, "ksh") { ret "x.sh" }
    if ui.same(base, "perl") { ret "x.pl" }
    if ui.same(base, "ruby") { ret "x.rb" }
    if ui.same(base, "php") { ret "x.php" }
    if ui.same(base, "lua") { ret "x.lua" }
    ret ""
}

// A page of a handed file is this many lines.
const PAGE_LINES: usize = 26usize

// The lines of a page at the text size chosen, and the size's factor.
fn lines_per_page(s: *State) -> usize {
    if s.zoom == 0usize { ret 30usize }
    if s.zoom == 2usize { ret 20usize }
    ret PAGE_LINES
}

fn zoom_factor(s: *State) -> f32 {
    if s.zoom == 0usize { ret 0.85 }
    if s.zoom == 2usize { ret 1.3 }
    ret 1.0
}

// The lines in the handed file's text.
fn hand_lines(s: *State) -> usize {
    var n = 1usize
    var i = 0usize
    while i < s.hand_len {
        if s.hand_text[i] == 10u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

// The pages of what is open: a handed file's lines in pages, or a sample's own count.
fn pages_of(s: *State) -> usize {
    if s.open == FILES && s.hand_kind == PDFPAGE && !s.pdf_text { ret s.pdf_pages }
    if s.open == FILES && s.hand_kind == SLIDES && s.deck_slides > 0usize { ret s.deck_slides }
    if s.open == FILES { ret (hand_lines(s) + lines_per_page(s) - 1usize) / lines_per_page(s) }
    ret page_count(s.open)
}

// The first line the open text shows: the page's, for a handed file.
fn first_line(s: *State) -> usize {
    if s.open == FILES { ret s.page * lines_per_page(s) }
    ret 0usize
}

// The byte offset of line `n` of the handed text.
fn line_offset(s: *State, n: usize) -> usize {
    var line = 0usize
    var i = 0usize
    while i < s.hand_len && line < n {
        if s.hand_text[i] == 10u8 { line += 1usize }
        i += 1usize
    }
    ret i
}

// The text a screen draws: the handed file's, or entry `i`'s sample.
fn content_of(a: *mem.Arena, s: *State) -> str {
    if s.open == FILES { ret ui.text_of(a, s.hand_text[0usize..], s.hand_len) }
    ret body(s.open)
}

// The sample whose highlighter rules (keywords, comment marker) the open file uses.
fn code_lang(s: *State) -> usize {
    if s.open == FILES { ret s.hand_lang }
    ret s.open
}

// How a file called `name` is shown, by its extension: Markdown, a language's code (the sample index whose rules
// apply), or text.
fn kind_by_name(name: str) -> (usize, usize) {
    if ends_with(name, ".md") { ret (MD, 0usize) }
    if ends_with(name, ".ne") || ends_with(name, ".e") { ret (CODE, 2usize) }
    if ends_with(name, ".py") { ret (CODE, 6usize) }
    if ends_with(name, ".c") || ends_with(name, ".h") { ret (CODE, 7usize) }
    if ends_with(name, ".js") { ret (CODE, 8usize) }
    if ends_with(name, ".sql") { ret (CODE, 9usize) }
    if ends_with(name, ".rs") { ret (CODE, 10usize) }
    if ends_with(name, ".go") { ret (CODE, 11usize) }
    if ends_with(name, ".java") { ret (CODE, 12usize) }
    ret (TXT, 0usize)
}

// The language shown on the code view's pill.
fn shown_language(s: *State) -> str {
    if s.open == FILES && s.hand_has_hl { ret hl.name(s.hand_hl) }
    ret lang_name(code_lang(s))
}

fn file_name(i: usize) -> str {
    if i == 0usize { ret "README.md" }
    if i == 1usize { ret "notes.txt" }
    if i == 2usize { ret "hello.ne" }
    if i == 3usize { ret "report.pdf" }
    if i == 4usize { ret "letter.docx" }
    if i == 5usize { ret "slides.pptx" }
    if i == 6usize { ret "script.py" }
    if i == 7usize { ret "main.c" }
    if i == 8usize { ret "app.js" }
    if i == 9usize { ret "query.sql" }
    if i == 10usize { ret "main.rs" }
    if i == 11usize { ret "server.go" }
    ret "App.java"
}

fn file_kind(i: usize) -> usize {
    if i == FILES { ret TXT }
    if i == 0usize { ret MD }
    if i == 1usize { ret TXT }
    if i == 3usize { ret PDF }
    if i == 4usize { ret DOCX }
    if i == 5usize { ret PPTX }
    ret CODE
}

fn lang_name(i: usize) -> str {
    if i == 2usize { ret "Neper" }
    if i == 6usize { ret "Python" }
    if i == 7usize { ret "C" }
    if i == 8usize { ret "JavaScript" }
    if i == 9usize { ret "SQL" }
    if i == 10usize { ret "Rust" }
    if i == 11usize { ret "Go" }
    ret "Java"
}

fn tag_of(kind: usize) -> str {
    if kind == MD { ret "MD" }
    if kind == TXT { ret "TXT" }
    if kind == CODE { ret "</>" }
    if kind == PDF { ret "PDF" }
    if kind == DOCX { ret "DOC" }
    ret "PPT"
}

fn tile_color(kind: usize) -> paint.Color {
    if kind == MD { ret paint.Color { red: 0.50, green: 0.64, blue: 0.88, alpha: 1.0 } }
    if kind == TXT { ret paint.Color { red: 0.70, green: 0.70, blue: 0.72, alpha: 1.0 } }
    if kind == CODE { ret paint.Color { red: 0.45, green: 0.75, blue: 0.80, alpha: 1.0 } }
    if kind == PDF { ret paint.Color { red: 0.85, green: 0.45, blue: 0.40, alpha: 1.0 } }
    if kind == DOCX { ret paint.Color { red: 0.45, green: 0.58, blue: 0.90, alpha: 1.0 } }
    ret paint.Color { red: 0.90, green: 0.62, blue: 0.40, alpha: 1.0 }
}

fn page_count(i: usize) -> usize {
    if i == 3usize { ret 3usize }
    if i == 4usize { ret 2usize }
    if i == 5usize { ret 3usize }
    ret 1usize
}

// The text of a Markdown, text or source file: lines separated by a newline.
fn body(i: usize) -> str {
    if i == 0usize { ret "# Neper phone\n\nA phone that runs on the Neper language.\n\n## Apps\n- Calc, Clock and Tasks\n- Messages, Mail and Chat\n- Camera, Photos and Files\n\n## Build\n```\nneper build neperos/src/shell.e\n```\n\nEverything here is sample data until the network exists." }
    if i == 1usize { ret "Shopping list\n\nmilk\nbread\ncoffee beans\n\nCall the library about the hold.\nSend Maya the lunch place.\nFriday: review the icons." }
    if i == 2usize { ret "// Say hello, then count.\nuse e.os\n\nfn main() -> err {\n    let name = \"Neper\"\n    var total = 0usize\n    while total < 3usize {\n        total += 1usize\n    }\n    ret ok\n}" }
    if i == 6usize { ret "# count the words\nimport sys\n\nclass Counter:\n    def __init__(self):\n        self.total = 0\n\n    def add(self, word):\n        if word != \"\":\n            self.total += 1\n        return self.total" }
    if i == 7usize { ret "#include <stdio.h>\n\n/* sum of 1..n */\nint sum(int n) {\n    int total = 0;\n    for (int i = 1; i <= n; i++) {\n        total += i;\n    }\n    return total;\n}\n\nint main(void) { printf(\"%d\\n\", sum(10)); return 0; }" }
    if i == 8usize { ret "// fetch and show a user\nasync function show(id) {\n  const res = await fetch(\"/user/\" + id)\n  if (!res.ok) { return null }\n  const user = await res.json()\n  console.log(user.name, 42)\n  return user\n}\n\nexport default show" }
    if i == 9usize { ret "-- the ten best customers\nSELECT name, SUM(total) AS spent\nFROM orders\nJOIN customers ON customers.id = orders.customer\nWHERE total > 100\nGROUP BY name\nORDER BY spent DESC\nLIMIT 10;" }
    if i == 10usize { ret "// a counter\nuse std::collections::HashMap;\n\nfn count(words: &[&str]) -> HashMap<String, u32> {\n    let mut map = HashMap::new();\n    for w in words {\n        *map.entry(w.to_string()).or_insert(0) += 1;\n    }\n    map\n}" }
    if i == 11usize { ret "package main\n\nimport \"fmt\"\n\n// a tiny server loop\nfunc main() {\n\tcounts := map[string]int{}\n\tfor _, w := range []string{\"a\", \"b\", \"a\"} {\n\t\tcounts[w]++\n\t}\n\tfmt.Println(counts, 3)\n}" }
    ret "package app;\n\n// a greeter\npublic class App {\n    private final String name = \"Neper\";\n\n    public static void main(String[] args) {\n        for (int i = 0; i < 3; i++) {\n            System.out.println(\"hello \" + i);\n        }\n    }\n}"
}

// The keywords of a language, as a list of words each between spaces.
fn keywords(i: usize) -> str {
    if i == 2usize { ret " fn let var ret if else while for in try use type const struct union enum error true false zero ok match " }
    if i == 6usize { ret " def class return if elif else while for in import from as with try except finally raise lambda None True False and or not pass yield self " }
    if i == 7usize { ret " int char void return if else while for struct typedef static const unsigned long short double float sizeof break continue switch case default include " }
    if i == 8usize { ret " function const let var return if else while for of in class new this async await import from export default true false null undefined " }
    if i == 9usize { ret " select from where group by order insert into values update set delete create table and or not null join on as limit desc asc sum " }
    if i == 10usize { ret " fn let mut pub struct impl enum match if else while for in return use mod true false self Self " }
    if i == 11usize { ret " func var const type struct interface return if else for range package import go defer map chan true false nil " }
    ret " public private class static void int String return if else while for new import package final true false null extends implements "
}

fn comment_start(i: usize) -> str {
    if i == 6usize { ret "#" }
    if i == 9usize { ret "--" }
    ret "//"
}

fn is_letter(c: u8) -> bool {
    ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8
}

fn is_digit(c: u8) -> bool {
    ret c >= 48u8 && c <= 57u8
}

fn lower_text(a: *mem.Arena, word: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, word.len + 2usize)
    if buffer_error != ok { ret word }
    buffer[0usize] = 32u8
    var i = 0usize
    while i < word.len {
        var c = word[i]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        buffer[i + 1usize] = c
        i += 1usize
    }
    buffer[word.len + 1usize] = 32u8
    ret buffer[0usize..word.len + 2usize]
}

// Is `word` in the language's keyword list (SQL ignores case)?
fn is_keyword(a: *mem.Arena, lang: usize, word: str) -> bool {
    let list = keywords(lang)
    var probe = word
    if lang == 9usize { probe = lower_text(a, word) } else { probe = ui.join(a, " ", word, " ") }
    if probe.len > list.len { ret false }
    var at = 0usize
    while at + probe.len <= list.len {
        var k = 0usize
        var same_all = true
        while k < probe.len {
            if list[at + k] != probe[k] { same_all = false }
            k += 1usize
        }
        if same_all { ret true }
        at += 1usize
    }
    ret false
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn token_color(kind: usize) -> paint.Color {
    if kind == 1usize { ret paint.Color { red: 0.78, green: 0.58, blue: 0.88, alpha: 1.0 } }
    if kind == 2usize { ret paint.Color { red: 0.60, green: 0.82, blue: 0.55, alpha: 1.0 } }
    if kind == 3usize { ret paint.Color { red: 0.90, green: 0.70, blue: 0.42, alpha: 1.0 } }
    if kind == 4usize { ret paint.Color { red: 0.50, green: 0.62, blue: 0.52, alpha: 1.0 } }
    if kind == 5usize { ret paint.Color { red: 0.50, green: 0.76, blue: 0.90, alpha: 1.0 } }
    ret paint.Color { red: 0.88, green: 0.88, blue: 0.86, alpha: 1.0 }
}

// One source line with its tokens in colour: 1 keyword, 2 string, 3 number, 4 comment, 5 type, 0 the rest.
fn draw_code_line(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, lang: usize, row: str, x: f32, y: f32) -> err {
    let size: f32 = 13.0
    let marker = comment_start(lang)
    var i = 0usize
    while i < row.len {
        let c = row[i]
        if c == 32u8 || c == 9u8 {
            i += 1usize
        } else {
            var end = i + 1usize
            var kind = 0usize
            var at_comment = false
            if row.len - i >= marker.len {
                var k = 0usize
                var match_all = true
                while k < marker.len {
                    if row[i + k] != marker[k] { match_all = false }
                    k += 1usize
                }
                at_comment = match_all
            }
            if at_comment {
                end = row.len
                kind = 4usize
            } else if c == 34u8 {
                end = i + 1usize
                while end < row.len && row[end] != 34u8 { end += 1usize }
                if end < row.len { end += 1usize }
                kind = 2usize
            } else if is_digit(c) {
                while end < row.len && (is_digit(row[end]) || row[end] == 46u8 || is_letter(row[end])) { end += 1usize }
                kind = 3usize
            } else if is_letter(c) {
                while end < row.len && (is_letter(row[end]) || is_digit(row[end])) { end += 1usize }
                let word = row[i..end]
                if is_keyword(a, lang, word) { kind = 1usize } else if c >= 65u8 && c <= 90u8 { kind = 5usize }
            }
            // The width of what comes before, spaces included (a sentinel keeps trailing spaces).
            let prefix = text.measure(a, faces.grotesk, size, ui.join(a, row[0usize..i], "|", "")) - text.measure(a, faces.grotesk, size, "|")
            try ui.put(a, builder, faces.grotesk, size, row[i..end], x + prefix, y, token_color(kind))
            i = end
        }
    }
    ret ok
}

fn splitter(a: *mem.Arena, content: str, index: usize) -> str {
    // The `index`th line of `content`.
    var at = 0usize
    var line = 0usize
    var start = 0usize
    while at <= content.len {
        if at == content.len || content[at] == 10u8 {
            if line == index { ret content[start..at] }
            line += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    ret ""
}

fn line_total(content: str) -> usize {
    var n = 1usize
    var i = 0usize
    while i < content.len {
        if content[i] == 10u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Document", 20.0, 16.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, 700usize, 272.0, 18.0, 124.0, 34.0, "On this device", ui.amber(), 13.0)
    var i = 0usize
    while i < FILES {
        let y: f32 = 78.0 + f32(i) * 58.0
        try ui.card(a, builder, 16.0, y, 380.0, 52.0, 16.0, ui.cream())
        try ui.card(a, builder, 26.0, y + 8.0, 38.0, 36.0, 10.0, tile_color(file_kind(i)))
        try ui.centred(a, builder, faces.grotesk, 11.0, tag_of(file_kind(i)), 45.0, y + 18.0, ui.ink())
        try ui.put(a, builder, faces.jost, 17.0, file_name(i), 78.0, y + 7.0, ui.ink())
        var detail = "Document"
        if file_kind(i) == MD { detail = "Markdown" }
        if file_kind(i) == TXT { detail = "Plain text" }
        if file_kind(i) == CODE { detail = lang_name(i) }
        if file_kind(i) == PDF { detail = "PDF, 3 pages" }
        if file_kind(i) == DOCX { detail = "Word, 2 pages" }
        if file_kind(i) == PPTX { detail = "PowerPoint, 3 slides" }
        try ui.put(a, builder, faces.grotesk, 12.0, detail, 78.0, y + 30.0, ui.muted())
        ui.hit(&s.hits, 100usize + i, 16.0, y, 380.0, 52.0)
        i += 1usize
    }
    ret ok
}

// A Markdown table row (C172) starts with a bar; `trim_bar` is the row without its outer bars and spaces.
fn is_bar_row(line: str) -> bool {
    var i = 0usize
    while i < line.len && line[i] == 32u8 { i += 1usize }
    ret i < line.len && line[i] == 124u8
}

fn trim_bar(line: str) -> str {
    var start = 0usize
    var end = line.len
    while start < end && line[start] == 32u8 { start += 1usize }
    if start < end && line[start] == 124u8 { start += 1usize }
    while end > start && (line[end - 1usize] == 32u8 || line[end - 1usize] == 13u8) { end -= 1usize }
    if end > start && line[end - 1usize] == 124u8 { end -= 1usize }
    ret line[start..end]
}

// The delimiter row under a table's header: only dashes, colons, bars and spaces, with a dash.
fn is_rule_row(line: str) -> bool {
    if !is_bar_row(line) { ret false }
    var dash = false
    var i = 0usize
    while i < line.len {
        let c = line[i]
        if c == 45u8 { dash = true }
        if c != 45u8 && c != 58u8 && c != 124u8 && c != 32u8 && c != 13u8 { ret false }
        i += 1usize
    }
    ret dash
}

// The number of `sep`-separated fields of a line, and the `k`th, without surrounding spaces.
fn field_count(line: str, sep: u8) -> usize {
    var n = 1usize
    var i = 0usize
    while i < line.len {
        if line[i] == sep { n += 1usize }
        i += 1usize
    }
    ret n
}

fn field_at(line: str, k: usize, sep: u8) -> str {
    var start = 0usize
    var index = 0usize
    var i = 0usize
    while i <= line.len {
        if i == line.len || line[i] == sep {
            if index == k {
                var from = start
                var to = i
                while from < to && line[from] == 32u8 { from += 1usize }
                while to > from && line[to - 1usize] == 32u8 { to -= 1usize }
                ret line[from..to]
            }
            index += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret ""
}

// One row of cells in a grid of `columns` equal columns across `width`, at `x` and `y`: each cell clipped to the
// characters that fit its column (7 dp a character at the 13 pt grotesk).
fn draw_cells(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, row: str, sep: u8, columns: usize, x: f32, y: f32, width: f32, bold: bool, color: paint.Color) -> err {
    if columns == 0usize { ret ok }
    let each = width / f32(columns)
    var fit = 2usize
    while f32(fit + 1usize) * 7.0 <= each { fit += 1usize }
    var k = 0usize
    while k < columns {
        var cell = field_at(row, k, sep)
        if cell.len > fit { cell = cell[0usize..fit] }
        if cell.len > 0usize {
            if bold {
                try ui.put(a, builder, faces.jost_bold, 14.0, cell, x + f32(k) * each + 5.0, y, color)
            } else {
                try ui.put(a, builder, faces.grotesk, 13.0, cell, x + f32(k) * each + 5.0, y, color)
            }
        }
        k += 1usize
    }
    ret ok
}

// A spreadsheet's rows of the page as a grid (C172): the first row a header band, hairlines between rows and columns.
// The columns are equal and at most eight; a sheet wider than that shows its first eight.
fn draw_sheet(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 12.0, 84.0, 388.0, 730.0, 18.0, ui.cream())
    let content = content_of(a, s)
    var total = line_total(content)
    // The text ends with a newline: the empty line after it is not a row.
    if total > 1usize && content.len > 0usize && content[content.len - 1usize] == 10u8 { total -= 1usize }
    var columns = field_count(splitter(a, content, 0usize), 9u8)
    if columns > 8usize { columns = 8usize }
    let zf = zoom_factor(s)
    let pitch: f32 = 26.0 * zf
    let first = first_line(s)
    let last = first + lines_per_page(s)
    var n = first
    while n < total && n < last {
        let y: f32 = 96.0 + f32(n - first) * pitch
        if n == 0usize { try ui.card(a, builder, 20.0, y - 4.0, 372.0, pitch, 4.0, paint.Color { red: 0.93, green: 0.86, blue: 0.70, alpha: 1.0 }) }
        try draw_cells(a, builder, faces, splitter(a, content, n), 9u8, columns, 20.0, y, 372.0, n == 0usize, ui.ink())
        try ui.card(a, builder, 20.0, y - 4.0 + pitch, 372.0, 1.0, 0.5, ui.muted())
        n += 1usize
    }
    // Column hairlines over the rows drawn.
    var shown = total - first
    if shown > lines_per_page(s) { shown = lines_per_page(s) }
    var k = 0usize
    while k <= columns {
        let x: f32 = 20.0 + f32(k) * 372.0 / f32(columns)
        try ui.card(a, builder, x, 92.0, 1.0, f32(shown) * pitch, 0.5, ui.muted())
        k += 1usize
    }
    ret ok
}

fn draw_md(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 12.0, 84.0, 388.0, 730.0, 18.0, ui.cream())
    let content = content_of(a, s)
    var y: f32 = 100.0
    var in_code = false
    var n = first_line(s)
    let total = line_total(content)
    let last = n + lines_per_page(s)
    while n < total && n < last {
        let row = splitter(a, content, n)
        if row.len >= 3usize && ui.same(row[0usize..3usize], "```") {
            in_code = !in_code
            y += 4.0
        } else if in_code {
            try ui.card(a, builder, 24.0, y - 2.0, 364.0, 22.0, 4.0, paint.Color { red: 0.12, green: 0.13, blue: 0.16, alpha: 1.0 })
            try ui.put(a, builder, faces.grotesk, 13.0, row, 32.0, y + 2.0, ui.light())
            y += 24.0
        } else if row.len >= 2usize && ui.same(row[0usize..2usize], "# ") {
            try ui.put(a, builder, faces.jost_bold, 28.0, row[2usize..row.len], 28.0, y, ui.ink())
            y += 44.0
        } else if row.len >= 3usize && ui.same(row[0usize..3usize], "## ") {
            try ui.put(a, builder, faces.jost_bold, 21.0, row[3usize..row.len], 28.0, y, ui.amber_dark())
            y += 34.0
        } else if row.len >= 2usize && ui.same(row[0usize..2usize], "- ") {
            try ui.disc(a, builder, 36.0, y + 11.0, 3.0, ui.muted())
            try ui.put(a, builder, faces.jost, 17.0, row[2usize..row.len], 50.0, y, ui.ink())
            y += 26.0
        } else if row.len == 0usize {
            y += 12.0
        } else if is_bar_row(row) {
            // A table row (C172): its delimiter row draws nothing, the row above it is the header.
            if !is_rule_row(row) {
                let cells = trim_bar(row)
                let header = n + 1usize < total && is_rule_row(splitter(a, content, n + 1usize))
                if header { try ui.card(a, builder, 24.0, y - 3.0, 364.0, 26.0, 4.0, paint.Color { red: 0.93, green: 0.86, blue: 0.70, alpha: 1.0 }) }
                try draw_cells(a, builder, faces, cells, 124u8, field_count(cells, 124u8), 24.0, y, 364.0, header, ui.ink())
                try ui.card(a, builder, 24.0, y + 23.0, 364.0, 1.0, 0.5, ui.muted())
                y += 28.0
            }
        } else {
            let (box, box_error) = ui.wrapped(a, builder, faces.jost, 17.0, row, 28.0, y, 356.0, 0u32, ui.ink())
            if box_error != ok { ret box_error }
            y += box.height + 6.0
        }
        n += 1usize
    }
    ret ok
}

fn draw_txt(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 12.0, 84.0, 388.0, 730.0, 18.0, ui.cream())
    var content = body(s.open)
    if s.open == FILES { content = ui.text_of(a, s.hand_text[0usize..], s.hand_len) }
    let first = first_line(s)
    var n = first
    let total = line_total(content)
    // Only the lines of the page are drawn.
    let zf = zoom_factor(s)
    while n < total && n < first + lines_per_page(s) + 1usize {
        let row = splitter(a, content, n)
        let row_y: f32 = 100.0 + f32(n - first) * 26.0 * zf
        if field_count(row, 9u8) > 1usize {
            // A table row of a Word document (C152): its cells in equal columns with a hairline under it.
            try draw_cells(a, builder, faces, row, 9u8, field_count(row, 9u8), 28.0, row_y, 356.0, false, ui.ink())
            try ui.card(a, builder, 28.0, row_y + 22.0, 356.0, 1.0, 0.5, ui.muted())
        } else {
            try ui.put(a, builder, faces.grotesk, 15.0 * zf, row, 28.0, row_y, ui.ink())
            // (D4807) An entry of an open zip is a tap target: it extracts that one entry.
            if s.zip_path_len > 0usize && n >= 1usize && n - 1usize < 200usize {
                ui.hit(&s.hits, 2000usize + n - 1usize, 12.0, row_y - 4.0, 388.0, 26.0 * zf)
            }
        }
        n += 1usize
    }
    ret ok
}

// One line of a handed file with its token classes (0 plain, 1 keyword, 2 string, 3 number, 4 comment, 5 type):
// each run of one class drawn in its colour, at its measured offset.
fn draw_class_line(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, row: str, classes: []const u8, x: f32, y: f32) -> err {
    let size: f32 = 13.0
    var i = 0usize
    while i < row.len {
        if row[i] == 32u8 || row[i] == 9u8 {
            i += 1usize
        } else {
            let klass = classes[i]
            var end = i + 1usize
            while end < row.len && classes[end] == klass && row[end] != 32u8 && row[end] != 9u8 { end += 1usize }
            let prefix = text.measure(a, faces.grotesk, size, ui.join(a, row[0usize..i], "|", "")) - text.measure(a, faces.grotesk, size, "|")
            var color_kind = 0usize
            if klass == 1u8 { color_kind = 1usize }
            if klass == 2u8 { color_kind = 2usize }
            if klass == 3u8 { color_kind = 3usize }
            if klass == 4u8 { color_kind = 4usize }
            if klass == 5u8 { color_kind = 5usize }
            try ui.put(a, builder, faces.grotesk, size, row[i..end], x + prefix, y, token_color(color_kind))
            i = end
        }
    }
    ret ok
}

fn draw_code(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 12.0, 84.0, 388.0, 730.0, 18.0, paint.Color { red: 0.12, green: 0.13, blue: 0.16, alpha: 1.0 })
    let content = content_of(a, s)
    let total = line_total(content)
    let first = first_line(s)
    var n = first
    while n < total && n < first + 30usize {
        let y: f32 = 100.0 + f32(n - first) * 22.0
        try ui.put_right(a, builder, faces.grotesk, 12.0, ui.number(a, n + 1usize), 44.0, y + 1.0, ui.light_muted())
        if s.open == FILES && s.hand_has_hl {
            // The classes of this line: the bytes before it are the lines before plus their newlines.
            let offset = line_offset(s, n)
            let line = splitter(a, content, n)
            if offset + line.len <= s.hand_len {
                try draw_class_line(a, builder, faces, line, s.hand_classes[offset..offset + line.len], 56.0, y)
            }
        } else {
            try draw_code_line(a, builder, faces, code_lang(s), splitter(a, content, n), 56.0, y)
        }
        n += 1usize
    }
    // The legend of the colours.
    var legend = 0usize
    while legend < 5usize {
        var name = "keyword"
        if legend == 1usize { name = "string" }
        if legend == 2usize { name = "number" }
        if legend == 3usize { name = "comment" }
        if legend == 4usize { name = "type" }
        var kind = 1usize
        if legend == 1usize { kind = 2usize }
        if legend == 2usize { kind = 3usize }
        if legend == 3usize { kind = 4usize }
        if legend == 4usize { kind = 5usize }
        try ui.disc(a, builder, 32.0 + f32(legend) * 76.0, 786.0, 5.0, token_color(kind))
        try ui.put(a, builder, faces.grotesk, 11.0, name, 42.0 + f32(legend) * 76.0, 780.0, ui.light_muted())
        legend += 1usize
    }
    ret ok
}

fn pdf_color(red: f64, green: f64, blue: f64) -> paint.Color {
    ret paint.Color { red: f32(red), green: f32(green), blue: f32(blue), alpha: 1.0 }
}

// (C152) A PDF page painted: e.fmt.pdf's shapes (filled rectangles, stroked segments, text at its position and size)
// laid out on a white sheet scaled to the card. The file is read and the page parsed for each draw (a frame's arena
// is given back at the next).
// The zoom factor of step `pz`.
fn page_zoom(pz: usize) -> f32 {
    if pz == 1usize { ret 1.5 }
    if pz == 2usize { ret 2.0 }
    if pz == 3usize { ret 3.0 }
    ret 1.0
}

// (D4801) Upload the images of a painted page as textures, once per page: a picture over 65536 pixels is averaged
// down by a whole factor first (a texture is four floats a pixel). The old page's textures are released.
fn upload_page_images(a: *mem.Arena, kit: *appkit.Kit, s: *State, images: []pdf.Image, page: usize) {
    if s.pdf_tex_page == page + 1usize { ret }
    var k = 0usize
    while k < s.pdf_tex_n {
        let released = scene.release_image(&kit.renderer, s.pdf_tex[k])
        k += 1usize
    }
    s.pdf_tex_n = 0usize
    s.pdf_tex_page = page + 1usize
    var i = 0usize
    while i < images.len && i < 6usize {
        let source = images[i]
        var factor = 1usize
        while (usize(source.width) / factor) * (usize(source.height) / factor) > 65536usize { factor += 1usize }
        let w = usize(source.width) / factor
        let h = usize(source.height) / factor
        var uploaded = false
        if w > 0usize && h > 0usize {
            let (small, small_error) = mem.alloc[u8](a, w * h * 4usize)
            if small_error == ok {
                var y = 0usize
                while y < h {
                    var x = 0usize
                    while x < w {
                        var sum_r = 0usize
                        var sum_g = 0usize
                        var sum_b = 0usize
                        var sum_a = 0usize
                        var dy = 0usize
                        while dy < factor {
                            var dx = 0usize
                            while dx < factor {
                                let at = ((y * factor + dy) * usize(source.width) + x * factor + dx) * 4usize
                                sum_r += usize(source.pixels[at])
                                sum_g += usize(source.pixels[at + 1usize])
                                sum_b += usize(source.pixels[at + 2usize])
                                sum_a += usize(source.pixels[at + 3usize])
                                dx += 1usize
                            }
                            dy += 1usize
                        }
                        let n = factor * factor
                        let o = (y * w + x) * 4usize
                        small[o] = u8(sum_r / n)
                        small[o + 1usize] = u8(sum_g / n)
                        small[o + 2usize] = u8(sum_b / n)
                        small[o + 3usize] = u8(sum_a / n)
                        x += 1usize
                    }
                    y += 1usize
                }
                let (view, view_error) = image.make_const(small, u32(w), u32(h), w * 4usize, .Rgba8, .Straight)
                if view_error == ok {
                    let (texture, upload_error) = scene.upload_image(&kit.renderer, view)
                    if upload_error == ok {
                        s.pdf_tex[i] = texture
                        s.pdf_tex_w[i] = f32(w)
                        s.pdf_tex_h[i] = f32(h)
                        s.pdf_tex_n = i + 1usize
                        uploaded = true
                    }
                }
            }
        }
        if !uploaded {
            // Keep the slot count honest: a picture that did not upload is drawn as a placeholder.
            s.pdf_tex_w[i] = 0.0
            s.pdf_tex_n = i + 1usize
        }
        i += 1usize
    }
}

// Whether `needle` (the Find word, no case) is at `at` in `hay`.
fn same_at(hay: str, at: usize, needle: []const u8, needle_len: usize) -> bool {
    if needle_len == 0usize || at + needle_len > hay.len { ret false }
    var k = 0usize
    while k < needle_len {
        var c = hay[at + k]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        var q = needle[k]
        if q >= 65u8 && q <= 90u8 { q = q + 32u8 }
        if c != q { ret false }
        k += 1usize
    }
    ret true
}

fn draw_pdf_page(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 24.0, 84.0, 364.0, 680.0, 8.0, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 })
    let path = ui.text_of(a, s.pdf_path[0usize..], s.pdf_path_len)
    let (size, kind, day, found) = vaultfs.stat(path)
    if !found || size == 0usize || size > 262144usize {
        try ui.centred(a, builder, faces.jost, 17.0, "This page cannot be painted", 206.0, 400.0, ui.muted())
        ret ok
    }
    let (raw, raw_error) = mem.alloc[u8](a, size)
    if raw_error != ok { ret raw_error }
    let (got, read_ok) = vaultfs.read_big(path, mem.address_of(&raw[0usize]), size)
    if !read_ok || got != size {
        try ui.centred(a, builder, faces.jost, 17.0, "This page cannot be painted", 206.0, 400.0, ui.muted())
        ret ok
    }
    let (painting, paint_error) = pdf.page_painting(a, raw[0usize..got], s.page)
    if paint_error != ok {
        try ui.centred(a, builder, faces.jost, 17.0, "This page cannot be painted", 206.0, 400.0, ui.muted())
        ret ok
    }
    if s.pdf_said != s.page + 1usize {
        s.pdf_said = s.page + 1usize
        ui.say("document pdf painted ")
        ui.say_num(painting.shapes.len)
        ui.say(" shapes\n")
        ui.say("document pdf images ")
        ui.say_num(painting.images.len)
        ui.say("\n")
    }
    upload_page_images(a, kit, s, painting.images, s.page)
    // The page fits the card at step 0; zoomed, it is larger and panned (the pan is kept inside the page).
    var scale = 364.0 / f32(painting.width)
    let tall = 680.0 / f32(painting.height)
    if tall < scale { scale = tall }
    scale = scale * page_zoom(s.pz)
    let shown_w = f32(painting.width) * scale
    let shown_h = f32(painting.height) * scale
    var left: f32 = 24.0 + (364.0 - shown_w) / 2.0
    var top: f32 = 84.0
    if shown_w > 364.0 {
        if s.pan_x < 364.0 - shown_w { s.pan_x = 364.0 - shown_w }
        if s.pan_x > 0.0 { s.pan_x = 0.0 }
        left = 24.0 + s.pan_x
    }
    if shown_h > 680.0 {
        if s.pan_y < 680.0 - shown_h { s.pan_y = 680.0 - shown_h }
        if s.pan_y > 0.0 { s.pan_y = 0.0 }
        top = 84.0 + s.pan_y
    }
    let page_height = f32(painting.height)
    let save_clip: scene.Command = .Save
    try scene.push(builder, save_clip)
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: geometry.rect(24.0, 84.0, 364.0, 680.0) } })
    var highlighted = 0usize
    var i = 0usize
    while i < painting.shapes.len {
        let piece = painting.shapes[i]
        let color = pdf_color(piece.red, piece.green, piece.blue)
        let x0: f32 = left + f32(piece.x0) * scale
        let y0: f32 = top + (page_height - f32(piece.y0)) * scale
        if piece.kind == pdf.SHAPE_IMAGE {
            let x1: f32 = left + f32(piece.x1) * scale
            let y1: f32 = top + (page_height - f32(piece.y1)) * scale
            var ix = x0
            var iy = y0
            var iw = x1 - x0
            var ih = y1 - y0
            if iw < 0.0 {
                ix = x1
                iw = 0.0 - iw
            }
            if ih < 0.0 {
                iy = y1
                ih = 0.0 - ih
            }
            let slot = i32(piece.size)
            if slot >= 0i32 && usize(slot) < s.pdf_tex_n && s.pdf_tex_w[usize(slot)] > 0.0 {
                let k = usize(slot)
                try scene.push(builder, scene.Command { Image: scene.DrawImage { texture: s.pdf_tex[k], source: geometry.rect(0.0, 0.0, s.pdf_tex_w[k], s.pdf_tex_h[k]), destination: geometry.rect(ix, iy, iw, ih), opacity: 1.0 } })
            } else {
                try ui.card(a, builder, ix, iy, iw, ih, 0.0, paint.Color { red: 0.86, green: 0.86, blue: 0.88, alpha: 1.0 })
            }
        } else if piece.kind == pdf.SHAPE_FILL {
            let x1: f32 = left + f32(piece.x1) * scale
            let y1: f32 = top + (page_height - f32(piece.y1)) * scale
            var rx = x0
            var ry = y0
            var rw = x1 - x0
            var rh = y1 - y0
            if rw < 0.0 {
                rx = x1
                rw = 0.0 - rw
            }
            if rh < 0.0 {
                ry = y1
                rh = 0.0 - rh
            }
            try ui.card(a, builder, rx, ry, rw, rh, 0.0, color)
        } else if piece.kind == pdf.SHAPE_LINE {
            let x1: f32 = left + f32(piece.x1) * scale
            let y1: f32 = top + (page_height - f32(piece.y1)) * scale
            var thick = f32(piece.width) * scale
            if thick < 1.0 { thick = 1.0 }
            var dx = x1 - x0
            var dy = y1 - y0
            if dx < 0.0 { dx = 0.0 - dx }
            if dy < 0.0 { dy = 0.0 - dy }
            if dy < 0.5 {
                var from = x0
                if x1 < x0 { from = x1 }
                try ui.card(a, builder, from, y0 - thick / 2.0, dx, thick, 0.0, color)
            } else if dx < 0.5 {
                var from = y0
                if y1 < y0 { from = y1 }
                try ui.card(a, builder, x0 - thick / 2.0, from, thick, dy, 0.0, color)
            } else {
                // A slanted segment as a run of dots.
                var length = dx
                if dy > length { length = dy }
                var t: f32 = 0.0
                let step: f32 = 1.5 / length
                while t <= 1.0 {
                    try ui.disc(a, builder, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, thick / 2.0 + 0.3, color)
                    t += step
                }
            }
        } else {
            var size_dp = f32(piece.size) * scale
            if size_dp < 5.0 { size_dp = 5.0 }
            // (D4801) The Find word, marked behind the run it is in: the run's width is split by characters.
            if s.hl_on && s.find.len > 0usize {
                let run_w = (f32(piece.x1) - f32(piece.x0)) * scale
                var at = 0usize
                while at + s.find.len <= piece.text.len {
                    if same_at(piece.text, at, s.find.bytes[0usize..], s.find.len) {
                        let from = run_w * f32(at) / f32(piece.text.len)
                        let span = run_w * f32(s.find.len) / f32(piece.text.len)
                        try ui.card(a, builder, x0 + from - 1.0, y0 - size_dp * 0.95, span + 2.0, size_dp * 1.2, 2.0, paint.Color { red: 1.0, green: 0.88, blue: 0.30, alpha: 1.0 })
                        highlighted += 1usize
                        at += s.find.len
                    } else {
                        at += 1usize
                    }
                }
            }
            try ui.put(a, builder, faces.jost, size_dp, piece.text, x0, y0 - size_dp * 0.85, color)
        }
        i += 1usize
    }
    let restore_clip: scene.Command = .Restore
    try scene.push(builder, restore_clip)
    if highlighted > 0usize && s.hl_on {
        ui.say("document pdf highlight ")
        ui.say_num(highlighted)
        ui.say("\n")
    }
    ret ok
}

// (D4805) Decode a PNG or JPEG as stored (by its first bytes; at most 262144 pixels) and upload it into texture slot
// `slot`; false when it is neither, is too large or does not decode.
fn upload_picture(a: *mem.Arena, kit: *appkit.Kit, s: *State, slot: usize, bytes: []const u8) -> bool {
    if slot >= 6usize || bytes.len < 8usize { ret false }
    var reader_state: io.SliceReader = zero
    reader_state.data = bytes
    reader_state.off = 0usize
    var decoded: image.Image = zero
    var decode_error = ok
    if bytes[0usize] == 255u8 && bytes[1usize] == 216u8 {
        let (jpeg_image, jpeg_error) = jpeg.decode(a, io.slice_reader(&reader_state), jpeg.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 262144u64 })
        decoded = jpeg_image
        decode_error = jpeg_error
    } else {
        let (png_image, png_error) = png.decode(a, io.slice_reader(&reader_state), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 262144u64, verify_crc: true })
        decoded = png_image
        decode_error = png_error
    }
    if decode_error != ok { ret false }
    let (view, view_error) = image.make_const(decoded.pixels, decoded.width, decoded.height, decoded.stride, decoded.format, decoded.alpha)
    if view_error != ok { ret false }
    let (texture, upload_error) = scene.upload_image(&kit.renderer, view)
    if upload_error != ok { ret false }
    s.pdf_tex[slot] = texture
    s.pdf_tex_w[slot] = f32(decoded.width)
    s.pdf_tex_h[slot] = f32(decoded.height)
    ret true
}

// The package at `office_path`, read whole (up to 256 KB); empty when it is missing or larger.
fn read_office(a: *mem.Arena, s: *State) -> []const u8 {
    let path = ui.text_of(a, s.office_path[0usize..], s.office_path_len)
    let (size, kind, day, found) = vaultfs.stat(path)
    if !found || size == 0usize || size > 262144usize { ret "" }
    let (raw, raw_error) = mem.alloc[u8](a, size)
    if raw_error != ok { ret "" }
    let (got, read_ok) = vaultfs.read_big(path, mem.address_of(&raw[0usize]), size)
    if !read_ok || got != size { ret "" }
    ret raw[0usize..got]
}

fn release_page_textures(kit: *appkit.Kit, s: *State) {
    var k = 0usize
    while k < s.pdf_tex_n {
        let released = scene.release_image(&kit.renderer, s.pdf_tex[k])
        k += 1usize
    }
    s.pdf_tex_n = 0usize
}

// A Word document's lines: headings in bold at their size, a table row as cells, a picture (its textures uploaded the
// first time) at the width of its extent inside the card, the rest as plain lines.
fn draw_word(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 12.0, 84.0, 388.0, 730.0, 18.0, ui.cream())
    if s.pdf_tex_page != 1usize {
        release_page_textures(kit, s)
        s.pdf_tex_page = 1usize
        let raw = read_office(a, s)
        if raw.len > 0usize {
            let (found, found_error) = ooxml.pictures(a, raw)
            if found_error == ok {
                var p = 0usize
                while p < found.len && p < 6usize {
                    var loaded = upload_picture(a, kit, s, p, found[p].data)
                    if !loaded { s.pdf_tex_w[p] = 0.0 }
                    // The size it is drawn at: 52 dp to the inch (a 6.5 inch text width fills the card).
                    s.pic_dp_w[p] = f32(found[p].cx) / 914400.0 * 52.0
                    s.pdf_tex_n = p + 1usize
                    p += 1usize
                }
                ui.say("document word pictures drawn ")
                ui.say_num(s.pdf_tex_n)
                ui.say("\n")
            }
        }
    }
    let content = content_of(a, s)
    let first = first_line(s)
    var n = first
    let total = line_total(content)
    let zf = zoom_factor(s)
    while n < total && n < first + lines_per_page(s) + 1usize {
        let row = splitter(a, content, n)
        let row_y: f32 = 100.0 + f32(n - first) * 26.0 * zf
        var style = 0u8
        if n < 512usize { style = s.line_style[n] }
        if style == 9u8 {
            // The picture's number is the line's text.
            var k = 0usize
            var d = 0usize
            while d < row.len {
                k = k * 10usize + usize(row[d] - 48u8)
                d += 1usize
            }
            if k < s.pdf_tex_n && s.pdf_tex_w[k] > 0.0 {
                var w = s.pic_dp_w[k]
                if w < 1.0 { w = s.pdf_tex_w[k] * 2.0 }
                var h = w * s.pdf_tex_h[k] / s.pdf_tex_w[k]
                let room: f32 = 98.0 * zf
                if w > 340.0 {
                    h = h * 340.0 / w
                    w = 340.0
                }
                if h > room {
                    w = w * room / h
                    h = room
                }
                try scene.push(builder, scene.Command { Image: scene.DrawImage { texture: s.pdf_tex[k], source: geometry.rect(0.0, 0.0, s.pdf_tex_w[k], s.pdf_tex_h[k]), destination: geometry.rect(28.0, row_y, w, h), opacity: 1.0 } })
            } else {
                try ui.card(a, builder, 28.0, row_y, 200.0, 80.0, 6.0, paint.Color { red: 0.86, green: 0.86, blue: 0.88, alpha: 1.0 })
            }
        } else if style == 8u8 {
            // The rest of a picture's lines.
        } else if style == 1u8 {
            try ui.put(a, builder, faces.jost_bold, 22.0 * zf, row, 28.0, row_y - 4.0, ui.ink())
        } else if style == 2u8 {
            try ui.put(a, builder, faces.jost_bold, 18.0 * zf, row, 28.0, row_y - 1.0, ui.amber_dark())
        } else if style == 3u8 {
            try ui.put(a, builder, faces.jost_bold, 16.0 * zf, row, 28.0, row_y, ui.ink())
        } else if field_count(row, 9u8) > 1usize {
            try draw_cells(a, builder, faces, row, 9u8, field_count(row, 9u8), 28.0, row_y, 356.0, false, ui.ink())
            try ui.card(a, builder, 28.0, row_y + 22.0, 356.0, 1.0, 0.5, ui.muted())
        } else {
            try ui.put(a, builder, faces.grotesk, 15.0 * zf, row, 28.0, row_y, ui.ink())
        }
        n += 1usize
    }
    ret ok
}

// The colour of a 0xRRGGBB fill.
fn rgb_color(value: u32) -> paint.Color {
    ret paint.Color { red: f32((value >> 16u32) & 255u32) / 255.0, green: f32((value >> 8u32) & 255u32) / 255.0, blue: f32(value & 255u32) / 255.0, alpha: 1.0 }
}

// (D4805) A slide drawn from its shapes: the slide canvas at the width of the screen, each positioned slide_shape as a
// rectangle, ellipse, line or picture with its fill and text; shapes with no position of their own (placeholders take
// theirs from the layout, which is not read) are listed as text under the canvas.
fn draw_slide_shapes(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State, faces: text.Faces) -> err {
    let raw = read_office(a, s)
    var drawn = false
    if raw.len > 0usize {
        let (deck_layout, layout_error) = ooxml.slide_layout(a, raw, s.page + 1usize)
        if layout_error == ok && deck_layout.width > 0usize {
            if s.pdf_tex_page != s.page + 1usize {
                release_page_textures(kit, s)
                s.pdf_tex_page = s.page + 1usize
                var p = 0usize
                while p < deck_layout.pictures.len && p < 6usize {
                    var loaded = upload_picture(a, kit, s, p, deck_layout.pictures[p].data)
                    if !loaded { s.pdf_tex_w[p] = 0.0 }
                    s.pdf_tex_n = p + 1usize
                    p += 1usize
                }
                ui.say("document slide shapes ")
                ui.say_num(deck_layout.shapes.len)
                ui.say("\n")
            }
            let canvas_w: f32 = 380.0
            let canvas_h: f32 = canvas_w * f32(deck_layout.height) / f32(deck_layout.width)
            let unit = canvas_w / f32(deck_layout.width)
            try ui.card(a, builder, 16.0, 96.0, canvas_w, canvas_h, 8.0, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 })
            var below_y: f32 = 96.0 + canvas_h + 16.0
            var i = 0usize
            while i < deck_layout.shapes.len {
                let slide_shape = deck_layout.shapes[i]
                if slide_shape.cx == 0usize && slide_shape.cy == 0usize {
                    // No position: its text goes under the canvas.
                    var start = 0usize
                    var at = 0usize
                    while at <= slide_shape.text.len {
                        if at == slide_shape.text.len || slide_shape.text[at] == 10u8 {
                            if at > start && below_y < 800.0 {
                                try ui.put(a, builder, faces.jost, 17.0, slide_shape.text[start..at], 24.0, below_y, ui.light())
                                below_y += 26.0
                            }
                            start = at + 1usize
                        }
                        at += 1usize
                    }
                } else {
                    let x: f32 = 16.0 + f32(slide_shape.x) * unit
                    let y: f32 = 96.0 + f32(slide_shape.y) * unit
                    var w: f32 = f32(slide_shape.cx) * unit
                    var h: f32 = f32(slide_shape.cy) * unit
                    if w < 1.0 { w = 1.0 }
                    if h < 1.0 { h = 1.0 }
                    var ink = ui.ink()
                    if slide_shape.kind == ooxml.SHAPE_PICTURE {
                        if slide_shape.picture < s.pdf_tex_n && s.pdf_tex_w[slide_shape.picture] > 0.0 {
                            let k = slide_shape.picture
                            try scene.push(builder, scene.Command { Image: scene.DrawImage { texture: s.pdf_tex[k], source: geometry.rect(0.0, 0.0, s.pdf_tex_w[k], s.pdf_tex_h[k]), destination: geometry.rect(x, y, w, h), opacity: 1.0 } })
                        } else {
                            try ui.card(a, builder, x, y, w, h, 0.0, paint.Color { red: 0.86, green: 0.86, blue: 0.88, alpha: 1.0 })
                        }
                    } else if slide_shape.kind == ooxml.SHAPE_LINE {
                        if w >= h {
                            try ui.card(a, builder, x, y, w, 1.5, 0.0, ui.muted())
                        } else {
                            try ui.card(a, builder, x, y, 1.5, h, 0.0, ui.muted())
                        }
                    } else {
                        var radius: f32 = 0.0
                        if slide_shape.kind == ooxml.SHAPE_ELLIPSE {
                            radius = w / 2.0
                            if h < w { radius = h / 2.0 }
                        }
                        if slide_shape.fill != ooxml.NO_COLOR {
                            try ui.card(a, builder, x, y, w, h, radius, rgb_color(slide_shape.fill))
                            // Light text on a dark fill.
                            let lum = ((slide_shape.fill >> 16u32) & 255u32) + ((slide_shape.fill >> 8u32) & 255u32) + (slide_shape.fill & 255u32)
                            if lum < 384u32 { ink = ui.light() }
                        } else if slide_shape.text.len == 0usize {
                            try ui.card(a, builder, x, y, w, h, radius, paint.Color { red: 0.80, green: 0.80, blue: 0.82, alpha: 1.0 })
                            try ui.card(a, builder, x + 1.0, y + 1.0, w - 2.0, h - 2.0, radius, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 })
                        }
                    }
                    if slide_shape.kind != ooxml.SHAPE_PICTURE && slide_shape.text.len > 0usize {
                        var line_y = y + 4.0
                        var start = 0usize
                        var at = 0usize
                        while at <= slide_shape.text.len {
                            if at == slide_shape.text.len || slide_shape.text[at] == 10u8 {
                                if at > start {
                                    try ui.put(a, builder, faces.jost, 14.0, slide_shape.text[start..at], x + 6.0, line_y, ink)
                                    line_y += 18.0
                                }
                                start = at + 1usize
                            }
                            at += 1usize
                        }
                    }
                }
                i += 1usize
            }
            drawn = true
        }
    }
    if !drawn { try ui.centred(a, builder, faces.jost, 17.0, "This slide cannot be drawn", 206.0, 300.0, ui.light_muted()) }
    try ui.put(a, builder, faces.grotesk, 13.0, ui.join(a, "Slide ", ui.number(a, s.page + 1usize), ui.join(a, " of ", ui.number(a, s.deck_slides), "")), 24.0, 78.0, ui.light_muted())
    ret ok
}

// A page of a PDF or Word file, drawn by hand.
fn draw_page(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let kind = file_kind(s.open)
    try ui.card(a, builder, 24.0, 84.0, 364.0, 680.0, 8.0, ui.cream())
    if kind == PDF {
        if s.page == 0usize {
            try ui.put(a, builder, faces.jost_bold, 28.0, "Quarterly report", 44.0, 112.0, ui.ink())
            try ui.put(a, builder, faces.grotesk, 12.0, "Third quarter, sample figures", 44.0, 150.0, ui.muted())
            let (b1, e1) = ui.wrapped(a, builder, faces.jost, 16.0, "Sales grew in every region this quarter. The largest gain came from the new apps, which brought in a third of the new customers.", 44.0, 190.0, 324.0, 0u32, ui.ink())
            if e1 != ok { ret e1 }
            let (b2, e2) = ui.wrapped(a, builder, faces.jost, 16.0, "Costs stayed flat. The team plans to add storage and network support next quarter.", 44.0, 320.0, 324.0, 0u32, ui.ink())
            if e2 != ok { ret e2 }
        } else if s.page == 1usize {
            try ui.put(a, builder, faces.jost_bold, 22.0, "Revenue by month", 44.0, 112.0, ui.ink())
            var m = 0usize
            while m < 6usize {
                let h: f32 = 40.0 + f32((m * 37usize) % 90usize) + f32(m) * 12.0
                try ui.card(a, builder, 52.0 + f32(m) * 54.0, 400.0 - h, 38.0, h, 6.0, ui.amber())
                m += 1usize
            }
            try ui.card(a, builder, 44.0, 404.0, 324.0, 1.5, 0.75, ui.muted())
        } else {
            try ui.put(a, builder, faces.jost_bold, 22.0, "Conclusion", 44.0, 112.0, ui.ink())
            let (b3, e3) = ui.wrapped(a, builder, faces.jost, 16.0, "The numbers support going on as planned. Page three of a sample document: nothing here is real.", 44.0, 156.0, 324.0, 0u32, ui.ink())
            if e3 != ok { ret e3 }
        }
    } else {
        if s.page == 0usize {
            try ui.put(a, builder, faces.grotesk, 12.0, "Neper Street 1, Berlin", 44.0, 112.0, ui.muted())
            try ui.put(a, builder, faces.jost, 17.0, "Dear Sam,", 44.0, 170.0, ui.ink())
            let (b1, e1) = ui.wrapped(a, builder, faces.jost, 16.0, "Thank you for your letter. We are pleased to confirm your place in the programme and look forward to seeing you in the spring.", 44.0, 210.0, 324.0, 0u32, ui.ink())
            if e1 != ok { ret e1 }
        } else {
            let (b2, e2) = ui.wrapped(a, builder, faces.jost, 16.0, "Please bring your passport and the signed form. If anything changes, write to us.", 44.0, 112.0, 324.0, 0u32, ui.ink())
            if e2 != ok { ret e2 }
            try ui.put(a, builder, faces.jost, 17.0, "Kind regards,", 44.0, 260.0, ui.ink())
            try ui.put(a, builder, faces.jost_bold, 17.0, "The office", 44.0, 290.0, ui.ink())
        }
    }
    ret ok
}

fn draw_slide(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 16.0, 200.0, 380.0, 214.0, 12.0, ui.cream())
    if s.page == 0usize {
        try ui.card(a, builder, 16.0, 200.0, 380.0, 214.0, 12.0, paint.Color { red: 0.20, green: 0.30, blue: 0.45, alpha: 1.0 })
        try ui.centred(a, builder, faces.jost_bold, 30.0, "Apps from a prompt", 206.0, 270.0, ui.cream())
        try ui.centred(a, builder, faces.jost, 16.0, "Sample deck, slide 1", 206.0, 320.0, ui.amber())
    } else if s.page == 1usize {
        try ui.put(a, builder, faces.jost_bold, 24.0, "How it works", 36.0, 216.0, ui.ink())
        try ui.put(a, builder, faces.jost, 17.0, "1. You write a prompt", 44.0, 262.0, ui.ink())
        try ui.put(a, builder, faces.jost, 17.0, "2. A server writes and compiles it", 44.0, 292.0, ui.ink())
        try ui.put(a, builder, faces.jost, 17.0, "3. It is scanned and installed", 44.0, 322.0, ui.ink())
    } else {
        try ui.put(a, builder, faces.jost_bold, 24.0, "Installs", 36.0, 216.0, ui.ink())
        var b = 0usize
        while b < 5usize {
            let h: f32 = 30.0 + f32(b) * 24.0
            try ui.card(a, builder, 50.0 + f32(b) * 64.0, 396.0 - h, 44.0, h, 6.0, ui.amber())
            b += 1usize
        }
    }
    try ui.put(a, builder, faces.grotesk, 13.0, ui.join(a, "Slide ", ui.number(a, s.page + 1usize), ui.join(a, " of ", ui.number(a, page_count(s.open)), "")), 24.0, 436.0, ui.light_muted())
    ret ok
}

fn draw_view(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State, faces: text.Faces) -> err {
    var kind = file_kind(s.open)
    if s.open == FILES { kind = s.hand_kind }
    var painted_pdf = false
    if kind == PDFPAGE {
        // The painted page, or the text lines when the toggle says so.
        if s.pdf_text { kind = TXT } else { painted_pdf = true }
    }
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    var shown = file_name(s.open)
    if s.open == FILES { shown = ui.text_of(a, s.hand_name[0usize..], s.hand_name_len) }
    try ui.put(a, builder, faces.jost_bold, 22.0, shown, 62.0, 20.0, ui.light())
    if kind == CODE { try ui.pill(a, builder, &s.hits, faces, 501usize, 300.0, 18.0, 96.0, 32.0, shown_language(s), ui.amber(), 14.0) }
    if s.open == FILES {
        try ui.pill(a, builder, &s.hits, faces, 701usize, 16.0, 50.0, 70.0, 28.0, "Find", ui.soft(), 13.0)
        try ui.pill(a, builder, &s.hits, faces, 702usize, 94.0, 50.0, 40.0, 28.0, "A-", ui.soft(), 13.0)
        try ui.pill(a, builder, &s.hits, faces, 703usize, 142.0, 50.0, 40.0, 28.0, "A+", ui.soft(), 13.0)
        if s.pdf_path_len > 0usize {
            var toggle = "Text"
            if s.pdf_text { toggle = "Page" }
            try ui.pill(a, builder, &s.hits, faces, 705usize, 196.0, 50.0, 80.0, 28.0, toggle, ui.amber(), 13.0)
            if s.ol_n > 0usize { try ui.pill(a, builder, &s.hits, faces, 706usize, 284.0, 50.0, 100.0, 28.0, "Outline", ui.amber(), 13.0) }
        }
        if s.zip_path_len > 0usize { try ui.pill(a, builder, &s.hits, faces, 704usize, 196.0, 50.0, 96.0, 28.0, "Extract", ui.amber(), 13.0) }
    }
    if kind == MD { try draw_md(a, builder, s, faces) }
    if kind == TXT { try draw_txt(a, builder, s, faces) }
    if kind == CODE { try draw_code(a, builder, s, faces) }
    if kind == SHEET { try draw_sheet(a, builder, s, faces) }
    if kind == WORD { try draw_word(a, builder, kit, s, faces) }
    if kind == SLIDES { try draw_slide_shapes(a, builder, kit, s, faces) }
    if painted_pdf { try draw_pdf_page(a, builder, kit, s, faces) }
    if kind == PDF || kind == DOCX { try draw_page(a, builder, s, faces) }
    if kind == PPTX { try draw_slide(a, builder, s, faces) }
    if pages_of(s) > 1usize || s.big_more || s.big_chunk > 0usize {
        try ui.card(a, builder, 0.0, 828.0, 412.0, 68.0, 0.0, paint.Color { red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0 })
        try ui.pill(a, builder, &s.hits, faces, 600usize, 40.0, 838.0, 110.0, 46.0, "Previous", ui.soft(), 15.0)
        // A big file's pages count from its first window; the total grows as the windows are read (a plus sign).
        var more_mark = ""
        if s.big_more { more_mark = "+" }
        try ui.centred(a, builder, faces.jost, 17.0, ui.join(a, ui.number(a, s.big_base[s.big_chunk] + s.page + 1usize), " / ", ui.join(a, ui.number(a, s.big_base[s.big_chunk] + pages_of(s)), more_mark, "")), 206.0, 850.0, ui.light())
        try ui.pill(a, builder, &s.hits, faces, 601usize, 262.0, 838.0, 110.0, 46.0, "Next", ui.amber(), 15.0)
    }
    ret ok
}

// The files of the device's disk the app can show (up to eight), by name.
fn draw_disk(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, "On this device", 62.0, 20.0, ui.light())
    if s.disk_total == 0usize {
        try ui.centred(a, builder, faces.jost, 19.0, "No documents on the disk", 206.0, 200.0, ui.light_muted())
    }
    var i = 0usize
    while i < s.disk_total {
        let y: f32 = 84.0 + f32(i) * 58.0
        try ui.card(a, builder, 16.0, y, 380.0, 52.0, 16.0, ui.cream())
        try ui.put(a, builder, faces.jost, 17.0, ui.text_of(a, s.disk_names[i * 24usize..], s.disk_len[i]), 32.0, y + 14.0, ui.ink())
        ui.hit(&s.hits, 800usize + i, 16.0, y, 380.0, 52.0)
        i += 1usize
    }
    ret ok
}

// Find: a text field on the on-screen keyboard.
fn draw_find(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, "Find in the document", 62.0, 20.0, ui.light())
    try ui.card(a, builder, 16.0, 76.0, 380.0, 50.0, 14.0, ui.cream())
    if s.find.len == 0usize {
        try ui.put(a, builder, faces.jost, 20.0, "Type a word", 30.0, 88.0, ui.muted())
    } else {
        try ui.put(a, builder, faces.jost, 20.0, ui.field_text(a, &s.find), 30.0, 88.0, ui.ink())
    }
    try ui.keyboard(a, builder, &s.hits, faces, "Find")
    ret ok
}

// (D4801) The bookmarks of the open PDF: each a row indented by its depth with its page; a tap goes to the page.
fn draw_outline(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, "Outline", 62.0, 20.0, ui.light())
    var i = 0usize
    while i < s.ol_n {
        let y: f32 = 84.0 + f32(i) * 58.0
        let indent: f32 = f32(s.ol_level[i]) * 18.0
        try ui.card(a, builder, 16.0 + indent, y, 380.0 - indent, 52.0, 16.0, ui.cream())
        try ui.put(a, builder, faces.jost, 17.0, ui.text_of(a, s.ol_text[i * 40usize..], s.ol_len[i]), 32.0 + indent, y + 14.0, ui.ink())
        if s.ol_page[i] != pdf.NO_PAGE {
            try ui.put_right(a, builder, faces.grotesk, 13.0, ui.number(a, s.ol_page[i] + 1usize), 380.0, y + 18.0, ui.muted())
        }
        ui.hit(&s.hits, 900usize + i, 16.0, y, 380.0, 52.0)
        i += 1usize
    }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == LIST_SCREEN {
        try draw_list(a, builder, s, faces)
    } else if s.screen == DISK_SCREEN {
        try draw_disk(a, builder, s, faces)
    } else if s.screen == FIND_SCREEN {
        try draw_find(a, builder, s, faces)
    } else if s.screen == OUTLINE_SCREEN {
        try draw_outline(a, builder, s, faces)
    } else {
        try draw_view(a, builder, kit, s, faces)
    }
    try ui.handle(a, builder)
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

// Whether `name` is a file the app can show: a document format, Markdown or text, or a language the highlighter knows.
fn showable(name: str) -> bool {
    if ends_with(name, ".md") || ends_with(name, ".txt") || ends_with(name, ".docx") || ends_with(name, ".pptx") || ends_with(name, ".pdf") || ends_with(name, ".odt") || ends_with(name, ".odp") || ends_with(name, ".zip") || ends_with(name, ".xlsx") || ends_with(name, ".ods") || ends_with(name, ".html") || ends_with(name, ".htm") { ret true }
    let (index, found) = hl.language_for(name)
    ret found
}

// The showable files in the disk's root, into the State.
fn load_disk(s: *State) {
    s.disk_total = 0usize
    var names: [512]u8 = zero
    let (count, listed) = vaultfs.list("/", mem.address_of(&names[0usize]), 512usize)
    if !listed { ret }
    var start = 0usize
    var at = 0usize
    while at < count && s.disk_total < 8usize {
        if names[at] == 10u8 {
            let name = names[start..at]
            if showable(name) && name.len <= 24usize {
                var k = 0usize
                while k < name.len {
                    s.disk_names[s.disk_total * 24usize + k] = name[k]
                    k += 1usize
                }
                s.disk_len[s.disk_total] = name.len
                s.disk_total += 1usize
            }
            start = at + 1usize
        }
        at += 1usize
    }
}

// Look for the field's text (case-insensitively) in the handed text: the number of matches, and the page of the
// first one (set on `s.page`).
fn do_find(s: *State) -> usize {
    var matches = 0usize
    var found_line = 0usize
    var line = 0usize
    // (D4801) A PDF's text lines are "Page n" headings and the page's lines: the heading a match follows is its page.
    var headings = 0usize
    var found_heading = 0usize
    var i = 0usize
    while i < s.hand_len {
        if s.hand_text[i] == 10u8 { line += 1usize }
        if s.pdf_path_len > 0usize && (i == 0usize || s.hand_text[i - 1usize] == 10u8) && i + 5usize <= s.hand_len && s.hand_text[i] == 80u8 && s.hand_text[i + 1usize] == 97u8 && s.hand_text[i + 2usize] == 103u8 && s.hand_text[i + 3usize] == 101u8 && s.hand_text[i + 4usize] == 32u8 { headings += 1usize }
        var same = s.find.len > 0usize && i + s.find.len <= s.hand_len
        var k = 0usize
        while same && k < s.find.len {
            var c = s.hand_text[i + k]
            if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
            var q = s.find.bytes[k]
            if q >= 65u8 && q <= 90u8 { q = q + 32u8 }
            if c != q { same = false }
            k += 1usize
        }
        if same {
            if matches == 0usize {
                found_line = line
                found_heading = headings
            }
            matches += 1usize
        }
        i += 1usize
    }
    if matches > 0usize {
        if s.pdf_path_len > 0usize && !s.pdf_text {
            s.page = 0usize
            if found_heading > 0usize { s.page = found_heading - 1usize }
        } else {
            s.page = found_line / lines_per_page(s)
        }
    }
    ret matches
}

// A zip entry name that would leave the extraction folder: absolute, with a backslash or a `..` segment.
fn unsafe_entry(name: str) -> bool {
    if name.len == 0usize || name[0usize] == 47u8 { ret true }
    var segment = 0usize
    var i = 0usize
    while i <= name.len {
        if i == name.len || name[i] == 47u8 {
            if i - segment == 2usize && name[segment] == 46u8 && name[segment + 1usize] == 46u8 { ret true }
            segment = i + 1usize
        }
        if i < name.len && name[i] == 92u8 { ret true }
        i += 1usize
    }
    ret false
}

// (C150) Extract the open zip archive into a folder named after it, at the root: directories made, files written
// in pieces; an entry that is unsafe, or larger than 200 KB, is skipped. Says how many files and bytes were written
// (read back from the disk), and returns the files written.
fn extract_zip(a: *mem.Arena, s: *State, only: usize) -> usize {
    if s.zip_path_len == 0usize { ret 0usize }
    let path = ui.text_of(a, s.zip_path[0usize..], s.zip_path_len)
    let (size, kind, day, found) = vaultfs.stat(path)
    if !found || size == 0usize || size > 262144usize { ret 0usize }
    let (raw, raw_error) = mem.alloc[u8](a, size)
    if raw_error != ok { ret 0usize }
    let (got, read_ok) = vaultfs.read_big(path, mem.address_of(&raw[0usize]), size)
    if !read_ok || got != size { ret 0usize }
    let (archive, open_error) = ooxml.open_package(a, raw[0usize..got])
    if open_error != ok { ret 0usize }
    var ar = archive
    // The folder: the file's leaf name without ".zip".
    var leaf = 0usize
    var i = 0usize
    while i < path.len {
        if path[i] == 47u8 { leaf = i + 1usize }
        i += 1usize
    }
    var stem = path[leaf..path.len]
    if ends_with(stem, ".zip") { stem = stem[0usize..stem.len - 4usize] }
    let base = ui.join(a, "/", stem, "")
    let made_base = vaultfs.mkdir(base)
    let listed = zip.entries(&ar)
    var files = 0usize
    var bytes = 0usize
    var k = 0usize
    while k < listed.len {
        let name = listed[k].name
        // (D4807) One chosen entry (an index into the archive) or all of them (NONE).
        if (only == NONE || only == k) && !unsafe_entry(name) && listed[k].size <= 204800u64 {
            let dest_path = ui.join(a, base, "/", name)
            // Every directory above the entry (an archive need not list them).
            var j = base.len + 1usize
            while j < dest_path.len {
                if dest_path[j] == 47u8 { let made = vaultfs.mkdir(dest_path[0usize..j]) }
                j += 1usize
            }
            if !listed[k].directory {
                let (data, data_error) = zip.extract(a, &ar, k)
                if data_error == ok {
                    var stored = false
                    if data.len == 0usize {
                        stored = vaultfs.write(dest_path, 0usize, 0usize)
                    } else {
                        stored = vaultfs.write_big(dest_path, mem.address_of(&data[0usize]), data.len)
                    }
                    if stored {
                        let (written, written_kind, written_day, written_found) = vaultfs.stat(dest_path)
                        if written_found {
                            files += 1usize
                            bytes += written
                        }
                    }
                }
            }
        }
        k += 1usize
    }
    ui.say("document extracted ")
    ui.say_num(files)
    ui.say(" files ")
    ui.say_num(bytes)
    ui.say(" bytes into ")
    ui.say_text(base)
    ui.say("\n")
    ret files
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == DISK_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            ret true
        }
        if id >= 800usize && id < 808usize && id - 800usize < s.disk_total {
            let k = id - 800usize
            let path = ui.join(a, "/", ui.text_of(a, s.disk_names[k * 24usize..], s.disk_len[k]), "")
            if open_path(a, s, path) {
                s.page = 0usize
                ret true
            }
        }
        ret false
    }
    if s.screen == OUTLINE_SCREEN {
        if id == 500usize {
            s.screen = VIEW_SCREEN
            ret true
        }
        if id >= 900usize && id < 911usize && id - 900usize < s.ol_n {
            let k = id - 900usize
            if s.ol_page[k] != pdf.NO_PAGE && s.ol_page[k] < s.pdf_pages {
                s.page = s.ol_page[k]
                s.pdf_text = false
                s.pan_x = 0.0
                s.pan_y = 0.0
            }
            ui.say("document pdf outline jump ")
            ui.say_num(s.page + 1usize)
            ui.say("\n")
            s.screen = VIEW_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == FIND_SCREEN {
        if id == 500usize {
            s.screen = VIEW_SCREEN
            ret true
        }
        if ui.is_key(id) && id != 1205usize {
            if ui.field_key(&s.find, id, false) { ret true }
            ret false
        }
        if id == 1205usize {
            let count = do_find(s)
            // (D4801) On a painted PDF the match is shown on its page, highlighted: the page is the one whose
            // "Page n" heading the first match follows.
            s.hl_on = false
            if s.pdf_path_len > 0usize && !s.pdf_text && count > 0usize {
                s.hl_on = true
                s.pan_x = 0.0
                s.pan_y = 0.0
            }
            ui.say("document find ")
            ui.say_text(ui.field_text(a, &s.find))
            ui.say(" ")
            ui.say_num(count)
            ui.say(" page ")
            ui.say_num(s.page + 1usize)
            ui.say("\n")
            s.screen = VIEW_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == LIST_SCREEN && id == 700usize {
        load_disk(s)
        s.screen = DISK_SCREEN
        ui.say("document device ")
        ui.say_num(s.disk_total)
        ui.say("\n")
        ret true
    }
    if s.screen == VIEW_SCREEN && s.open == FILES {
        if id == 701usize {
            s.find.len = 0usize
            s.hl_on = false
            s.screen = FIND_SCREEN
            ret true
        }
        if id == 706usize && s.ol_n > 0usize {
            s.screen = OUTLINE_SCREEN
            ui.say("document pdf outline ")
            ui.say_num(s.ol_n)
            ui.say("\n")
            ret true
        }
        if id == 705usize && s.pdf_path_len > 0usize {
            s.pdf_text = !s.pdf_text
            s.page = 0usize
            ui.say("document pdf ")
            if s.pdf_text { ui.say("text\n") } else { ui.say("page\n") }
            ret true
        }
        if id >= 2000usize && id < 2200usize && s.zip_path_len > 0usize {
            let extracted_one = extract_zip(a, s, id - 2000usize)
            ret extracted_one > 0usize
        }
        if id == 704usize && s.zip_path_len > 0usize {
            let extracted = extract_zip(a, s, NONE)
            ret extracted > 0usize
        }
        if (id == 702usize || id == 703usize) && s.pdf_path_len > 0usize && !s.pdf_text {
            // (D4801) A painted page zooms in steps (fit, 1.5x, 2x, 3x) and is dragged to pan.
            if id == 702usize && s.pz > 0usize { s.pz -= 1usize }
            if id == 703usize && s.pz < 3usize { s.pz += 1usize }
            s.pan_x = 0.0
            s.pan_y = 0.0
            ui.say("document pdf zoom ")
            ui.say_num(s.pz)
            ui.say("\n")
            ret true
        }
        if id == 702usize || id == 703usize {
            if id == 702usize && s.zoom > 0usize { s.zoom -= 1usize }
            if id == 703usize && s.zoom < 2usize { s.zoom += 1usize }
            if s.page >= pages_of(s) { s.page = pages_of(s) - 1usize }
            ui.say("document zoom ")
            ui.say_num(s.zoom)
            ui.say("\n")
            ret true
        }
    }
    if s.screen == VIEW_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            ret true
        }
        if id == 600usize {
            if s.page > 0usize {
                s.page -= 1usize
            } else if s.big_path_len > 0usize && s.big_chunk > 0usize {
                // (C152) Back across a window of a big file.
                if load_chunk(a, s, s.big_chunk - 1usize) { s.page = pages_of(s) - 1usize }
            }
            ui.say("document page ")
            ui.say_num(s.big_base[s.big_chunk] + s.page + 1usize)
            ui.say("\n")
            ret true
        }
        if id == 601usize {
            if s.page + 1usize < pages_of(s) {
                s.page += 1usize
            } else if s.big_path_len > 0usize && s.big_more {
                // (C152) On into the next window of a big file: the pages before it are those of the window left.
                let following_base = s.big_base[s.big_chunk] + pages_of(s)
                let following = s.big_chunk + 1usize
                if load_chunk(a, s, following) {
                    s.big_base[following] = following_base
                    s.page = 0usize
                }
            }
            ui.say("document page ")
            ui.say_num(s.big_base[s.big_chunk] + s.page + 1usize)
            ui.say("\n")
            ret true
        }
        ret false
    }
    if id >= 100usize && id < 100usize + FILES {
        s.open = id - 100usize
        s.page = 0usize
        s.screen = VIEW_SCREEN
        ui.say("document opened ")
        ui.say(file_name(s.open))
        ui.say("\n")
        if file_kind(s.open) == CODE {
            ui.say("document lang ")
            ui.say(lang_name(s.open))
            ui.say("\n")
        }
        ret true
    }
    ret false
}

// (C123) Read the file at `hand_path` and make it the open document: Office and PDF text through the readers, a
// text or source file up to 16 KB, the kind and highlighter picked by its extension. True when it read.
fn open_path(a: *mem.Arena, s: *State, hand_path: str) -> bool {
    s.big_path_len = 0usize
    s.big_chunk = 0usize
    s.big_more = false
    s.hand_has_hl = false
    var text_len = 0usize
    var has_text = false
    s.pdf_tex_page = 0usize
    s.office_path_len = 0usize
    s.deck_slides = 0usize
    var cleared = 0usize
    while cleared < 512usize {
        s.line_style[cleared] = 0u8
        cleared += 1usize
    }
    if ends_with(hand_path, ".docx") || ends_with(hand_path, ".pptx") || ends_with(hand_path, ".pdf") || ends_with(hand_path, ".odt") || ends_with(hand_path, ".odp") || ends_with(hand_path, ".zip") || ends_with(hand_path, ".xlsx") || ends_with(hand_path, ".ods") || ends_with(hand_path, ".html") || ends_with(hand_path, ".htm") {
        // An Office file: read it whole (up to 256 KB, in pieces) and take its text.
        let (size, kind, day, found) = vaultfs.stat(hand_path)
        if found && size > 0usize && size <= 262144usize {
            let (raw, raw_error) = mem.alloc[u8](a, size)
            if raw_error == ok {
                let (got, read_ok) = vaultfs.read_big(hand_path, mem.address_of(&raw[0usize]), size)
                if read_ok && got == size {
                    if ends_with(hand_path, ".zip") {
                        text_len = zip_text(a, s, raw[0usize..got])
                    } else if ends_with(hand_path, ".xlsx") {
                        text_len = xlsx_text(a, s, raw[0usize..got])
                    } else if ends_with(hand_path, ".ods") {
                        let (ods_grid, ods_error) = odf.sheet_grid(a, raw[0usize..got], 1usize)
                        if ods_error == ok && ods_grid.rows > 0usize && ods_grid.columns > 0usize { text_len = add_grid(s, 0usize, ods_grid) }
                    } else if ends_with(hand_path, ".html") || ends_with(hand_path, ".htm") {
                        // (D4805) A page as its reading view: Markdown the viewer draws.
                        let (markdown, markdown_error) = html.to_markdown(a, ui.text_of(a, raw[0usize..], got))
                        if markdown_error == ok && markdown.len > 0usize {
                            var copied = 0usize
                            while copied < markdown.len && copied < 16000usize {
                                s.hand_text[copied] = markdown[copied]
                                copied += 1usize
                            }
                            text_len = copied
                            ui.say("document html markdown ")
                            ui.say_num(markdown.len)
                            ui.say(" bytes\n")
                        }
                    } else if ends_with(hand_path, ".pdf") {
                        text_len = pdf_text(a, s, raw[0usize..got])
                    } else {
                        text_len = office_text(a, s, ends_with(hand_path, ".pptx") || ends_with(hand_path, ".odp"), ends_with(hand_path, ".odt") || ends_with(hand_path, ".odp"), raw[0usize..got])
                    }
                    has_text = text_len > 0usize
                }
            }
        }
    } else {
        // A text or source file: up to 16 KB of it, in pieces; the rest is not shown.
        let (plain_size, plain_kind, plain_day, plain_found) = vaultfs.stat(hand_path)
        if plain_found && plain_size > 16000usize && hand_path.len <= 64usize {
            // (C152) Over 16 KB: read a window at a time from the disk, not the whole.
            var b = 0usize
            while b < hand_path.len {
                s.big_path[b] = hand_path[b]
                b += 1usize
            }
            s.big_path_len = hand_path.len
            s.big_size = plain_size
            s.big_starts[0usize] = 0usize
            s.big_base[0usize] = 0usize
            if load_chunk(a, s, 0usize) {
                text_len = s.hand_len
                has_text = true
            } else {
                s.big_path_len = 0usize
            }
        } else if plain_found {
            var want = plain_size
            if want > 16000usize { want = 16000usize }
            let (plain_len, plain_ok) = vaultfs.read_big(hand_path, mem.address_of(&s.hand_text[0usize]), want)
            text_len = plain_len
            has_text = plain_ok
        }
    }
    if has_text {
        s.hand_len = text_len
        // A zip can be extracted from its path (C150); any other file clears it.
        s.zip_path_len = 0usize
        if ends_with(hand_path, ".zip") && hand_path.len <= 64usize {
            var z = 0usize
            while z < hand_path.len {
                s.zip_path[z] = hand_path[z]
                z += 1usize
            }
            s.zip_path_len = hand_path.len
        }
        var leaf = 0usize
        var i = 0usize
        while i < hand_path.len {
            if hand_path[i] == 47u8 { leaf = i + 1usize }
            i += 1usize
        }
        var n = 0usize
        while leaf + n < hand_path.len && n < 24usize {
            s.hand_name[n] = hand_path[leaf + n]
            n += 1usize
        }
        s.hand_name_len = n
        s.open = FILES
        s.screen = VIEW_SCREEN
        let (shown_kind, shown_lang) = kind_by_name(ui.text_of(a, s.hand_name[0usize..], n))
        s.hand_kind = shown_kind
        s.hand_lang = shown_lang
        // (C152) A PDF is painted, one page at a time; its text lines stay behind a tap.
        s.pdf_path_len = 0usize
        s.pdf_text = false
        if hand_path.len > 4usize && ends_with(hand_path, ".pdf") {
            s.hand_kind = TXT
            if hand_path.len <= 64usize {
                var q = 0usize
                while q < hand_path.len {
                    s.pdf_path[q] = hand_path[q]
                    q += 1usize
                }
                s.pdf_path_len = hand_path.len
                s.hand_kind = PDFPAGE
            }
        }
        if ends_with(hand_path, ".xlsx") || ends_with(hand_path, ".ods") { s.hand_kind = SHEET }
        if ends_with(hand_path, ".html") || ends_with(hand_path, ".htm") { s.hand_kind = MD }
        if (ends_with(hand_path, ".docx") || ends_with(hand_path, ".pptx")) && hand_path.len <= 64usize {
            // (D4805) A Word file or a deck is drawn from its package: styled lines and pictures, or the shapes.
            var o = 0usize
            while o < hand_path.len {
                s.office_path[o] = hand_path[o]
                o += 1usize
            }
            s.office_path_len = hand_path.len
            if ends_with(hand_path, ".docx") { s.hand_kind = WORD }
            if ends_with(hand_path, ".pptx") && s.deck_slides > 0usize { s.hand_kind = SLIDES }
        }
        // The table-driven highlighter takes any extension it knows that is not a document format.
        let (named_index, named_found) = hl.language_for(ui.text_of(a, s.hand_name[0usize..], n))
        var hl_index = named_index
        var hl_found = named_found
        // (C152) A file with no known extension that starts `#!` is the language of its interpreter.
        if !hl_found && s.hand_kind == TXT && s.hand_len > 2usize {
            let guess = shebang_name(ui.text_of(a, s.hand_text[0usize..], s.hand_len))
            if guess.len > 0usize {
                let (guessed_index, guessed_found) = hl.language_for(guess)
                hl_index = guessed_index
                hl_found = guessed_found
                if guessed_found {
                    ui.say("document shebang ")
                    ui.say(hl.name(guessed_index))
                    ui.say("\n")
                }
            }
        }
        if hl_found && s.hand_kind != MD && !ends_with(hand_path, ".pdf") && !ends_with(hand_path, ".docx") && !ends_with(hand_path, ".pptx") && !ends_with(hand_path, ".odt") && !ends_with(hand_path, ".odp") && !ends_with(hand_path, ".zip") && !ends_with(hand_path, ".xlsx") {
            s.hand_kind = CODE
            s.hand_hl = hl_index
            s.hand_has_hl = true
            let classified = hl.classify(hl_index, ui.text_of(a, s.hand_text[0usize..], s.hand_len), s.hand_classes[0usize..])
        }
        if s.hand_kind == MD {
            ui.say("document kind markdown\n")
            // The table rows (a delimiter row excluded), so a fixture can tell a table was seen (C172).
            var table_rows = 0usize
            var line_number = 0usize
            let whole = ui.text_of(a, s.hand_text[0usize..], s.hand_len)
            let line_count = line_total(whole)
            while line_number < line_count {
                let line_text = splitter(a, whole, line_number)
                if is_bar_row(line_text) && !is_rule_row(line_text) { table_rows += 1usize }
                line_number += 1usize
            }
            if table_rows > 0usize {
                ui.say("document md table rows ")
                ui.say_num(table_rows)
                ui.say("\n")
            }
        }
        if s.hand_kind == SHEET {
            ui.say("document sheet ")
            ui.say_num(hand_lines(s) - 1usize)
            ui.say(" rows\n")
        }
        if s.hand_kind == CODE {
            ui.say("document kind code ")
            ui.say(shown_language(s))
            ui.say("\n")
        }
        ui.say("document handed ")
        ui.say_text(ui.text_of(a, s.hand_name[0usize..], n))
        ui.say("\n")
        // The first line of what was read, so a fixture can check the text.
        var first = 0usize
        while first < s.hand_len && s.hand_text[first] != 10u8 { first += 1usize }
        if s.big_path_len > 0usize {
            ui.say("document big file ")
            ui.say_num(s.big_size)
            ui.say(" bytes, window 1 ")
            ui.say_num(s.hand_len)
            ui.say("\n")
        }
        ui.say("document first line ")
        ui.say_text(ui.text_of(a, s.hand_text[0usize..], first))
        ui.say("\n")
    }
    ret has_text
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "document")
    if kit_error != ok {
        ui.say("document open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("document fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.open = NONE
    // A file handed over by Files: its path is in /handover; read it and open it.
    var path_bytes: [64]u8 = zero
    let (path_len, has_path) = vaultfs.read("/handover", mem.address_of(&path_bytes[0usize]), 63usize)
    if has_path && path_len > 0usize {
        let opened = open_path(a, &s, ui.text_of(a, path_bytes[0usize..], path_len))
        let cleared = vaultfs.remove("/handover")
    }
    if !show(a, &kit, &s) {
        ui.say("document present failed\n")
        ret ok
    }
    ui.say("document shown\n")
    var running = true
    while running {
        let tap = appkit.next_touch(&kit, 0usize)
        let painted_view = s.screen == VIEW_SCREEN && s.open == FILES && s.hand_kind == PDFPAGE && !s.pdf_text
        if tap.kind == appkit.TOUCH_END {
            running = false
        } else if tap.kind == appkit.TOUCH_TICK || tap.kind == appkit.TOUCH_MOVE || tap.kind == appkit.TOUCH_TIMEOUT {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.kind == appkit.TOUCH_UP {
            // (D4801) A drag that began on a zoomed painted page pans it by how far the finger went.
            var panned = false
            if s.drag_on {
                s.drag_on = false
                let dx = tap.x - s.drag_x
                let dy = tap.y - s.drag_y
                if dx > 6.0 || dx < -6.0 || dy > 6.0 || dy < -6.0 {
                    s.pan_x = s.pan_x + dx
                    s.pan_y = s.pan_y + dy
                    ui.say("document pdf pan\n")
                    panned = true
                }
            }
            if panned {
                if !show(a, &kit, &s) {
                    ui.say("document present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("document home\n")
            appkit.leave()
            running = false
        } else if painted_view && s.pz > 0usize && tap.x >= 24.0 && tap.x < 388.0 && tap.y >= 84.0 && tap.y < 764.0 {
            s.drag_on = true
            s.drag_x = tap.x
            s.drag_y = tap.y
            appkit.answer(appkit.ANSWER_NONE)
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("document present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
