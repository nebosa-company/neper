// `e.algo.journal` against appdor's own run journal (src/workflow/journal.js): scripts/journal_reference.mjs drives it
// through random operation scripts and writes `{"ops": [...], "e": one canonical result per op joined by newlines}`
// lines; the fixture replays the same ops over the Neper module and must render the same. Operations: `create`,
// `apply` (entries, header patch, rebase, expected override, tamper), `q` (an index query), `summary`, `clock`, and the
// store's `s_create`, `s_load`, `s_commit`, `s_due`, `s_list`.
use e.algo.journal as journal
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.contract as contract

fn members_of(x: json.Value) -> []const json.Member {
    var none: []const json.Member = zero
    switch x {
    case .Object as m:
        ret m
    default:
        ret none
    }
}

fn items_of(x: json.Value) -> []const json.Value {
    var none: []const json.Value = zero
    switch x {
    case .Array as xs:
        ret xs
    default:
        ret none
    }
}

fn field(v: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = journal.get(v, key)
    ret (x, found)
}

fn text_field(v: json.Value, key: str) -> str {
    let (x, found) = field(v, key)
    if !found { ret "" }
    let (s, is_text) = journal.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn count_field(v: json.Value, key: str, fallback: usize) -> (usize, bool) {
    let (x, found) = field(v, key)
    if !found { ret (fallback, false) }
    let (n, good) = journal.count_of(x)
    if !good { ret (fallback, false) }
    ret (n, true)
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn canon(a: *mem.Arena, v: json.Value) -> str {
    let (text, e) = contract.canonical_json(a, v)
    if e != ok { os.exit(81i32) }
    ret text
}

fn number(a: *mem.Arena, n: usize) -> json.Value {
    let (v, e) = journal.number_value(a, n)
    if e != ok { os.exit(82i32) }
    ret v
}

fn boolean(b: bool) -> str {
    if b { ret "true" }
    ret "false"
}

// A commit as the script describes it, built the way the reference builds it: entries, patch, rebase, expected, tamper.
// The result is the built commit value, or "" and the error text when an entry type is unknown.
fn build_commit(a: *mem.Arena, run: json.Value, spec: json.Value) -> (json.Value, str) {
    let (c, ce) = journal.begin_commit(a, run)
    if ce != ok { os.exit(83i32) }
    var commit = c
    let (entries, have_entries) = field(spec, "entries")
    let items = items_of(entries)
    if have_entries {
        var at = 0usize
        while at < items.len {
            let (kind, have_kind) = field(items[at], "type")
            let (kind_text, kind_is_text) = journal.string_of(kind)
            let (fields, have_fields) = field(items[at], "fields")
            var f = fields
            if !have_fields { f = .Null }
            if !have_kind || !kind_is_text { os.exit(84i32) }
            let added = journal.add(a, &commit, kind_text, f)
            if added != ok { ret (.Null, "unknown-journal-entry-type") }
            at += 1usize
        }
    }
    let (patch, have_patch) = field(spec, "patch")
    if have_patch {
        let set = journal.set_header(&commit, patch)
        if set != ok { os.exit(85i32) }
    }
    let (rebase_to, has_rebase) = count_field(spec, "rebase", 0usize)
    if has_rebase {
        let rebased = journal.rebase(a, &commit, rebase_to)
        if rebased != ok { os.exit(86i32) }
    }
    let (built, be) = journal.build(a, &commit)
    if be != ok { os.exit(87i32) }
    var result = built
    let (expected, has_expected) = count_field(spec, "expected", 0usize)
    if has_expected {
        let (o, oe) = journal.from_value(a, result)
        if oe != ok { os.exit(88i32) }
        var obj = o
        let put = journal.put(&obj, "expectedSeq", number(a, expected))
        if put != ok { os.exit(88i32) }
        result = journal.obj_value(&obj)
    }
    let (tamper, has_tamper) = field(spec, "tamper")
    if has_tamper {
        let (index, has_index) = count_field(tamper, "index", 0usize)
        let (to_seq, has_seq) = count_field(tamper, "seq", 0usize)
        let (built_entries, have_built) = field(result, "entries")
        let built_items = items_of(built_entries)
        if has_index && has_seq && have_built && index < built_items.len {
            let (copy, copy_error) = mem.alloc[json.Value](a, built_items.len + 1usize)
            if copy_error != ok { os.exit(89i32) }
            var i = 0usize
            while i < built_items.len {
                copy[i] = built_items[i]
                i += 1usize
            }
            let (eo, ee) = journal.from_value(a, built_items[index])
            if ee != ok { os.exit(89i32) }
            var entry = eo
            let put_seq = journal.put(&entry, "seq", number(a, to_seq))
            if put_seq != ok { os.exit(89i32) }
            copy[index] = journal.obj_value(&entry)
            let (ro, re) = journal.from_value(a, result)
            if re != ok { os.exit(89i32) }
            var out = ro
            let put_entries = journal.put(&out, "entries", json.Value{ Array: copy[0usize..built_items.len] })
            if put_entries != ok { os.exit(89i32) }
            result = journal.obj_value(&out)
        }
    }
    ret (result, "")
}

fn applied_value(a: *mem.Arena, r: journal.Applied) -> json.Value {
    if !r.landed { ret r.failure }
    let (o, oe) = journal.new_obj(a)
    if oe != ok { os.exit(90i32) }
    var out = o
    let p1 = journal.put(&out, "ok", json.Value{ Bool: true })
    let p2 = journal.put(&out, "run", r.run)
    if p1 != ok || p2 != ok { os.exit(90i32) }
    ret journal.obj_value(&out)
}

fn query(a: *mem.Arena, run: json.Value, name: str, key: str) -> str {
    if str.eq(name, "result") {
        let (v, found) = journal.result(run, key)
        if !found { ret "undefined" }
        ret canon(a, v)
    }
    if str.eq(name, "isComplete") { ret boolean(journal.is_complete(run, key)) }
    if str.eq(name, "skipped") || str.eq(name, "started") || str.eq(name, "branch") || str.eq(name, "loop") || str.eq(name, "signal") {
        var v: json.Value = .Null
        var found = false
        if str.eq(name, "skipped") {
            let (x, f) = journal.skipped(run, key)
            v = x
            found = f
        } else if str.eq(name, "started") {
            let (x, f) = journal.started(run, key)
            v = x
            found = f
        } else if str.eq(name, "branch") {
            let (x, f) = journal.branch(run, key)
            v = x
            found = f
        } else if str.eq(name, "loop") {
            let (x, f) = journal.loop_entry(run, key)
            v = x
            found = f
        } else {
            let (x, f) = journal.signal(run, key)
            v = x
            found = f
        }
        if !found { ret "undefined" }
        ret canon(a, v)
    }
    if str.eq(name, "forkBranches") {
        let (names, e) = journal.fork_branches(a, run, key)
        if e != ok { os.exit(91i32) }
        ret canon(a, json.Value{ Array: names })
    }
    if str.eq(name, "failureCount") { ret canon(a, number(a, journal.failure_count(run, key))) }
    if str.eq(name, "lastFailure") {
        let (v, found) = journal.last_failure(run, key)
        if !found { ret "undefined" }
        ret canon(a, v)
    }
    if str.eq(name, "hasSignal") { ret boolean(journal.has_signal(run, key)) }
    if str.eq(name, "timerFired") { ret boolean(journal.timer_fired(run, key)) }
    if str.eq(name, "hasRecorded") { ret boolean(journal.has_recorded(run, key)) }
    if str.eq(name, "recorded") {
        let (v, found) = journal.recorded(run, key)
        if !found { ret "undefined" }
        ret canon(a, v)
    }
    ret canon(a, number(a, journal.size(run)))
}

fn run_case(a: *mem.Arena, spec: json.Value) -> str {
    let (ops_value, have_ops) = field(spec, "ops")
    let ops = items_of(ops_value)
    var out = ""
    var run: json.Value = .Null
    let (made, store_error) = journal.new_store(a, text_field(spec, "prefix"))
    if store_error != ok { os.exit(92i32) }
    var store = made
    var at = 0usize
    while at < ops.len {
        let op = ops[at]
        let name = text_field(op, "op")
        var line = ""
        if str.eq(name, "create") {
            let (w, hw) = field(op, "workflow")
            let (t, ht) = field(op, "trigger")
            let (o, ho) = field(op, "options")
            let (r, re) = journal.create_run(a, w, t, o)
            if re != ok { os.exit(93i32) }
            run = r
            line = canon(a, run)
        } else if str.eq(name, "apply") {
            let (built, problem) = build_commit(a, run, op)
            if problem.len > 0usize {
                line = join(a, "error:", problem)
            } else {
                let (applied, ae) = journal.apply_commit(a, run, built)
                if ae != ok { os.exit(94i32) }
                if applied.landed { run = applied.run }
                line = canon(a, applied_value(a, applied))
            }
        } else if str.eq(name, "q") {
            line = query(a, run, text_field(op, "name"), text_field(op, "key"))
        } else if str.eq(name, "summary") {
            let (s, se) = journal.summarize_run(a, run)
            if se != ok { os.exit(95i32) }
            line = canon(a, s)
        } else if str.eq(name, "clock") {
            let (c, ce) = journal.begin_commit(a, run)
            if ce != ok { os.exit(96i32) }
            var commit = c
            let (now, has_now) = count_field(op, "now", 0usize)
            let (value, has_value, clock_error) = journal.record_clock(a, run, &commit, text_field(op, "key"), number(a, now))
            if clock_error != ok { os.exit(96i32) }
            var wrote = false
            if !journal.is_empty(&commit) {
                let (built, be) = journal.build(a, &commit)
                if be != ok { os.exit(96i32) }
                let (applied, ae) = journal.apply_commit(a, run, built)
                if ae != ok { os.exit(96i32) }
                if applied.landed {
                    run = applied.run
                    wrote = true
                }
            }
            let (o, oe) = journal.new_obj(a)
            if oe != ok { os.exit(96i32) }
            var result = o
            if has_value {
                let pv = journal.put(&result, "value", value)
                if pv != ok { os.exit(96i32) }
            }
            let pw = journal.put(&result, "wrote", json.Value{ Bool: wrote })
            if pw != ok { os.exit(96i32) }
            line = canon(a, journal.obj_value(&result))
        } else if str.eq(name, "s_create") {
            let (w, hw) = field(op, "workflow")
            let (t, ht) = field(op, "trigger")
            let (o, ho) = field(op, "options")
            let (r, re) = journal.create_run(a, w, t, o)
            if re != ok { os.exit(97i32) }
            let (header, have_header) = field(op, "header")
            var fresh = r
            if have_header {
                let (ob, obe) = journal.from_value(a, r)
                if obe != ok { os.exit(97i32) }
                var obj = ob
                let assigned = journal.assign(&obj, header)
                if assigned != ok { os.exit(97i32) }
                fresh = journal.obj_value(&obj)
            }
            let (stored, ce) = journal.store_create(&store, fresh)
            if ce != ok { os.exit(97i32) }
            line = canon(a, stored)
        } else if str.eq(name, "s_load") {
            let (v, found) = journal.store_load(&store, text_field(op, "id"))
            if found { line = canon(a, v) } else { line = "null" }
        } else if str.eq(name, "s_commit") {
            let id = text_field(op, "id")
            let (loaded, found) = journal.store_load(&store, id)
            if !found {
                let (o, oe) = journal.new_obj(a)
                if oe != ok { os.exit(98i32) }
                var dummy = o
                let empty_entries: []const json.Value = zero
                let empty_patch: []const json.Member = zero
                let p1 = journal.put(&dummy, "expectedSeq", number(a, 0usize))
                let p2 = journal.put(&dummy, "entries", json.Value{ Array: empty_entries })
                let p3 = journal.put(&dummy, "patch", json.Value{ Object: empty_patch })
                if p1 != ok || p2 != ok || p3 != ok { os.exit(98i32) }
                let (r, re) = journal.store_commit(&store, id, journal.obj_value(&dummy))
                if re != ok { os.exit(98i32) }
                line = canon(a, r)
            } else {
                let (built, problem) = build_commit(a, loaded, op)
                if problem.len > 0usize {
                    line = join(a, "error:", problem)
                } else {
                    let (r, re) = journal.store_commit(&store, id, built)
                    if re != ok { os.exit(98i32) }
                    line = canon(a, r)
                }
            }
        } else if str.eq(name, "s_due") {
            let (now, has_now) = count_field(op, "now", 0usize)
            let (limit, has_limit) = count_field(op, "limit", 100usize)
            let (due, de) = journal.store_due(&store, number(a, now), limit)
            if de != ok { os.exit(99i32) }
            line = canon(a, json.Value{ Array: due })
        } else {
            line = canon(a, json.Value{ Array: journal.store_list(&store) })
        }
        if at > 0usize { out = join(a, out, "\n") }
        out = join(a, out, line)
        at += 1usize
    }
    ret out
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 40u16 })
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                want = text_field(root, "e")
                got = run_case(a, root)
                good = str.eq(got, want)
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(join(a, "\ngot ", got))
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("algo journal ok")
    ret ok
}
