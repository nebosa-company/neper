use lex
use graph

// Which `use` declarations of one module are never named: `check --unused-imports`.
// A qualifier is named when an identifier spelling it stands first in a `q.name`
// outside every `use` line; `x.q` is a field, not the module. `out` receives the
// token index of each unnamed `use`, up to its length, and the count is returned.
fn find(source: str, tokens: []const lex.Token, out: []usize) -> usize {
    var found = 0usize
    var at = 0usize
    while at < tokens.len {
        if tokens[at].kind == .KwUse && at + 1usize < tokens.len {
            var last = at + 1usize
            var end = last
            while end + 1usize < tokens.len && (tokens[end + 1usize].kind == .PunctDot || tokens[end + 1usize].kind == .Identifier) {
                end += 1usize
                if tokens[end].kind == .Identifier { last = end }
            }
            var qualifier = tokens[last]
            if end + 2usize < tokens.len && tokens[end + 1usize].kind == .KwAs { qualifier = tokens[end + 2usize] }
            let name = lex.token_text(source, qualifier)
            var named = false
            var scan = 0usize
            while scan + 1usize < tokens.len && !named {
                if tokens[scan].kind == .Identifier && tokens[scan + 1usize].kind == .PunctDot && (scan == 0usize || tokens[scan - 1usize].kind != .PunctDot) && graph.same(lex.token_text(source, tokens[scan]), name) {
                    var line = scan
                    while line > 0usize && tokens[line - 1usize].kind != .Newline { line = line - 1usize }
                    if tokens[line].kind != .KwUse { named = true }
                }
                scan += 1usize
            }
            if !named && found < out.len {
                out[found] = at
                found += 1usize
            }
            at = end
        }
        at += 1usize
    }
    ret found
}
