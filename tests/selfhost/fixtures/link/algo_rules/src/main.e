// `e.algo.rules`: the Rete engine, the DSL and decision tables against the independent
// brute-force model in scripts/gen_algo_rules_test.py. The expected counts, fact sets and fire
// logs below are that model's output for the same rule text and the same assertion order.
// Sections: forward chaining over facts asserted before the rule (S1), a transitive closure with
// its interleaved firing order (S2), conflict resolution by salience, recency, specificity and
// rule order (S3), arithmetic right-hand sides with retract (S4), negation both ways (S5),
// halt and the fire limit (S6), decision tables with the first-hit and collect policies (S7),
// and the refusals (S8). Every check has its own exit code.
use e.os
use e.mem
use e.algo.rules as rules

fn engine(a: *mem.Arena) -> (rules.Engine, err) {
    let lim = rules.Limits { facts: 64usize, tokens: 512usize, rules: 8usize, alphas: 16usize, entries: 256usize, names: 32usize, log: 64usize }
    let (e, init_error) = rules.init(a, lim)
    ret (e, init_error)
}

fn put(e: *rules.Engine, name: str, a: i64, b: i64, c: i64, n: usize) -> bool {
    let (k, kind_error) = rules.intern_kind(e, name)
    if kind_error != ok { ret false }
    var v: [3]i64 = zero
    v[0] = a
    v[1] = b
    v[2] = c
    let (id, fresh, assert_error) = rules.assert_fact(e, k, v[0..n])
    ret assert_error == ok
}

fn drop(e: *rules.Engine, name: str, a: i64, n: usize) -> bool {
    let (k, kind_error) = rules.intern_kind(e, name)
    if kind_error != ok { ret false }
    var v: [1]i64 = zero
    v[0] = a
    let (id, fresh, assert_error) = rules.assert_fact(e, k, v[0..n])
    if assert_error != ok || fresh { ret false }
    ret rules.retract(e, id) == ok
}

fn holds(e: *rules.Engine, name: str, a: i64, b: i64, c: i64, n: usize) -> bool {
    let (k, kind_error) = rules.intern_kind(e, name)
    if kind_error != ok { ret false }
    var v: [3]i64 = zero
    v[0] = a
    v[1] = b
    v[2] = c
    ret rules.has(e, k, v[0..n])
}

fn total(e: *rules.Engine, name: str) -> usize {
    let (k, kind_error) = rules.intern_kind(e, name)
    if kind_error != ok { ret 999usize }
    ret rules.count(e, k)
}

fn log_is(e: *rules.Engine, expected: []const u32) -> bool {
    var i = 0usize
    while i < expected.len {
        if rules.fired_rule(e, i) != expected[i] { ret false }
        i += 1usize
    }
    ret rules.fired_rule(e, expected.len) == rules.NONE
}

// S1: facts first, the rule after; three grandparent pairs.
fn s1(a: *mem.Arena) -> i32 {
    let (e0, engine_error) = engine(a)
    if engine_error != ok { ret 10i32 }
    var e = e0
    if !put(&e, "parent", 1i64, 2i64, 0i64, 2usize) { ret 11i32 }
    if !put(&e, "parent", 2i64, 3i64, 0i64, 2usize) { ret 11i32 }
    if !put(&e, "parent", 3i64, 4i64, 0i64, 2usize) { ret 11i32 }
    if !put(&e, "parent", 2i64, 5i64, 0i64, 2usize) { ret 11i32 }
    if rules.load(&e, "rule grand when parent(?x, ?y) parent(?y, ?z) then assert grandparent(?x, ?z) end") != ok { ret 12i32 }
    let (n, fire_error) = rules.fire(&e, 100usize)
    if fire_error != ok || n != 3usize { ret 13i32 }
    if total(&e, "grandparent") != 3usize { ret 14i32 }
    if !holds(&e, "grandparent", 1i64, 3i64, 0i64, 2usize) { ret 15i32 }
    if !holds(&e, "grandparent", 1i64, 5i64, 0i64, 2usize) { ret 16i32 }
    if !holds(&e, "grandparent", 2i64, 4i64, 0i64, 2usize) { ret 17i32 }
    // A duplicate assert is not a new fact and fires nothing.
    if !put(&e, "parent", 1i64, 2i64, 0i64, 2usize) { ret 18i32 }
    let (n2, fire_error2) = rules.fire(&e, 100usize)
    if fire_error2 != ok || n2 != 0usize { ret 19i32 }
    ret 0i32
}

// S2: the closure of parent over six facts, rules base=0 and step=1: 11 firings in the model's order.
fn s2(a: *mem.Arena) -> i32 {
    let (e0, engine_error) = engine(a)
    if engine_error != ok { ret 20i32 }
    var e = e0
    let src = "rule base when parent(?x, ?y) then assert anc(?x, ?y) end rule step when anc(?x, ?y) parent(?y, ?z) then assert anc(?x, ?z) end"
    if rules.load(&e, src) != ok { ret 21i32 }
    if !put(&e, "parent", 1i64, 2i64, 0i64, 2usize) { ret 22i32 }
    if !put(&e, "parent", 2i64, 3i64, 0i64, 2usize) { ret 22i32 }
    if !put(&e, "parent", 3i64, 4i64, 0i64, 2usize) { ret 22i32 }
    if !put(&e, "parent", 2i64, 5i64, 0i64, 2usize) { ret 22i32 }
    if !put(&e, "parent", 5i64, 6i64, 0i64, 2usize) { ret 22i32 }
    let (n, fire_error) = rules.fire(&e, 100usize)
    if fire_error != ok || n != 11usize { ret 23i32 }
    if total(&e, "anc") != 11usize { ret 24i32 }
    // "bbsbbsbssss"
    var expected: [11]u32 = zero
    expected[0] = 0u32
    expected[1] = 0u32
    expected[2] = 1u32
    expected[3] = 0u32
    expected[4] = 0u32
    expected[5] = 1u32
    expected[6] = 0u32
    expected[7] = 1u32
    expected[8] = 1u32
    expected[9] = 1u32
    expected[10] = 1u32
    if !log_is(&e, expected[0..]) { ret 25i32 }
    if !holds(&e, "anc", 1i64, 6i64, 0i64, 2usize) { ret 26i32 }
    if holds(&e, "anc", 4i64, 1i64, 0i64, 2usize) { ret 27i32 }
    ret 0i32
}

// S3: low=0 high=1 wide=2 pair=3 over a(1) a(2) a(3).
fn s3(a: *mem.Arena) -> i32 {
    let (e0, engine_error) = engine(a)
    if engine_error != ok { ret 30i32 }
    var e = e0
    let src = "rule low when a(?x) then assert lo(?x) end rule high salience 10 when a(?x) then assert hi(?x) end rule wide salience 10 when a(?x>1) then assert wi(?x) end rule pair when a(?x) a(?y>?x) then assert pr(?x, ?y) end"
    if rules.load(&e, src) != ok { ret 31i32 }
    if !put(&e, "a", 1i64, 0i64, 0i64, 1usize) { ret 32i32 }
    if !put(&e, "a", 2i64, 0i64, 0i64, 1usize) { ret 32i32 }
    if !put(&e, "a", 3i64, 0i64, 0i64, 1usize) { ret 32i32 }
    let (n, fire_error) = rules.fire(&e, 100usize)
    if fire_error != ok || n != 11usize { ret 33i32 }
    var expected: [11]u32 = zero
    expected[0] = 2u32
    expected[1] = 1u32
    expected[2] = 2u32
    expected[3] = 1u32
    expected[4] = 1u32
    expected[5] = 3u32
    expected[6] = 3u32
    expected[7] = 0u32
    expected[8] = 3u32
    expected[9] = 0u32
    expected[10] = 0u32
    if !log_is(&e, expected[0..]) { ret 34i32 }
    if total(&e, "pr") != 3usize || total(&e, "wi") != 2usize || total(&e, "hi") != 3usize || total(&e, "lo") != 3usize { ret 35i32 }
    ret 0i32
}

// S4: ten steps of a Fibonacci state, each a retract and an assert with arithmetic.
fn s4(a: *mem.Arena) -> i32 {
    let (e0, engine_error) = engine(a)
    if engine_error != ok { ret 40i32 }
    var e = e0
    if rules.load(&e, "rule step when state(?n<10, ?a, ?b) then retract 0 assert state(?n+1, ?b, ?a+?b) end") != ok { ret 41i32 }
    if !put(&e, "state", 0i64, 0i64, 1i64, 3usize) { ret 42i32 }
    let (n, fire_error) = rules.fire(&e, 100usize)
    if fire_error != ok || n != 10usize { ret 43i32 }
    if total(&e, "state") != 1usize { ret 44i32 }
    if !holds(&e, "state", 10i64, 55i64, 89i64, 3usize) { ret 45i32 }
    ret 0i32
}

// S5: a not-condition, blocked at assert, unblocked by a retract, and blocked before it fires.
fn s5(a: *mem.Arena) -> i32 {
    let (e0, engine_error) = engine(a)
    if engine_error != ok { ret 50i32 }
    var e = e0
    if rules.load(&e, "rule childless when person(?x) not has_child(?x) then assert childless(?x) end") != ok { ret 51i32 }
    if !put(&e, "person", 1i64, 0i64, 0i64, 1usize) { ret 52i32 }
    if !put(&e, "person", 2i64, 0i64, 0i64, 1usize) { ret 52i32 }
    if !put(&e, "has_child", 1i64, 0i64, 0i64, 1usize) { ret 52i32 }
    let (n1, f1) = rules.fire(&e, 100usize)
    if f1 != ok || n1 != 1usize { ret 53i32 }
    if total(&e, "childless") != 1usize || !holds(&e, "childless", 2i64, 0i64, 0i64, 1usize) { ret 54i32 }
    if !drop(&e, "has_child", 1i64, 1usize) { ret 55i32 }
    let (n2, f2) = rules.fire(&e, 100usize)
    if f2 != ok || n2 != 1usize { ret 56i32 }
    if total(&e, "childless") != 2usize || !holds(&e, "childless", 1i64, 0i64, 0i64, 1usize) { ret 57i32 }
    // person(3) would match, but has_child(3) is asserted before the agenda runs.
    if !put(&e, "person", 3i64, 0i64, 0i64, 1usize) { ret 58i32 }
    if !put(&e, "has_child", 3i64, 0i64, 0i64, 1usize) { ret 58i32 }
    let (n3, f3) = rules.fire(&e, 100usize)
    if f3 != ok || n3 != 0usize { ret 59i32 }
    if total(&e, "childless") != 2usize { ret 60i32 }
    ret 0i32
}

// S6: stop (salience 10) halts when n reaches 3; the limit bounds a loop that would not end.
fn s6(a: *mem.Arena) -> i32 {
    let (e0, engine_error) = engine(a)
    if engine_error != ok { ret 70i32 }
    var e = e0
    let src = "rule inc when n(?x<5) then retract 0 assert n(?x+1) end rule stop salience 10 when n(3) then halt end"
    if rules.load(&e, src) != ok { ret 71i32 }
    if !put(&e, "n", 0i64, 0i64, 0i64, 1usize) { ret 72i32 }
    let (n, fire_error) = rules.fire(&e, 100usize)
    if fire_error != ok || n != 4usize { ret 73i32 }
    if total(&e, "n") != 1usize || !holds(&e, "n", 3i64, 0i64, 0i64, 1usize) { ret 74i32 }
    var expected: [4]u32 = zero
    expected[0] = 0u32
    expected[1] = 0u32
    expected[2] = 0u32
    expected[3] = 1u32
    if !log_is(&e, expected[0..]) { ret 75i32 }
    // Resumed, the halted run carries on: the stop match was refracted, inc runs to 5.
    let (n2, fire_error2) = rules.fire(&e, 100usize)
    if fire_error2 != ok || n2 != 2usize || !holds(&e, "n", 5i64, 0i64, 0i64, 1usize) { ret 76i32 }
    // A limit stops a run short.
    let (e1, engine_error1) = engine(a)
    if engine_error1 != ok { ret 77i32 }
    var f = e1
    if rules.load(&f, "rule inc when n(?x<50) then retract 0 assert n(?x+1) end") != ok { ret 78i32 }
    if !put(&f, "n", 0i64, 0i64, 0i64, 1usize) { ret 78i32 }
    let (n3, fire_error3) = rules.fire(&f, 7usize)
    if fire_error3 != ok || n3 != 7usize || !holds(&f, "n", 7i64, 0i64, 0i64, 1usize) { ret 79i32 }
    ret 0i32
}

// S7: the table over applicant(age, score): rows (age >= 65 -> 30), (18 <= age < 65, score >= 100 -> 10),
// (18 <= age < 65 -> 5), (age < 18 -> 0), run for one input at a time in a fresh engine.
fn table(a: *mem.Arena, first_hit: bool, age: i64, score: i64, want_a: i64, want_b: i64) -> bool {
    let (e0, engine_error) = engine(a)
    if engine_error != ok { ret false }
    var e = e0
    var cols: [3]rules.Column = zero
    cols[0] = rules.Column { field: 0u32, op: rules.OP_GE }
    cols[1] = rules.Column { field: 0u32, op: rules.OP_LT }
    cols[2] = rules.Column { field: 1u32, op: rules.OP_GE }
    let any = rules.any_cell()
    var cells: [12]i64 = zero
    cells[0] = 65i64
    cells[1] = any
    cells[2] = any
    cells[3] = 18i64
    cells[4] = 65i64
    cells[5] = 100i64
    cells[6] = 18i64
    cells[7] = 65i64
    cells[8] = any
    cells[9] = any
    cells[10] = 18i64
    cells[11] = any
    var outs: [4]i64 = zero
    outs[0] = 30i64
    outs[1] = 10i64
    outs[2] = 5i64
    outs[3] = 0i64
    let t = rules.Table { name: "discount", in_kind: "applicant", out_kind: "pct", in_arity: 2usize, out_arity: 1usize, cols: cols[0..], rows: 4usize, cells: cells[0..], outs: outs[0..], first_hit: first_hit, salience: 100i32 }
    if rules.add_table(&e, t) != ok { ret false }
    if !put(&e, "applicant", age, score, 0i64, 2usize) { ret false }
    let (n, fire_error) = rules.fire(&e, 100usize)
    if fire_error != ok { ret false }
    var want = 0usize
    if want_a >= 0i64 { want += 1usize }
    if want_b >= 0i64 { want += 1usize }
    if total(&e, "pct") != want { ret false }
    if want_a >= 0i64 && !holds(&e, "pct", want_a, 0i64, 0i64, 1usize) { ret false }
    if want_b >= 0i64 && !holds(&e, "pct", want_b, 0i64, 0i64, 1usize) { ret false }
    ret true
}

fn s7(a: *mem.Arena) -> i32 {
    // first hit: one answer per input, the first matching row's
    if !table(a, true, 70i64, 0i64, 30i64, -1i64) { ret 80i32 }
    if !table(a, true, 30i64, 120i64, 10i64, -1i64) { ret 81i32 }
    if !table(a, true, 30i64, 50i64, 5i64, -1i64) { ret 82i32 }
    if !table(a, true, 10i64, 0i64, 0i64, -1i64) { ret 83i32 }
    if !table(a, true, 65i64, 0i64, 30i64, -1i64) { ret 84i32 }
    if !table(a, true, 18i64, 100i64, 10i64, -1i64) { ret 85i32 }
    // collect: every matching row answers
    if !table(a, false, 30i64, 120i64, 10i64, 5i64) { ret 86i32 }
    if !table(a, false, 70i64, 0i64, 30i64, -1i64) { ret 87i32 }
    if !table(a, false, 18i64, 99i64, 5i64, -1i64) { ret 88i32 }
    ret 0i32
}

// S8: refusals and capacity.
fn s8(a: *mem.Arena) -> i32 {
    let (e0, engine_error) = engine(a)
    if engine_error != ok { ret 90i32 }
    var e = e0
    if rules.load(&e, "rule r when p(?x) then assert q(?y) end") != rules.BadRule { ret 91i32 }
    if rules.load(&e, "rule r when p(?x then end") != rules.Syntax { ret 92i32 }
    if rules.load(&e, "rule r when p(?x>?y) then end") != rules.BadRule { ret 93i32 }
    if rules.load(&e, "frob") != rules.Syntax { ret 94i32 }
    let (k, kind_error) = rules.intern_kind(&e, "p")
    var big: [7]i64 = zero
    let (id, fresh, assert_error) = rules.assert_fact(&e, k, big[0..])
    if assert_error != rules.TooMany { ret 95i32 }
    if rules.retract(&e, 99u32) != rules.NotFound { ret 96i32 }
    let tiny = rules.Limits { facts: 2usize, tokens: 8usize, rules: 2usize, alphas: 4usize, entries: 8usize, names: 4usize, log: 4usize }
    let (t0, tiny_error) = rules.init(a, tiny)
    if tiny_error != ok { ret 97i32 }
    var t = t0
    if !put(&t, "p", 1i64, 0i64, 0i64, 1usize) { ret 98i32 }
    if !put(&t, "p", 2i64, 0i64, 0i64, 1usize) { ret 98i32 }
    let (k2, kind_error2) = rules.intern_kind(&t, "p")
    var one: [1]i64 = zero
    one[0] = 3i64
    let (id2, fresh2, full_error) = rules.assert_fact(&t, k2, one[0..])
    if full_error != rules.Full { ret 99i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var code = s1(a)
    if code == 0i32 { code = s2(a) }
    if code == 0i32 { code = s3(a) }
    if code == 0i32 { code = s4(a) }
    if code == 0i32 { code = s5(a) }
    if code == 0i32 { code = s6(a) }
    if code == 0i32 { code = s7(a) }
    if code == 0i32 { code = s8(a) }
    if code != 0i32 { os.exit(code) }
    ret ok
}
