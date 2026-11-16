// A page script that never ends is stopped by a per-task step budget and reported as a script error; the page and the next script
// carry on. The same holds for a timer callback and a lifecycle handler.
use e.fmt.dom as dom
use e.fmt.html as html
use e.mem
use e.os
use e.web.script as script

fn main(a: *mem.Arena, args: []str) -> err {
    let options = html.Options { max_bytes: 1048576usize, max_nodes: 4096usize, max_attributes: 64usize, max_depth: 64u16, preserve_comments: false }
    let (parsed, pe) = dom.parse(a, "<!doctype html><title>t</title>", options, 32usize)
    if pe != ok { os.exit(90i32) }
    var tree = parsed
    let (it, ie) = script.new_context(a, &tree, "https://page.test/index.html")
    if ie != ok { os.exit(91i32) }
    // an endless classic script: false (an error was reported), and the interpreter is usable afterwards
    if script.run_script(it, "while (true) {}", "loop.js") { os.exit(1i32) }
    if !script.run_script(it, "var after = 1 + 1", "after.js") { os.exit(2i32) }
    // an endless timer callback: the pump returns and later scripts still run
    if !script.run_script(it, "setTimeout(function () { while (true) {} }, 0)", "timer.js") { os.exit(4i32) }
    script.pump(it, 10.0f64)
    if !script.run_script(it, "var later = 3", "later.js") { os.exit(5i32) }
    // a bounded loop is far inside the budget
    if !script.run_script(it, "var n = 0; for (var i = 0; i < 100000; i++) { n += i } n", "bounded.js") { os.exit(6i32) }
    ret ok
}
