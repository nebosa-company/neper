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
    let (context, context_error) = script.new_context(a, &tree, "https://xml-entities.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const parser = new DOMParser(); const parse = markup => parser.parseFromString(markup, 'application/xml').documentElement.localName; window.xmlEntityNames = ['<r>&broken</r>', '<r>&#12</r>', '<r a=\"&broken\"></r>', '<r a=\"& foo;\"></r>', '<r>&unknown;</r>'].map(parse); window.xmlEntityText = parser.parseFromString('<r>&amp;&#65;&#x42;</r>', 'application/xml').documentElement.textContent;"
    if !script.run_script(context, setup, "xml-entity-errors-setup.js") { os.exit(3i32) }
    let check = "if (window.xmlEntityNames.some(name => name !== 'parsererror')) throw new Error('malformed XML entity reference was accepted'); if (window.xmlEntityText !== '&AB') throw new Error('valid XML entity reference was not decoded');"
    if !script.run_script(context, check, "xml-entity-errors-check.js") { os.exit(4i32) }
    ret ok
}
