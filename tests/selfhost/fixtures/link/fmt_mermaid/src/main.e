// `e.fmt.mermaid`: quoted YAML titles and HTML-safe labels stay one diagram
// statement, while a builder shortage is returned rather than accepted as a
// truncated graph.
use e.fmt.mermaid as mermaid
use e.io
use e.mem
use e.os
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    var none: [0]str = zero
    var nodes: [1]mermaid.Node = zero
    nodes[0usize].id = "<img src=x onerror=1>&\"id\r\nnext"
    nodes[0usize].kind = "</small><a href=x>&\"kind\r\nnext"
    nodes[0usize].depends_on = none[..]
    let (text, text_error) = mermaid.flowchart(a, "prod: eu #1 \"slash\\\r\nnext", nodes[..])
    if text_error != ok { os.exit(1i32) }
    if !str.contains(text, "title: \"PetCow infrastructure — prod: eu #1 \\\"slash\\\\ next\"") { os.exit(2i32) }
    if !str.contains(text, "&lt;img src=x onerror=1&gt;&amp;&quot;id next") { os.exit(3i32) }
    if !str.contains(text, "&lt;/small&gt;&lt;a href=x&gt;&amp;&quot;kind next") { os.exit(4i32) }
    if str.contains(text, "<img") || str.contains(text, "</small><a") { os.exit(5i32) }

    // Measure a complete graph, then leave the same call one byte short.  The
    // result must surface the builder's allocation failure instead of returning
    // a partial Mermaid document with `ok`.
    var label: [2048]u8 = zero
    var at = 0usize
    while at < label.len {
        label[at] = 97u8
        at += 1usize
    }
    var large: [1]mermaid.Node = zero
    large[0usize].id = label[..]
    large[0usize].kind = "kind"
    large[0usize].depends_on = none[..]
    var full_storage: [8192]u8 = zero
    var full_arena = mem.arena_from(full_storage[..])
    let (_, full_error) = mermaid.flowchart(&full_arena, "", large[..])
    if full_error != ok { os.exit(6i32) }
    let used = mem.mark(&full_arena)
    if used == 0usize || used >= full_storage.len { os.exit(7i32) }
    var tight_storage: [8192]u8 = zero
    var tight_arena = mem.arena_from(tight_storage[0usize..used - 1usize])
    let (_, tight_error) = mermaid.flowchart(&tight_arena, "", large[..])
    if tight_error != mem.Exhausted { os.exit(8i32) }
    try io.print("fmt mermaid ok\n")
    ret ok
}
