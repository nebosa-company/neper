// `e.test.coverage` summaries, `e.test.fuzz` grammar generation and HDD, and
// `e.test.support` golden files, snapshots, fault injection and HTTP replay.
// Expected values come from scratchpad/test_gaps/ref.py; every check has its
// own exit code.

use e.algo.rand
use e.io
use e.mem
use e.os
use e.test
use e.test.coverage as coverage
use e.test.fuzz as fuzz
use e.test.support as support

error Crash

// Fails on a `[` opened inside a bracket.
fn nested(input: fuzz.Input) -> err {
    var depth = 0usize
    var i = 0usize
    while i < input.bytes.len {
        if input.bytes[i] == 91u8 {
            if depth > 0usize { ret Crash }
            depth += 1usize
        } else if input.bytes[i] == 93u8 && depth > 0usize { depth -= 1usize }
        i += 1usize
    }
    ret ok
}

fn balanced(bytes: []const u8) -> bool {
    var depth = 0i64
    var i = 0usize
    while i < bytes.len {
        let b = bytes[i]
        if b == 91u8 { depth += 1i64 }
        if b == 93u8 { depth -= 1i64 }
        if depth < 0i64 { ret false }
        if b != 91u8 && b != 93u8 && b != 44u8 && b != 49u8 { ret false }
        i += 1usize
    }
    ret depth == 0i64
}

type Record = struct { name: str, stamp: u64 }

fn serialise_record(rec: *Record, w: *io.Writer) -> err {
    try io.write_all(w, "name: ")
    try io.write_all(w, rec.name)
    try io.write_all(w, "\ntime: ")
    if rec.stamp == 12345u64 { try io.write_all(w, "12345") } else { try io.write_all(w, "0") }
    ret io.write_all(w, "\nid: 7\n")
}

fn node(terminal: bool, rule: usize, parent: usize, text: []const u8) -> fuzz.Node {
    ret fuzz.Node { terminal: terminal, rule: rule, parent: parent, text: text }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Coverage: blocks 3/6 = 50%, branches 3/6.
    var counters: [4]coverage.Counter = zero
    counters[0] = coverage.Counter { file_id: 0u32, region_id: 0u32, hits: 3u64 }
    counters[1] = coverage.Counter { file_id: 0u32, region_id: 1u32, hits: 0u64 }
    counters[2] = coverage.Counter { file_id: 0u32, region_id: 2u32, hits: 5u64 }
    counters[3] = coverage.Counter { file_id: 1u32, region_id: 0u32, hits: 1u64 }
    let summary = coverage.blocks(counters[..], 6usize)
    if summary.covered != 3usize || summary.total != 6usize || summary.percent != 50.0f64 { os.exit(1i32) }
    if coverage.blocks(counters[..0usize], 0usize).percent != 0.0f64 { os.exit(2i32) }
    var pairs: [3]coverage.Branch = zero
    pairs[0] = coverage.Branch { file_id: 0u32, taken: 0u32, not_taken: 1u32 }
    pairs[1] = coverage.Branch { file_id: 0u32, taken: 2u32, not_taken: 3u32 }
    pairs[2] = coverage.Branch { file_id: 1u32, taken: 0u32, not_taken: 1u32 }
    let (outcomes, total_outcomes) = coverage.branches(counters[..], pairs[..])
    if outcomes != 3usize || total_outcomes != 6usize { os.exit(3i32) }
    // MC/DC over A && (B || C): pairs (0,4), (0,1), (1,2); without vector 2, C has none.
    var vectors: [5]coverage.Vector = zero
    vectors[0] = coverage.Vector { mask: 3u32, outcome: true }
    vectors[1] = coverage.Vector { mask: 1u32, outcome: false }
    vectors[2] = coverage.Vector { mask: 5u32, outcome: true }
    vectors[3] = coverage.Vector { mask: 4u32, outcome: false }
    vectors[4] = coverage.Vector { mask: 2u32, outcome: false }
    var found: [3]coverage.Pair = zero
    let (covered, mcdc_error) = coverage.mcdc(3u32, vectors[..], found[..])
    if mcdc_error != ok || covered != 3usize { os.exit(4i32) }
    if !found[0].found || found[0].first != 0usize || found[0].second != 4usize { os.exit(5i32) }
    if !found[1].found || found[1].first != 0usize || found[1].second != 1usize { os.exit(6i32) }
    if !found[2].found || found[2].first != 1usize || found[2].second != 2usize { os.exit(7i32) }
    var fewer: [4]coverage.Vector = zero
    fewer[0] = vectors[0]
    fewer[1] = vectors[1]
    fewer[2] = vectors[3]
    fewer[3] = vectors[4]
    let (covered2, mcdc_error2) = coverage.mcdc(3u32, fewer[..], found[..])
    if mcdc_error2 != ok || covered2 != 2usize || found[2].found || found[0].second != 3usize { os.exit(8i32) }
    let (_, short_error) = coverage.mcdc(4u32, vectors[..], found[..])
    if short_error != coverage.TooLarge { os.exit(9i32) }

    // Grammar: value -> "1" | list; list -> "[" items "]"; items -> "" | value | value "," items.
    var value_one: [1]fuzz.Symbol = [1]fuzz.Symbol{ fuzz.terminal("1") }
    var value_list: [1]fuzz.Symbol = [1]fuzz.Symbol{ fuzz.nonterminal(1usize) }
    var list_body: [3]fuzz.Symbol = [3]fuzz.Symbol{ fuzz.terminal("["), fuzz.nonterminal(2usize), fuzz.terminal("]") }
    var items_empty: [1]fuzz.Symbol = [1]fuzz.Symbol{ fuzz.terminal("") }
    var items_one: [1]fuzz.Symbol = [1]fuzz.Symbol{ fuzz.nonterminal(0usize) }
    var items_more: [3]fuzz.Symbol = [3]fuzz.Symbol{ fuzz.nonterminal(0usize), fuzz.terminal(","), fuzz.nonterminal(2usize) }
    var value_alts: [2]fuzz.Alternative = [2]fuzz.Alternative{ fuzz.Alternative { symbols: value_one[..] }, fuzz.Alternative { symbols: value_list[..] } }
    var list_alts: [1]fuzz.Alternative = [1]fuzz.Alternative{ fuzz.Alternative { symbols: list_body[..] } }
    var items_alts: [3]fuzz.Alternative = [3]fuzz.Alternative{ fuzz.Alternative { symbols: items_empty[..] }, fuzz.Alternative { symbols: items_one[..] }, fuzz.Alternative { symbols: items_more[..] } }
    var rules: [3]fuzz.Rule = [3]fuzz.Rule{ fuzz.Rule { alternatives: value_alts[..] }, fuzz.Rule { alternatives: list_alts[..] }, fuzz.Rule { alternatives: items_alts[..] } }
    let g = fuzz.Grammar { rules: rules[..] }
    var out: [256]u8 = zero
    var scratch: [256]u8 = zero
    let (s0, s0_error) = fuzz.shortest(g, 0usize, out[..])
    if s0_error != ok || s0 != 1usize || out[0] != 49u8 { os.exit(10i32) }
    let (s1, s1_error) = fuzz.shortest(g, 1usize, out[..])
    if s1_error != ok || s1 != 2usize || out[0] != 91u8 || out[1] != 93u8 { os.exit(11i32) }
    var r = rand.pcg64(7u64, 1u64)
    var seen_list = false
    var round = 0usize
    while round < 20usize {
        let (n, gen_error) = fuzz.grammar(&r, g, 0usize, 6usize, out[..])
        if gen_error != ok || n == 0usize || !balanced(out[..n]) { os.exit(12i32) }
        if out[0] == 91u8 { seen_list = true }
        round += 1usize
    }
    if !seen_list { os.exit(13i32) }
    let (_, tiny_error) = fuzz.grammar(&r, g, 1usize, 0usize, out[..1usize])
    if tiny_error != fuzz.Limit { os.exit(14i32) }
    // A grammar that cannot end is refused.
    var loop_body: [1]fuzz.Symbol = [1]fuzz.Symbol{ fuzz.nonterminal(0usize) }
    var loop_alts: [1]fuzz.Alternative = [1]fuzz.Alternative{ fuzz.Alternative { symbols: loop_body[..] } }
    var loop_rules: [1]fuzz.Rule = [1]fuzz.Rule{ fuzz.Rule { alternatives: loop_alts[..] } }
    let (_, loop_error) = fuzz.grammar(&r, fuzz.Grammar { rules: loop_rules[..] }, 0usize, 3usize, out[..])
    if loop_error != fuzz.InvalidCorpus { os.exit(15i32) }

    // HDD over the derivation of `[1,[2],3]` minimizes to `[1,[],]` (7 bytes).
    let none = 0usize
    var nodes: [20]fuzz.Node = zero
    nodes[0] = node(false, 0usize, none, "")
    nodes[1] = node(false, 1usize, 0usize, "")
    nodes[2] = node(true, none, 1usize, "[")
    nodes[3] = node(false, 2usize, 1usize, "")
    nodes[4] = node(false, 0usize, 3usize, "")
    nodes[5] = node(true, none, 4usize, "1")
    nodes[6] = node(true, none, 3usize, ",")
    nodes[7] = node(false, 2usize, 3usize, "")
    nodes[8] = node(false, 0usize, 7usize, "")
    nodes[9] = node(false, 1usize, 8usize, "")
    nodes[10] = node(true, none, 9usize, "[")
    nodes[11] = node(false, 2usize, 9usize, "")
    nodes[12] = node(false, 0usize, 11usize, "")
    nodes[13] = node(true, none, 12usize, "2")
    nodes[14] = node(true, none, 9usize, "]")
    nodes[15] = node(true, none, 7usize, ",")
    nodes[16] = node(false, 2usize, 7usize, "")
    nodes[17] = node(false, 0usize, 16usize, "")
    nodes[18] = node(true, none, 17usize, "3")
    nodes[19] = node(true, none, 1usize, "]")
    let (small, small_error) = fuzz.minimize_tree(nested, g, nodes[..], 1u64, out[..], scratch[..])
    if small_error != ok || small != 7usize || !mem.eq[u8](out[..small], "[1,[],]") { os.exit(16i32) }
    if nested(fuzz.Input { bytes: out[..small], seed: 1u64 }) != Crash { os.exit(17i32) }

    // Golden.
    let (v1, at1) = support.golden("a\nb\nc\n", "a\nx\nc\n")
    if v1 != .Differ || at1 != 2usize { os.exit(18i32) }
    let (v2, at2) = support.golden("ab", "abc")
    if v2 != .Differ || at2 != 2usize { os.exit(19i32) }
    let (v3, at3) = support.golden("abc", "abc")
    if v3 != .Match || at3 != 3usize { os.exit(20i32) }
    var diff_capture: [32]u8 = zero
    var diff_slice = io.SliceWriter { data: diff_capture[..], off: 0usize }
    var sink_writer = io.slice_writer(&diff_slice)
    if support.golden_diff(a, &sink_writer, "a\nb\nc\n", "a\nx\nc\n") != ok { os.exit(22i32) }
    let diff_text = diff_capture[..diff_slice.off]
    if diff_text.len != 12usize || !mem.eq[u8](diff_text[..3usize], " a\n") || !mem.eq[u8](diff_text[9usize..], " c\n") { os.exit(23i32) }
    if !(mem.eq[u8](diff_text[3usize..9usize], "-b\n+x\n") || mem.eq[u8](diff_text[3usize..9usize], "+x\n-b\n")) { os.exit(24i32) }
    var update_capture: [8]u8 = zero
    var update_slice = io.SliceWriter { data: update_capture[..], off: 0usize }
    var sink2_writer = io.slice_writer(&update_slice)
    if support.golden_update(&sink2_writer, "new\n") != ok || !mem.eq[u8](update_capture[..update_slice.off], "new\n") { os.exit(26i32) }

    // Snapshot: the time line is volatile.
    var rec = Record { name: "foo", stamp: 12345u64 }
    var volatile: [1]str = [1]str{ "time:" }
    let (sv1, _, snap1_error) = support.snapshot[Record](a, &rec, serialise_record, "name: foo\ntime: 999\nid: 7\n", volatile[..], 64usize)
    if snap1_error != ok || sv1 != .Match { os.exit(27i32) }
    let (sv2, sat2, snap2_error) = support.snapshot[Record](a, &rec, serialise_record, "name: foo\ntime: 999\nid: 7\n", volatile[..0usize], 64usize)
    if snap2_error != ok || sv2 != .Differ || sat2 != 16usize { os.exit(28i32) }
    let (sv3, _, snap3_error) = support.snapshot[Record](a, &rec, serialise_record, "name: bar\ntime: 999\nid: 7\n", volatile[..], 64usize)
    if snap3_error != ok || sv3 != .Differ { os.exit(29i32) }

    // Fault plans.
    var third = support.fault_nth(3u64, io.NoProgress)
    if support.inject_fault(&third, 1u64) || support.inject_fault(&third, 1u64) || !support.inject_fault(&third, 1u64) || support.inject_fault(&third, 1u64) { os.exit(30i32) }
    var every = support.fault_every(2u64, io.NoProgress)
    if support.inject_fault(&every, 0u64) || !support.inject_fault(&every, 0u64) || support.inject_fault(&every, 0u64) || !support.inject_fault(&every, 0u64) { os.exit(31i32) }
    var elsewhere = support.fault_nth(1u64, io.NoProgress)
    elsewhere.site = 5u64
    if support.inject_fault(&elsewhere, 4u64) || !support.inject_fault(&elsewhere, 5u64) { os.exit(32i32) }
    var never = support.fault_probability(0.0f64, &r, io.NoProgress)
    var always = support.fault_probability(1.0f64, &r, io.NoProgress)
    round = 0usize
    while round < 50usize {
        if support.inject_fault(&never, 0u64) || !support.inject_fault(&always, 0u64) { os.exit(33i32) }
        round += 1usize
    }
    // A faulty reader over "hello world" fails its second read only.
    var source = io.SliceReader { data: "hello world", off: 0usize }
    var second = support.fault_nth(2u64, io.NoProgress)
    let (faulty, faulty_error) = support.faulty_reader(a, io.slice_reader(&source), &second, 0u64)
    if faulty_error != ok { os.exit(34i32) }
    var fr = faulty
    var buffer: [5]u8 = zero
    let (n1, e1) = io.read(&fr, buffer[..])
    if n1 != 5usize || e1 != ok || !mem.eq[u8](buffer[..], "hello") { os.exit(35i32) }
    let (n2, e2) = io.read(&fr, buffer[..])
    if n2 != 0usize || e2 != io.NoProgress { os.exit(36i32) }
    let (n3, e3) = io.read(&fr, buffer[..])
    if n3 != 5usize || e3 != ok || !mem.eq[u8](buffer[..], " worl") { os.exit(37i32) }
    var capture: [16]u8 = zero
    var target_slice = io.SliceWriter { data: capture[..], off: 0usize }
    var first = support.fault_nth(1u64, io.NoProgress)
    let (faulty_sink, faulty_sink_error) = support.faulty_writer(a, io.slice_writer(&target_slice), &first, 0u64)
    if faulty_sink_error != ok { os.exit(38i32) }
    var fw = faulty_sink
    let (w1, we1) = io.write(&fw, "abc")
    if w1 != 0usize || we1 != io.NoProgress { os.exit(39i32) }
    let (w2, we2) = io.write(&fw, "abc")
    if w2 != 3usize || we2 != ok || !mem.eq[u8](capture[..3usize], "abc") { os.exit(40i32) }

    // HTTP record and replay.
    var slots: [3]support.Exchange = zero
    var cassette = support.Cassette { exchanges: slots[..], count: 0usize, match_body: false }
    if support.http_record(&cassette, "GET /a HTTP/1.1\r\nHost: x\r\n\r\n", "200 a") != ok { os.exit(41i32) }
    if support.http_record(&cassette, "POST /b HTTP/1.1\r\nHost: x\r\n\r\nbody1", "201 b") != ok { os.exit(42i32) }
    if support.http_record(&cassette, "GET /c HTTP/1.1\r\n\r\n", "200 c") != ok { os.exit(43i32) }
    if support.http_record(&cassette, "GET /d HTTP/1.1\r\n\r\n", "200 d") != io.TooSmall { os.exit(44i32) }
    if support.http_record(&cassette, "nonsense", "x") != test.Failed { os.exit(45i32) }
    let (r1, m1) = support.http_replay(&cassette, "GET /a HTTP/1.1\r\nHost: y\r\n\r\n")
    if !m1 || !mem.eq[u8](r1, "200 a") { os.exit(46i32) }
    let (_, m2) = support.http_replay(&cassette, "GET /zzz HTTP/1.1\r\n\r\n")
    if m2 { os.exit(47i32) }
    let (_, m3) = support.http_replay(&cassette, "DELETE /a HTTP/1.1\r\n\r\n")
    if m3 { os.exit(48i32) }
    let (r4, m4) = support.http_replay(&cassette, "POST /b HTTP/1.1\r\n\r\nother")
    if !m4 || !mem.eq[u8](r4, "201 b") { os.exit(49i32) }
    cassette.match_body = true
    let (_, m5) = support.http_replay(&cassette, "POST /b HTTP/1.1\r\n\r\nother")
    if m5 { os.exit(50i32) }
    let (r6, m6) = support.http_replay(&cassette, "POST /b HTTP/1.1\r\nX: 1\r\n\r\nbody1")
    if !m6 || !mem.eq[u8](r6, "201 b") { os.exit(51i32) }
    let (r7, m7) = support.http_replay(&cassette, "GET /c HTTP/1.1\r\n\r\n")
    if !m7 || !mem.eq[u8](r7, "200 c") { os.exit(52i32) }

    try io.print("test gaps ok\n")
    ret ok
}
