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
    let (context, context_error) = script.new_context(a, &tree, "https://unsigned-long.test/")
    if context_error != ok { os.exit(2i32) }
    let test = "const value = 3000000000; const image = document.createElement('img'); image.width = value; if (image.getAttribute('width') !== '3000000000' || image.width !== value) throw new Error('image width rejected a valid unsigned long'); image.setAttribute('height', '3000000000'); if (image.height !== value) throw new Error('image height getter rejected a valid unsigned long'); const canvas = document.createElement('canvas'); canvas.width = value; if (canvas.getAttribute('width') !== '3000000000' || canvas.width !== value) throw new Error('canvas width rejected a valid unsigned long');"
    if !script.run_script(context, test, "unsigned-long-reflection.js") { os.exit(3i32) }
    ret ok
}
