// html5lib tree-construction runner for e.fmt.html (browser tracker 0.6).
//
//   neper run tests/browser/html5lib/run.e <toolchain-root> x64 windows <out.exe> --json --capture 4194304 -- [--show] FILE.dat...
//   or: tests/browser/html5lib/run.sh [--show] [files...]
//
// Each case parses `#data` through e.fmt.html, serializes the tree in html5lib's
// `#document` format and compares it with the expected block, exactly as the Dart
// runner did (vaper/packages/vaper_engine_core/test/conformance/html5lib_runner.dart),
// so the totals are comparable with its 1549 of 1791. `basic.dat` is skipped, as there.
// Fragment cases (`#document-fragment`) run through html.parse_fragment. `--show` prints every failing case. Exits 0 as a
// measurement unless `--floor N` is given: then it fails when fewer than N cases pass.
// run.sh passes the recorded floor for the whole corpus.
//
// ponytail: an element with more than 64 attributes prints them unsorted.

use e.fmt.html
use e.fs
use e.io
use e.mem
use e.str

const MAX_ATTRS: usize = 64usize

error BelowFloor

type Counts = struct { total: usize, pass: usize, fragment: usize, errored: usize, trace: bool }

fn put_indent(b: *str.Builder, depth: usize) -> err {
    try str.push(b, "| ")
    try str.push_repeated(b, "  ", depth)
    ret ok
}

fn emit_children(b: *str.Builder, doc: *const html.Document, parent: html.NodeId, depth: usize) -> err {
    var it = html.children(doc, parent)
    while true {
        let (child, more) = html.children_next(&it)
        if !more { break }
        try emit_node(b, doc, child, depth)
    }
    ret ok
}

fn emit_node(b: *str.Builder, doc: *const html.Document, id: html.NodeId, depth: usize) -> err {
    let node = html.node(doc, id)
    try put_indent(b, depth)
    if node.kind == .Text {
        try str.push(b, "\"")
        try str.push(b, node.value)
        try str.push(b, "\"\n")
        ret ok
    }
    if node.kind == .Comment {
        try str.push(b, "<!-- ")
        try str.push(b, node.value)
        try str.push(b, " -->\n")
        ret ok
    }
    if node.kind == .Doctype {
        try str.push(b, "<!DOCTYPE ")
        try str.push(b, node.name)
        let pub_id = html.doctype_public(node)
        let sys_id = html.doctype_system(node)
        if pub_id.len > 0usize || sys_id.len > 0usize {
            try str.push(b, " \"")
            try str.push(b, pub_id)
            try str.push(b, "\" \"")
            try str.push(b, sys_id)
            try str.push(b, "\"")
        }
        try str.push(b, ">\n")
        ret ok
    }
    try str.push(b, "<")
    if node.namespace == .Svg { try str.push(b, "svg ") }
    if node.namespace == .MathMl { try str.push(b, "math ") }
    try str.push(b, node.name)
    try str.push(b, ">\n")
    var order: [64]usize = zero
    var count = node.attributes.len
    if count > MAX_ATTRS { count = MAX_ATTRS }
    var i = 0usize
    while i < count {
        var j = i
        while j > 0usize && str.compare(node.attributes[order[j - 1usize]].name, node.attributes[i].name) > 0i32 {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = i
        i += 1usize
    }
    i = 0usize
    while i < count {
        let attr = &node.attributes[order[i]]
        try put_indent(b, depth + 1usize)
        if attr.namespace == .Xlink { try str.push(b, "xlink ") }
        if attr.namespace == .Xml { try str.push(b, "xml ") }
        if attr.namespace == .Xmlns && !str.eq(attr.name, "xmlns") { try str.push(b, "xmlns ") }
        try str.push(b, attr.name)
        try str.push(b, "=\"")
        try str.push(b, attr.value)
        try str.push(b, "\"\n")
        i += 1usize
    }
    if node.namespace == .Html && str.eq(node.name, "template") {
        try put_indent(b, depth + 1usize)
        try str.push(b, "content\n")
        ret emit_children(b, doc, id, depth + 2usize)
    }
    ret emit_children(b, doc, id, depth + 1usize)
}

// Parses `input` and reports whether its serialized tree equals `expected`. The arena is
// handed back to its mark by the caller.
fn run_case(a: *mem.Arena, input: str, expected: str, context: str, fragment: bool, scripting: bool, show: bool) -> (bool, err) {
    let options = html.Options { max_bytes: 262144usize, max_nodes: 8192usize, max_attributes: 64usize, max_depth: 512u16, preserve_comments: true }
    var doc: html.Document = zero
    var parse_error: err = ok
    if fragment {
        var ns: html.Namespace = .Html
        var name = context
        if str.starts_with(context, "svg ") {
            ns = .Svg
            name = context[4usize..]
        }
        if str.starts_with(context, "math ") {
            ns = .MathMl
            name = context[5usize..]
        }
        let (made, made_error) = html.parse_fragment_with(a, input, name, ns, options, scripting)
        doc = made
        parse_error = made_error
    } else {
        let (made, made_error) = html.parse_with(a, input, options, scripting)
        doc = made
        parse_error = made_error
    }
    if parse_error != ok { ret (false, parse_error) }
    var b = try str.builder(a, 4096usize)
    try emit_children(&b, &doc, doc.root, 0usize)
    let actual = str.trim_end(str.done(&b))
    let matched = str.eq(actual, expected)
    if !matched && show {
        try io.printf["--- input: {}\n--- expected:\n{}\n--- actual:\n{}\n"](input, expected, actual)
    }
    ret (matched, ok)
}

fn finish_case(a: *mem.Arena, source: str, tc: *Case, counts: *Counts, show: bool) -> err {
    if !tc.open { ret ok }
    counts.total += 1usize
    if tc.fragment { counts.fragment += 1usize }
    let expected = str.trim_end(source[tc.doc_lo..tc.doc_hi])
    let mark = mem.mark(a)
    defer mem.reset(a, mark)
    if counts.trace { try io.printf["TRACE {}\n"](source[tc.data_lo..tc.data_hi]) }
    let (matched, run_error) = run_case(a, source[tc.data_lo..tc.data_hi], expected, str.trim(source[tc.ctx_lo..tc.ctx_hi]), tc.fragment, tc.scripting, show)
    if run_error != ok {
        counts.errored += 1usize
        ret ok
    }
    if matched { counts.pass += 1usize }
    ret ok
}

type Case = struct { open: bool, fragment: bool, data_lo: usize, data_hi: usize, doc_lo: usize, doc_hi: usize, ctx_lo: usize, ctx_hi: usize, scripting: bool }

// 1 data, 2 document, 0 anything else (errors, script flags, fragment context).
fn scan_file(a: *mem.Arena, source: str, counts: *Counts, show: bool) -> err {
    var tc: Case = zero
    var section = 0u8
    var off = 0usize
    // Lines end at LF only: a CR inside a data line is part of the test input.
    while off < source.len {
        var eol = off
        while eol < source.len && source[eol] != 10u8 { eol += 1usize }
        let line = source[off..eol]
        let next = eol + 1usize
        if line.len > 0usize && line[0usize] == 35u8 {
            if str.eq(line, "#data") {
                try finish_case(a, source, &tc, counts, show)
                tc = Case { open: true, fragment: false, data_lo: next, data_hi: next, doc_lo: next, doc_hi: next, ctx_lo: 0usize, ctx_hi: 0usize, scripting: false }
                section = 1u8
            } else if str.eq(line, "#document") {
                section = 2u8
                tc.doc_lo = next
                tc.doc_hi = next
            } else {
                if str.eq(line, "#script-on") { tc.scripting = true }
                if str.starts_with(line, "#document-fragment") {
                    tc.fragment = true
                    section = 3u8
                } else {
                    section = 0u8
                }
            }
        } else if section == 1u8 {
            tc.data_hi = off + line.len
        } else if section == 2u8 {
            tc.doc_hi = off + line.len
        } else if section == 3u8 {
            tc.ctx_lo = off
            tc.ctx_hi = off + line.len
            section = 0u8
        }
        off = next
    }
    ret finish_case(a, source, &tc, counts, show)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var show = false
    var trace = false
    var floor = 0usize
    var all: Counts = zero
    var i = 0usize
    while i < args.len {
        let name = args[i]
        i += 1usize
        if str.eq(name, "--trace") {
            trace = true
            continue
        }
        if str.eq(name, "--floor") {
            if i < args.len {
                let (value, parse_error) = str.parse_u64(args[i])
                if parse_error == ok { floor = usize(value) }
            }
            i += 1usize
            continue
        }
        if str.eq(name, "--show") {
            show = true
            continue
        }
        if !str.ends_with(name, ".dat") || str.ends_with(name, "basic.dat") { continue }
        let mark = mem.mark(a)
        let (bytes, read_error) = fs.read_file(a, name, 4194304usize)
        if read_error != ok {
            try io.printf["{}: unreadable\n"](name)
            mem.reset(a, mark)
            continue
        }
        var file_counts: Counts = zero
        file_counts.trace = trace
        try scan_file(a, bytes, &file_counts, show)
        try io.printf["{} {}/{} (fragment {}, errored {})\n"](name, file_counts.pass, file_counts.total, file_counts.fragment, file_counts.errored)
        all.total += file_counts.total
        all.pass += file_counts.pass
        all.fragment += file_counts.fragment
        all.errored += file_counts.errored
        mem.reset(a, mark)
    }
    try io.printf["TOTAL {}/{} (fragment {}, errored {})\n"](all.pass, all.total, all.fragment, all.errored)
    if all.pass < floor { ret BelowFloor }
    ret ok
}
