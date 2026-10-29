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
    let (context, context_error) = script.new_context(a, &tree, "https://attribute-replacement.test/")
    if context_error != ok { os.exit(2i32) }
    let test = "const el = document.createElement('div'); el.setAttribute('a', 'old'); el.setAttribute('b', 'two'); const replacement = document.createAttribute('a'); replacement.value = 'new'; const previous = el.attributes.setNamedItem(replacement); if (previous === null || previous.value !== 'old') throw new Error('NamedNodeMap did not return the replaced attribute'); if (el.attributes.length !== 2 || el.attributes[0].name !== 'a' || el.attributes[0].value !== 'new' || el.attributes[1].name !== 'b' || el.attributes[1].value !== 'two') throw new Error('NamedNodeMap wrapper order or values changed'); if (el.outerHTML.indexOf('a=\\\"new\\\" b=\\\"two\\\"') < 0) throw new Error('native attribute order or value diverged from NamedNodeMap'); const ns = 'http://www.w3.org/1999/xlink'; const prefixed = document.createElement('div'); prefixed.setAttributeNS(ns, 'p:item', 'first'); prefixed.setAttributeNS(ns, 'q:item', 'second'); const attr = prefixed.getAttributeNodeNS(ns, 'item'); if (attr === null || attr.name !== 'q:item' || attr.value !== 'second') throw new Error('attribute prefix was not replaced'); if (prefixed.outerHTML.indexOf('q:item=\\\"second\\\"') < 0 || prefixed.outerHTML.indexOf('p:item=') >= 0) throw new Error('native prefix did not match the attribute wrapper');"
    if !script.run_script(context, test, "attribute-native-replacement.js") { os.exit(3i32) }
    ret ok
}
