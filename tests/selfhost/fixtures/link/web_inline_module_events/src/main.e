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
    let (context, context_error) = script.new_context(a, &tree, "https://inline-module-events.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "window.ran = 0; window.goodLoad = 0; window.goodError = 0; window.badLoad = 0; window.badError = 0; const good = document.createElement('script'); good.type = 'module'; good.addEventListener('load', () => { window.goodLoad += 1; }); good.addEventListener('error', () => { window.goodError += 1; }); good.appendChild(document.createTextNode('window.ran += 1;')); document.body.appendChild(good); const bad = document.createElement('script'); bad.type = 'module'; bad.addEventListener('load', () => { window.badLoad += 1; }); bad.addEventListener('error', () => { window.badError += 1; }); bad.appendChild(document.createTextNode('const = ;')); document.body.appendChild(bad);"
    if !script.run_script(context, setup, "inline-module-events-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let check = "if (window.ran !== 1 || window.goodLoad !== 1 || window.goodError !== 0 || window.badLoad !== 0 || window.badError !== 1) throw new Error('inline module events failed');"
    if !script.run_script(context, check, "inline-module-events-check.js") { os.exit(4i32) }
    ret ok
}
