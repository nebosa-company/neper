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

fn push(b: *str.Builder, s: str) -> err {
    ret str.push(b, s)
}

// A quoted YAML scalar keeps project names containing `: ` or ` #` from changing
// the front matter. Newlines become spaces so the front matter stays one line.
fn push_title(b: *str.Builder, s: str) -> err {
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 34u8 {
            try push(b, "\\\"")
        } else if c == 92u8 {
            try push(b, "\\\\")
        } else if c == 10u8 || c == 13u8 {
            try push(b, " ")
            if c == 13u8 && at + 1usize < s.len && s[at + 1usize] == 10u8 { at += 1usize }
        } else if c < 32u8 || c == 127u8 {
            let digits = "0123456789abcdef"
            try push(b, "\\x")
            try str.push_byte(b, digits[usize(c) / 16usize])
            try str.push_byte(b, digits[usize(c) % 16usize])
        } else {
            try str.push_byte(b, c)
        }
        at += 1usize
    }
    ret ok
}

// Labels are HTML-bearing Mermaid text, so syntax bytes become entities and line
// breaks cannot open a new diagram statement.
fn push_label(b: *str.Builder, s: str) -> err {
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 38u8 {
            try push(b, "&amp;")
        } else if c == 60u8 {
            try push(b, "&lt;")
        } else if c == 62u8 {
            try push(b, "&gt;")
        } else if c == 34u8 {
            try push(b, "&quot;")
        } else if c == 10u8 || c == 13u8 {
            try push(b, " ")
            if c == 13u8 && at + 1usize < s.len && s[at + 1usize] == 10u8 { at += 1usize }
        } else if c < 32u8 || c == 127u8 {
            try push(b, " ")
        } else {
            try str.push_byte(b, c)
        }
        at += 1usize
    }
    ret ok
}

fn push_index(b: *str.Builder, n: usize) -> err {
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
        try str.push_byte(b, digits[count])
    }
    ret ok
}

// The Mermaid source for a graph.
fn flowchart(a: *mem.Arena, project: str, nodes: []const Node) -> (str, err) {
    let (made, e) = str.builder(a, 512usize)
    if e != ok { ret ("", e) }
    var b = made
    try push(&b, "---\ntitle: \"PetCow infrastructure — ")
    try push_title(&b, project)
    try push(&b, "\"\n---\nflowchart TD\n  classDef blocked fill:#ffd6d6,stroke:#cc0000,color:#000000;\n")
    if nodes.len == 0usize {
        try push(&b, "  empty[\"(no resources)\"]\n")
        ret (str.done(&b), ok)
    }
    var i = 0usize
    while i < nodes.len {
        try push(&b, "  n")
        try push_index(&b, i)
        try push(&b, "[\"")
        try push_label(&b, nodes[i].id)
        try push(&b, "<br/><small>")
        try push_label(&b, nodes[i].kind)
        try push(&b, "</small>\"]\n")
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
                    try push(&b, "  n")
                    try push_index(&b, t)
                    try push(&b, " --> n")
                    try push_index(&b, i)
                    try push(&b, "\n")
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
            try push(&b, "  class n")
            try push_index(&b, i)
            try push(&b, " blocked;\n")
        }
        i += 1usize
    }
    ret (str.done(&b), ok)
}
