// Wadler-style pretty printing over a caller document pool. A `Doc` is one of
// `Text`, `Line` (a newline, or a space when flattened), `SoftLine` (a newline,
// or nothing), `Nest(indent, child)`, `Concat(a, b)` and `Group(child)`;
// `layout` renders `root` into `out` at `width`, deciding each group flat or
// broken by whether its flat rendering, and the rest of the line after it,
// fits in what remains. Node 0 is the empty document.
//
// The lookahead is Wadler's own: a later group met while measuring is decided
// the way it will be rendered -- flat if its flat form and the rest fit, else
// broken, where its first line ends the measure. That is the lazy semantics of
// "A prettier printer", not Lindig's strict one that measures every later
// group flat, and it is why `fits` recurses. All the recursion needs is the
// caller's `stack`: scratch frames grow up from the main stack, and each
// nested measure records at the top end of `stack` where its read-only view
// jumps over the frames its parent already consumed.

type Kind = enum u8 { Text, Line, SoftLine, Nest, Concat, Group }
type Doc = struct { kind: Kind, content: str, indent: u32, first: u32, second: u32 }
type Pool = struct { docs: []Doc, used: usize }
type Frame = struct { doc: u32, indent: u32, flat: bool }
error TooSmall
error Invalid

// A pool over `docs`; slot 0 becomes the empty document.
fn pool(docs: []Doc) -> (Pool, err) {
    if docs.len == 0usize { ret (zero, TooSmall) }
    docs[0usize] = Doc { kind: .Text, content: "", indent: 0u32, first: 0u32, second: 0u32 }
    ret (Pool { docs: docs, used: 1usize }, ok)
}

fn add(p: *Pool, d: Doc) -> (u32, err) {
    if p.used >= p.docs.len { ret (0u32, TooSmall) }
    if usize(d.first) >= p.used || usize(d.second) >= p.used { ret (0u32, Invalid) }
    p.docs[p.used] = d
    p.used += 1usize
    ret (u32(p.used - 1usize), ok)
}

fn text(p: *Pool, s: str) -> (u32, err) {
    let (id, e) = add(p, Doc { kind: .Text, content: s, indent: 0u32, first: 0u32, second: 0u32 })
    ret (id, e)
}

// A newline, or one space when the enclosing group is flat.
fn line(p: *Pool) -> (u32, err) {
    let (id, e) = add(p, Doc { kind: .Line, content: "", indent: 0u32, first: 0u32, second: 0u32 })
    ret (id, e)
}

// A newline, or nothing when the enclosing group is flat.
fn soft_line(p: *Pool) -> (u32, err) {
    let (id, e) = add(p, Doc { kind: .SoftLine, content: "", indent: 0u32, first: 0u32, second: 0u32 })
    ret (id, e)
}

// `child` with every line break inside it indented `amount` more.
fn nest(p: *Pool, amount: u32, child: u32) -> (u32, err) {
    let (id, e) = add(p, Doc { kind: .Nest, content: "", indent: amount, first: child, second: 0u32 })
    ret (id, e)
}

fn concat(p: *Pool, a: u32, b: u32) -> (u32, err) {
    let (id, e) = add(p, Doc { kind: .Concat, content: "", indent: 0u32, first: a, second: b })
    ret (id, e)
}

// `child` rendered flat when it fits the rest of the line, broken otherwise.
fn group(p: *Pool, child: u32) -> (u32, err) {
    let (id, e) = add(p, Doc { kind: .Group, content: "", indent: 0u32, first: child, second: 0u32 })
    ret (id, e)
}

// Does the flat frame at `stack[base]` (the scratch is `[base, top)`), followed by the rest
// of the line, fit in `remaining` columns? The rest is read downward from `base`; the
// `depth` skips at the top end of `stack` jump over frames a parent measure consumed.
fn fits(p: *const Pool, stack: []Frame, base: usize, top: usize, depth: usize, remaining: i64) -> (bool, err) {
    var s_top = top
    var z = base
    var rem = remaining
    let limit = stack.len - depth
    while true {
        if rem < 0i64 { ret (false, ok) }
        var f: Frame = zero
        if s_top > base {
            s_top -= 1usize
            f = stack[s_top]
        } else {
            var j = depth
            while j > 0usize {
                let s = stack[stack.len - j]
                if z == usize(s.doc) { z = usize(s.indent) }
                j -= 1usize
            }
            if z == 0usize { ret (true, ok) }
            z -= 1usize
            f = stack[z]
        }
        let d = p.docs[usize(f.doc)]
        if d.kind == .Text {
            rem -= i64(d.content.len)
        } else if d.kind == .Line {
            if f.flat { rem -= 1i64 } else { ret (true, ok) }
        } else if d.kind == .SoftLine {
            if !f.flat { ret (true, ok) }
        } else if d.kind == .Nest {
            if s_top >= limit { ret (false, TooSmall) }
            stack[s_top] = Frame { doc: d.first, indent: f.indent + d.indent, flat: f.flat }
            s_top += 1usize
        } else if d.kind == .Concat {
            if s_top + 1usize >= limit { ret (false, TooSmall) }
            stack[s_top] = Frame { doc: d.second, indent: f.indent, flat: f.flat }
            stack[s_top + 1usize] = Frame { doc: d.first, indent: f.indent, flat: f.flat }
            s_top += 2usize
        } else if f.flat {
            if s_top >= limit { ret (false, TooSmall) }
            stack[s_top] = Frame { doc: d.first, indent: f.indent, flat: true }
            s_top += 1usize
        } else {
            // A group in break mode: flat if its flat form and the rest fit from here, in
            // which case the whole measure succeeds; otherwise it breaks and is measured so.
            if s_top + 1usize >= limit { ret (false, TooSmall) }
            stack[limit - 1usize] = Frame { doc: u32(base), indent: u32(z), flat: false }
            stack[s_top] = Frame { doc: d.first, indent: f.indent, flat: true }
            let (flat_fits, e) = fits(p, stack, s_top, s_top + 1usize, depth + 1usize, rem)
            if e != ok { ret (false, e) }
            if flat_fits { ret (true, ok) }
            stack[s_top] = Frame { doc: d.first, indent: f.indent, flat: false }
            s_top += 1usize
        }
    }
    ret (true, ok)
}

fn emit(out: []u8, n: usize, byte: u8) -> (usize, err) {
    if n >= out.len { ret (n, TooSmall) }
    out[n] = byte
    ret (n + 1usize, ok)
}

// Render `root` at `width` into `out`; answers the byte count. `stack` is the frame
// stack, deep enough for the document's nesting plus the lookahead's.
fn layout(p: *const Pool, root: u32, width: usize, out: []u8, stack: []Frame) -> (usize, err) {
    if usize(root) >= p.used { ret (0usize, Invalid) }
    if stack.len == 0usize { ret (0usize, TooSmall) }
    var top = 0usize
    stack[0usize] = Frame { doc: root, indent: 0u32, flat: false }
    top = 1usize
    var column = 0usize
    var n = 0usize
    while top > 0usize {
        top -= 1usize
        let f = stack[top]
        let d = p.docs[usize(f.doc)]
        if d.kind == .Text {
            if n + d.content.len > out.len { ret (n, TooSmall) }
            var i = 0usize
            while i < d.content.len {
                out[n + i] = d.content[i]
                i += 1usize
            }
            n += d.content.len
            column += d.content.len
        } else if d.kind == .Line || d.kind == .SoftLine {
            if f.flat {
                if d.kind == .Line {
                    let (n1, e) = emit(out, n, 32u8)
                    if e != ok { ret (n, e) }
                    n = n1
                    column += 1usize
                }
            } else {
                let (n1, e) = emit(out, n, 10u8)
                if e != ok { ret (n, e) }
                n = n1
                var i = 0u32
                while i < f.indent {
                    let (n2, e2) = emit(out, n, 32u8)
                    if e2 != ok { ret (n, e2) }
                    n = n2
                    i += 1u32
                }
                column = usize(f.indent)
            }
        } else if d.kind == .Nest {
            if top >= stack.len { ret (n, TooSmall) }
            stack[top] = Frame { doc: d.first, indent: f.indent + d.indent, flat: f.flat }
            top += 1usize
        } else if d.kind == .Concat {
            if top + 1usize >= stack.len { ret (n, TooSmall) }
            stack[top] = Frame { doc: d.second, indent: f.indent, flat: f.flat }
            stack[top + 1usize] = Frame { doc: d.first, indent: f.indent, flat: f.flat }
            top += 2usize
        } else {
            var flat = f.flat
            if !flat {
                if top >= stack.len { ret (n, TooSmall) }
                stack[top] = Frame { doc: d.first, indent: f.indent, flat: true }
                let (fits_flat, e) = fits(p, stack, top, top + 1usize, 0usize, i64(width) - i64(column))
                if e != ok { ret (n, e) }
                flat = fits_flat
            }
            if top >= stack.len { ret (n, TooSmall) }
            stack[top] = Frame { doc: d.first, indent: f.indent, flat: flat }
            top += 1usize
        }
    }
    ret (n, ok)
}
