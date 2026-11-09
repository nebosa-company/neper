use e.fmt.dom as dom
use e.fmt.html as html
use e.mem
use e.os
use e.web.script as script

fn main(a: *mem.Arena, args: []str) -> err {
    let options = html.Options { max_bytes: 1048576usize, max_nodes: 4096usize, max_attributes: 64usize, max_depth: 64u16, preserve_comments: false }
    let (parsed, parse_error) = dom.parse(a, "<!doctype html><html><body></body></html>", options, 32usize)
    if parse_error != ok { os.exit(1i32) }
    var tree = parsed
    let (context, context_error) = script.new_context(a, &tree, "https://static-range.test/")
    if context_error != ok { os.exit(2i32) }
    let check = "const text = document.createTextNode('ok'); const past = new StaticRange({ startContainer: text, startOffset: 3, endContainer: text, endOffset: 2 }); if (past.startOffset !== 3 || past.endOffset !== 2 || past.collapsed) throw new Error('StaticRange rejected or changed offsets past the node length');"
    if !script.run_script(context, check, "static-range-bounds.js") { os.exit(3i32) }
    ret ok
}
