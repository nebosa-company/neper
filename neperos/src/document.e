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
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use ui

const NONE: usize = 99usize
const FILES: usize = 13usize
const LIST_SCREEN: usize = 0usize
const VIEW_SCREEN: usize = 1usize
const MD: usize = 0usize
const TXT: usize = 1usize
const CODE: usize = 2usize
const PDF: usize = 3usize
const DOCX: usize = 4usize
const PPTX: usize = 5usize

type State = struct {
    screen: usize,
    open: usize,
    page: usize,
    hits: ui.Hits,
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

fn draw_md(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 12.0, 84.0, 388.0, 730.0, 18.0, ui.cream())
    let content = body(s.open)
    var y: f32 = 100.0
    var in_code = false
    var n = 0usize
    let total = line_total(content)
    while n < total {
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
    let content = body(s.open)
    var n = 0usize
    let total = line_total(content)
    while n < total {
        try ui.put(a, builder, faces.grotesk, 15.0, splitter(a, content, n), 28.0, 100.0 + f32(n) * 26.0, ui.ink())
        n += 1usize
    }
    ret ok
}

fn draw_code(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 12.0, 84.0, 388.0, 730.0, 18.0, paint.Color { red: 0.12, green: 0.13, blue: 0.16, alpha: 1.0 })
    let content = body(s.open)
    let total = line_total(content)
    var n = 0usize
    while n < total {
        let y: f32 = 100.0 + f32(n) * 22.0
        try ui.put_right(a, builder, faces.grotesk, 12.0, ui.number(a, n + 1usize), 44.0, y + 1.0, ui.light_muted())
        try draw_code_line(a, builder, faces, s.open, splitter(a, content, n), 56.0, y)
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

fn draw_view(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let kind = file_kind(s.open)
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 22.0, file_name(s.open), 62.0, 20.0, ui.light())
    if kind == CODE { try ui.pill(a, builder, &s.hits, faces, 501usize, 300.0, 18.0, 96.0, 32.0, lang_name(s.open), ui.amber(), 14.0) }
    if kind == MD { try draw_md(a, builder, s, faces) }
    if kind == TXT { try draw_txt(a, builder, s, faces) }
    if kind == CODE { try draw_code(a, builder, s, faces) }
    if kind == PDF || kind == DOCX { try draw_page(a, builder, s, faces) }
    if kind == PPTX { try draw_slide(a, builder, s, faces) }
    if page_count(s.open) > 1usize {
        try ui.card(a, builder, 0.0, 828.0, 412.0, 68.0, 0.0, paint.Color { red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0 })
        try ui.pill(a, builder, &s.hits, faces, 600usize, 40.0, 838.0, 110.0, 46.0, "Previous", ui.soft(), 15.0)
        try ui.centred(a, builder, faces.jost, 17.0, ui.join(a, ui.number(a, s.page + 1usize), " / ", ui.number(a, page_count(s.open))), 206.0, 850.0, ui.light())
        try ui.pill(a, builder, &s.hits, faces, 601usize, 262.0, 838.0, 110.0, 46.0, "Next", ui.amber(), 15.0)
    }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == LIST_SCREEN { try draw_list(a, builder, s, faces) } else { try draw_view(a, builder, s, faces) }
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

fn act(s: *State, id: usize) -> bool {
    if s.screen == VIEW_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            ret true
        }
        if id == 600usize {
            if s.page > 0usize { s.page -= 1usize }
            ui.say("document page ")
            ui.say_num(s.page + 1usize)
            ui.say("\n")
            ret true
        }
        if id == 601usize {
            if s.page + 1usize < page_count(s.open) { s.page += 1usize }
            ui.say("document page ")
            ui.say_num(s.page + 1usize)
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
    if !show(a, &kit, &s) {
        ui.say("document present failed\n")
        ret ok
    }
    ui.say("document shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            ui.say("document home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(&s, id) {
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
