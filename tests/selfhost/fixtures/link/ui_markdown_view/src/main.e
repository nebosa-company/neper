// `e.ui.markdown_view` (L066): eight documents laid out by the viewer and compared, item by
// item, node by node and link by link, with the layout scripts/gen_markdown_view_test.py
// computes from a markdown-it-py parse (an oracle that shares nothing with e.fmt.markdown):
// headings, wrapping, emphasis, strong, code, links, hard breaks, tight and loose and
// nested lists, quotes, fenced and indented code, rules, images, raw HTML as literal text,
// a word wider than the line. Then selection text, hit points, the `control` rich spans,
// the link policy (display-only versus host-activated, safe and unsafe schemes), and the
// fallbacks for hostile or unboundable input. Each check exits with its own code.

use e.fmt.markdown
use e.io
use e.mem
use e.os
use e.str
use e.ui.control
use e.ui.markdown_view as mv
use e.ui.widget

// BEGIN DOCS
fn doc_count() -> usize { ret 12usize }

fn doc_src(i: usize) -> str {
    if i == 0usize { ret "# Title of the page\n\nA paragraph with *emphasis*, **strong text**, `inline code` and a [link](https://example.org/a) in it,\nwrapped over several lines of the viewer width.\n\n### Third\n\nfirst line\\\nline two after a hard break\n\n###### six" }
    if i == 1usize { ret "- one\n- two\n  1. nested a\n  2. nested b\n- three\n\ntext between\n\n1. first\n\n   second para\n\n2. second\n\n7. seven\n8. eight" }
    if i == 2usize { ret "> quoted line one\n> and two\n>\n> - item in quote\n> - another\n>\n> > nested quote\n\n- list with\n\n  > quote inside" }
    if i == 3usize { ret "```neper\n# not a heading\n**not bold** <script>alert(1)</script>\n\nfn main() {}\n```\n\n    indented code\n    more\n\n---\n\nafter" }
    if i == 4usize { ret "[web](http://example.org) [secure](HTTPS://example.org/x) [rel](docs/a.md) [frag](#top) [js](javascript:alert(1)) [data](data:text/html,x) [mail](mailto:a@example.org) <https://example.org/auto> <me@example.org> ![alt text](https://example.org/i.png)" }
    if i == 5usize { ret "<script>alert(1)</script> and <img src=x onerror=alert(1)>\n\n<div>\n**bold in html block**\n</div>\n\n[ref][1] stays\n\n<b>tag</b> stays" }
    if i == 6usize { ret "short supercalifragilisticexpialidocious end foo**bar**baz `code` x" }
    if i == 7usize { ret "1. > ## Heading in quote\n   > text\n\n- - nested bullets\n  - second" }
    if i == 8usize { ret "Before the table\n| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit from the market |\n| fig | 12 |\n| `code` | 7 | a | extra | cells |\n\nafter the table" }
    if i == 9usize { ret "- item\n\n  a | b\n  --|--\n  1 | 2\n\n> | x | y |\n> |---|---|\n> | left \\| pipe | z |\n" }
    if i == 10usize { ret "| alpha | beta |\n|---|---|\n| supercalifragilistic | b |\n| c | d |" }
    if i == 11usize { ret "a | b | c\n--|--\n\n| a | b |\n| c | d |\n\n| h1 | h2 |\n|----|----|\n| 1 | 2 |\n# heading\n\n| h |\n|---|\n| only |\n- list" }
    ret ""
}

fn doc_width(i: usize) -> f32 {
    if i == 0usize { ret 240.0 }
    if i == 1usize { ret 200.0 }
    if i == 2usize { ret 200.0 }
    if i == 3usize { ret 240.0 }
    if i == 4usize { ret 240.0 }
    if i == 5usize { ret 240.0 }
    if i == 6usize { ret 96.0 }
    if i == 7usize { ret 240.0 }
    if i == 8usize { ret 240.0 }
    if i == 9usize { ret 240.0 }
    if i == 10usize { ret 120.0 }
    if i == 11usize { ret 240.0 }
    ret 0.0
}

fn doc_expected(i: usize) -> str {
    if i == 0usize { ret "W 0 0 80 32 64 0 Title\nW 96 0 32 32 64 0 of\nW 144 0 48 32 64 0 the\nW 0 32 64 32 64 0 page\nW 0 72 8 16 0 0 A\nW 16 72 72 16 0 0 paragraph\nW 96 72 32 16 0 0 with\nW 136 72 64 16 2 0 emphasis\nW 200 72 8 16 32 0 ,\nW 0 88 48 16 1 0 strong\nW 56 88 32 16 1 0 text\nW 88 88 8 16 32 0 ,\nW 104 88 48 16 4 0 inline\nW 160 88 32 16 4 0 code\nW 200 88 24 16 0 0 and\nW 232 88 8 16 0 0 a\nW 0 104 32 16 8 1 link\nW 40 104 16 16 0 0 in\nW 64 104 24 16 0 0 it,\nW 96 104 56 16 0 0 wrapped\nW 160 104 32 16 0 0 over\nW 0 120 56 16 0 0 several\nW 64 120 40 16 0 0 lines\nW 112 120 16 16 0 0 of\nW 136 120 24 16 0 0 the\nW 168 120 48 16 0 0 viewer\nW 0 136 48 16 0 0 width.\nW 0 160 50 20 64 0 Third\nW 0 188 40 16 0 0 first\nW 48 188 32 16 0 0 line\nW 0 204 32 16 0 0 line\nW 40 204 24 16 0 0 two\nW 72 204 40 16 0 0 after\nW 120 204 8 16 0 0 a\nW 136 204 32 16 0 0 hard\nW 176 204 40 16 0 0 break\nW 0 228 24 16 64 0 six\nN H 1 0 0 4 Title of the page\nN P 0 0 4 23 A paragraph with emphasis, strong text, inline code and a link in it, wrapped over several lines of the viewer width.\nN H 3 0 27 1 Third\nN P 0 0 28 8 first line\nline two after a hard break\nN H 6 0 36 1 six\nK 1 https://example.org/a\nH 244\n" }
    if i == 1usize { ret "M 0 0 16 16 0 0 •\nW 16 0 24 16 0 0 one\nM 0 16 16 16 0 0 •\nW 16 16 24 16 0 0 two\nM 16 32 16 16 0 0 1.\nW 32 32 48 16 0 0 nested\nW 88 32 8 16 0 0 a\nM 16 48 16 16 0 0 2.\nW 32 48 48 16 0 0 nested\nW 88 48 8 16 0 0 b\nM 0 64 16 16 0 0 •\nW 16 64 40 16 0 0 three\nW 0 88 32 16 0 0 text\nW 40 88 56 16 0 0 between\nM 0 112 16 16 0 0 1.\nW 16 112 40 16 0 0 first\nW 16 136 48 16 0 0 second\nW 72 136 32 16 0 0 para\nM 0 160 16 16 0 0 2.\nW 16 160 48 16 0 0 second\nM 0 184 16 16 0 0 3.\nW 16 184 40 16 0 0 seven\nM 0 208 16 16 0 0 4.\nW 16 208 40 16 0 0 eight\nN L 0 0 0 12 \nN I 0 0 0 2 \nN P 0 1 0 2 one\nN I 0 0 2 8 \nN P 0 1 2 2 two\nN L 1 1 4 6 \nN I 1 1 4 3 \nN P 0 2 4 3 nested a\nN I 2 1 7 3 \nN P 0 2 7 3 nested b\nN I 0 0 10 2 \nN P 0 1 10 2 three\nN P 0 0 12 2 text between\nN L 1 0 14 10 \nN I 1 0 14 4 \nN P 0 1 14 2 first\nN P 0 1 16 2 second para\nN I 2 0 18 2 \nN P 0 1 18 2 second\nN I 3 0 20 2 \nN P 0 1 20 2 seven\nN I 4 0 22 2 \nN P 0 1 22 2 eight\nH 224\n" }
    if i == 2usize { ret "W 16 0 48 16 0 0 quoted\nW 72 0 32 16 0 0 line\nW 112 0 24 16 0 0 one\nW 144 0 24 16 0 0 and\nW 176 0 24 16 0 0 two\nQ 0 0 2 16 0 0 \nM 16 24 16 16 0 0 •\nW 32 24 32 16 0 0 item\nW 72 24 16 16 0 0 in\nW 96 24 40 16 0 0 quote\nQ 0 24 2 16 0 0 \nM 16 40 16 16 0 0 •\nW 32 40 56 16 0 0 another\nQ 0 40 2 16 0 0 \nW 32 64 48 16 0 0 nested\nW 88 64 40 16 0 0 quote\nQ 0 64 2 16 0 0 \nQ 16 64 2 16 0 0 \nM 0 88 16 16 0 0 •\nW 16 88 32 16 0 0 list\nW 56 88 32 16 0 0 with\nW 32 112 40 16 0 0 quote\nW 80 112 48 16 0 0 inside\nQ 16 112 2 16 0 0 \nN Q 0 0 0 18 \nN P 0 1 0 6 quoted line one and two\nN L 0 1 6 8 \nN I 0 1 6 5 \nN P 0 2 6 5 item in quote\nN I 0 1 11 3 \nN P 0 2 11 3 another\nN Q 0 1 14 4 \nN P 0 2 14 4 nested quote\nN L 0 0 18 6 \nN I 0 0 18 6 \nN P 0 1 18 3 list with\nN Q 0 1 21 3 \nN P 0 2 21 3 quote inside\nH 128\n" }
    if i == 3usize { ret "B 0 0 240 72 4 0 \nL 4 4 120 16 4 0 # not a heading\nL 4 20 304 16 4 0 **not bold** <script>alert(1)</script>\nL 4 36 0 16 4 0 \nL 4 52 96 16 4 0 fn main() {}\nB 0 80 240 40 4 0 \nL 4 84 104 16 4 0 indented code\nL 4 100 32 16 4 0 more\nR 0 128 240 1 0 0 \nW 0 137 40 16 0 0 after\nN C 0 0 0 5 neper\nN C 0 0 5 3 \nN S 0 0 8 1 \nN P 0 0 9 1 after\nH 153\n" }
    if i == 4usize { ret "W 0 0 24 16 8 1 web\nW 32 0 48 16 8 2 secure\nW 88 0 24 16 8 3 rel\nW 120 0 32 16 8 4 frag\nW 160 0 16 16 8 5 js\nW 184 0 32 16 8 6 data\nW 0 16 32 16 8 7 mail\nW 40 16 192 16 8 8 https://example.org/auto\nW 0 32 112 16 8 9 me@example.org\nW 120 32 24 16 16 0 alt\nW 152 32 32 16 16 0 text\nN P 0 0 0 11 web secure rel frag js data mail https://example.org/auto me@example.org alt text\nK 1 http://example.org\nK 1 HTTPS://example.org/x\nK 1 docs/a.md\nK 1 #top\nK 0 javascript:alert(1)\nK 0 data:text/html,x\nK 1 mailto:a@example.org\nK 1 https://example.org/auto\nK 1 mailto:me@example.org\nH 48\n" }
    if i == 5usize { ret "W 0 0 200 16 0 0 <script>alert(1)</script>\nW 208 0 24 16 0 0 and\nW 0 16 32 16 0 0 <img\nW 40 16 40 16 0 0 src=x\nW 88 16 136 16 0 0 onerror=alert(1)>\nW 0 40 40 16 0 0 <div>\nW 48 40 32 16 1 0 bold\nW 88 40 16 16 1 0 in\nW 112 40 32 16 1 0 html\nW 152 40 40 16 1 0 block\nW 0 56 48 16 0 0 </div>\nW 0 80 64 16 0 0 [ref][1]\nW 72 80 40 16 0 0 stays\nW 0 104 80 16 0 0 <b>tag</b>\nW 88 104 40 16 0 0 stays\nN P 0 0 0 5 <script>alert(1)</script> and <img src=x onerror=alert(1)>\nN P 0 0 5 6 <div> bold in html block </div>\nN P 0 0 11 2 [ref][1] stays\nN P 0 0 13 2 <b>tag</b> stays\nH 120\n" }
    if i == 6usize { ret "W 0 0 40 16 0 0 short\nW 0 16 272 16 0 0 supercalifragilisticexpialidocious\nW 0 32 24 16 0 0 end\nW 32 32 24 16 0 0 foo\nW 56 32 24 16 33 0 bar\nW 0 48 24 16 32 0 baz\nW 32 48 32 16 4 0 code\nW 72 48 8 16 0 0 x\nN P 0 0 0 8 short supercalifragilisticexpialidocious end foobarbaz code x\nH 64\n" }
    if i == 7usize { ret "M 0 0 16 24 0 0 1.\nW 32 0 84 24 64 0 Heading\nW 128 0 24 24 64 0 in\nW 164 0 60 24 64 0 quote\nQ 16 0 2 24 0 0 \nW 32 24 32 16 0 0 text\nQ 16 24 2 16 0 0 \nM 0 40 16 16 0 0 •\nM 16 40 16 16 0 0 •\nW 32 40 48 16 0 0 nested\nW 88 40 56 16 0 0 bullets\nM 16 56 16 16 0 0 •\nW 32 56 48 16 0 0 second\nN L 1 0 0 7 \nN I 1 0 0 7 \nN Q 0 1 0 7 \nN H 2 2 0 5 Heading in quote\nN P 0 2 5 2 text\nN L 0 0 7 6 \nN I 0 0 7 6 \nN L 0 1 7 6 \nN I 0 1 7 4 \nN P 0 2 7 4 nested bullets\nN I 0 1 11 2 \nN P 0 2 11 2 second\nH 72\n" }
    if i == 8usize { ret "W 0 0 48 16 0 0 Before\nW 56 0 24 16 0 0 the\nW 88 0 40 16 0 0 table\nT 0 24 80 24 0 0 \nW 4 28 32 16 1 0 Name\nT 80 24 80 24 0 0 \nW 108 28 24 16 1 0 Qty\nT 160 24 80 24 0 0 \nW 204 28 32 16 1 0 Note\nT 0 48 80 88 0 0 \nW 4 52 40 16 0 0 apple\nT 80 48 80 88 0 0 \nW 116 52 8 16 0 0 3\nT 160 48 80 88 0 0 \nW 164 52 40 16 1 0 fresh\nW 212 52 24 16 0 0 and\nW 196 68 40 16 2 0 sweet\nW 196 84 40 16 0 0 fruit\nW 172 100 32 16 0 0 from\nW 212 100 24 16 0 0 the\nW 188 116 48 16 0 0 market\nT 0 136 80 24 0 0 \nW 4 140 24 16 0 0 fig\nT 80 136 80 24 0 0 \nW 112 140 16 16 0 0 12\nT 160 136 80 24 0 0 \nT 0 160 80 24 0 0 \nW 4 164 32 16 4 0 code\nT 80 160 80 24 0 0 \nW 116 164 8 16 0 0 7\nT 160 160 80 24 0 0 \nW 228 164 8 16 0 0 a\nW 0 192 40 16 0 0 after\nW 48 192 24 16 0 0 the\nW 80 192 40 16 0 0 table\nN P 0 0 0 3 Before the table\nN A 3 0 3 29 \nN O 0 0 3 6 \nN E 1 0 3 2 Name\nN E 2 0 5 2 Qty\nN E 3 0 7 2 Note\nN O 1 0 9 12 \nN D 1 0 9 2 apple\nN D 2 0 11 2 3\nN D 3 0 13 8 fresh and sweet fruit from the market\nN O 2 0 21 5 \nN D 1 0 21 2 fig\nN D 2 0 23 2 12\nN D 3 0 25 1 \nN O 3 0 26 6 \nN D 1 0 26 2 code\nN D 2 0 28 2 7\nN D 3 0 30 2 a\nN P 0 0 32 3 after the table\nH 208\n" }
    if i == 9usize { ret "M 0 0 16 16 0 0 •\nW 16 0 32 16 0 0 item\nT 16 24 112 24 0 0 \nW 20 28 8 16 1 0 a\nT 128 24 112 24 0 0 \nW 132 28 8 16 1 0 b\nT 16 48 112 24 0 0 \nW 20 52 8 16 0 0 1\nT 128 48 112 24 0 0 \nW 132 52 8 16 0 0 2\nT 16 80 112 24 0 0 \nW 20 84 8 16 1 0 x\nT 128 80 112 24 0 0 \nW 132 84 8 16 1 0 y\nT 16 104 112 24 0 0 \nW 20 108 32 16 0 0 left\nW 60 108 8 16 0 0 |\nW 76 108 32 16 0 0 pipe\nT 128 104 112 24 0 0 \nW 132 108 8 16 0 0 z\nQ 0 80 2 48 0 0 \nN L 0 0 0 10 \nN I 0 0 0 10 \nN P 0 1 0 2 item\nN A 2 1 2 8 \nN O 0 1 2 4 \nN E 0 1 2 2 a\nN E 0 1 4 2 b\nN O 1 1 6 4 \nN D 0 1 6 2 1\nN D 0 1 8 2 2\nN Q 0 0 10 11 \nN A 2 1 10 11 \nN O 0 1 10 4 \nN E 0 1 10 2 x\nN E 0 1 12 2 y\nN O 1 1 14 6 \nN D 0 1 14 4 left | pipe\nN D 0 1 18 2 z\nH 128\n" }
    if i == 10usize { ret "T 0 0 60 24 0 0 \nW 4 4 40 16 1 0 alpha\nT 60 0 60 24 0 0 \nW 64 4 32 16 1 0 beta\nT 0 24 60 24 0 0 \nW 4 28 160 16 0 0 supercalifragilistic\nT 60 24 60 24 0 0 \nW 64 28 8 16 0 0 b\nT 0 48 60 24 0 0 \nW 4 52 8 16 0 0 c\nT 60 48 60 24 0 0 \nW 64 52 8 16 0 0 d\nN A 2 0 0 12 \nN O 0 0 0 4 \nN E 0 0 0 2 alpha\nN E 0 0 2 2 beta\nN O 1 0 4 4 \nN D 0 0 4 2 supercalifragilistic\nN D 0 0 6 2 b\nN O 2 0 8 4 \nN D 0 0 8 2 c\nN D 0 0 10 2 d\nH 72\n" }
    if i == 11usize { ret "W 0 0 8 16 0 0 a\nW 16 0 8 16 0 0 |\nW 32 0 8 16 0 0 b\nW 48 0 8 16 0 0 |\nW 64 0 8 16 0 0 c\nW 80 0 40 16 0 0 --|--\nW 0 24 8 16 0 0 |\nW 16 24 8 16 0 0 a\nW 32 24 8 16 0 0 |\nW 48 24 8 16 0 0 b\nW 64 24 8 16 0 0 |\nW 80 24 8 16 0 0 |\nW 96 24 8 16 0 0 c\nW 112 24 8 16 0 0 |\nW 128 24 8 16 0 0 d\nW 144 24 8 16 0 0 |\nT 0 48 120 24 0 0 \nW 4 52 16 16 1 0 h1\nT 120 48 120 24 0 0 \nW 124 52 16 16 1 0 h2\nT 0 72 120 24 0 0 \nW 4 76 8 16 0 0 1\nT 120 72 120 24 0 0 \nW 124 76 8 16 0 0 2\nW 0 104 112 32 64 0 heading\nT 0 144 240 24 0 0 \nW 4 148 8 16 1 0 h\nT 0 168 240 24 0 0 \nW 4 172 32 16 0 0 only\nM 0 200 16 16 0 0 •\nW 16 200 32 16 0 0 list\nN P 0 0 0 6 a | b | c --|--\nN P 0 0 6 10 | a | b | | c | d |\nN A 2 0 16 8 \nN O 0 0 16 4 \nN E 0 0 16 2 h1\nN E 0 0 18 2 h2\nN O 1 0 20 4 \nN D 0 0 20 2 1\nN D 0 0 22 2 2\nN H 1 0 24 1 heading\nN A 1 0 25 4 \nN O 0 0 25 2 \nN E 0 0 25 2 h\nN O 1 0 27 2 \nN D 0 0 27 2 only\nN L 0 0 29 2 \nN I 0 0 29 2 \nN P 0 1 29 2 list\nH 216\n" }
    ret ""
}

fn doc_selection(i: usize) -> str {
    if i == 0usize { ret "Title of the\npage\nA paragraph with emphasis,\nstrong text, inline code and a\nlink in it, wrapped over\nseveral lines of the viewer\nwidth.\nThird\nfirst line\nline two after a hard break\nsix" }
    if i == 1usize { ret "one\ntwo\nnested a\nnested b\nthree\ntext between\nfirst\nsecond para\nsecond\nseven\neight" }
    if i == 2usize { ret "quoted line one and two\nitem in quote\nanother\nnested quote\nlist with\nquote inside" }
    if i == 3usize { ret "# not a heading\n**not bold** <script>alert(1)</script>\n\nfn main() {}\nindented code\nmore\nafter" }
    if i == 4usize { ret "web secure rel frag js data\nmail https://example.org/auto\nme@example.org alt text" }
    if i == 5usize { ret "<script>alert(1)</script> and\n<img src=x onerror=alert(1)>\n<div> bold in html block\n</div>\n[ref][1] stays\n<b>tag</b> stays" }
    if i == 6usize { ret "short\nsupercalifragilisticexpialidocious\nend foobar\nbaz code x" }
    if i == 7usize { ret "Heading in quote\ntext\nnested bullets\nsecond" }
    if i == 8usize { ret "Before the table\nName\tQty\tNote\napple\t3\tfresh and\nsweet\nfruit\nfrom the\nmarket\nfig\t12\ncode\t7\ta\nafter the table" }
    if i == 9usize { ret "item\na\tb\n1\t2\nx\ty\nleft | pipe\tz" }
    if i == 10usize { ret "alpha\tbeta\nsupercalifragilistic\tb\nc\td" }
    if i == 11usize { ret "a | b | c --|--\n| a | b | | c | d |\nh1\th2\n1\t2\nheading\nh\nonly\nlist" }
    ret ""
}

fn doc_probes(i: usize) -> str {
    if i == 0usize { ret "1,1,0;97,1,1;145,1,2;1,33,3;1,73,4;17,73,5;97,73,6;137,73,7;201,73,8;1,89,9;57,89,10;89,89,11;105,89,12;161,89,13;201,89,14;233,89,15;1,105,16;41,105,17;65,105,18;97,105,19;161,105,20;1,121,21;65,121,22;113,121,23;137,121,24;169,121,25;1,137,26;1,161,27;1,189,28;49,189,29;1,205,30;41,205,31;73,205,32;121,205,33;137,205,34;177,205,35;1,229,36;290,3,-1;1,294,-1" }
    if i == 1usize { ret "1,1,0;17,1,1;1,17,2;17,17,3;17,33,4;33,33,5;89,33,6;17,49,7;33,49,8;89,49,9;1,65,10;17,65,11;1,89,12;41,89,13;1,113,14;17,113,15;17,137,16;73,137,17;1,161,18;17,161,19;1,185,20;17,185,21;1,209,22;17,209,23;250,3,-1;1,274,-1" }
    if i == 2usize { ret "17,1,0;73,1,1;113,1,2;145,1,3;177,1,4;17,25,6;33,25,7;73,25,8;97,25,9;17,41,11;33,41,12;33,65,14;89,65,15;1,89,18;17,89,19;57,89,20;33,113,21;81,113,22;250,3,-1;1,178,-1" }
    if i == 3usize { ret "5,5,1;5,21,2;5,37,-1;5,53,4;5,85,6;5,101,7;1,138,9;290,3,-1;1,203,-1" }
    if i == 4usize { ret "1,1,0;33,1,1;89,1,2;121,1,3;161,1,4;185,1,5;1,17,6;41,17,7;1,33,8;121,33,9;153,33,10;290,3,-1;1,98,-1" }
    if i == 5usize { ret "1,1,0;209,1,1;1,17,2;41,17,3;89,17,4;1,41,5;49,41,6;89,41,7;113,41,8;153,41,9;1,57,10;1,81,11;73,81,12;1,105,13;89,105,14;290,3,-1;1,170,-1" }
    if i == 6usize { ret "1,1,0;1,17,1;1,33,2;33,33,3;57,33,4;1,49,5;33,49,6;73,49,7;146,3,-1;1,114,-1" }
    if i == 7usize { ret "1,1,0;33,1,1;129,1,2;165,1,3;33,25,5;1,41,7;17,41,8;33,41,9;89,41,10;17,57,11;33,57,12;290,3,-1;1,122,-1" }
    if i == 8usize { ret "1,1,0;57,1,1;89,1,2;5,29,4;109,29,6;205,29,8;5,53,10;117,53,12;165,53,14;213,53,15;197,69,16;197,85,17;173,101,18;213,101,19;189,117,20;5,141,22;113,141,24;5,165,27;117,165,29;229,165,31;1,193,32;49,193,33;81,193,34;290,3,-1;1,258,-1" }
    if i == 9usize { ret "1,1,0;17,1,1;21,29,3;133,29,5;21,53,7;133,53,9;21,85,11;133,85,13;21,109,15;61,109,16;77,109,17;133,109,19;290,3,-1;1,178,-1" }
    if i == 10usize { ret "5,5,1;65,5,3;5,29,5;65,29,7;5,53,9;65,53,11;170,3,-1;1,122,-1" }
    if i == 11usize { ret "1,1,0;17,1,1;33,1,2;49,1,3;65,1,4;81,1,5;1,25,6;17,25,7;33,25,8;49,25,9;65,25,10;81,25,11;97,25,12;113,25,13;129,25,14;145,25,15;5,53,17;125,53,19;5,77,21;125,77,23;1,105,24;5,149,26;5,173,28;1,201,29;17,201,30;290,3,-1;1,266,-1" }
    ret ""
}

fn doc_spans(i: usize) -> str {
    if i == 0usize { ret "p:A :0;p:paragraph :0;p:with :0;i:emphasis:0;p:, :0;b:strong :0;b:text:0;p:, :0;c:inline :0;c:code :0;p:and :0;p:a :0;l:link :1;p:in :0;p:it, :0;p:wrapped :0;p:over :0;p:several :0;p:lines :0;p:of :0;p:the :0;p:viewer :0;p:width.:0;" }
    if i == 1usize { ret "-" }
    if i == 2usize { ret "-" }
    if i == 3usize { ret "-" }
    if i == 4usize { ret "l:web :1;l:secure :1;l:rel :1;l:frag :1;l:js :0;l:data :0;l:mail :1;l:https://example.org/auto :1;l:me@example.org :1;p:alt :0;p:text:0;" }
    if i == 5usize { ret "-" }
    if i == 6usize { ret "p:short :0;p:supercalifragilisticexpialidocious :0;p:end :0;p:foo:0;b:bar:0;p:baz :0;c:code :0;p:x:0;" }
    if i == 7usize { ret "-" }
    if i == 8usize { ret "b:Name:0;" }
    if i == 9usize { ret "-" }
    if i == 10usize { ret "-" }
    if i == 11usize { ret "-" }
    ret ""
}
// END DOCS

fn noop(ctx: *void) -> err { ret ok }

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

fn kind_letter(k: control.SpanKind) -> str {
    if k == .Code { ret "c" }
    if k == .Link { ret "l" }
    if k == .Strong { ret "b" }
    if k == .Emphasis { ret "i" }
    ret "p"
}

fn render_spans(b: *str.Builder, v: *const mv.View, node: usize, action: widget.Submit) -> err {
    var spans: [64]control.RichSpan = zero
    let (n, e) = mv.rich_spans(v, node, spans[..], action)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        try str.push(b, kind_letter(spans[i].kind))
        try str.push(b, ":")
        try str.push(b, spans[i].value)
        if widget.submit_set(spans[i].action.invoke) {
            try str.push(b, ":1;")
        } else {
            try str.push(b, ":0;")
        }
        i += 1usize
    }
    ret ok
}

// The integer at `at` in a "x,y,i;" list (a leading minus allowed); the next position.
fn next_int(s: str, at: usize) -> (i32, usize) {
    var i = at
    var neg = false
    if i < s.len && s[i] == 45u8 {
        neg = true
        i += 1usize
    }
    var v = 0i32
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        v = v * 10i32 + i32(s[i] - 48u8)
        i += 1usize
    }
    if neg { v = 0i32 - v }
    ret (v, i + 1usize)
}

// The probes of a document: the first failing probe number plus one, zero when all agree.
fn run_probes(v: *const mv.View, list: str) -> u32 {
    var at = 0usize
    var n = 0u32
    while at < list.len {
        let (px, after_x) = next_int(list, at)
        let (py, after_y) = next_int(list, after_x)
        let (want, after_i) = next_int(list, after_y)
        at = after_i
        n += 1u32
        let (got, found) = mv.item_at(v, f32(px), f32(py))
        if want < 0i32 {
            if found { ret n }
        } else {
            if !found || i32(got) != want { ret n }
        }
    }
    ret 0u32
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
    let action = widget.Submit { ctx: zero, invoke: noop }

    // The eight documents against the oracle: rows, selection, probes and spans.
    var d = 0usize
    while d < doc_count() {
        let mark = mem.mark(a)
        let (v, build_error) = mv.build(doc_src(d), st, metrics(doc_width(d)), .HostActivated)
        if build_error != ok || v.fallback { os.exit(1) }
        let (b, b_error) = str.builder(a, 16384usize)
        if b_error != ok { os.exit(2) }
        var bb = b
        if render(&bb, &v) != ok { os.exit(3) }
        let got_rows = str.done(&bb)
        if !str.eq(got_rows, doc_expected(d)) {
            try io.print(got_rows)
            os.exit(10 + i32(d))
        }
        let (sel, sel_error) = mem.alloc[u8](a, 2048usize)
        if sel_error != ok { os.exit(4) }
        let (n_sel, sel_run) = mv.selected_text(&v, 0usize, v.item_count - 1usize, sel)
        if sel_run != ok || !str.eq(sel[0usize..n_sel], doc_selection(d)) { os.exit(30 + i32(d)) }
        if run_probes(&v, doc_probes(d)) != 0u32 { os.exit(50 + i32(d)) }
        mem.reset(a, mark)
        d += 1usize
    }

    // Rich spans for the paragraph of doc 0, the links of doc 4 and the narrow doc 6, under
    // the host-activated policy; none of them carries the action when display-only.
    var s = 0usize
    while s < 4usize {
        let mark = mem.mark(a)
        var which = 0usize
        var which_node = 1usize
        if s == 3usize {
            // The first header cell of the table of doc 8 (after its paragraph, the table and a row).
            which = 8usize
            which_node = 3usize
        }
        if s == 1usize {
            which = 4usize
            which_node = 0usize
        }
        if s == 2usize {
            which = 6usize
            which_node = 0usize
        }
        let (v, e) = mv.build(doc_src(which), st, metrics(doc_width(which)), .HostActivated)
        if e != ok { os.exit(70) }
        let (b, b_error) = str.builder(a, 4096usize)
        if b_error != ok { os.exit(71) }
        var bb = b
        if render_spans(&bb, &v, which_node, action) != ok { os.exit(72) }
        if !str.eq(str.done(&bb), doc_spans(which)) { os.exit(73 + i32(s)) }
        mem.reset(a, mark)
        s += 1usize
    }
    let (shy, shy_error) = mv.build(doc_src(4usize), st, metrics(240.0), .DisplayOnly)
    if shy_error != ok { os.exit(80) }
    var q = 0usize
    while q < shy.link_count {
        let (_, live) = mv.activation(&shy, q)
        if live { os.exit(81) }
        q += 1usize
    }
    var spans: [32]control.RichSpan = zero
    let (shy_n, shy_spans) = mv.rich_spans(&shy, 0usize, spans[..], action)
    if shy_spans != ok || shy_n == 0usize { os.exit(82) }
    var t = 0usize
    while t < shy_n {
        if widget.submit_set(spans[t].action.invoke) { os.exit(83) }
        t += 1usize
    }

    // Host-activated: the destinations of doc 4 in order are web, secure, rel, frag, js,
    // data, mail, auto, email; only the unsafe schemes (js, data) refuse.
    let (live_view, live_error) = mv.build(doc_src(4usize), st, metrics(240.0), .HostActivated)
    if live_error != ok || live_view.link_count != 9usize { os.exit(84) }
    var live_count = 0usize
    q = 0usize
    while q < live_view.link_count {
        let (dest, live) = mv.activation(&live_view, q)
        if live { live_count += 1usize }
        if q == 4usize && live { os.exit(85) }
        if q == 5usize && live { os.exit(86) }
        if q == 0usize && (!live || !str.eq(dest, "http://example.org")) { os.exit(87) }
        if q == 8usize && (!live || !str.eq(dest, "mailto:me@example.org")) { os.exit(88) }
        q += 1usize
    }
    if live_count != 7usize { os.exit(89) }
    // The first word is the first link: a point on it names link 0; one beyond names none.
    let (hit_link, has_link) = mv.link_at(&live_view, 1.0, 1.0)
    if !has_link || hit_link != 0usize { os.exit(90) }
    let (_, has_none) = mv.link_at(&live_view, 9999.0, 1.0)
    if has_none { os.exit(91) }

    // Selection of two words, an invalid range, a non-text node for spans.
    let (p0, p0_error) = mv.build(doc_src(0usize), st, metrics(240.0), .DisplayOnly)
    if p0_error != ok { os.exit(92) }
    var two: [32]u8 = zero
    let (n_two, two_error) = mv.selected_text(&p0, 0usize, 1usize, two[..])
    if two_error != ok || !str.eq(two[0usize..n_two], "Title of") { os.exit(93) }
    let (_, bad_range) = mv.selected_text(&p0, 2usize, 1usize, two[..])
    if bad_range != mv.Invalid { os.exit(94) }
    let (_, tiny_error) = mv.selected_text(&p0, 0usize, 1usize, two[0usize..3usize])
    if tiny_error != mv.TooLarge { os.exit(95) }
    let (list_view, list_error) = mv.build(doc_src(1usize), st, metrics(200.0), .DisplayOnly)
    if list_error != ok { os.exit(96) }
    let (_, not_leaf) = mv.rich_spans(&list_view, 0usize, spans[..], action)
    if not_leaf != mv.Invalid { os.exit(97) }

    // Empty source: nothing, no fallback.
    let (empty, empty_error) = mv.build("", st, metrics(240.0), .DisplayOnly)
    if empty_error != ok || empty.item_count != 0usize || empty.fallback || empty.height != 0.0 { os.exit(98) }

    // Forty nested quotes pass the depth limit: the source is drawn whole, as one code line.
    var deep: [64]u8 = zero
    var k = 0usize
    while k < 40usize {
        deep[k] = 62u8
        k += 1usize
    }
    deep[40usize] = 32u8
    deep[41usize] = 120u8
    let (flat, flat_error) = mv.build(deep[0usize..42usize], st, metrics(240.0), .HostActivated)
    if flat_error != ok || !flat.fallback || flat.item_count != 1usize || flat.node_count != 1usize { os.exit(100) }
    if flat.items[0usize].len != 42usize || flat.items[0usize].w != 336.0 || flat.height != 24.0 { os.exit(101) }
    if flat.nodes[0usize].role != .Code || flat.link_count != 0usize { os.exit(102) }

    // Storage too small for the layout falls back to the plain lines: doc 0 is eleven source lines.
    var few: [12]mv.Item = zero
    let small = mv.Storage { items: few[..], nodes: nodes[..], links: links[..], store: store[..], scratch: scratch[..], blocks: blocks[..], inlines: inlines[..], words: words[..] }
    let (cut, cut_error) = mv.build(doc_src(0usize), small, metrics(240.0), .DisplayOnly)
    if cut_error != ok || !cut.fallback || cut.item_count != 11usize || cut.height != 184.0 { os.exit(103) }
    let (n_cut, cut_sel) = mv.selected_text(&cut, 0usize, 10usize, two[0usize..0usize])
    if cut_sel != mv.TooLarge || n_cut != 0usize { os.exit(104) }
    let (big, big_error) = mem.alloc[u8](a, 1024usize)
    if big_error != ok { os.exit(108) }
    let (n_big, big_sel) = mv.selected_text(&cut, 0usize, 10usize, big)
    if big_sel != ok || !str.eq(big[0usize..n_big], doc_src(0usize)) { os.exit(109) }
    // Not even the plain lines fit: the one error.
    var three: [3]mv.Item = zero
    let tiny = mv.Storage { items: three[..], nodes: nodes[..], links: links[..], store: store[..], scratch: scratch[..], blocks: blocks[..], inlines: inlines[..], words: words[..] }
    let (_, tiny_build) = mv.build(doc_src(0usize), tiny, metrics(240.0), .DisplayOnly)
    if tiny_build != mv.TooLarge { os.exit(105) }

    // Raw HTML is literal: doc 5's first paragraph shows the script tag as words.
    let (html, html_error) = mv.build(doc_src(5usize), st, metrics(240.0), .HostActivated)
    if html_error != ok || html.link_count != 0usize { os.exit(106) }
    if !str.eq(html.store[html.nodes[0usize].label_start..html.nodes[0usize].label_start + 12usize], "<script>aler") { os.exit(107) }

    try io.print("ui markdown view ok\n")
    ret ok
}
