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
    let (context, context_error) = script.new_context(a, &tree, "https://shadow-active.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const outerHost = document.createElement('div'); document.body.appendChild(outerHost); const outerRoot = outerHost.attachShadow({ mode: 'open' }); const innerHost = document.createElement('div'); outerRoot.appendChild(innerHost); const innerRoot = innerHost.attachShadow({ mode: 'open' }); const input = document.createElement('input'); innerRoot.appendChild(input); const unrelatedHost = document.createElement('div'); document.body.appendChild(unrelatedHost); const unrelatedRoot = unrelatedHost.attachShadow({ mode: 'open' }); window.outerHost = outerHost; window.outerRoot = outerRoot; window.innerHost = innerHost; window.innerRoot = innerRoot; window.input = input; window.unrelatedRoot = unrelatedRoot; input.focus();"
    if !script.run_script(context, setup, "shadow-active-setup.js") { os.exit(3i32) }
    let focused_check = "if (document.activeElement !== window.outerHost) throw new Error('document activeElement did not retarget to outer host'); if (window.outerRoot.activeElement !== window.innerHost) throw new Error('outer shadow root activeElement did not retarget to inner host'); if (window.innerRoot.activeElement !== window.input) throw new Error('inner shadow root activeElement did not expose focused input'); if (window.unrelatedRoot.activeElement !== null) throw new Error('unrelated shadow root exposed focused input');"
    if !script.run_script(context, focused_check, "shadow-active-focused-check.js") { os.exit(4i32) }
    let blur = "window.input.blur();"
    if !script.run_script(context, blur, "shadow-active-blur.js") { os.exit(5i32) }
    let blurred_check = "if (document.activeElement !== document.body) throw new Error('document activeElement did not fall back to body'); if (window.outerRoot.activeElement !== null || window.innerRoot.activeElement !== null || window.unrelatedRoot.activeElement !== null) throw new Error('shadow root retained activeElement after blur');"
    if !script.run_script(context, blurred_check, "shadow-active-blurred-check.js") { os.exit(6i32) }
    ret ok
}
