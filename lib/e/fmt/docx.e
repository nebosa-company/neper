// Word document generation (L146): a `.docx` from a list of blocks -- paragraphs with a
// style (Title, Heading1-3, list items, Normal), alignment and styled runs (bold, italic,
// underline, size, colour, tabs and line breaks), tables with a header row, inline PNG
// and JPEG images, page breaks -- written as a WordprocessingML package over
// `e.fmt.zip.write`. The package carries a styles part, a numbering part (a shared bullet
// list and restartable numbered lists) and core properties, so Word, LibreOffice and
// python-docx open it as a document with the named styles, not as loose XML.
//
// Reading back: `e.fmt.ooxml.paragraphs` returns the paragraphs of what is written here,
// with their style names and list flags; a table cell's paragraphs come in document order.
//
// Not here: tracked changes, comments, fields and a table of contents, headers and
// footers, footnotes, section changes, text boxes, hyperlinks, run fonts, merged table
// cells, and compression of the package (parts are stored). Images are placed inline at
// the size given or 96 dpi from their pixel size.
//
// Memory: the package and every part live in the arena passed in.
use e.mem
use e.str
use e.fmt.zip.write as zipw

error BadText
error BadColor
error BadTable
error BadImage
error BadMeta
error TooLarge

type Style = enum u8 { Normal, Title, Heading1, Heading2, Heading3 }
type Align = enum u8 { Left, Center, Right, Justify }
type ListKind = enum u8 { None, Bullet, Number }
type Page = enum u8 { A4, Letter }
type Kind = enum u8 { Paragraph, Table, Image, PageBreak }
type Run = struct { text: str, bold: bool, italic: bool, underline: bool, half_points: u32, color: str }
type Para = struct { style: Style, align: Align, list: ListKind, list_id: u32, level: u32, runs: []const Run }
type Cell = struct { paras: []const Para }
type Row = struct { cells: []const Cell }
type Table = struct { widths: []const u32, rows: []const Row, header: bool }
type Image = struct { data: []const u8, width_emu: u32, height_emu: u32, alt: str }
type Block = struct { kind: Kind, para: Para, table: Table, image: Image }
type Meta = struct { title: str, creator: str, created: str, page: Page }

const MAX_LISTS: u32 = 64u32
const MAX_LEVEL: u32 = 8u32
const MAX_HALF_POINTS: u32 = 1638u32
const EMU_PER_PIXEL: u32 = 9525u32

fn run(s: str) -> Run {
    ret Run { text: s, bold: false, italic: false, underline: false, half_points: 0u32, color: "" }
}

fn bold_run(s: str) -> Run {
    ret Run { text: s, bold: true, italic: false, underline: false, half_points: 0u32, color: "" }
}

fn para(style: Style, runs: []const Run) -> Para {
    ret Para { style: style, align: .Left, list: .None, list_id: 0u32, level: 0u32, runs: runs }
}

fn paragraph(p: Para) -> Block {
    ret Block { kind: .Paragraph, para: p, table: zero, image: zero }
}

fn table(t: Table) -> Block {
    ret Block { kind: .Table, para: zero, table: t, image: zero }
}

fn image(i: Image) -> Block {
    ret Block { kind: .Image, para: zero, table: zero, image: i }
}

fn page_break() -> Block {
    ret Block { kind: .PageBreak, para: zero, table: zero, image: zero }
}

fn default_meta() -> Meta {
    ret Meta { title: "", creator: "", created: "", page: .A4 }
}

// ---- helpers -----------------------------------------------------------------------------

fn clean(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c < 32u8 && c != 9u8 && c != 10u8 { ret false }
        i += 1usize
    }
    ret true
}

fn hex_color(s: str) -> bool {
    if s.len == 0usize { ret true }
    if s.len != 6usize { ret false }
    var i = 0usize
    while i < 6usize {
        let c = s[i]
        let digit = (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 70u8) || (c >= 97u8 && c <= 102u8)
        if !digit { ret false }
        i += 1usize
    }
    ret true
}

fn push_escaped(b: *str.Builder, s: str, attribute: bool) -> err {
    var i = 0usize
    var from = 0usize
    while i < s.len {
        let c = s[i]
        var rep = ""
        if c == 38u8 {
            rep = "&amp;"
        } else if c == 60u8 {
            rep = "&lt;"
        } else if c == 62u8 {
            rep = "&gt;"
        } else if attribute && c == 34u8 {
            rep = "&quot;"
        }
        if rep.len > 0usize {
            try str.push(b, s[from..i])
            try str.push(b, rep)
            from = i + 1usize
        }
        i += 1usize
    }
    ret str.push(b, s[from..s.len])
}

fn style_id(style: Style) -> str {
    if style == .Title { ret "Title" }
    if style == .Heading1 { ret "Heading1" }
    if style == .Heading2 { ret "Heading2" }
    if style == .Heading3 { ret "Heading3" }
    ret ""
}

// The pixel size of a PNG or JPEG, and whether `data` is one: (width, height, jpeg, ok).
fn image_info(data: []const u8) -> (u32, u32, bool, bool) {
    if data.len >= 24usize && data[0usize] == 137u8 && data[1usize] == 80u8 && data[2usize] == 78u8 && data[3usize] == 71u8 {
        let w = (u32(data[16usize]) << 24u32) | (u32(data[17usize]) << 16u32) | (u32(data[18usize]) << 8u32) | u32(data[19usize])
        let h = (u32(data[20usize]) << 24u32) | (u32(data[21usize]) << 16u32) | (u32(data[22usize]) << 8u32) | u32(data[23usize])
        ret (w, h, false, w > 0u32 && h > 0u32)
    }
    if data.len >= 4usize && data[0usize] == 255u8 && data[1usize] == 216u8 {
        var at = 2usize
        while at + 4usize <= data.len {
            if data[at] != 255u8 { ret (0u32, 0u32, true, false) }
            let marker = data[at + 1usize]
            if marker == 255u8 {
                at += 1usize
                continue
            }
            let length = (usize(data[at + 2usize]) << 8usize) | usize(data[at + 3usize])
            let sof = marker >= 192u8 && marker <= 207u8 && marker != 196u8 && marker != 200u8 && marker != 204u8
            if sof {
                if at + 9usize > data.len { ret (0u32, 0u32, true, false) }
                let h = (u32(data[at + 5usize]) << 8u32) | u32(data[at + 6usize])
                let w = (u32(data[at + 7usize]) << 8u32) | u32(data[at + 8usize])
                ret (w, h, true, w > 0u32 && h > 0u32)
            }
            at += 2usize + length
        }
    }
    ret (0u32, 0u32, false, false)
}

// ---- parts -------------------------------------------------------------------------------

fn push_run(b: *str.Builder, r: Run) -> err {
    try str.push(b, "<w:r>")
    if r.bold || r.italic || r.underline || r.half_points > 0u32 || r.color.len > 0usize {
        try str.push(b, "<w:rPr>")
        if r.bold { try str.push(b, "<w:b/>") }
        if r.italic { try str.push(b, "<w:i/>") }
        if r.color.len > 0usize {
            try str.push(b, "<w:color w:val=\"")
            try str.push(b, r.color)
            try str.push(b, "\"/>")
        }
        if r.half_points > 0u32 {
            try str.push(b, "<w:sz w:val=\"")
            try str.push_u32(b, r.half_points)
            try str.push(b, "\"/>")
        }
        if r.underline { try str.push(b, "<w:u w:val=\"single\"/>") }
        try str.push(b, "</w:rPr>")
    }
    // Text, with a tab and a line break as the elements Word reads them as.
    var i = 0usize
    var from = 0usize
    var open = false
    while i <= r.text.len {
        var special = false
        if i == r.text.len {
            special = true
        } else if r.text[i] == 9u8 || r.text[i] == 10u8 {
            special = true
        }
        if special {
            if i > from {
                try str.push(b, "<w:t xml:space=\"preserve\">")
                try push_escaped(b, r.text[from..i], false)
                try str.push(b, "</w:t>")
            }
            if i < r.text.len {
                if r.text[i] == 9u8 { try str.push(b, "<w:tab/>") } else { try str.push(b, "<w:br/>") }
            }
            from = i + 1usize
        }
        i += 1usize
    }
    ret str.push(b, "</w:r>")
}

fn push_para(b: *str.Builder, p: Para) -> err {
    try str.push(b, "<w:p>")
    let styled = p.style != .Normal
    let listed = p.list != .None
    if styled || listed || p.align != .Left {
        try str.push(b, "<w:pPr>")
        if styled {
            try str.push(b, "<w:pStyle w:val=\"")
            try str.push(b, style_id(p.style))
            try str.push(b, "\"/>")
        } else if listed {
            try str.push(b, "<w:pStyle w:val=\"ListParagraph\"/>")
        }
        if listed {
            try str.push(b, "<w:numPr><w:ilvl w:val=\"")
            try str.push_u32(b, p.level)
            try str.push(b, "\"/><w:numId w:val=\"")
            if p.list == .Bullet {
                try str.push(b, "1")
            } else {
                try str.push_u32(b, p.list_id + 1u32)
            }
            try str.push(b, "\"/></w:numPr>")
        }
        if p.align != .Left {
            try str.push(b, "<w:jc w:val=\"")
            if p.align == .Center {
                try str.push(b, "center")
            } else if p.align == .Right {
                try str.push(b, "right")
            } else {
                try str.push(b, "both")
            }
            try str.push(b, "\"/>")
        }
        try str.push(b, "</w:pPr>")
    }
    var i = 0usize
    while i < p.runs.len {
        try push_run(b, p.runs[i])
        i += 1usize
    }
    ret str.push(b, "</w:p>")
}

fn push_image(b: *str.Builder, im: Image, number: usize, ext: str, cx: u32, cy: u32) -> err {
    try str.push(b, "<w:p><w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"")
    try str.push_u32(b, cx)
    try str.push(b, "\" cy=\"")
    try str.push_u32(b, cy)
    try str.push(b, "\"/><wp:docPr id=\"")
    try str.push_usize(b, number)
    try str.push(b, "\" name=\"Picture ")
    try str.push_usize(b, number)
    try str.push(b, "\" descr=\"")
    try push_escaped(b, im.alt, true)
    try str.push(b, "\"/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>")
    try str.push(b, "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">")
    try str.push(b, "<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"image")
    try str.push_usize(b, number)
    try str.push(b, ".")
    try str.push(b, ext)
    try str.push(b, "\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"rId")
    try str.push_usize(b, number + 2usize)
    try str.push(b, "\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"")
    try str.push_u32(b, cx)
    try str.push(b, "\" cy=\"")
    try str.push_u32(b, cy)
    ret str.push(b, "\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>")
}

fn push_table(b: *str.Builder, t: Table) -> err {
    try str.push(b, "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr><w:tblGrid>")
    var c = 0usize
    while c < t.widths.len {
        try str.push(b, "<w:gridCol w:w=\"")
        try str.push_u32(b, t.widths[c])
        try str.push(b, "\"/>")
        c += 1usize
    }
    try str.push(b, "</w:tblGrid>")
    var r = 0usize
    while r < t.rows.len {
        try str.push(b, "<w:tr>")
        if t.header && r == 0usize { try str.push(b, "<w:trPr><w:tblHeader/></w:trPr>") }
        c = 0usize
        while c < t.widths.len {
            try str.push(b, "<w:tc><w:tcPr><w:tcW w:w=\"")
            try str.push_u32(b, t.widths[c])
            try str.push(b, "\" w:type=\"dxa\"/></w:tcPr>")
            var wrote = false
            if c < t.rows[r].cells.len {
                let paras = t.rows[r].cells[c].paras
                var p = 0usize
                while p < paras.len {
                    try push_para(b, paras[p])
                    wrote = true
                    p += 1usize
                }
            }
            if !wrote { try str.push(b, "<w:p/>") }
            try str.push(b, "</w:tc>")
            c += 1usize
        }
        try str.push(b, "</w:tr>")
        r += 1usize
    }
    ret str.push(b, "</w:tbl><w:p/>")
}

fn check_para(p: Para) -> err {
    if p.list_id > MAX_LISTS || p.level > MAX_LEVEL { ret TooLarge }
    if p.list == .Number && p.list_id == 0u32 { ret TooLarge }
    var i = 0usize
    while i < p.runs.len {
        let r = p.runs[i]
        if !clean(r.text) { ret BadText }
        if !hex_color(r.color) { ret BadColor }
        if r.half_points > MAX_HALF_POINTS { ret TooLarge }
        i += 1usize
    }
    ret ok
}

fn styles_xml() -> str {
    ret r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="120"/></w:pPr><w:rPr><w:sz w:val="56"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="60"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="160" w:after="40"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style><w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style><w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tblBorders></w:tblPr></w:style></w:styles>"#
}

fn numbering_xml(a: *mem.Arena, numbered: u32) -> (str, err) {
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">")
    // abstractNum 0 is the bullet list, 1 the decimal list; nine levels each, 720 twips apart.
    var kind = 0u32
    while kind < 2u32 {
        try str.push(&b, "<w:abstractNum w:abstractNumId=\"")
        try str.push_u32(&b, kind)
        try str.push(&b, "\"><w:multiLevelType w:val=\"hybridMultilevel\"/>")
        var level = 0u32
        while level <= MAX_LEVEL {
            try str.push(&b, "<w:lvl w:ilvl=\"")
            try str.push_u32(&b, level)
            try str.push(&b, "\"><w:start w:val=\"1\"/>")
            if kind == 0u32 {
                try str.push(&b, "<w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\xe2\x80\xa2\"/>")
            } else {
                try str.push(&b, "<w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%")
                try str.push_u32(&b, level + 1u32)
                try str.push(&b, ".\"/>")
            }
            try str.push(&b, "<w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"")
            try str.push_u32(&b, 720u32 * (level + 1u32))
            try str.push(&b, "\" w:hanging=\"360\"/></w:pPr></w:lvl>")
            level += 1u32
        }
        try str.push(&b, "</w:abstractNum>")
        kind += 1u32
    }
    // num 1 is the bullet list; num k + 1 is numbered list k, restarting at 1.
    try str.push(&b, "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num>")
    var k = 1u32
    while k <= numbered {
        try str.push(&b, "<w:num w:numId=\"")
        try str.push_u32(&b, k + 1u32)
        try str.push(&b, "\"><w:abstractNumId w:val=\"1\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"1\"/></w:lvlOverride></w:num>")
        k += 1u32
    }
    try str.push(&b, "</w:numbering>")
    ret (str.done(&b), ok)
}

fn core_xml(a: *mem.Arena, meta: Meta) -> (str, err) {
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">")
    if meta.title.len > 0usize {
        try str.push(&b, "<dc:title>")
        try push_escaped(&b, meta.title, false)
        try str.push(&b, "</dc:title>")
    }
    if meta.creator.len > 0usize {
        try str.push(&b, "<dc:creator>")
        try push_escaped(&b, meta.creator, false)
        try str.push(&b, "</dc:creator>")
    }
    if meta.created.len > 0usize {
        try str.push(&b, "<dcterms:created xsi:type=\"dcterms:W3CDTF\">")
        try push_escaped(&b, meta.created, false)
        try str.push(&b, "</dcterms:created>")
    }
    try str.push(&b, "</cp:coreProperties>")
    ret (str.done(&b), ok)
}

fn media_name(a: *mem.Arena, number: usize, ext: str) -> (str, err) {
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "word/media/image")
    try str.push_usize(&b, number)
    try str.push(&b, ".")
    try str.push(&b, ext)
    ret (str.done(&b), ok)
}

// The document: `blocks` in order, with `meta`'s page size and core properties.
fn encode(a: *mem.Arena, blocks: []const Block, meta: Meta) -> ([]u8, err) {
    if meta.title.len > 1024usize || meta.creator.len > 1024usize || meta.created.len > 64usize { ret (zero, BadMeta) }
    if !clean(meta.title) || !clean(meta.creator) || !clean(meta.created) { ret (zero, BadMeta) }
    var images = 0usize
    var numbered = 0u32
    var uses_png = false
    var uses_jpeg = false
    var i = 0usize
    while i < blocks.len {
        let block = blocks[i]
        if block.kind == .Paragraph {
            try check_para(block.para)
            if block.para.list == .Number && block.para.list_id > numbered { numbered = block.para.list_id }
        } else if block.kind == .Table {
            let t = block.table
            if t.widths.len == 0usize || t.rows.len == 0usize { ret (zero, BadTable) }
            var c = 0usize
            while c < t.widths.len {
                if t.widths[c] == 0u32 { ret (zero, BadTable) }
                c += 1usize
            }
            var r = 0usize
            while r < t.rows.len {
                if t.rows[r].cells.len > t.widths.len { ret (zero, BadTable) }
                c = 0usize
                while c < t.rows[r].cells.len {
                    var p = 0usize
                    while p < t.rows[r].cells[c].paras.len {
                        try check_para(t.rows[r].cells[c].paras[p])
                        let cp = t.rows[r].cells[c].paras[p]
                        if cp.list == .Number && cp.list_id > numbered { numbered = cp.list_id }
                        p += 1usize
                    }
                    c += 1usize
                }
                r += 1usize
            }
        } else if block.kind == .Image {
            let (iw, ih, jpeg, good) = image_info(block.image.data)
            if !good || !clean(block.image.alt) { ret (zero, BadImage) }
            if jpeg { uses_jpeg = true } else { uses_png = true }
            images += 1usize
        }
        i += 1usize
    }
    let (parts, parts_error) = mem.alloc[zipw.Part](a, 7usize + images)
    if parts_error != ok { ret (zero, parts_error) }
    // word/document.xml
    var (b, builder_error) = str.builder(a, 0usize)
    if builder_error != ok { ret (zero, builder_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\"><w:body>")
    var shown = 0usize
    i = 0usize
    while i < blocks.len {
        let block = blocks[i]
        if block.kind == .Paragraph {
            try push_para(&b, block.para)
        } else if block.kind == .Table {
            try push_table(&b, block.table)
        } else if block.kind == .PageBreak {
            try str.push(&b, "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
        } else {
            let im = block.image
            let (iw, ih, jpeg, good) = image_info(im.data)
            var cx = im.width_emu
            var cy = im.height_emu
            if cx == 0u32 { cx = iw * EMU_PER_PIXEL }
            if cy == 0u32 { cy = ih * EMU_PER_PIXEL }
            shown += 1usize
            var ext = "png"
            if jpeg { ext = "jpeg" }
            try push_image(&b, im, shown, ext, cx, cy)
        }
        i += 1usize
    }
    try str.push(&b, "<w:sectPr>")
    if meta.page == .Letter {
        try str.push(&b, "<w:pgSz w:w=\"12240\" w:h=\"15840\"/>")
    } else {
        try str.push(&b, "<w:pgSz w:w=\"11906\" w:h=\"16838\"/>")
    }
    try str.push(&b, "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>")
    let document_text = str.done(&b)
    // Content types.
    var (ct, ct_error) = str.builder(a, 0usize)
    if ct_error != ok { ret (zero, ct_error) }
    try str.push(&ct, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>")
    if uses_png { try str.push(&ct, "<Default Extension=\"png\" ContentType=\"image/png\"/>") }
    if uses_jpeg { try str.push(&ct, "<Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>") }
    try str.push(&ct, "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/></Types>")
    let types_text = str.done(&ct)
    // Document relationships: styles, numbering, then the images in order.
    var (rb, rb_error) = str.builder(a, 0usize)
    if rb_error != ok { ret (zero, rb_error) }
    try str.push(&rb, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>")
    var n = 0usize
    i = 0usize
    while i < blocks.len {
        if blocks[i].kind == .Image {
            n += 1usize
            let (iw, ih, jpeg, good) = image_info(blocks[i].image.data)
            try str.push(&rb, "<Relationship Id=\"rId")
            try str.push_usize(&rb, n + 2usize)
            try str.push(&rb, "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image")
            try str.push_usize(&rb, n)
            if jpeg { try str.push(&rb, ".jpeg\"/>") } else { try str.push(&rb, ".png\"/>") }
        }
        i += 1usize
    }
    try str.push(&rb, "</Relationships>")
    let doc_rels_text = str.done(&rb)
    let (numbering_text, numbering_error) = numbering_xml(a, numbered)
    if numbering_error != ok { ret (zero, numbering_error) }
    let (core_text, core_error) = core_xml(a, meta)
    if core_error != ok { ret (zero, core_error) }
    parts[0usize] = zipw.Part { name: "[Content_Types].xml", data: types_text }
    parts[1usize] = zipw.Part { name: "_rels/.rels", data: root_rels() }
    parts[2usize] = zipw.Part { name: "docProps/core.xml", data: core_text }
    parts[3usize] = zipw.Part { name: "word/document.xml", data: document_text }
    parts[4usize] = zipw.Part { name: "word/_rels/document.xml.rels", data: doc_rels_text }
    parts[5usize] = zipw.Part { name: "word/styles.xml", data: styles_xml() }
    parts[6usize] = zipw.Part { name: "word/numbering.xml", data: numbering_text }
    n = 0usize
    i = 0usize
    while i < blocks.len {
        if blocks[i].kind == .Image {
            n += 1usize
            let (iw, ih, jpeg, good) = image_info(blocks[i].image.data)
            var ext = "png"
            if jpeg { ext = "jpeg" }
            let (name, name_error) = media_name(a, n, ext)
            if name_error != ok { ret (zero, name_error) }
            parts[6usize + n] = zipw.Part { name: name, data: blocks[i].image.data }
        }
        i += 1usize
    }
    let (package, package_error) = zipw.store(a, parts[0usize..7usize + images])
    ret (package, package_error)
}

fn root_rels() -> str {
    ret r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>"#
}
