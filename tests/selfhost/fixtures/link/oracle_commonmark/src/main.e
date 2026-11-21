// e.fmt.commonmark against R's commonmark (cmark-gfm): html, xml, latex and man over every CommonMark spec
// example, the GFM extension examples (tables, strikethrough, autolink, tasklist, tagfilter), the smart
// punctuation examples and the cmark regression examples, with source positions, hard breaks, smart
// punctuation and line widths. tests/oracle/commonmark.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R commonmark`. A case holds the markdown ("in"),
// the renderer (fn) and the options (args: hardbreaks, smart, normalize, sourcepos, footnotes, width,
// extension mask where table=1 strikethrough=2 autolink=4 tagfilter=8 tasklist=16); the answer is the
// rendered text, compared exactly.

use e.io
use e.mem
use e.os
use e.str
use e.fmt.commonmark as cm
use e.test.oracle as oracle

fn options(args: []f64) -> cm.Options {
    let mask = i64(args[6usize])
    var o: cm.Options = zero
    o.hardbreaks = args[0usize] != 0.0f64
    o.smart = args[1usize] != 0.0f64
    o.sourcepos = args[3usize] != 0.0f64
    o.width = i32(args[5usize])
    o.table = (mask & 1i64) != 0i64
    o.strikethrough = (mask & 2i64) != 0i64
    o.autolink = (mask & 4i64) != 0i64
    o.tagfilter = (mask & 8i64) != 0i64
    o.tasklist = (mask & 16i64) != 0i64
    ret o
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> str {
    let o = options(c.args)
    let text = c.inputs[0usize]
    var out = ""
    var e = ok
    if str.eq(c.name, "html") {
        let (r, re) = cm.render_html(a, text, o)
        out = r
        e = re
    } else {
        if str.eq(c.name, "xml") {
            let (r, re) = cm.render_xml(a, text, o)
            out = r
            e = re
        } else {
            if str.eq(c.name, "latex") {
                let (r, re) = cm.render_latex(a, text, o)
                out = r
                e = re
            } else {
                let (r, re) = cm.render_man(a, text, o)
                out = r
                e = re
            }
        }
    }
    if e != ok { os.exit(7) }
    ret out
}

fn print_count(a: *mem.Arena, n: usize) {
    let (initial, be) = str.builder(a, 24usize)
    if be != ok { os.exit(5) }
    var b = initial
    let _ = str.push_usize(&b, n)
    let _ = io.print(str.done(&b))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/commonmark.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let text = answer(a, c)
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 6usize {
                let _ = io.print(c.name)
                let _ = io.print(" ")
                let _ = io.print("\n in ")
                let _ = io.print(c.inputs[0usize])
                let _ = io.print("\n got ")
                let _ = io.print(text)
                let _ = io.print("\n  R  ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    let _ = io.print("failures: ")
    print_count(a, failures)
    let _ = io.print(" of ")
    print_count(a, golden.cases.len)
    let _ = io.print("\n")
    if failures > 0usize { os.exit(1) }
    ret ok
}
