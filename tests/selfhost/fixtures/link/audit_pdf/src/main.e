// `e.fmt.pdf` reader audit: a stream's indirect /Length is authoritative (an embedded
// `endstream` byte sequence is data), object-like bytes inside a stream are not indirect
// objects, and a page inherits MediaBox/Resources from its own /Parent chain.
use e.fmt.pdf as pdf
use e.io
use e.mem
use e.os
use e.str

fn contains(text: str, needle: str) -> bool {
    if needle.len == 0usize { ret true }
    if text.len < needle.len { ret false }
    var at = 0usize
    while at + needle.len <= text.len {
        var k = 0usize
        var same = true
        while k < needle.len {
            if text[at + k] != needle[k] { same = false }
            if !same { break }
            k += 1usize
        }
        if same { ret true }
        at += 1usize
    }
    ret false
}

// A one-page PDF whose content stream is object 4 and whose `/Length` is the indirect
// object 6, with the page inheriting the font resources from the Pages node.
fn indirect_pdf(a: *mem.Arena, content: str) -> (str, err) {
    let (b0, be) = str.builder(a, 4096usize)
    if be != ok { ret ("", be) }
    var b = b0
    try str.push(&b, "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n4 0 obj\n<< /Length 6 0 R >>\nstream\n")
    try str.push(&b, content)
    try str.push(&b, "\nendstream\nendobj\n6 0 obj\n")
    try str.push_u64(&b, u64(content.len))
    try str.push(&b, "\nendobj\n5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n%%EOF\n")
    ret (str.done(&b), ok)
}

// Two page-tree branches: page 0 (object 4) inherits MediaBox from object 3, page 1
// (object 5) declares its own; both inherit the root Resources for the font.
fn branch_pdf(a: *mem.Arena) -> (str, err) {
    let left = "BT /F1 12 Tf 72 720 Td (left) Tj ET"
    let right = "BT /F1 12 Tf 72 720 Td (right) Tj ET"
    let (b0, be) = str.builder(a, 4096usize)
    if be != ok { ret ("", be) }
    var b = b0
    try str.push(&b, "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 /Resources << /Font << /F1 8 0 R >> >> >>\nendobj\n3 0 obj\n<< /Type /Pages /Parent 2 0 R /Kids [4 0 R] /Count 1 /MediaBox [0 0 200 400] >>\nendobj\n4 0 obj\n<< /Type /Page /Parent 3 0 R /Contents 6 0 R >>\nendobj\n5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 7 0 R /MediaBox [0 0 640 480] >>\nendobj\n")
    try str.push(&b, "6 0 obj\n<< /Length ")
    try str.push_u64(&b, u64(left.len))
    try str.push(&b, " >>\nstream\n")
    try str.push(&b, left)
    try str.push(&b, "\nendstream\nendobj\n7 0 obj\n<< /Length ")
    try str.push_u64(&b, u64(right.len))
    try str.push(&b, " >>\nstream\n")
    try str.push(&b, right)
    try str.push(&b, "\nendstream\nendobj\n8 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n%%EOF\n")
    ret (str.done(&b), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 585: the payload also holds a fake `1 0 obj ... endobj`; it must not become object 1.
    let (doc585, d585) = indirect_pdf(a, "BT /F1 12 Tf 72 720 Td (x) Tj ET\n% endstream\nendobj\n3 0 obj\n<< /Type /Page >>\nendobj\n")
    if d585 != ok { os.exit(90i32) }
    let (texts585, e585) = pdf.pages(a, doc585)
    if e585 != ok || texts585.len != 1usize || !contains(texts585[0usize], "x") { os.exit(85i32) }
    // 584: the payload contains the `endstream` keyword; the indirect /Length must win.
    let (doc584, d584) = indirect_pdf(a, "BT /F1 12 Tf 72 720 Td (endstream) Tj ET")
    if d584 != ok { os.exit(90i32) }
    let (texts584, e584) = pdf.pages(a, doc584)
    if e584 != ok || texts584.len != 1usize || !contains(texts584[0usize], "endstream") { os.exit(84i32) }
    // 587: page 0 inherits 200x400 from its branch, page 1 keeps its own 640x480.
    let (tree_doc, tree_build_error) = branch_pdf(a)
    if tree_build_error != ok { os.exit(90i32) }
    let (left, left_error) = pdf.page_painting(a, tree_doc, 0usize)
    let (right, right_error) = pdf.page_painting(a, tree_doc, 1usize)
    if left_error != ok || right_error != ok || left.width != 200.0f64 || right.width != 640.0f64 { os.exit(87i32) }
    let (texts, texts_error) = pdf.pages(a, tree_doc)
    if texts_error != ok || texts.len != 2usize || !contains(texts[0usize], "left") || !contains(texts[1usize], "right") { os.exit(87i32) }
    try io.print("audit pdf ok\n")
    ret ok
}
