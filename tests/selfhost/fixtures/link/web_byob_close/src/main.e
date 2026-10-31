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
    let (context, context_error) = script.new_context(a, &tree, "https://byob-close.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const stream = new ReadableStream({ type: 'bytes', pull(controller) { controller.close(); } }); const reader = stream.getReader({ mode: 'byob' }); window.result = null; window.failure = null; reader.read(new Uint8Array(8)).then(value => { window.result = value; }, error => { window.failure = error; });"
    if !script.run_script(context, setup, "byob-close-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let check = "if (window.failure !== null || window.result === null || window.result.done !== true || window.result.value.byteLength !== 0) throw new Error('BYOB close did not settle read');"
    if !script.run_script(context, check, "byob-close-check.js") { os.exit(4i32) }
    ret ok
}
