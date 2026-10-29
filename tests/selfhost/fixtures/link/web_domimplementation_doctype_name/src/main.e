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
    let (context, context_error) = script.new_context(a, &tree, "https://doctype-name.test/")
    if context_error != ok { os.exit(2i32) }
    let test = "const impl = document.implementation; if (impl.createDocumentType('', '', '').name !== '') throw new Error('empty doctype name was not retained'); if (impl.createDocumentType('a?', '', '').name !== 'a?') throw new Error('permissive valid doctype name was rejected'); const invalid = ['bad name', 'bad>name', 'bad\\tname', 'bad' + String.fromCharCode(0) + 'name']; for (const name of invalid) { let thrown = null; try { impl.createDocumentType(name, '', ''); } catch (error) { thrown = error; } if (thrown === null || thrown.name !== 'InvalidCharacterError') throw new Error('invalid doctype name was accepted'); }"
    if !script.run_script(context, test, "domimplementation-doctype-name.js") { os.exit(3i32) }
    ret ok
}
