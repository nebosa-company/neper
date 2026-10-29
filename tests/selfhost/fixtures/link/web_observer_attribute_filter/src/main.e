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
    let (context, context_error) = script.new_context(a, &tree, "https://observer-filter.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const target = document.createElement('use'); window.namespacedRecords = []; const observer = new MutationObserver((records) => { window.namespacedRecords = records; }); observer.observe(target, { attributes: true, attributeFilter: ['href'] }); target.setAttributeNS('http://www.w3.org/1999/xlink', 'xlink:href', '#target');"
    if !script.run_script(context, setup, "observer-filter-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let check = "const records = window.namespacedRecords; if (records.length !== 1 || records[0].attributeName !== 'href' || records[0].attributeNamespace !== 'http://www.w3.org/1999/xlink') throw new Error('namespaced attribute filter failed');"
    if !script.run_script(context, check, "observer-filter-check.js") { os.exit(4i32) }
    ret ok
}
