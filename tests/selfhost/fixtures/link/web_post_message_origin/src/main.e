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
    let setup = "window.messages = []; window.messageOrigins = []; window.addEventListener('message', event => { window.messages.push(event.data); window.messageOrigins.push(event.origin); }); window.selfOrigin = window.origin; window.objectUrl = URL.createObjectURL(new Blob(['x'])); const blank = document.createElement('iframe'); document.body.appendChild(blank); window.blankFrame = blank; const srcdoc = document.createElement('iframe'); srcdoc.srcdoc = '<p>srcdoc</p>'; document.body.appendChild(srcdoc); window.srcdocFrame = srcdoc; const opaque = document.createElement('iframe'); opaque.src = 'data:text/html,opaque'; document.body.appendChild(opaque); window.opaqueFrame = opaque; window.postMessage('default-port', 'https://POSTMESSAGE.TEST:443/path'); window.postMessage('case', 'HTTPS://postmessage.test/another'); window.postMessage('wrong-port', 'https://postmessage.test:444/'); window.postMessage('wildcard', '*'); window.postMessage('slash', '/'); try { window.postMessage('invalid', 'https://'); } catch (error) { window.invalidTargetName = error.name; }"
    if !script.run_script(context, setup, "post-message-origin-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let check = "const origin = 'https://postmessage.test'; if (window.origin !== origin || window.selfOrigin !== origin) throw new Error('window origin was not initialized from the document URL'); if (window.messages.length !== 4 || window.messages.join(',') !== 'default-port,case,wildcard,slash') throw new Error('postMessage target origin matching failed'); if (window.messageOrigins.length !== 4 || window.messageOrigins.join(',') !== origin + ',' + origin + ',' + origin + ',' + origin) throw new Error('MessageEvent origin was not the sender origin'); if (window.objectUrl.indexOf('blob:' + origin + '/') !== 0) throw new Error('blob URL did not use the document origin'); if (window.blankFrame.contentWindow.origin !== origin) throw new Error('about:blank iframe did not inherit its parent origin'); if (window.srcdocFrame.contentWindow.origin !== origin) throw new Error('srcdoc iframe did not inherit its parent origin'); if (window.opaqueFrame.contentWindow.origin !== 'null') throw new Error('opaque iframe origin was not null'); if (window.invalidTargetName !== 'SyntaxError') throw new Error('invalid target origin did not throw SyntaxError');"
    if !script.run_script(context, check, "post-message-origin-check.js") { os.exit(4i32) }
    ret ok
}
