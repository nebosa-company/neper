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
    let (context, context_error) = script.new_context(a, &tree, "https://foreign-relations.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const frame = document.createElement('iframe'); document.body.appendChild(frame); window.localNode = document.createElement('div'); window.foreignNode = frame.contentDocument.createElement('div');"
    if !script.run_script(context, setup, "foreign-node-relations-setup.js") { os.exit(3i32) }
    let local_contains = "window.localContains = window.localNode.contains(window.foreignNode);"
    if !script.run_script(context, local_contains, "foreign-node-relations-local-contains.js") { os.exit(4i32) }
    let foreign_contains = "window.foreignContains = window.foreignNode.contains(window.localNode);"
    if !script.run_script(context, foreign_contains, "foreign-node-relations-foreign-contains.js") { os.exit(5i32) }
    let positions = "window.outward = window.localNode.compareDocumentPosition(window.foreignNode); window.inward = window.foreignNode.compareDocumentPosition(window.localNode);"
    if !script.run_script(context, positions, "foreign-node-relations-positions.js") { os.exit(6i32) }
    let contains_check = "if (window.localContains || window.foreignContains) throw new Error('nodes from different realms are not disconnected');"
    if !script.run_script(context, contains_check, "foreign-node-relations-contains-check.js") { os.exit(7i32) }
    let disconnected_check = "const required = 1 | 32; if ((window.outward & required) !== required || (window.inward & required) !== required) throw new Error('cross-realm nodes did not report disconnected implementation-specific positions');"
    if !script.run_script(context, disconnected_check, "foreign-node-relations-disconnected-check.js") { os.exit(8i32) }
    let order_check = "if (!!(window.outward & 2) === !!(window.outward & 4) || !!(window.inward & 2) === !!(window.inward & 4)) throw new Error('cross-realm positions did not choose exactly one order bit');"
    if !script.run_script(context, order_check, "foreign-node-relations-order-check.js") { os.exit(9i32) }
    let relation_check = "if ((window.outward & 24) !== 0 || (window.inward & 24) !== 0) throw new Error('cross-realm positions had containment bits');"
    if !script.run_script(context, relation_check, "foreign-node-relations-relation-check.js") { os.exit(10i32) }
    ret ok
}
