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
    let test = "const value = 3000000000; const image = document.createElement('img'); image.width = value; if (image.getAttribute('width') !== '0' || image.width !== 0) throw new Error('image width kept a value past 2147483647'); image.setAttribute('height', '3000000000'); if (image.height !== 0) throw new Error('image height getter returned a value past 2147483647'); image.width = 2147483647; if (image.getAttribute('width') !== '2147483647' || image.width !== 2147483647) throw new Error('image width rejected the largest valid value'); const canvas = document.createElement('canvas'); canvas.width = value; if (canvas.getAttribute('width') !== '300' || canvas.width !== 300) throw new Error('canvas width kept a value past 2147483647');"
    if !script.run_script(context, test, "unsigned-long-reflection.js") { os.exit(3i32) }
    ret ok
}
