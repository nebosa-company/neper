// Driving a page's realm through the eval path the browser control uses (browser tracker 7.1).
//
// A host embedding the browser needs to run JavaScript in the page's own realm and see what it did - fill a field, click
// a control, read back the result. `page.eval_js` is that entry, and `e.ui.browser`'s `eval_js` calls it. This fixture
// builds the realm the way tests/selfhost/fixtures/link/web_shell does (a real Dom plus `script.new_context`), which is
// the same context `page.start_scripts` creates, then drives it through `page.eval_js`'s two primitives.
//
// Each failure returns a distinct error so the exit status names the step.
use e.fmt.dom as dom
use e.fmt.html as html
use e.js.interp as js
use e.mem
use e.str
use e.web.script as script

error ParseFailed
error ContextFailed
error Eval1
error Eval2
error Eval3
error Eval4
error ThrowReportedAsSuccess
error ThrowNotDescribed
error ValueFailed
error ValueWrong

fn options() -> html.Options {
    ret html.Options { max_bytes: 1048576usize, max_nodes: 4096usize, max_attributes: 64usize, max_depth: 64u16, preserve_comments: false }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (parsed, pe) = dom.parse(a, "<!doctype html><html><body><div id=box>0</div></body></html>", options(), 32usize)
    if pe != ok { ret ParseFailed }
    var tree = parsed
    let (it, ie) = script.new_context(a, &tree, "https://eval.test/")
    if ie != ok { ret ContextFailed }
    // 1. A script runs and its effect survives into a later evaluation: one realm, reused.
    if !script.run_script(it, "window.__counter = 1", "one.js") { ret Eval1 }
    script.pump(it, 0.0f64)
    if !script.run_script(it, "if (window.__counter !== 1) throw new Error('realm not reused')", "two.js") { ret Eval2 }
    // 2. The DOM can be written and read back.
    if !script.run_script(it, "document.getElementById('box').textContent = 'driven'", "three.js") { ret Eval3 }
    if !script.run_script(it, "if (document.getElementById('box').textContent !== 'driven') throw new Error('DOM write lost')", "four.js") { ret Eval4 }
    // 3. A throw is reported rather than swallowed, and names the exception.
    if script.run_script(it, "throw new Error('deliberate')", "five.js") { ret ThrowReportedAsSuccess }
    let why = script.describe_thrown(it)
    if !str.contains(why, "deliberate") { ret ThrowNotDescribed }
    // 4. The read half: an expression's value comes back, which is what `page.eval_value` does with these two calls.
    let (value, ve) = js.eval_source(it, "document.getElementById('box').textContent")
    if ve != ok { ret ValueFailed }
    let (text, te) = js.to_string(it, value)
    if te != ok { ret ValueFailed }
    if !str.eq(text, "driven") { ret ValueWrong }
    let (num, ne) = js.eval_source(it, "1 + 41")
    if ne != ok { ret ValueFailed }
    let (num_text, nte) = js.to_string(it, num)
    if nte != ok { ret ValueFailed }
    if !str.eq(num_text, "42") { ret ValueWrong }
    script.close(it)
    ret ok
}
