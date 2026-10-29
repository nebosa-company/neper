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
    let (context, context_error) = script.new_context(a, &tree, "https://formdata-entries.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const form = document.createElement('form'); const input = document.createElement('input'); input.setAttribute('name', 'text'); input.setAttribute('value', 'hello'); form.appendChild(input); document.body.appendChild(form); const data = new FormData(form); window.hasText = data.has('text'); window.text = data.get('text');"
    if !script.run_script(context, setup, "formdata-entries-setup.js") { os.exit(3i32) }
    let check = "if (window.hasText !== true || window.text !== 'hello') throw new Error('FormData could not read a constructed form entry');"
    if !script.run_script(context, check, "formdata-entries-check.js") { os.exit(4i32) }
    ret ok
}
