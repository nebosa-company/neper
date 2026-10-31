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
    let (context, context_error) = script.new_context(a, &tree, "https://stop-propagation.test/")
    if context_error != ok { os.exit(2i32) }
    let test = "const parent = document.createElement('div'); const target = document.createElement('span'); parent.appendChild(target); document.body.appendChild(parent); const order = []; parent.addEventListener('probe', () => order.push('parent-capture'), true); target.addEventListener('probe', event => { order.push('target-capture'); event.stopPropagation(); }, true); target.addEventListener('probe', () => order.push('target-bubble')); parent.addEventListener('probe', () => order.push('parent-bubble')); target.dispatchEvent(new Event('probe', { bubbles: true })); if (order.join(',') !== 'parent-capture,target-capture,target-bubble') throw new Error('stopPropagation suppressed a remaining listener on the target'); const immediate = document.createElement('span'); document.body.appendChild(immediate); const immediateOrder = []; immediate.addEventListener('immediate', event => { immediateOrder.push('capture'); event.stopImmediatePropagation(); }, true); immediate.addEventListener('immediate', () => immediateOrder.push('bubble')); immediate.dispatchEvent(new Event('immediate', { bubbles: true })); if (immediateOrder.join(',') !== 'capture') throw new Error('stopImmediatePropagation did not suppress a remaining target listener');"
    if !script.run_script(context, test, "stop-propagation-target.js") { os.exit(3i32) }
    ret ok
}
