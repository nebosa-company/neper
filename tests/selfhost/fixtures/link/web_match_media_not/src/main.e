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
    let (context, context_error) = script.new_context(a, &tree, "https://match-media.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "window.matchResults = [matchMedia('not print').matches, matchMedia('not screen').matches, matchMedia('not screen and (min-width: 1px)').matches, matchMedia('not print and (min-width: 1px)').matches, matchMedia('neper-unknown').matches, matchMedia('not neper-unknown').matches, matchMedia('only screen').matches, matchMedia('all').matches];"
    if !script.run_script(context, setup, "match-media-not-setup.js") { os.exit(3i32) }
    let check = "const expected = [true, false, false, true, false, true, true, true]; if (window.matchResults.length !== expected.length || window.matchResults.some((value, index) => value !== expected[index])) throw new Error('matchMedia did not evaluate not or unknown media types');"
    if !script.run_script(context, check, "match-media-not-check.js") { os.exit(4i32) }
    ret ok
}
