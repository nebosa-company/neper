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
    let (context, context_error) = script.new_context(a, &tree, "https://abort-listener-cleanup.test/")
    if context_error != ok { os.exit(2i32) }
    let test = "const controller = new AbortController(); const target = new EventTarget(); const callback = () => {}; target.addEventListener('probe', callback, { signal: controller.signal }); if (window.__realm.slotOf(controller.signal).algorithms.length !== 1) throw new Error('listener abort algorithm was not registered'); target.removeEventListener('probe', callback); if (window.__realm.slotOf(controller.signal).algorithms.length !== 0) throw new Error('removed listener retained an abort algorithm'); const onceController = new AbortController(); const onceTarget = new EventTarget(); onceTarget.addEventListener('once', () => {}, { once: true, signal: onceController.signal }); onceTarget.dispatchEvent(new Event('once')); if (window.__realm.slotOf(onceController.signal).algorithms.length !== 0) throw new Error('once listener retained an abort algorithm'); const fetchSuccess = new AbortController(); const fetchFailure = new AbortController(); const fetchInvalid = new AbortController(); window.__fetchSuccessSignal = fetchSuccess.signal; window.__fetchFailureSignal = fetchFailure.signal; window.__fetchInvalidSignal = fetchInvalid.signal; fetch('data:text/plain,ok', { signal: fetchSuccess.signal }); fetch('data:', { signal: fetchFailure.signal }).then(() => { throw new Error('failed fetch fulfilled'); }, () => {}); fetch('data:text/plain,ok', { method: 'GET', body: 'x', signal: fetchInvalid.signal }).then(() => { throw new Error('invalid fetch fulfilled'); }, () => {}); if (window.__realm.slotOf(fetchSuccess.signal).algorithms.length !== 1) throw new Error('successful fetch handler was not registered'); if (window.__realm.slotOf(fetchFailure.signal).algorithms.length !== 1) throw new Error('failed fetch handler was not registered'); if (window.__realm.slotOf(fetchInvalid.signal).algorithms.length !== 0) throw new Error('invalid fetch retained an abort handler');"
    if !script.run_script(context, test, "abort-listener-cleanup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let settled = "if (window.__realm.slotOf(window.__fetchSuccessSignal).algorithms.length !== 0) throw new Error('completed fetch retained an abort handler'); if (window.__realm.slotOf(window.__fetchFailureSignal).algorithms.length !== 0) throw new Error('failed fetch retained an abort handler'); if (window.__realm.slotOf(window.__fetchInvalidSignal).algorithms.length !== 0) throw new Error('invalid fetch retained an abort handler after settling');"
    if !script.run_script(context, settled, "fetch-abort-cleanup.js") { os.exit(4i32) }
    ret ok
}
