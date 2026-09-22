// In-process fuzzing: `run` feeds a target the corpus as given, then mutations of
// it until one fails, the run budget is spent or the deadline passes; `minimize`
// shrinks a failing input while it keeps failing. Everything is deterministic:
// mutation `i` of the run draws from a PCG seeded by the base entry's `seed` and
// `i`, so a failing input's `seed` and the corpus reproduce it. Corpus
// persistence, subprocess isolation and reproduction commands are the harness's
// (`neper test --fuzz`), as the fence says; nothing here touches a file.
//
// `Options`: `max_input` bounds every candidate (0 means 4096); `max_runs` bounds
// the target calls, corpus included (0 means no bound); `deadline` is a monotonic
// instant (`nanos` 0 means none). A run with neither bound is refused with
// `Limit`, since it could not end. An empty corpus, or an entry over `max_input`,
// is `InvalidCorpus`. `minimize` answers the smallest input it reached; when the
// deadline passes first it answers the best so far with `Limit`.
//
// Mutations: flip a bit, set a byte to a random or an interesting value, insert,
// delete, duplicate a range, splice in another corpus entry -- one to four per
// candidate. Minimization is delta debugging: drop halves, then quarters, down
// to single bytes, then simplify bytes toward zero, repeating until a pass
// changes nothing. ponytail: no coverage feedback (the compiler's instrumentation
// is not here yet); a candidate that reaches new regions would join the corpus.

use e.algo.rand
use e.mem
use e.test
use e.time

type Input = struct { bytes: []const u8, seed: u64 }
type Options = struct { max_input: usize, max_runs: u64, deadline: time.Instant }
type Result = struct { runs: u64, failing: Input, failed: bool }
type Target = fn(input: Input) -> err
error InvalidCorpus
error Limit

const DEFAULT_MAX_INPUT: usize = 4096usize

fn interesting(r: *rand.Pcg64) -> u8 {
    let values: [8]u8 = [8]u8{ 0, 1, 127, 128, 255, 254, 32, 10 }
    ret values[usize(rand.pcg64_bounded(r, 8u64))]
}

// One candidate from `base` into `buffer`; answers its length.
fn mutate(r: *rand.Pcg64, base: []const u8, corpus: []const Input, buffer: []u8, max_input: usize) -> usize {
    var len = base.len
    if len > max_input { len = max_input }
    mem.copy[u8](buffer[..len], base[..len])
    let rounds = 1usize + usize(rand.pcg64_bounded(r, 4u64))
    var round = 0usize
    while round < rounds {
        let op = rand.pcg64_bounded(r, 7u64)
        if op == 0u64 && len > 0usize {
            let at = usize(rand.pcg64_bounded(r, u64(len)))
            buffer[at] = buffer[at] ^ u8(1u64 << rand.pcg64_bounded(r, 8u64))
        } else if op == 1u64 && len > 0usize {
            let at = usize(rand.pcg64_bounded(r, u64(len)))
            buffer[at] = u8(rand.pcg64_bounded(r, 256u64))
        } else if op == 2u64 && len > 0usize {
            let at = usize(rand.pcg64_bounded(r, u64(len)))
            buffer[at] = interesting(r)
        } else if op == 3u64 && len < max_input {
            let at = usize(rand.pcg64_bounded(r, u64(len) + 1u64))
            var i = len
            while i > at {
                buffer[i] = buffer[i - 1usize]
                i -= 1usize
            }
            var value = u8(rand.pcg64_bounded(r, 256u64))
            if rand.pcg64_bounded(r, 2u64) == 0u64 { value = interesting(r) }
            buffer[at] = value
            len += 1usize
        } else if op == 4u64 && len > 0usize {
            let at = usize(rand.pcg64_bounded(r, u64(len)))
            var i = at
            while i + 1usize < len {
                buffer[i] = buffer[i + 1usize]
                i += 1usize
            }
            len -= 1usize
        } else if op == 5u64 && len > 0usize && len < max_input {
            // Duplicate a range after itself, as far as the bound allows.
            let from = usize(rand.pcg64_bounded(r, u64(len)))
            var count = 1usize + usize(rand.pcg64_bounded(r, u64(len - from)))
            if len + count > max_input { count = max_input - len }
            var i = len
            while i > from + count {
                buffer[i + count - 1usize] = buffer[i - 1usize]
                i -= 1usize
            }
            i = 0usize
            while i < count {
                buffer[from + count + i] = buffer[from + i]
                i += 1usize
            }
            len += count
        } else if op == 6u64 && corpus.len > 0usize {
            // Splice: the tail of another entry replaces this one's tail.
            let other = corpus[usize(rand.pcg64_bounded(r, u64(corpus.len)))].bytes
            if other.len > 0usize {
                let cut = usize(rand.pcg64_bounded(r, u64(len) + 1u64))
                let from = usize(rand.pcg64_bounded(r, u64(other.len)))
                var count = other.len - from
                if cut + count > max_input { count = max_input - cut }
                mem.copy[u8](buffer[cut..cut + count], other[from..from + count])
                len = cut + count
            }
        }
        round += 1usize
    }
    ret len
}

fn past(deadline: time.Instant) -> (bool, err) {
    if deadline.nanos == 0i64 { ret (false, ok) }
    let (now, now_error) = time.monotonic()
    if now_error != ok { ret (false, now_error) }
    ret (time.instant_cmp(now, deadline) >= 0i32, ok)
}

fn keep(a: *mem.Arena, bytes: []const u8, seed: u64) -> (Input, err) {
    let (copy, copy_error) = mem.alloc[u8](a, bytes.len)
    if copy_error != ok { ret (zero, copy_error) }
    mem.copy[u8](copy, bytes)
    ret (Input { bytes: copy, seed: seed }, ok)
}

fn run(a: *mem.Arena, target_fn: Target, corpus: []const Input, options: Options) -> (Result, err) {
    var max_input = options.max_input
    if max_input == 0usize { max_input = DEFAULT_MAX_INPUT }
    if corpus.len == 0usize { ret (zero, InvalidCorpus) }
    var i = 0usize
    while i < corpus.len {
        if corpus[i].bytes.len > max_input { ret (zero, InvalidCorpus) }
        i += 1usize
    }
    if options.max_runs == 0u64 && options.deadline.nanos == 0i64 { ret (zero, Limit) }
    var runs = 0u64
    // The corpus first, as given.
    i = 0usize
    while i < corpus.len {
        if options.max_runs > 0u64 && runs >= options.max_runs { break }
        runs += 1u64
        if target_fn(corpus[i]) != ok {
            let (failing, keep_error) = keep(a, corpus[i].bytes, corpus[i].seed)
            if keep_error != ok { ret (zero, keep_error) }
            ret (Result { runs: runs, failing: failing, failed: true }, ok)
        }
        i += 1usize
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, max_input)
    if buffer_error != ok { ret (zero, buffer_error) }
    var index = 0u64
    while options.max_runs == 0u64 || runs < options.max_runs {
        let (over, past_error) = past(options.deadline)
        if past_error != ok { ret (zero, past_error) }
        if over { break }
        let base = corpus[usize(index % u64(corpus.len))]
        var r = rand.pcg64(base.seed, index)
        let len = mutate(&r, base.bytes, corpus, buffer, max_input)
        let candidate = Input { bytes: buffer[..len], seed: base.seed ^ (index *% 6364136223846793005u64) }
        runs += 1u64
        if target_fn(candidate) != ok {
            let (failing, keep_error) = keep(a, candidate.bytes, candidate.seed)
            if keep_error != ok { ret (zero, keep_error) }
            ret (Result { runs: runs, failing: failing, failed: true }, ok)
        }
        index += 1u64
    }
    ret (Result { runs: runs, failing: zero, failed: false }, ok)
}

// Whether `candidate` still fails; a passing candidate is not kept.
fn still_fails(target_fn: Target, candidate: []const u8, seed: u64) -> bool {
    ret target_fn(Input { bytes: candidate, seed: seed }) != ok
}

fn minimize(a: *mem.Arena, target_fn: Target, failing: Input, deadline: time.Instant) -> (Input, err) {
    let (best, best_error) = mem.alloc[u8](a, failing.bytes.len)
    if best_error != ok { ret (zero, best_error) }
    let (scratch, scratch_error) = mem.alloc[u8](a, failing.bytes.len)
    if scratch_error != ok { ret (zero, scratch_error) }
    mem.copy[u8](best, failing.bytes)
    var len = failing.bytes.len
    if !still_fails(target_fn, best[..len], failing.seed) { ret (Input { bytes: best[..len], seed: failing.seed }, ok) }
    var changed = true
    while changed && len > 0usize {
        changed = false
        // Drop a chunk: halves, then quarters, down to single bytes.
        var chunk = len / 2usize
        if chunk == 0usize { chunk = 1usize }
        while chunk >= 1usize {
            var at = 0usize
            while at < len {
                let (over, past_error) = past(deadline)
                if past_error != ok { ret (zero, past_error) }
                if over { ret (Input { bytes: best[..len], seed: failing.seed }, Limit) }
                var take = chunk
                if at + take > len { take = len - at }
                mem.copy[u8](scratch[..at], best[..at])
                mem.copy[u8](scratch[at..len - take], best[at + take..len])
                if still_fails(target_fn, scratch[..len - take], failing.seed) {
                    mem.copy[u8](best[..len - take], scratch[..len - take])
                    len -= take
                    changed = true
                } else {
                    at += take
                }
            }
            if chunk == 1usize { break }
            chunk = chunk / 2usize
        }
        // Simplify bytes: toward zero, then toward a printable.
        var at = 0usize
        while at < len {
            if best[at] != 0u8 {
                let (over, past_error) = past(deadline)
                if past_error != ok { ret (zero, past_error) }
                if over { ret (Input { bytes: best[..len], seed: failing.seed }, Limit) }
                mem.copy[u8](scratch[..len], best[..len])
                scratch[at] = 0u8
                if still_fails(target_fn, scratch[..len], failing.seed) {
                    best[at] = 0u8
                    changed = true
                } else if best[at] != 97u8 {
                    scratch[at] = 97u8
                    if still_fails(target_fn, scratch[..len], failing.seed) {
                        best[at] = 97u8
                        changed = true
                    }
                }
            }
            at += 1usize
        }
    }
    ret (Input { bytes: best[..len], seed: failing.seed }, ok)
}

// Grammar-based generation and hierarchical delta debugging, over caller
// arrays. A `Grammar` is rules of alternatives of symbols, a symbol a terminal
// (its `text`) or a reference to a rule; `grammar` derives a sentence from
// `start`, choosing alternatives at random until `max_depth`, from where every
// choice is the alternative with the shortest derivation (so generation always
// ends when the grammar can end); `shortest` is that derivation alone.
// `minimize_tree` is HDD (Misherghi and Su): a derivation as pre-ordered
// `Node`s linked by `parent` (node 0 the root, children in index order), and
// level by level the nonterminal nodes still standing are reduced by ddmin
// (Zeller; complements only, the whole level tried first), a reduced node
// rendering as the shortest sentence of its rule; the answer is the sentence
// of what stands. ponytail: rules are capped at MAX_RULES and nodes at
// MAX_NODES so the shortest lengths and the marks live on the stack; a
// caller-supplied scratch would lift both.

type Symbol = struct { terminal: bool, rule: usize, text: []const u8 }
type Alternative = struct { symbols: []const Symbol }
type Rule = struct { alternatives: []const Alternative }
type Grammar = struct { rules: []const Rule }
type Node = struct { terminal: bool, rule: usize, parent: usize, text: []const u8 }
error TooLarge

const MAX_RULES: usize = 64usize
const MAX_NODES: usize = 256usize
const UNREACHABLE: usize = 1000000000usize

fn terminal(text: []const u8) -> Symbol { ret Symbol { terminal: true, rule: 0usize, text: text } }
fn nonterminal(rule: usize) -> Symbol { ret Symbol { terminal: false, rule: rule, text: zero } }

fn alternative_len(g: Grammar, alt: Alternative, min_len: []const usize) -> usize {
    var total = 0usize
    var i = 0usize
    while i < alt.symbols.len {
        let s = alt.symbols[i]
        if s.terminal { total += s.text.len } else {
            if s.rule >= g.rules.len || min_len[s.rule] >= UNREACHABLE { ret UNREACHABLE }
            total += min_len[s.rule]
        }
        i += 1usize
    }
    ret total
}

// The shortest sentence length per rule, by fixpoint; `UNREACHABLE` for a rule that cannot end.
fn shortest_lengths(g: Grammar, min_len: []usize) -> err {
    if g.rules.len > min_len.len { ret TooLarge }
    var i = 0usize
    while i < g.rules.len {
        min_len[i] = UNREACHABLE
        i += 1usize
    }
    var changed = true
    while changed {
        changed = false
        i = 0usize
        while i < g.rules.len {
            var k = 0usize
            while k < g.rules[i].alternatives.len {
                let n = alternative_len(g, g.rules[i].alternatives[k], min_len)
                if n < min_len[i] {
                    min_len[i] = n
                    changed = true
                }
                k += 1usize
            }
            i += 1usize
        }
    }
    ret ok
}

fn shortest_alternative(g: Grammar, rule: usize, min_len: []const usize) -> usize {
    var best = 0usize
    var best_len = UNREACHABLE
    var k = 0usize
    while k < g.rules[rule].alternatives.len {
        let n = alternative_len(g, g.rules[rule].alternatives[k], min_len)
        if n < best_len {
            best_len = n
            best = k
        }
        k += 1usize
    }
    ret best
}

fn expand(r: *rand.Pcg64, g: Grammar, rule: usize, depth: usize, max_depth: usize, min_len: []const usize, out: []u8, at: usize) -> (usize, err) {
    if rule >= g.rules.len || g.rules[rule].alternatives.len == 0usize || min_len[rule] >= UNREACHABLE { ret (at, InvalidCorpus) }
    var pick = shortest_alternative(g, rule, min_len)
    if depth < max_depth { pick = usize(rand.pcg64_bounded(r, u64(g.rules[rule].alternatives.len))) }
    let alt = g.rules[rule].alternatives[pick]
    var pos = at
    var i = 0usize
    while i < alt.symbols.len {
        let s = alt.symbols[i]
        if s.terminal {
            if pos + s.text.len > out.len { ret (pos, Limit) }
            mem.copy[u8](out[pos..pos + s.text.len], s.text)
            pos += s.text.len
        } else {
            let (next_pos, e) = expand(r, g, s.rule, depth + 1usize, max_depth, min_len, out, pos)
            if e != ok { ret (next_pos, e) }
            pos = next_pos
        }
        i += 1usize
    }
    ret (pos, ok)
}

// A sentence from `start` into `out`; answers its length. `Limit` when `out`
// is too small, `InvalidCorpus` for a rule with no alternatives or no end.
fn grammar(r: *rand.Pcg64, g: Grammar, start: usize, max_depth: usize, out: []u8) -> (usize, err) {
    var min_len: [64]usize = zero
    let e = shortest_lengths(g, min_len[..])
    if e != ok { ret (0usize, e) }
    let (n, expand_error) = expand(r, g, start, 0usize, max_depth, min_len[..], out, 0usize)
    ret (n, expand_error)
}

fn shortest(g: Grammar, start: usize, out: []u8) -> (usize, err) {
    var r = rand.pcg64(0u64, 0u64)
    let (n, e) = grammar(&r, g, start, 0usize, out)
    ret (n, e)
}

fn render(g: Grammar, nodes: []const Node, node: usize, replaced: []const bool, min_len: []const usize, out: []u8, at: usize) -> (usize, err) {
    if replaced[node] {
        var r = rand.pcg64(0u64, 0u64)
        let (pos, e) = expand(&r, g, nodes[node].rule, 0usize, 0usize, min_len, out, at)
        ret (pos, e)
    }
    if nodes[node].terminal {
        let text = nodes[node].text
        if at + text.len > out.len { ret (at, Limit) }
        mem.copy[u8](out[at..at + text.len], text)
        ret (at + text.len, ok)
    }
    var pos = at
    var child = node + 1usize
    while child < nodes.len {
        if nodes[child].parent == node {
            let (next_pos, e) = render(g, nodes, child, replaced, min_len, out, pos)
            if e != ok { ret (next_pos, e) }
            pos = next_pos
        }
        child += 1usize
    }
    ret (pos, ok)
}

fn depth_of(nodes: []const Node, node: usize) -> usize {
    var d = 0usize
    var i = node
    while i != 0usize {
        i = nodes[i].parent
        d += 1usize
    }
    ret d
}

fn under_replaced(nodes: []const Node, node: usize, replaced: []const bool) -> bool {
    var i = node
    while i != 0usize {
        i = nodes[i].parent
        if replaced[i] { ret true }
    }
    ret false
}

fn tree_fails(target_fn: Target, g: Grammar, nodes: []const Node, replaced: []const bool, min_len: []const usize, scratch: []u8, seed: u64) -> (bool, err) {
    let (n, e) = render(g, nodes, 0usize, replaced, min_len, scratch, 0usize)
    if e != ok { ret (false, e) }
    ret (target_fn(Input { bytes: scratch[..n], seed: seed }) != ok, ok)
}

fn mark(set: []const usize, lo: usize, hi: usize, replaced: []bool, value: bool) {
    var i = lo
    while i < hi {
        replaced[set[i]] = value
        i += 1usize
    }
}

// The minimized sentence into `out` (`scratch` holds candidates; both at least
// the longest sentence the tree can render); answers its length.
fn minimize_tree(target_fn: Target, g: Grammar, nodes: []const Node, seed: u64, out: []u8, scratch: []u8) -> (usize, err) {
    if nodes.len == 0usize || nodes.len > MAX_NODES { ret (0usize, TooLarge) }
    var min_len: [64]usize = zero
    let lengths_error = shortest_lengths(g, min_len[..])
    if lengths_error != ok { ret (0usize, lengths_error) }
    var replaced: [256]bool = zero
    var level_nodes: [256]usize = zero
    var max_depth = 0usize
    var i = 0usize
    while i < nodes.len {
        let d = depth_of(nodes, i)
        if d > max_depth { max_depth = d }
        i += 1usize
    }
    var level = 0usize
    while level <= max_depth {
        var count = 0usize
        i = 0usize
        while i < nodes.len {
            if !nodes[i].terminal && depth_of(nodes, i) == level && !under_replaced(nodes, i, replaced[..]) {
                level_nodes[count] = i
                count += 1usize
            }
            i += 1usize
        }
        if count > 0usize {
            // The whole level first, then ddmin over what must stand.
            mark(level_nodes[..], 0usize, count, replaced[..], true)
            let (all_fail, all_error) = tree_fails(target_fn, g, nodes, replaced[..], min_len[..], scratch, seed)
            if all_error != ok { ret (0usize, all_error) }
            if !all_fail {
                mark(level_nodes[..], 0usize, count, replaced[..], false)
                var n = 2usize
                while count >= 2usize {
                    var some = false
                    var k = 0usize
                    while k < n && !some {
                        let lo = k * count / n
                        let hi = (k + 1usize) * count / n
                        mark(level_nodes[..], lo, hi, replaced[..], true)
                        let (fails, fail_error) = tree_fails(target_fn, g, nodes, replaced[..], min_len[..], scratch, seed)
                        if fail_error != ok { ret (0usize, fail_error) }
                        if fails {
                            var j = hi
                            while j < count {
                                level_nodes[lo + j - hi] = level_nodes[j]
                                j += 1usize
                            }
                            count -= hi - lo
                            if n > 2usize { n -= 1usize }
                            some = true
                        } else {
                            mark(level_nodes[..], lo, hi, replaced[..], false)
                        }
                        k += 1usize
                    }
                    if !some {
                        if n >= count { count = 0usize } else {
                            n *= 2usize
                            if n > count { n = count }
                        }
                    }
                }
            }
        }
        level += 1usize
    }
    let (len, render_error) = render(g, nodes, 0usize, replaced[..], min_len[..], out, 0usize)
    ret (len, render_error)
}
