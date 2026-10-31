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
    let (context, context_error) = script.new_context(a, &tree, "https://frame-registry.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const frame = document.createElement('iframe'); document.body.appendChild(frame); window.frameRegistryOld = frame.contentWindow; window.frameRegistryHits = 0; window.frameRegistryOld.__realm.ensureCeWrapped = function() { window.frameRegistryHits += 1; }; frame.srcdoc = '<p>replacement</p>'; window.frameRegistryFrame = frame;"
    if !script.run_script(context, setup, "frame-registry-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let replacement_check = "if (window.frameRegistryFrame.contentWindow === window.frameRegistryOld) throw new Error('frame replacement failed');"
    if !script.run_script(context, replacement_check, "frame-registry-replacement.js") { os.exit(4i32) }
    let length_check = "if (window.length !== 1) throw new Error('frame count failed');"
    if !script.run_script(context, length_check, "frame-registry-length.js") { os.exit(5i32) }
    let registry_check = "class FrameRegistryProbe extends HTMLElement {} customElements.define('frame-registry-probe', FrameRegistryProbe); if (window.frameRegistryHits !== 0) throw new Error('dropped frame was retained');"
    if !script.run_script(context, registry_check, "frame-registry-custom-elements.js") { os.exit(6i32) }
    let removal_check = "window.frameRegistryFrame.remove(); if (window.length !== 0) throw new Error('frame removal failed');"
    if !script.run_script(context, removal_check, "frame-registry-removal.js") { os.exit(7i32) }
    ret ok
}
