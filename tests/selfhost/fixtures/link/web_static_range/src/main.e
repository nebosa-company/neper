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
    let check = "const text = document.createTextNode('ok'); let startRejected = false; try { new StaticRange({ startContainer: text, startOffset: 3, endContainer: text, endOffset: 2 }); } catch (error) { startRejected = error.name === 'IndexSizeError'; } let endRejected = false; try { new StaticRange({ startContainer: text, startOffset: 0, endContainer: text, endOffset: 3 }); } catch (error) { endRejected = error.name === 'IndexSizeError'; } const valid = new StaticRange({ startContainer: text, startOffset: 2, endContainer: text, endOffset: 2 }); if (!startRejected || !endRejected || valid.startOffset !== 2 || valid.endOffset !== 2) throw new Error('StaticRange bounds validation failed');"
    if !script.run_script(context, check, "static-range-bounds.js") { os.exit(3i32) }
    ret ok
}
