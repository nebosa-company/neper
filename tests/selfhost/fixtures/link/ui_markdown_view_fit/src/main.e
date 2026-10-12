// `e.ui.markdown_view` build_with (L066, D3603): a host text measurement and content-sized table columns against
// the layout scripts/gen_markdown_view_fit_test.py computes (a markdown-it-py parse laid out by the module header's
// rules with a proportional, ligature- and kerning-aware synthetic measurement). Each check exits with its own code.

use e.fmt.markdown
use e.io
use e.mem
use e.os
use e.str
use e.ui.markdown_view as mv

// The measurement the model uses: a width per character class (narrow 3, wide 12, capitals 9, other 7, other scripts
// 8, a space 4), one more per character in bold, code monospaced at 8, and the pairs fi, AV, VA, To two narrower.
fn measure_text(state: *void, text: str, style: u8) -> f32 {
    var total: f32 = 0.0
    var i = 0usize
    if (style & 4u8) != 0u8 {
        var cps = 0usize
        while i < text.len {
            if (text[i] & 192u8) != 128u8 { cps += 1usize }
            i += 1usize
        }
        ret f32(cps) * 8.0
    }
    while i < text.len {
        let ch = text[i]
        if ch >= 128u8 {
            if (ch & 192u8) != 128u8 { total += 8.0 }
        } else {
            if ch == 32u8 {
                total += 4.0
            } else if ch == 105u8 || ch == 106u8 || ch == 108u8 || ch == 116u8 || ch == 102u8 || ch == 114u8 || ch == 73u8 || ch == 46u8 || ch == 44u8 || ch == 58u8 || ch == 59u8 || ch == 33u8 || ch == 124u8 || ch == 39u8 {
                total += 3.0
            } else if ch == 109u8 || ch == 119u8 || ch == 77u8 || ch == 87u8 || ch == 64u8 || ch == 37u8 {
                total += 12.0
            } else if ch >= 65u8 && ch <= 90u8 {
                total += 9.0
            } else {
                total += 7.0
            }
            if (style & 1u8) != 0u8 { total += 1.0 }
        }
        if i + 1usize < text.len {
            let next = text[i + 1usize]
            if (ch == 102u8 && next == 105u8) || (ch == 65u8 && next == 86u8) || (ch == 86u8 && next == 65u8) || (ch == 84u8 && next == 111u8) {
                total -= 2.0
            }
        }
        i += 1usize
    }
    ret total
}

fn letter(k: mv.ItemKind) -> str {
    if k == .Word { ret "W" }
    if k == .Marker { ret "M" }
    if k == .Rule { ret "R" }
    if k == .QuoteBar { ret "Q" }
    if k == .CodeBack { ret "B" }
    if k == .CellBack { ret "T" }
    ret "L"
}

fn role_letter(r: mv.NodeRole) -> str {
    if r == .Heading { ret "H" }
    if r == .Paragraph { ret "P" }
    if r == .List { ret "L" }
    if r == .ListItem { ret "I" }
    if r == .Quote { ret "Q" }
    if r == .Code { ret "C" }
    if r == .Table { ret "A" }
    if r == .Row { ret "O" }
    if r == .Cell { ret "D" }
    if r == .HeaderCell { ret "E" }
    ret "S"
}

fn number(b: *str.Builder, v: f32) -> err {
    ret str.push_u32(b, u32(v))
}

fn doc_count() -> usize { ret 12usize }

fn doc_src(i: usize) -> str {
    if i == 0usize { ret "# Title of the page\n\nA paragraph with *emphasis*, **strong text**, `inline code` and a [link](https://example.org/a) in it,\nwrapped over several lines of the viewer width.\n\n### Third\n\nfirst line\\\nline two after a hard break\n\n###### six" }
    if i == 1usize { ret "short supercalifragilisticexpialidocious end foo**bar**baz `code` x" }
    if i == 2usize { ret "```neper\n# not a heading\n**not bold** <script>alert(1)</script>\n\nfn main() {}\n```\n\n    indented code\n    more\n\n---\n\nafter" }
    if i == 3usize { ret "| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit |\n| fig | 12 |\n| `code` | 7 | a |" }
    if i == 4usize { ret "| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit from the market |\n| fig | 12 |\n| `code` | 7 | a |" }
    if i == 5usize { ret "| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit from the market |\n| fig | 12 |\n| `code` | 7 | a |" }
    if i == 6usize { ret "| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit from the market |\n| fig | 12 |\n| `code` | 7 | a |" }
    if i == 7usize { ret "| alpha | beta |\n|---|---|\n| supercalifragilistic | b |\n| c | d |" }
    if i == 8usize { ret "- item\n\n  a | b\n  --|--\n  1 | 2222\n\n> | x | y |\n> |---|---|\n> | left \\| pipe | z |\n" }
    if i == 9usize { ret "| T | |\n|---|---|\n| | |" }
    if i == 10usize { ret "| AVA Tofu | office |\n|---|---:|\n| fifi | W@m |" }
    if i == 11usize { ret "Before the table\n| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit from the market |\n| fig | 12 |\n| `code` | 7 | a | extra | cells |\n\nafter the table" }
    ret ""
}

fn doc_width(i: usize) -> f32 {
    if i == 0usize { ret 240.0 }
    if i == 1usize { ret 120.0 }
    if i == 2usize { ret 240.0 }
    if i == 3usize { ret 400.0 }
    if i == 4usize { ret 150.0 }
    if i == 5usize { ret 400.0 }
    if i == 6usize { ret 130.0 }
    if i == 7usize { ret 60.0 }
    if i == 8usize { ret 240.0 }
    if i == 9usize { ret 200.0 }
    if i == 10usize { ret 200.0 }
    if i == 11usize { ret 240.0 }
    ret 0.0
}

fn doc_expected(i: usize) -> str {
    if i == 0usize { ret "W 0 0 50 32 64 0 Title\nW 58 0 20 32 64 0 of\nW 86 0 34 32 64 0 the\nW 128 0 56 32 64 0 page\nW 0 40 9 16 0 0 A\nW 13 40 55 16 0 0 paragraph\nW 72 40 25 16 0 0 with\nW 101 40 57 16 2 0 emphasis\nW 158 40 3 16 32 0 ,\nW 166 40 40 16 1 0 strong\nW 211 40 24 16 1 0 text\nW 235 40 3 16 32 0 ,\nW 0 56 48 16 4 0 inline\nW 56 56 32 16 4 0 code\nW 92 56 21 16 0 0 and\nW 117 56 7 16 0 0 a\nW 128 56 20 16 8 1 link\nW 152 56 10 16 0 0 in\nW 166 56 9 16 0 0 it,\nW 179 56 50 16 0 0 wrapped\nW 0 72 24 16 0 0 over\nW 28 72 41 16 0 0 several\nW 73 72 27 16 0 0 lines\nW 104 72 10 16 0 0 of\nW 118 72 17 16 0 0 the\nW 139 72 39 16 0 0 viewer\nW 182 72 35 16 0 0 width.\nW 0 96 36 20 64 0 Third\nW 0 124 17 16 0 0 first\nW 21 124 20 16 0 0 line\nW 0 140 20 16 0 0 line\nW 24 140 22 16 0 0 two\nW 50 140 23 16 0 0 after\nW 77 140 7 16 0 0 a\nW 88 140 24 16 0 0 hard\nW 116 140 31 16 0 0 break\nW 0 164 17 16 64 0 six\nN H 1 0 0 4 Title of the page\nN P 0 0 4 23 A paragraph with emphasis, strong text, inline code and a link in it, wrapped over several lines of the viewer width.\nN H 3 0 27 1 Third\nN P 0 0 28 8 first line\nline two after a hard break\nN H 6 0 36 1 six\nK 1 https://example.org/a\nH 180\n" }
    if i == 1usize { ret "W 0 0 27 16 0 0 short\nW 0 16 182 16 0 0 supercalifragilisticexpialidocious\nW 0 32 21 16 0 0 end\nW 25 32 17 16 0 0 foo\nW 42 32 20 16 33 0 bar\nW 62 32 21 16 32 0 baz\nW 0 48 32 16 4 0 code\nW 36 48 7 16 0 0 x\nN P 0 0 0 8 short supercalifragilisticexpialidocious end foobarbaz code x\nH 64\n" }
    if i == 2usize { ret "B 0 0 240 72 4 0 \nL 4 4 120 16 4 0 # not a heading\nL 4 20 304 16 4 0 **not bold** <script>alert(1)</script>\nL 4 36 0 16 4 0 \nL 4 52 96 16 4 0 fn main() {}\nB 0 80 240 40 4 0 \nL 4 84 104 16 4 0 indented code\nL 4 100 32 16 4 0 more\nR 0 128 240 1 0 0 \nW 0 137 23 16 0 0 after\nN C 0 0 0 5 neper\nN C 0 0 5 3 \nN S 0 0 8 1 \nN P 0 0 9 1 after\nH 153\n" }
    if i == 3usize { ret "T 0 0 48 24 0 0 \nW 4 4 32 16 1 0 Name\nT 48 0 32 24 0 0 \nW 52 4 24 16 1 0 Qty\nT 80 0 176 24 0 0 \nW 220 4 32 16 1 0 Note\nT 0 24 48 24 0 0 \nW 4 28 40 16 0 0 apple\nT 48 24 32 24 0 0 \nW 60 28 8 16 0 0 3\nT 80 24 176 24 0 0 \nW 84 28 40 16 1 0 fresh\nW 132 28 24 16 0 0 and\nW 164 28 40 16 2 0 sweet\nW 212 28 40 16 0 0 fruit\nT 0 48 48 24 0 0 \nW 4 52 24 16 0 0 fig\nT 48 48 32 24 0 0 \nW 56 52 16 16 0 0 12\nT 80 48 176 24 0 0 \nT 0 72 48 24 0 0 \nW 4 76 32 16 4 0 code\nT 48 72 32 24 0 0 \nW 60 76 8 16 0 0 7\nT 80 72 176 24 0 0 \nW 244 76 8 16 0 0 a\nN A 3 0 0 26 \nN O 0 0 0 6 \nN E 1 0 0 2 Name\nN E 2 0 2 2 Qty\nN E 3 0 4 2 Note\nN O 1 0 6 9 \nN D 1 0 6 2 apple\nN D 2 0 8 2 3\nN D 3 0 10 5 fresh and sweet fruit\nN O 2 0 15 5 \nN D 1 0 15 2 fig\nN D 2 0 17 2 12\nN D 3 0 19 1 \nN O 3 0 20 6 \nN D 1 0 20 2 code\nN D 2 0 22 2 7\nN D 3 0 24 2 a\nH 96\n" }
    if i == 4usize { ret "T 0 0 48 24 0 0 \nW 4 4 32 16 1 0 Name\nT 48 0 32 24 0 0 \nW 52 4 24 16 1 0 Qty\nT 80 0 70 24 0 0 \nW 114 4 32 16 1 0 Note\nT 0 24 48 120 0 0 \nW 4 28 40 16 0 0 apple\nT 48 24 32 120 0 0 \nW 60 28 8 16 0 0 3\nT 80 24 70 120 0 0 \nW 106 28 40 16 1 0 fresh\nW 122 44 24 16 0 0 and\nW 106 60 40 16 2 0 sweet\nW 106 76 40 16 0 0 fruit\nW 114 92 32 16 0 0 from\nW 122 108 24 16 0 0 the\nW 98 124 48 16 0 0 market\nT 0 144 48 24 0 0 \nW 4 148 24 16 0 0 fig\nT 48 144 32 24 0 0 \nW 56 148 16 16 0 0 12\nT 80 144 70 24 0 0 \nT 0 168 48 24 0 0 \nW 4 172 32 16 4 0 code\nT 48 168 32 24 0 0 \nW 60 172 8 16 0 0 7\nT 80 168 70 24 0 0 \nW 138 172 8 16 0 0 a\nN A 3 0 0 29 \nN O 0 0 0 6 \nN E 1 0 0 2 Name\nN E 2 0 2 2 Qty\nN E 3 0 4 2 Note\nN O 1 0 6 12 \nN D 1 0 6 2 apple\nN D 2 0 8 2 3\nN D 3 0 10 8 fresh and sweet fruit from the market\nN O 2 0 18 5 \nN D 1 0 18 2 fig\nN D 2 0 20 2 12\nN D 3 0 22 1 \nN O 3 0 23 6 \nN D 1 0 23 2 code\nN D 2 0 25 2 7\nN D 3 0 27 2 a\nH 192\n" }
    if i == 5usize { ret "T 0 0 47 24 0 0 \nW 4 4 39 16 1 0 Name\nT 47 0 30 24 0 0 \nW 51 4 22 16 1 0 Qty\nT 77 0 221 24 0 0 \nW 264 4 30 16 1 0 Note\nT 0 24 47 24 0 0 \nW 4 28 31 16 0 0 apple\nT 47 24 30 24 0 0 \nW 58 28 7 16 0 0 3\nT 77 24 221 24 0 0 \nW 81 28 32 16 1 0 fresh\nW 117 28 21 16 0 0 and\nW 142 28 36 16 2 0 sweet\nW 182 28 19 16 0 0 fruit\nW 205 28 25 16 0 0 from\nW 234 28 17 16 0 0 the\nW 255 28 39 16 0 0 market\nT 0 48 47 24 0 0 \nW 4 52 11 16 0 0 fig\nT 47 48 30 24 0 0 \nW 55 52 14 16 0 0 12\nT 77 48 221 24 0 0 \nT 0 72 47 24 0 0 \nW 4 76 32 16 4 0 code\nT 47 72 30 24 0 0 \nW 58 76 7 16 0 0 7\nT 77 72 221 24 0 0 \nW 287 76 7 16 0 0 a\nN A 3 0 0 29 \nN O 0 0 0 6 \nN E 1 0 0 2 Name\nN E 2 0 2 2 Qty\nN E 3 0 4 2 Note\nN O 1 0 6 12 \nN D 1 0 6 2 apple\nN D 2 0 8 2 3\nN D 3 0 10 8 fresh and sweet fruit from the market\nN O 2 0 18 5 \nN D 1 0 18 2 fig\nN D 2 0 20 2 12\nN D 3 0 22 1 \nN O 3 0 23 6 \nN D 1 0 23 2 code\nN D 2 0 25 2 7\nN D 3 0 27 2 a\nH 96\n" }
    if i == 6usize { ret "T 0 0 47 24 0 0 \nW 4 4 39 16 1 0 Name\nT 47 0 30 24 0 0 \nW 51 4 22 16 1 0 Qty\nT 77 0 53 24 0 0 \nW 96 4 30 16 1 0 Note\nT 0 24 47 120 0 0 \nW 4 28 31 16 0 0 apple\nT 47 24 30 120 0 0 \nW 58 28 7 16 0 0 3\nT 77 24 53 120 0 0 \nW 94 28 32 16 1 0 fresh\nW 105 44 21 16 0 0 and\nW 90 60 36 16 2 0 sweet\nW 107 76 19 16 0 0 fruit\nW 101 92 25 16 0 0 from\nW 109 108 17 16 0 0 the\nW 87 124 39 16 0 0 market\nT 0 144 47 24 0 0 \nW 4 148 11 16 0 0 fig\nT 47 144 30 24 0 0 \nW 55 148 14 16 0 0 12\nT 77 144 53 24 0 0 \nT 0 168 47 24 0 0 \nW 4 172 32 16 4 0 code\nT 47 168 30 24 0 0 \nW 58 172 7 16 0 0 7\nT 77 168 53 24 0 0 \nW 119 172 7 16 0 0 a\nN A 3 0 0 29 \nN O 0 0 0 6 \nN E 1 0 0 2 Name\nN E 2 0 2 2 Qty\nN E 3 0 4 2 Note\nN O 1 0 6 12 \nN D 1 0 6 2 apple\nN D 2 0 8 2 3\nN D 3 0 10 8 fresh and sweet fruit from the market\nN O 2 0 18 5 \nN D 1 0 18 2 fig\nN D 2 0 20 2 12\nN D 3 0 22 1 \nN O 3 0 23 6 \nN D 1 0 23 2 code\nN D 2 0 25 2 7\nN D 3 0 27 2 a\nH 192\n" }
    if i == 7usize { ret "T 0 0 108 24 0 0 \nW 4 4 36 16 1 0 alpha\nT 108 0 36 24 0 0 \nW 112 4 28 16 1 0 beta\nT 0 24 108 24 0 0 \nW 4 28 100 16 0 0 supercalifragilistic\nT 108 24 36 24 0 0 \nW 112 28 7 16 0 0 b\nT 0 48 108 24 0 0 \nW 4 52 7 16 0 0 c\nT 108 48 36 24 0 0 \nW 112 52 7 16 0 0 d\nN A 2 0 0 12 \nN O 0 0 0 4 \nN E 0 0 0 2 alpha\nN E 0 0 2 2 beta\nN O 1 0 4 4 \nN D 0 0 4 2 supercalifragilistic\nN D 0 0 6 2 b\nN O 2 0 8 4 \nN D 0 0 8 2 c\nN D 0 0 10 2 d\nH 72\n" }
    if i == 8usize { ret "M 0 0 16 16 0 0 •\nW 16 0 25 16 0 0 item\nT 16 24 16 24 0 0 \nW 20 28 8 16 1 0 a\nT 32 24 36 24 0 0 \nW 36 28 8 16 1 0 b\nT 16 48 16 24 0 0 \nW 20 52 7 16 0 0 1\nT 32 48 36 24 0 0 \nW 36 52 28 16 0 0 2222\nT 16 80 59 24 0 0 \nW 20 84 8 16 1 0 x\nT 75 80 16 24 0 0 \nW 79 84 8 16 1 0 y\nT 16 104 59 24 0 0 \nW 20 108 16 16 0 0 left\nW 40 108 3 16 0 0 |\nW 47 108 24 16 0 0 pipe\nT 75 104 16 24 0 0 \nW 79 108 7 16 0 0 z\nQ 0 80 2 48 0 0 \nN L 0 0 0 10 \nN I 0 0 0 10 \nN P 0 1 0 2 item\nN A 2 1 2 8 \nN O 0 1 2 4 \nN E 0 1 2 2 a\nN E 0 1 4 2 b\nN O 1 1 6 4 \nN D 0 1 6 2 1\nN D 0 1 8 2 2222\nN Q 0 0 10 11 \nN A 2 1 10 11 \nN O 0 1 10 4 \nN E 0 1 10 2 x\nN E 0 1 12 2 y\nN O 1 1 14 6 \nN D 0 1 14 4 left | pipe\nN D 0 1 18 2 z\nH 128\n" }
    if i == 9usize { ret "T 0 0 18 24 0 0 \nW 4 4 10 16 1 0 T\nT 18 0 8 24 0 0 \nT 0 24 18 24 0 0 \nT 18 24 8 24 0 0 \nN A 2 0 0 5 \nN O 0 0 0 3 \nN E 0 0 0 2 T\nN E 0 0 2 1 \nN O 1 0 3 2 \nN D 0 0 3 1 \nN D 0 0 4 1 \nH 48\n" }
    if i == 10usize { ret "T 0 0 67 24 0 0 \nW 4 4 26 16 1 0 AVA\nW 35 4 28 16 1 0 Tofu\nT 67 0 44 24 0 0 \nW 73 4 34 16 1 0 office\nT 0 24 67 24 0 0 \nW 4 28 8 16 0 0 fifi\nT 67 24 44 24 0 0 \nW 71 28 36 16 0 0 W@m\nN A 2 0 0 9 \nN O 0 0 0 5 \nN E 0 0 0 3 AVA Tofu\nN E 3 0 3 2 office\nN O 1 0 5 4 \nN D 0 0 5 2 fifi\nN D 3 0 7 2 W@m\nH 48\n" }
    if i == 11usize { ret "W 0 0 48 16 0 0 Before\nW 56 0 24 16 0 0 the\nW 88 0 40 16 0 0 table\nT 0 24 80 24 0 0 \nW 4 28 32 16 1 0 Name\nT 80 24 80 24 0 0 \nW 108 28 24 16 1 0 Qty\nT 160 24 80 24 0 0 \nW 204 28 32 16 1 0 Note\nT 0 48 80 88 0 0 \nW 4 52 40 16 0 0 apple\nT 80 48 80 88 0 0 \nW 116 52 8 16 0 0 3\nT 160 48 80 88 0 0 \nW 164 52 40 16 1 0 fresh\nW 212 52 24 16 0 0 and\nW 196 68 40 16 2 0 sweet\nW 196 84 40 16 0 0 fruit\nW 172 100 32 16 0 0 from\nW 212 100 24 16 0 0 the\nW 188 116 48 16 0 0 market\nT 0 136 80 24 0 0 \nW 4 140 24 16 0 0 fig\nT 80 136 80 24 0 0 \nW 112 140 16 16 0 0 12\nT 160 136 80 24 0 0 \nT 0 160 80 24 0 0 \nW 4 164 32 16 4 0 code\nT 80 160 80 24 0 0 \nW 116 164 8 16 0 0 7\nT 160 160 80 24 0 0 \nW 228 164 8 16 0 0 a\nW 0 192 40 16 0 0 after\nW 48 192 24 16 0 0 the\nW 80 192 40 16 0 0 table\nN P 0 0 0 3 Before the table\nN A 3 0 3 29 \nN O 0 0 3 6 \nN E 1 0 3 2 Name\nN E 2 0 5 2 Qty\nN E 3 0 7 2 Note\nN O 1 0 9 12 \nN D 1 0 9 2 apple\nN D 2 0 11 2 3\nN D 3 0 13 8 fresh and sweet fruit from the market\nN O 2 0 21 5 \nN D 1 0 21 2 fig\nN D 2 0 23 2 12\nN D 3 0 25 1 \nN O 3 0 26 6 \nN D 1 0 26 2 code\nN D 2 0 28 2 7\nN D 3 0 30 2 a\nN P 0 0 32 3 after the table\nH 208\n" }
    ret ""
}

fn doc_measured(i: usize) -> bool {
    if i == 0usize { ret true }
    if i == 1usize { ret true }
    if i == 2usize { ret true }
    if i == 3usize { ret false }
    if i == 4usize { ret false }
    if i == 5usize { ret true }
    if i == 6usize { ret true }
    if i == 7usize { ret true }
    if i == 8usize { ret true }
    if i == 9usize { ret true }
    if i == 10usize { ret true }
    if i == 11usize { ret false }
    ret false
}

fn doc_fit(i: usize) -> bool {
    if i == 0usize { ret false }
    if i == 1usize { ret false }
    if i == 2usize { ret false }
    if i == 3usize { ret true }
    if i == 4usize { ret true }
    if i == 5usize { ret true }
    if i == 6usize { ret true }
    if i == 7usize { ret true }
    if i == 8usize { ret true }
    if i == 9usize { ret true }
    if i == 10usize { ret true }
    if i == 11usize { ret false }
    ret false
}

// The view in the generator's row format.
fn render(b: *str.Builder, v: *const mv.View) -> err {
    var i = 0usize
    while i < v.item_count {
        let it = v.items[i]
        try str.push(b, letter(it.kind))
        try str.push(b, " ")
        try number(b, it.x)
        try str.push(b, " ")
        try number(b, it.y)
        try str.push(b, " ")
        try number(b, it.w)
        try str.push(b, " ")
        try number(b, it.h)
        try str.push(b, " ")
        try str.push_u32(b, u32(it.style))
        try str.push(b, " ")
        try str.push_u32(b, it.link)
        try str.push(b, " ")
        try str.push(b, v.store[it.start..it.start + it.len])
        try str.push(b, "\n")
        i += 1usize
    }
    i = 0usize
    while i < v.node_count {
        let nd = v.nodes[i]
        try str.push(b, "N ")
        try str.push(b, role_letter(nd.role))
        try str.push(b, " ")
        try str.push_u32(b, nd.level)
        try str.push(b, " ")
        try str.push_u32(b, nd.depth)
        try str.push(b, " ")
        try str.push_u64(b, u64(nd.first))
        try str.push(b, " ")
        try str.push_u64(b, u64(nd.count))
        try str.push(b, " ")
        try str.push(b, v.store[nd.label_start..nd.label_start + nd.label_len])
        try str.push(b, "\n")
        i += 1usize
    }
    i = 0usize
    while i < v.link_count {
        let l = v.links[i]
        try str.push(b, "K ")
        if l.safe {
            try str.push(b, "1 ")
        } else {
            try str.push(b, "0 ")
        }
        try str.push(b, v.store[l.dest_start..l.dest_start + l.dest_len])
        try str.push(b, "\n")
        i += 1usize
    }
    try str.push(b, "H ")
    try number(b, v.height)
    try str.push(b, "\n")
    ret ok
}

fn metrics(width: f32) -> mv.Metrics {
    ret mv.Metrics { width: width, char_w: 8.0, line_h: 16.0, gap: 8.0, indent: 16.0, pad: 4.0, bar: 2.0 }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var items: [512]mv.Item = zero
    var nodes: [64]mv.Node = zero
    var links: [16]mv.Link = zero
    var store: [4096]u8 = zero
    var scratch: [1024]u8 = zero
    var blocks: [128]markdown.Block = zero
    var inlines: [128]markdown.Inline = zero
    var words: [128]mv.Word = zero
    let st = mv.Storage { items: items[..], nodes: nodes[..], links: links[..], store: store[..], scratch: scratch[..], blocks: blocks[..], inlines: inlines[..], words: words[..] }
    var d = 0usize
    while d < doc_count() {
        let mark = mem.mark(a)
        var opts: mv.Options = zero
        opts.measure = mv.Measure { state: zero, width: measure_text }
        opts.measured = doc_measured(d)
        opts.fit_columns = doc_fit(d)
        let (v, build_error) = mv.build_with(doc_src(d), st, metrics(doc_width(d)), .HostActivated, opts)
        if build_error != ok || v.fallback { os.exit(1) }
        let (b, b_error) = str.builder(a, 16384usize)
        if b_error != ok { os.exit(2) }
        var bb = b
        if render(&bb, &v) != ok { os.exit(3) }
        let got = str.done(&bb)
        if !str.eq(got, doc_expected(d)) {
            try io.print(got)
            os.exit(10 + i32(d))
        }
        mem.reset(a, mark)
        d += 1usize
    }
    // Without options `build` is the fixed grid and equal columns, and `build_with` of the zero options is `build`.
    let (plain_view, plain_error) = mv.build("| a | b |\n|---|---|\n| 1 | 2 |", st, metrics(160.0), .DisplayOnly)
    if plain_error != ok { os.exit(80) }
    var none: mv.Options = zero
    let (again, again_error) = mv.build_with("| a | b |\n|---|---|\n| 1 | 2 |", st, metrics(160.0), .DisplayOnly, none)
    if again_error != ok || again.item_count != plain_view.item_count { os.exit(81) }
    try io.print("markdown view fit ok")
    ret ok
}
