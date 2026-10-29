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
    let (context, context_error) = script.new_context(a, &tree, "https://shadow-selection.test/")
    if context_error != ok { os.exit(2i32) }
    let check = "const host = document.createElement('div'); document.body.appendChild(host); const shadow = host.attachShadow({ mode: 'open' }); const text = document.createTextNode('abc'); shadow.appendChild(text); const selection = getSelection(); const range = document.createRange(); range.setStart(text, 0); range.setEnd(text, 1); selection.addRange(range); if (selection.rangeCount !== 1 || selection.toString() !== 'a') throw new Error('addRange rejected shadow text'); selection.collapse(text, 1); selection.extend(text, 3); if (selection.toString() !== 'bc') throw new Error('collapse or extend rejected shadow text'); selection.setBaseAndExtent(text, 0, text, 2); if (selection.toString() !== 'ab') throw new Error('setBaseAndExtent rejected shadow text'); selection.selectAllChildren(text); if (selection.toString() !== 'abc') throw new Error('selectAllChildren rejected shadow text');"
    if !script.run_script(context, check, "shadow-selection.js") { os.exit(3i32) }
    ret ok
}
