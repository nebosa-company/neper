// `e.fmt.markdown`: the block and inline events are rendered to the HTML the CommonMark spec
// prints for its examples, and compared with the spec's own text (spec.json 0.31.2, the
// example numbers in the comments; markdown-it-py agrees on every one, see md_ref.py in the
// scratchpad). Then the spans themselves for one link. Each check exits with its own code.

use e.fmt.markdown
use e.io
use e.mem
use e.os
use e.str

error Failed

const EM: u8 = 1u8
const STRONG: u8 = 2u8
const ANCHOR: u8 = 3u8

fn escape(b: *str.Builder, text: str, breaks_to_space: bool) -> err {
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c == 38u8 {
            try str.push(b, "&amp;")
        } else if c == 60u8 {
            try str.push(b, "&lt;")
        } else if c == 62u8 {
            try str.push(b, "&gt;")
        } else if c == 34u8 {
            try str.push(b, "&quot;")
        } else if c == 10u8 && breaks_to_space {
            try str.push(b, " ")
        } else {
            try str.push(b, text[i..i + 1usize])
        }
        i += 1usize
    }
    ret ok
}

fn span(text: str, node: markdown.Inline) -> str {
    ret text[node.start..node.start + node.len]
}

fn close_tag(b: *str.Builder, tag: u8) -> err {
    if tag == EM { ret str.push(b, "</em>") }
    if tag == STRONG { ret str.push(b, "</strong>") }
    ret str.push(b, "</a>")
}

fn title_attr(b: *str.Builder, text: str, node: markdown.Inline) -> err {
    if node.title_len == 0usize { ret ok }
    try str.push(b, " title=\"")
    try escape(b, text[node.title_start..node.title_start + node.title_len], false)
    ret str.push(b, "\"")
}

// The inline spans as HTML: a container is open until the first node past its end.
fn render_inlines(b: *str.Builder, text: str, nodes: []const markdown.Inline) -> err {
    var ends: [32]usize = zero
    var tags: [32]u8 = zero
    var depth = 0usize
    var i = 0usize
    while i < nodes.len {
        let node = nodes[i]
        while depth > 0usize && ends[depth - 1usize] <= node.start {
            depth -= 1usize
            try close_tag(b, tags[depth])
        }
        if node.kind == .Text {
            try escape(b, span(text, node), false)
        } else if node.kind == .Code {
            try str.push(b, "<code>")
            try escape(b, span(text, node), true)
            try str.push(b, "</code>")
        } else if node.kind == .Emph || node.kind == .Strong {
            if node.kind == .Emph { try str.push(b, "<em>") } else { try str.push(b, "<strong>") }
            ends[depth] = node.start + node.len
            tags[depth] = EM
            if node.kind == .Strong { tags[depth] = STRONG }
            depth += 1usize
        } else if node.kind == .Link {
            try str.push(b, "<a href=\"")
            try escape(b, text[node.extra_start..node.extra_start + node.extra_len], false)
            try str.push(b, "\"")
            try title_attr(b, text, node)
            try str.push(b, ">")
            ends[depth] = node.start + node.len
            tags[depth] = ANCHOR
            depth += 1usize
        } else if node.kind == .Image {
            try str.push(b, "<img src=\"")
            try escape(b, text[node.extra_start..node.extra_start + node.extra_len], false)
            try str.push(b, "\" alt=\"")
            // The alt text is the contents, plain.
            var j = i + 1usize
            while j < nodes.len && nodes[j].start < node.start + node.len {
                if nodes[j].kind == .Text || nodes[j].kind == .Code { try escape(b, span(text, nodes[j]), false) }
                j += 1usize
            }
            try str.push(b, "\"")
            try title_attr(b, text, node)
            try str.push(b, " />")
            i = j
            continue
        } else if node.kind == .Autolink || node.kind == .Email {
            try str.push(b, "<a href=\"")
            if node.kind == .Email { try str.push(b, "mailto:") }
            try escape(b, span(text, node), false)
            try str.push(b, "\">")
            try escape(b, span(text, node), false)
            try str.push(b, "</a>")
        } else if node.kind == .SoftBreak {
            try str.push(b, "\n")
        } else {
            try str.push(b, "<br />\n")
        }
        i += 1usize
    }
    while depth > 0usize {
        depth -= 1usize
        try close_tag(b, tags[depth])
    }
    ret ok
}

// The lines of a leaf, joined by `\n` into `joined`; the index of the end event.
fn join_lines(text: str, blocks: []const markdown.Block, from: usize, joined: []u8) -> (usize, usize, err) {
    var used = 0usize
    var i = from
    while blocks[i].kind == .Line {
        if used > 0usize {
            if used >= joined.len { ret (0usize, 0usize, Failed) }
            joined[used] = 10u8
            used += 1usize
        }
        let line = text[blocks[i].start..blocks[i].start + blocks[i].len]
        if used + line.len > joined.len { ret (0usize, 0usize, Failed) }
        var k = 0usize
        while k < line.len {
            joined[used + k] = line[k]
            k += 1usize
        }
        used += line.len
        i += 1usize
    }
    ret (used, i, ok)
}

fn inline_html(b: *str.Builder, text: str, blocks: []const markdown.Block, from: usize) -> (usize, err) {
    var joined: [512]u8 = zero
    var nodes: [64]markdown.Inline = zero
    let (used, end, join_error) = join_lines(text, blocks, from, joined[..])
    if join_error != ok { ret (0usize, join_error) }
    let (count, inline_error) = markdown.parse_inlines(joined[0usize..used], nodes[..])
    if inline_error != ok { ret (0usize, inline_error) }
    let render_error = render_inlines(b, joined[0usize..used], nodes[0usize..count])
    ret (end, render_error)
}

fn code_html(b: *str.Builder, text: str, blocks: []const markdown.Block, from: usize) -> (usize, err) {
    var i = from
    while blocks[i].kind == .Line {
        let escape_error = escape(b, text[blocks[i].start..blocks[i].start + blocks[i].len], false)
        if escape_error != ok { ret (0usize, escape_error) }
        let push_error = str.push(b, "\n")
        if push_error != ok { ret (0usize, push_error) }
        i += 1usize
    }
    ret (i, ok)
}

// The block events as HTML. A paragraph directly in a tight item has no `<p>`, and a block
// after it in the same item starts on a new line.
fn render_blocks(b: *str.Builder, text: str, blocks: []const markdown.Block) -> err {
    var item_tight: [32]bool = zero
    var is_item: [32]bool = zero
    var list_loose: [32]bool = zero
    var depth = 0usize
    var after_tight = false
    var i = 0usize
    while i < blocks.len {
        let block = blocks[i]
        let kind = block.kind
        let in_tight = depth > 0usize && is_item[depth - 1usize] && item_tight[depth - 1usize]
        if after_tight && kind != .ParagraphStart && kind != .ItemEnd {
            try str.push(b, "\n")
        }
        after_tight = false
        if kind == .ParagraphStart {
            if !in_tight { try str.push(b, "<p>") }
            let (end, e) = inline_html(b, text, blocks, i + 1usize)
            if e != ok { ret e }
            if in_tight {
                after_tight = true
            } else {
                try str.push(b, "</p>\n")
            }
            i = end + 1usize
            continue
        }
        if kind == .HeadingStart {
            var tag: [4]u8 = zero
            tag[0usize] = 104u8
            tag[1usize] = 48u8 + u8(block.level)
            try str.push(b, "<")
            try str.push(b, tag[0usize..2usize])
            try str.push(b, ">")
            let (end, e) = inline_html(b, text, blocks, i + 1usize)
            if e != ok { ret e }
            try str.push(b, "</")
            try str.push(b, tag[0usize..2usize])
            try str.push(b, ">\n")
            i = end + 1usize
            continue
        }
        if kind == .FencedCodeStart || kind == .IndentedCodeStart {
            try str.push(b, "<pre><code")
            if block.extra_len > 0usize {
                var word = block.extra_start
                while word < block.extra_start + block.extra_len && text[word] != 32u8 { word += 1usize }
                try str.push(b, " class=\"language-")
                try escape(b, text[block.extra_start..word], false)
                try str.push(b, "\"")
            }
            try str.push(b, ">")
            let (end, e) = code_html(b, text, blocks, i + 1usize)
            if e != ok { ret e }
            try str.push(b, "</code></pre>\n")
            i = end + 1usize
            continue
        }
        if kind == .ThematicBreak {
            try str.push(b, "<hr />\n")
        } else if kind == .BlockQuoteStart {
            try str.push(b, "<blockquote>\n")
            is_item[depth] = false
            depth += 1usize
        } else if kind == .BlockQuoteEnd {
            try str.push(b, "</blockquote>\n")
            depth -= 1usize
        } else if kind == .BulletListStart || kind == .OrderedListStart {
            if kind == .BulletListStart {
                try str.push(b, "<ul>\n")
            } else {
                try str.push(b, "<ol")
                if block.level != 1u32 {
                    try str.push(b, " start=\"")
                    try str.push_u32(b, block.level)
                    try str.push(b, "\"")
                }
                try str.push(b, ">\n")
            }
            is_item[depth] = false
            list_loose[depth] = block.loose
            depth += 1usize
        } else if kind == .BulletListEnd {
            try str.push(b, "</ul>\n")
            depth -= 1usize
        } else if kind == .OrderedListEnd {
            try str.push(b, "</ol>\n")
            depth -= 1usize
        } else if kind == .ItemStart {
            try str.push(b, "<li>")
            is_item[depth] = true
            item_tight[depth] = !list_loose[depth - 1usize]
            if list_loose[depth - 1usize] { try str.push(b, "\n") }
            depth += 1usize
        } else if kind == .ItemEnd {
            try str.push(b, "</li>\n")
            depth -= 1usize
        } else {
            ret Failed
        }
        i += 1usize
    }
    ret ok
}

fn render(a: *mem.Arena, source: str) -> (str, err) {
    var blocks: [128]markdown.Block = zero
    let (count, block_error) = markdown.parse_blocks(source, blocks[..])
    if block_error != ok { ret ("", block_error) }
    let (builder, builder_error) = str.builder(a, 2048usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = builder
    let render_error = render_blocks(&b, source, blocks[0usize..count])
    if render_error != ok { ret ("", render_error) }
    ret (str.done(&b), ok)
}

// One spec example: its markdown rendered here against the HTML the spec prints.
fn check(a: *mem.Arena, source: str, expected: str, code: i32) -> err {
    let (html, render_error) = render(a, source)
    if render_error != ok {
        try io.print("render failed\n")
        os.exit(code)
    }
    if !str.eq(html, expected) {
        try io.print("--- got:\n")
        try io.print(html)
        try io.print("--- expected:\n")
        try io.print(expected)
        os.exit(code)
    }
    ret ok
}


fn main(a: *mem.Arena, args: []str) -> err {
    // --- Inlines.
    try check(a, "\\!\\\"\\#\\$\\%\\&\\'\\(\\)\\*\\+\\,\\-\\.\\/\\:\\;\\<\\=\\>\\?\\@\\[\\\\\\]\\^\\_\\`\\{\\|\\}\\~\n", "<p>!&quot;#$%&amp;'()*+,-./:;&lt;=&gt;?@[\\]^_`{|}~</p>\n", 1i32) // example 12
    try check(a, "\\*not emphasized*\n\\<br/> not a tag\n\\[not a link](/foo)\n\\`not code`\n1\\. not a list\n\\* not a list\n\\# not a heading\n\\[foo]: /url \"not a reference\"\n\\&ouml; not a character entity\n", "<p>*not emphasized*\n&lt;br/&gt; not a tag\n[not a link](/foo)\n`not code`\n1. not a list\n* not a list\n# not a heading\n[foo]: /url &quot;not a reference&quot;\n&amp;ouml; not a character entity</p>\n", 2i32) // example 14
    try check(a, "`foo`\n", "<p><code>foo</code></p>\n", 3i32) // example 328
    try check(a, "`` foo ` bar ``\n", "<p><code>foo ` bar</code></p>\n", 4i32) // example 329
    try check(a, "`  ``  `\n", "<p><code> `` </code></p>\n", 5i32) // example 331
    try check(a, "` a`\n", "<p><code> a</code></p>\n", 6i32) // example 332
    try check(a, "`foo   bar \nbaz`\n", "<p><code>foo   bar  baz</code></p>\n", 7i32) // example 337
    try check(a, "*foo bar*\n", "<p><em>foo bar</em></p>\n", 8i32) // example 350
    try check(a, "a * foo bar*\n", "<p>a * foo bar*</p>\n", 9i32) // example 351
    try check(a, "a*\"foo\"*\n", "<p>a*&quot;foo&quot;*</p>\n", 10i32) // example 352
    try check(a, "_ foo bar_\n", "<p>_ foo bar_</p>\n", 11i32) // example 358
    try check(a, "foo_bar_\n", "<p>foo_bar_</p>\n", 12i32) // example 360
    try check(a, "*foo bar\n*\n", "<p>*foo bar\n*</p>\n", 13i32) // example 367
    try check(a, "_foo bar _\n", "<p>_foo bar _</p>\n", 14i32) // example 371
    try check(a, "_(_foo_)_\n", "<p><em>(<em>foo</em>)</em></p>\n", 15i32) // example 373
    try check(a, "**foo bar**\n", "<p><strong>foo bar</strong></p>\n", 16i32) // example 378
    try check(a, "**foo bar **\n", "<p>**foo bar **</p>\n", 17i32) // example 391
    try check(a, "**foo**bar\n", "<p><strong>foo</strong>bar</p>\n", 18i32) // example 396
    try check(a, "__foo__bar__baz__\n", "<p><strong>foo__bar__baz</strong></p>\n", 19i32) // example 402
    try check(a, "*foo**bar**baz*\n", "<p><em>foo<strong>bar</strong>baz</em></p>\n", 20i32) // example 411
    try check(a, "*foo **bar *baz* bim** bop*\n", "<p><em>foo <strong>bar <em>baz</em> bim</strong> bop</em></p>\n", 21i32) // example 418
    try check(a, "** is not an empty emphasis\n", "<p>** is not an empty emphasis</p>\n", 22i32) // example 420
    try check(a, "__foo _bar_ baz__\n", "<p><strong>foo <em>bar</em> baz</strong></p>\n", 23i32) // example 424
    try check(a, "**foo *bar* baz**\n", "<p><strong>foo <em>bar</em> baz</strong></p>\n", 24i32) // example 428
    try check(a, "**foo *bar***\n", "<p><strong>foo <em>bar</em></strong></p>\n", 25i32) // example 431
    try check(a, "foo ***\n", "<p>foo ***</p>\n", 26i32) // example 436
    try check(a, "**foo*\n", "<p>*<em>foo</em></p>\n", 27i32) // example 442
    try check(a, "***foo**\n", "<p>*<strong>foo</strong></p>\n", 28i32) // example 444
    try check(a, "****foo*\n", "<p>***<em>foo</em></p>\n", 29i32) // example 445
    try check(a, "*foo****\n", "<p><em>foo</em>***</p>\n", 30i32) // example 447
    try check(a, "___foo__\n", "<p>_<strong>foo</strong></p>\n", 31i32) // example 456
    try check(a, "__foo___\n", "<p><strong>foo</strong>_</p>\n", 32i32) // example 458
    try check(a, "[link](/uri \"title\")\n", "<p><a href=\"/uri\" title=\"title\">link</a></p>\n", 33i32) // example 482
    try check(a, "[link](/uri)\n", "<p><a href=\"/uri\">link</a></p>\n", 34i32) // example 483
    try check(a, "[link]()\n", "<p><a href=\"\">link</a></p>\n", 35i32) // example 485
    try check(a, "[link](foo(and(bar))\n", "<p>[link](foo(and(bar))</p>\n", 36i32) // example 497
    try check(a, "[link](/url \"title\")\n[link](/url 'title')\n[link](/url (title))\n", "<p><a href=\"/url\" title=\"title\">link</a>\n<a href=\"/url\" title=\"title\">link</a>\n<a href=\"/url\" title=\"title\">link</a></p>\n", 37i32) // example 505
    try check(a, "[link](/url \"title \"and\" title\")\n", "<p>[link](/url &quot;title &quot;and&quot; title&quot;)</p>\n", 38i32) // example 508
    try check(a, "*foo [bar* baz]\n", "<p><em>foo [bar</em> baz]</p>\n", 39i32) // example 523
    try check(a, "![foo](/url \"title\")\n", "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>\n", 40i32) // example 572
    try check(a, "<http://foo.bar.baz>\n", "<p><a href=\"http://foo.bar.baz\">http://foo.bar.baz</a></p>\n", 41i32) // example 594
    try check(a, "<irc://foo.bar:2233/baz>\n", "<p><a href=\"irc://foo.bar:2233/baz\">irc://foo.bar:2233/baz</a></p>\n", 42i32) // example 596
    try check(a, "<foo+special@Bar.baz-bar0.com>\n", "<p><a href=\"mailto:foo+special@Bar.baz-bar0.com\">foo+special@Bar.baz-bar0.com</a></p>\n", 43i32) // example 605
    try check(a, "foo  \nbaz\n", "<p>foo<br />\nbaz</p>\n", 44i32) // example 633
    try check(a, "foo\\\nbaz\n", "<p>foo<br />\nbaz</p>\n", 45i32) // example 634
    try check(a, "foo  \n     bar\n", "<p>foo<br />\nbar</p>\n", 46i32) // example 636
    try check(a, "*foo  \nbar*\n", "<p><em>foo<br />\nbar</em></p>\n", 47i32) // example 638
    try check(a, "`code\\\nspan`\n", "<p><code>code\\ span</code></p>\n", 48i32) // example 641
    try check(a, "foo\\\n", "<p>foo\\</p>\n", 49i32) // example 644
    // --- Blocks.
    try check(a, "***\n---\n___\n", "<hr />\n<hr />\n<hr />\n", 50i32) // example 43
    try check(a, "+++\n", "<p>+++</p>\n", 51i32) // example 44
    try check(a, "===\n", "<p>===</p>\n", 52i32) // example 45
    try check(a, " ***\n  ***\n   ***\n", "<hr />\n<hr />\n<hr />\n", 53i32) // example 47
    try check(a, "    ***\n", "<pre><code>***\n</code></pre>\n", 54i32) // example 48
    try check(a, "# foo\n## foo\n### foo\n#### foo\n##### foo\n###### foo\n", "<h1>foo</h1>\n<h2>foo</h2>\n<h3>foo</h3>\n<h4>foo</h4>\n<h5>foo</h5>\n<h6>foo</h6>\n", 55i32) // example 62
    try check(a, "####### foo\n", "<p>####### foo</p>\n", 56i32) // example 63
    try check(a, "\\## foo\n", "<p>## foo</p>\n", 57i32) // example 65
    try check(a, " ### foo\n  ## foo\n   # foo\n", "<h3>foo</h3>\n<h2>foo</h2>\n<h1>foo</h1>\n", 58i32) // example 68
    try check(a, "## foo ##\n  ###   bar    ###\n", "<h2>foo</h2>\n<h3>bar</h3>\n", 59i32) // example 71
    try check(a, "### foo ### b\n", "<h3>foo ### b</h3>\n", 60i32) // example 74
    try check(a, "Foo *bar*\n=========\n\nFoo *bar*\n---------\n", "<h1>Foo <em>bar</em></h1>\n<h2>Foo <em>bar</em></h2>\n", 61i32) // example 80
    try check(a, "Foo *bar\nbaz*\n====\n", "<h1>Foo <em>bar\nbaz</em></h1>\n", 62i32) // example 81
    try check(a, "Foo\n-------------------------\n\nFoo\n=\n", "<h2>Foo</h2>\n<h1>Foo</h1>\n", 63i32) // example 83
    try check(a, "Foo\n    ---\n", "<p>Foo\n---</p>\n", 64i32) // example 87
    try check(a, "---\nFoo\n---\nBar\n---\nBaz\n", "<hr />\n<h2>Foo</h2>\n<h2>Bar</h2>\n<p>Baz</p>\n", 65i32) // example 96
    try check(a, "    a simple\n      indented code block\n", "<pre><code>a simple\n  indented code block\n</code></pre>\n", 66i32) // example 107
    try check(a, "  - foo\n\n    bar\n", "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n", 67i32) // example 108
    try check(a, "    chunk1\n\n    chunk2\n  \n \n \n    chunk3\n", "<pre><code>chunk1\n\nchunk2\n\n\n\nchunk3\n</code></pre>\n", 68i32) // example 111
    try check(a, "```\n<\n >\n```\n", "<pre><code>&lt;\n &gt;\n</code></pre>\n", 69i32) // example 119
    try check(a, "``\nfoo\n``\n", "<p><code>foo</code></p>\n", 70i32) // example 121
    try check(a, "~~~~\naaa\n~~~\n~~~~\n", "<pre><code>aaa\n~~~\n</code></pre>\n", 71i32) // example 125
    try check(a, "`````\n\n```\naaa\n", "<pre><code>\n```\naaa\n</code></pre>\n", 72i32) // example 127
    try check(a, " ```\n aaa\naaa\n```\n", "<pre><code>aaa\naaa\n</code></pre>\n", 73i32) // example 131
    try check(a, "``` ```\naaa\n", "<p><code> </code>\naaa</p>\n", 74i32) // example 138
    try check(a, "```ruby\ndef foo(x)\n  return 3\nend\n```\n", "<pre><code class=\"language-ruby\">def foo(x)\n  return 3\nend\n</code></pre>\n", 75i32) // example 142
    try check(a, "> # Foo\n> bar\n> baz\n", "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n", 76i32) // example 228
    try check(a, "># Foo\n>bar\n> baz\n", "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n", 77i32) // example 229
    try check(a, "> # Foo\n> bar\nbaz\n", "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n", 78i32) // example 232
    try check(a, "> ```\nfoo\n```\n", "<blockquote>\n<pre><code></code></pre>\n</blockquote>\n<p>foo</p>\n<pre><code></code></pre>\n", 79i32) // example 237
    try check(a, "> foo\n    - bar\n", "<blockquote>\n<p>foo\n- bar</p>\n</blockquote>\n", 80i32) // example 238
    try check(a, "A paragraph\nwith two lines.\n\n    indented code\n\n> A block quote.\n", "<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n", 81i32) // example 253
    try check(a, "-one\n\n2.two\n", "<p>-one</p>\n<p>2.two</p>\n", 82i32) // example 261
    try check(a, "- foo\n\n\n  bar\n", "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n", 83i32) // example 262
    try check(a, "123456789. ok\n", "<ol start=\"123456789\">\n<li>ok</li>\n</ol>\n", 84i32) // example 265
    try check(a, "1234567890. not ok\n", "<p>1234567890. not ok</p>\n", 85i32) // example 266
    try check(a, "- foo\n\n      bar\n", "<ul>\n<li>\n<p>foo</p>\n<pre><code>bar\n</code></pre>\n</li>\n</ul>\n", 86i32) // example 270
    try check(a, "  10.  foo\n\n           bar\n", "<ol start=\"10\">\n<li>\n<p>foo</p>\n<pre><code>bar\n</code></pre>\n</li>\n</ol>\n", 87i32) // example 271
    try check(a, "   foo\n\nbar\n", "<p>foo</p>\n<p>bar</p>\n", 88i32) // example 275
    try check(a, "- foo\n-\n- bar\n", "<ul>\n<li>foo</li>\n<li></li>\n<li>bar</li>\n</ul>\n", 89i32) // example 281
    try check(a, "- foo\n- bar\n+ baz\n", "<ul>\n<li>foo</li>\n<li>bar</li>\n</ul>\n<ul>\n<li>baz</li>\n</ul>\n", 90i32) // example 301
    try check(a, "The number of windows in my house is\n14.  The number of doors is 6.\n", "<p>The number of windows in my house is\n14.  The number of doors is 6.</p>\n", 91i32) // example 304
    try check(a, "The number of windows in my house is\n1.  The number of doors is 6.\n", "<p>The number of windows in my house is</p>\n<ol>\n<li>The number of doors is 6.</li>\n</ol>\n", 92i32) // example 305
    try check(a, "- foo\n  - bar\n    - baz\n\n\n      bim\n", "<ul>\n<li>foo\n<ul>\n<li>bar\n<ul>\n<li>\n<p>baz</p>\n<p>bim</p>\n</li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n", 93i32) // example 307
    try check(a, "- a\n- b\n\n- c\n", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>\n", 94i32) // example 314
    try check(a, "- a\n- b\n\n  c\n- d\n", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n<p>c</p>\n</li>\n<li>\n<p>d</p>\n</li>\n</ul>\n", 95i32) // example 316
    try check(a, "- a\n  - b\n\n    c\n- d\n", "<ul>\n<li>a\n<ul>\n<li>\n<p>b</p>\n<p>c</p>\n</li>\n</ul>\n</li>\n<li>d</li>\n</ul>\n", 96i32) // example 319
    try check(a, "* a\n  > b\n  >\n* c\n", "<ul>\n<li>a\n<blockquote>\n<p>b</p>\n</blockquote>\n</li>\n<li>c</li>\n</ul>\n", 97i32) // example 320

    // 98-99: the spans themselves. A link's content, destination and title are each a span
    // over the input (offsets from Python str.index in md_ref.py).
    var nodes: [8]markdown.Inline = zero
    let (count, inline_error) = markdown.parse_inlines("[link](/uri \"title\")", nodes[..])
    if inline_error != ok || count != 2usize { os.exit(98i32) }
    let link = nodes[0usize]
    if link.kind != .Link || link.start != 1usize || link.len != 4usize || link.extra_start != 7usize || link.extra_len != 4usize || link.title_start != 13usize || link.title_len != 5usize { os.exit(99i32) }
    if nodes[1usize].kind != .Text || nodes[1usize].start != 1usize || nodes[1usize].len != 4usize { os.exit(99i32) }

    // 100: an output array too small is `TooLarge`, not a silent cut.
    var few: [2]markdown.Block = zero
    let (_, small_error) = markdown.parse_blocks("# a\n", few[..])
    if small_error != markdown.TooLarge { os.exit(100i32) }

    try io.print("fmt markdown ok\n")
    ret ok
}
