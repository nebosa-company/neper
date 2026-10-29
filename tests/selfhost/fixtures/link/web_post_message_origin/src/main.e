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
    let (context, context_error) = script.new_context(a, &tree, "https://postmessage.test/index.html")
    if context_error != ok { os.exit(2i32) }
    let setup = "window.messages = []; window.addEventListener('message', event => window.messages.push(event.data)); window.postMessage('default-port', 'https://POSTMESSAGE.TEST:443/path'); window.postMessage('case', 'HTTPS://postmessage.test/another'); window.postMessage('wrong-port', 'https://postmessage.test:444/'); window.postMessage('wildcard', '*'); window.postMessage('slash', '/'); try { window.postMessage('invalid', 'https://'); } catch (error) { window.invalidTargetName = error.name; }"
    if !script.run_script(context, setup, "post-message-origin-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let check = "if (window.messages.length !== 4 || window.messages.join(',') !== 'default-port,case,wildcard,slash') throw new Error('postMessage target origin matching failed'); if (window.invalidTargetName !== 'SyntaxError') throw new Error('invalid target origin did not throw SyntaxError');"
    if !script.run_script(context, check, "post-message-origin-check.js") { os.exit(4i32) }
    ret ok
}
