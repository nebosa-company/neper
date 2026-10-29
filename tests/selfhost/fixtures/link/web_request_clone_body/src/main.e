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
    let (context, context_error) = script.new_context(a, &tree, "https://request-clone.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const streamFor = (a, b) => new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array([a, b])); controller.close(); } }); const response = new Response(streamFor(114, 115)); const responseClone = response.clone(); const request = new Request('https://request-clone.test/body', { method: 'POST', body: streamFor(114, 113) }); const requestClone = request.clone(); const locked = new Request('https://request-clone.test/locked', { method: 'POST', body: streamFor(108, 107) }); locked.body.getReader(); try { locked.clone(); window.lockedCloneName = ''; } catch (error) { window.lockedCloneName = error.name; } const source = new Request('https://request-clone.test/source', { method: 'POST', body: streamFor(109, 118) }); const transferred = new Request(source); window.sourceUsedAfterTransfer = source.bodyUsed; const consumed = new Request('https://request-clone.test/consumed', { method: 'POST', body: streamFor(117, 115) }); window.done = false; window.failure = null; Promise.all([response.text(), responseClone.text(), request.text(), requestClone.text(), transferred.text(), consumed.text()]).then(values => { window.responseText = values[0]; window.responseCloneText = values[1]; window.requestText = values[2]; window.requestCloneText = values[3]; window.transferredText = values[4]; try { new Request(consumed); window.usedConstructorName = ''; } catch (error) { window.usedConstructorName = error.name; } const override = new Request(consumed, { method: 'POST', body: 'override' }); return override.text(); }).then(value => { window.overrideText = value; window.done = true; }, error => { window.failure = error; window.done = true; });"
    if !script.run_script(context, setup, "request-clone-body-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let check = "if (!window.done || window.failure !== null) throw new Error('stream body promise chain did not complete'); if (window.responseText !== 'rs' || window.responseCloneText !== 'rs') throw new Error('Response clone did not preserve a stream body'); if (window.requestText !== 'rq' || window.requestCloneText !== 'rq') throw new Error('Request clone did not preserve independent stream bodies'); if (window.lockedCloneName !== 'TypeError') throw new Error('locked Request body could be cloned'); if (window.sourceUsedAfterTransfer !== true || window.transferredText !== 'mv') throw new Error('Request constructor did not transfer the input body'); if (window.usedConstructorName !== 'TypeError' || window.overrideText !== 'override') throw new Error('Request construction did not handle used or overridden bodies');"
    if !script.run_script(context, check, "request-clone-body-check.js") { os.exit(4i32) }
    let timeout_setup = "const timed = new XMLHttpRequest(); window.timeoutEvents = []; for (const type of ['loadstart', 'timeout', 'error', 'load', 'loadend']) timed.addEventListener(type, () => window.timeoutEvents.push(type)); timed.open('GET', 'https://timeout.test/slow'); timed.timeout = 5; timed.send(); window.timed = timed;"
    if !script.run_script(context, timeout_setup, "xhr-timeout-setup.js") { os.exit(5i32) }
    script.advance(context, 5.0f64)
    script.pump(context, 0.0f64)
    let timeout_check = "if (window.timeoutEvents.join(',') !== 'loadstart,timeout,loadend' || window.timed.readyState !== XMLHttpRequest.DONE || window.timed.status !== 0 || window.timed.responseText !== '' || window.timed.responseURL !== '') throw new Error('XMLHttpRequest did not time out before a delayed request started');"
    if !script.run_script(context, timeout_check, "xhr-timeout-check.js") { os.exit(6i32) }
    let complete_setup = "const completed = new XMLHttpRequest(); window.completeEvents = []; for (const type of ['loadstart', 'timeout', 'error', 'load', 'loadend']) completed.addEventListener(type, () => window.completeEvents.push(type)); completed.open('GET', 'data:text/plain,ok'); completed.timeout = 5; completed.send(); window.completed = completed;"
    if !script.run_script(context, complete_setup, "xhr-timeout-complete-setup.js") { os.exit(7i32) }
    script.pump(context, 0.0f64)
    script.advance(context, 5.0f64)
    script.pump(context, 0.0f64)
    let complete_check = "if (window.completeEvents.join(',') !== 'loadstart,load,loadend' || window.completed.readyState !== XMLHttpRequest.DONE || window.completed.status !== 200 || window.completed.responseText !== 'ok') throw new Error('completed XMLHttpRequest fired a stale timeout');"
    if !script.run_script(context, complete_check, "xhr-timeout-complete-check.js") { os.exit(8i32) }
    ret ok
}
