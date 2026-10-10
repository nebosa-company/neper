// Mermaid flowchart emission (L042), after petcow's `diagram::to_mermaid`: a `flowchart TD` of resources, one node each
// labelled with its id and kind, an edge from each dependency to what depends on it (so creation order runs top to
// bottom), and the nodes that carry a blocking finding classed `blocked`. A dependency names a node exactly or as a prefix
// of an expanded instance (`subnet` reaches `subnet[0]` and `subnet[1]`). The title is a front-matter line; an empty graph
// emits one placeholder node.
//
// Memory: the arena is retained; the text lives in it.

use e.mem
use e.str

// One node: its identifier, its kind, the nodes it depends on, and whether a blocking finding marks it.
type Node = struct { id: str, kind: str, depends_on: []const str, blocked: bool }

fn push(b: *str.Builder, s: str) {
    let e = str.push(b, s)
}

// Quotes break the `["..."]` syntax, so a label's become `&quot;`.
fn push_label(b: *str.Builder, s: str) {
    var at = 0usize
    while at < s.len {
        if s[at] == 34u8 {
            push(b, "&quot;")
        } else {
            let e = str.push_byte(b, s[at])
        }
        at += 1usize
    }
}

fn push_index(b: *str.Builder, n: usize) {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = n
    if rest == 0usize {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0usize {
        digits[count] = u8(48usize + rest % 10usize)
        count += 1usize
        rest = rest / 10usize
    }
    while count > 0usize {
        count -= 1usize
        let e = str.push_byte(b, digits[count])
    }
}

// The Mermaid source for a graph.
fn flowchart(a: *mem.Arena, project: str, nodes: []const Node) -> (str, err) {
    let (made, e) = str.builder(a, 512usize)
    if e != ok { ret ("", e) }
    var b = made
    push(&b, "---\ntitle: PetCow infrastructure — ")
    var at = 0usize
    while at < project.len {
        if project[at] == 10u8 {
            push(&b, " ")
        } else {
            let pushed = str.push_byte(&b, project[at])
        }
        at += 1usize
    }
    push(&b, "\n---\nflowchart TD\n  classDef blocked fill:#ffd6d6,stroke:#cc0000,color:#000000;\n")
    if nodes.len == 0usize {
        push(&b, "  empty[\"(no resources)\"]\n")
        ret (str.done(&b), ok)
    }
    var i = 0usize
    while i < nodes.len {
        push(&b, "  n")
        push_index(&b, i)
        push(&b, "[\"")
        push_label(&b, nodes[i].id)
        push(&b, "<br/><small>")
        push_label(&b, nodes[i].kind)
        push(&b, "</small>\"]\n")
        i += 1usize
    }
    i = 0usize
    while i < nodes.len {
        var d = 0usize
        while d < nodes[i].depends_on.len {
            let wanted = nodes[i].depends_on[d]
            var t = 0usize
            while t < nodes.len {
                let id = nodes[t].id
                let exact = str.eq(id, wanted)
                let expanded = id.len > wanted.len && str.starts_with(id, wanted) && id[wanted.len] == 91u8
                if exact || expanded {
                    push(&b, "  n")
                    push_index(&b, t)
                    push(&b, " --> n")
                    push_index(&b, i)
                    push(&b, "\n")
                }
                t += 1usize
            }
            d += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nodes.len {
        if nodes[i].blocked {
            push(&b, "  class n")
            push_index(&b, i)
            push(&b, " blocked;\n")
        }
        i += 1usize
    }
    ret (str.done(&b), ok)
}
