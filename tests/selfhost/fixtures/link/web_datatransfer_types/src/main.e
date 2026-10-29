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
    let (context, context_error) = script.new_context(a, &tree, "https://datatransfer-types.test/")
    if context_error != ok { os.exit(2i32) }
    let check = "const transfer = new DataTransfer(); transfer.items.add(new File(['a'], 'one.txt')); transfer.items.add(new File(['b'], 'two.txt')); if (transfer.files.length !== 2 || transfer.types.length !== 1 || transfer.types[0] !== 'Files') throw new Error('DataTransfer.types did not deduplicate Files');"
    if !script.run_script(context, check, "datatransfer-types.js") { os.exit(3i32) }
    ret ok
}
