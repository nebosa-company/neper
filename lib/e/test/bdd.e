// A Gherkin feature parser and a BDD runner whose step definitions bind through
// `e.meta`. The supported dialect is `Feature:`, `Background:`, `Scenario:` and
// `Scenario Outline:` with `Examples:` tables (`<name>` substituted in step text and
// step tables), `Given`/`When`/`Then`/`And`/`But`/`*` steps, `|`-delimited data tables
// under a step, `@tag` lines (feature tags apply to every scenario) and `#` comments.
// Free text under `Feature:` is a description and is ignored. Doc strings (`"""`),
// `Rule:` and non-English keywords are `Unsupported`.
//
// Parsing borrows the source text and writes into caller arrays (`document`);
// only outline substitutions allocate, from the arena given to `parse`. Each scenario
// owns a copy of the background steps followed by its own, so a scenario's steps are
// one run in `steps[step_start..step_start + step_count]`.
//
// A step definition set is a struct whose fields are all functions
// `fn(*World, *const Args) -> err`. A field's NAME is the step pattern: its words are
// separated by `_`, literal words match the step's words ignoring ASCII case, and the
// reserved words `int`, `word` and `quoted` capture an integer, any bare word, or a
// "double quoted" string into `Args.values` in order. `i_have_int_cucumbers` binds
// "I have 12 cucumbers"; `the_basket_contains_quoted` binds `the basket contains "a b"`.
// The step keyword is not part of the pattern. A step no field matches, and one whose
// function answers `Pending`, is reported pending; any other error fails the step; the
// remaining steps of that scenario are skipped.

use e.mem
use e.meta
use e.str

type Keyword = enum u8 { Given, When, Then, And, But }
type Outcome = enum u8 { Passed, Failed, Pending, Skipped, Filtered }
// A table under the step is `rows * cols` cells at `cells[cell_start..]`, row-major.
type Step = struct { keyword: Keyword, text: str, cell_start: usize, rows: usize, cols: usize, line: u32 }
type Scenario = struct { name: str, tag_start: usize, tag_count: usize, step_start: usize, step_count: usize, line: u32 }
type Document = struct { feature: str, feature_tag_count: usize, scenarios: []Scenario, steps: []Step, cells: []str, tags: []str, n_scenarios: usize, n_steps: usize, n_cells: usize, n_tags: usize, error_line: u32 }
// Include: a scenario runs when it (or the feature) carries any include tag, or the
// list is empty. Exclude: a scenario carrying any exclude tag never runs. Tags are
// written with the `@`.
type Filter = struct { include: []const str, exclude: []const str }
type Word = struct { text: str, quoted: bool }
type Args = struct { text: str, values: [4]str, count: usize, cells: []const str, rows: usize, cols: usize }
type Summary = struct { scenarios: usize, passed: usize, failed: usize, pending: usize, filtered: usize, steps_passed: usize, steps_failed: usize, steps_pending: usize, steps_skipped: usize }
error Invalid
error Unsupported
error TooSmall
error Pending

const MAX_WORDS: usize = 24usize
const MAX_TAGS_PER_LINE: usize = 16usize
const MAX_EXAMPLE_COLUMNS: usize = 8usize

fn document(scenarios: []Scenario, steps: []Step, cells: []str, tags: []str) -> Document {
    ret Document { feature: "", feature_tag_count: 0usize, scenarios: scenarios, steps: steps, cells: cells, tags: tags, n_scenarios: 0usize, n_steps: 0usize, n_cells: 0usize, n_tags: 0usize, error_line: 0u32 }
}

fn push_tag(d: *Document, tag: str) -> err {
    if d.n_tags >= d.tags.len { ret TooSmall }
    d.tags[d.n_tags] = tag
    d.n_tags += 1usize
    ret ok
}

fn push_step(d: *Document, s: Step) -> err {
    if d.n_steps >= d.steps.len { ret TooSmall }
    d.steps[d.n_steps] = s
    d.n_steps += 1usize
    ret ok
}

fn push_cell(d: *Document, value: str) -> err {
    if d.n_cells >= d.cells.len { ret TooSmall }
    d.cells[d.n_cells] = value
    d.n_cells += 1usize
    ret ok
}

fn push_scenario(d: *Document, s: Scenario) -> err {
    if d.n_scenarios >= d.scenarios.len { ret TooSmall }
    d.scenarios[d.n_scenarios] = s
    d.n_scenarios += 1usize
    ret ok
}

// The keyword of a step line and the text after it; false when the line is not a step.
fn step_line(line: str) -> (Keyword, str, bool) {
    if str.starts_with(line, "Given ") { ret (.Given, str.trim(line[6usize..]), true) }
    if str.starts_with(line, "When ") { ret (.When, str.trim(line[5usize..]), true) }
    if str.starts_with(line, "Then ") { ret (.Then, str.trim(line[5usize..]), true) }
    if str.starts_with(line, "And ") { ret (.And, str.trim(line[4usize..]), true) }
    if str.starts_with(line, "But ") { ret (.But, str.trim(line[4usize..]), true) }
    if str.starts_with(line, "* ") { ret (.And, str.trim(line[2usize..]), true) }
    ret (.Given, "", false)
}

// The cells of a `| a | b |` row, trimmed, into `out`; answers how many.
fn table_row(line: str, out: []str) -> (usize, err) {
    var n = 0usize
    var at = 1usize
    while at < line.len {
        var end = at
        while end < line.len && line[end] != 124u8 { end += 1usize }
        if end >= line.len { break }
        if n >= out.len { ret (n, TooSmall) }
        out[n] = str.trim(line[at..end])
        n += 1usize
        at = end + 1usize
    }
    ret (n, ok)
}

// `<name>` replaced by its example value, for every header.
fn substitute(a: *mem.Arena, text: str, heads: []const str, values: []const str) -> (str, err) {
    var s = text
    var i = 0usize
    while i < heads.len {
        let (left, left_error) = str.concat(a, "<", heads[i])
        if left_error != ok { ret ("", left_error) }
        let (needle, needle_error) = str.concat(a, left, ">")
        if needle_error != ok { ret ("", needle_error) }
        let (next, replace_error) = str.replace(a, s, needle, values[i])
        if replace_error != ok { ret ("", replace_error) }
        s = next
        i += 1usize
    }
    ret (s, ok)
}

// Append the outline's template steps (`template_start..template_end`) with one
// examples row substituted, as a new scenario.
fn expand_row(a: *mem.Arena, d: *Document, name: str, line: u32, tag_start: usize, tag_count: usize, template_start: usize, template_end: usize, heads: []const str, values: []const str, ordinal: usize) -> err {
    let (builder0, builder_error) = str.builder(a, name.len + 24usize)
    if builder_error != ok { ret builder_error }
    var b = builder0
    try str.push(&b, name)
    try str.push(&b, " #")
    try str.push_usize(&b, ordinal)
    let title = str.done(&b)
    let first = d.n_steps
    var k = template_start
    while k < template_end {
        var s = d.steps[k]
        let (text, text_error) = substitute(a, s.text, heads, values)
        if text_error != ok { ret text_error }
        s.text = text
        let start = d.n_cells
        var c = 0usize
        while c < s.rows * s.cols {
            let (replaced, replaced_error) = substitute(a, d.cells[s.cell_start + c], heads, values)
            if replaced_error != ok { ret replaced_error }
            try push_cell(d, replaced)
            c += 1usize
        }
        s.cell_start = start
        try push_step(d, s)
        k += 1usize
    }
    try push_scenario(d, Scenario { name: title, tag_start: tag_start, tag_count: tag_count, step_start: first, step_count: d.n_steps - first, line: line })
    ret ok
}

// Parse `source` into `d` (made by `document`). On `Invalid`/`Unsupported`,
// `d.error_line` is the 1-based line.
fn parse(a: *mem.Arena, source: str, d: *Document) -> err {
    var it = str.lines(source)
    var line_no = 0u32
    var pending: [16]str = zero
    var n_pending = 0usize
    // 0 header, 1 background, 2 scenario, 3 outline steps, 4 examples
    var section = 0u8
    var bg_start = 0usize
    var bg_count = 0usize
    var have_cur = false
    var cur_name = ""
    var cur_line = 0u32
    var cur_tag_start = 0usize
    var cur_tag_count = 0usize
    var cur_step_start = 0usize
    var template_end = 0usize
    var heads: [8]str = zero
    var n_heads = 0usize
    var header_read = false
    var ordinal = 0usize
    var seen_feature = false
    var last_step = false
    while true {
        let (raw, more) = str.split_next(&it)
        if !more { break }
        line_no += 1u32
        d.error_line = line_no
        let line = str.trim(raw)
        if line.len == 0usize || line[0usize] == 35u8 { continue }
        if str.starts_with(line, "\"\"\"") || str.starts_with(line, "Rule:") { ret Unsupported }
        if line[0usize] == 64u8 {
            // Tags: whitespace-separated words, each starting with `@`.
            var at = 0usize
            while at < line.len {
                while at < line.len && str.is_ascii_space(line[at]) { at += 1usize }
                var end = at
                while end < line.len && !str.is_ascii_space(line[end]) { end += 1usize }
                if end > at {
                    if line[at] != 64u8 { ret Invalid }
                    if n_pending >= MAX_TAGS_PER_LINE { ret TooSmall }
                    pending[n_pending] = line[at..end]
                    n_pending += 1usize
                }
                at = end
            }
            continue
        }
        if str.starts_with(line, "Feature:") {
            if seen_feature { ret Invalid }
            seen_feature = true
            d.feature = str.trim(line[8usize..])
            var t = 0usize
            while t < n_pending {
                try push_tag(d, pending[t])
                t += 1usize
            }
            d.feature_tag_count = n_pending
            n_pending = 0usize
            continue
        }
        if !seen_feature { ret Invalid }
        let is_scenario = str.starts_with(line, "Scenario:")
        let is_outline = str.starts_with(line, "Scenario Outline:") || str.starts_with(line, "Scenario Template:")
        if str.starts_with(line, "Background:") || is_scenario || is_outline {
            // Close the scenario in progress; an outline already expanded row by row.
            if have_cur && section == 2 {
                try push_scenario(d, Scenario { name: cur_name, tag_start: cur_tag_start, tag_count: cur_tag_count, step_start: cur_step_start, step_count: d.n_steps - cur_step_start, line: cur_line })
            }
            have_cur = false
            last_step = false
            if str.starts_with(line, "Background:") {
                section = 1u8
                bg_start = d.n_steps
                n_pending = 0usize
                continue
            }
            if section == 1 { bg_count = d.n_steps - bg_start }
            if is_outline {
                let (_, rest, _) = str.split_once(line, ":")
                cur_name = str.trim(rest)
            } else {
                cur_name = str.trim(line[9usize..])
            }
            cur_line = line_no
            cur_tag_start = d.n_tags
            cur_tag_count = n_pending
            var t = 0usize
            while t < n_pending {
                try push_tag(d, pending[t])
                t += 1usize
            }
            n_pending = 0usize
            cur_step_start = d.n_steps
            var k = 0usize
            while k < bg_count {
                try push_step(d, d.steps[bg_start + k])
                k += 1usize
            }
            have_cur = true
            ordinal = 0usize
            section = 2u8
            if is_outline { section = 3u8 }
            continue
        }
        if str.starts_with(line, "Examples:") {
            if section != 3 && section != 4 { ret Invalid }
            if section == 3 { template_end = d.n_steps }
            section = 4u8
            header_read = false
            n_heads = 0usize
            n_pending = 0usize
            continue
        }
        if line[0usize] == 124u8 {
            if section == 4 {
                var row: [8]str = zero
                let (n, row_error) = table_row(line, row[0..])
                if row_error != ok { ret row_error }
                if !header_read {
                    var h = 0usize
                    while h < n {
                        heads[h] = row[h]
                        h += 1usize
                    }
                    n_heads = n
                    header_read = true
                } else {
                    if n != n_heads { ret Invalid }
                    ordinal += 1usize
                    try expand_row(a, d, cur_name, cur_line, cur_tag_start, cur_tag_count, cur_step_start, template_end, heads[0..n_heads], row[0..n], ordinal)
                }
                continue
            }
            if !last_step || (section != 1 && section != 2 && section != 3) { ret Invalid }
            var trow: [8]str = zero
            let (tn, trow_error) = table_row(line, trow[0..])
            if trow_error != ok { ret trow_error }
            var s = d.steps[d.n_steps - 1usize]
            if s.rows == 0usize {
                s.cell_start = d.n_cells
                s.cols = tn
            }
            if tn != s.cols { ret Invalid }
            var c = 0usize
            while c < tn {
                try push_cell(d, trow[c])
                c += 1usize
            }
            s.rows += 1usize
            d.steps[d.n_steps - 1usize] = s
            continue
        }
        let (keyword, text, is_step) = step_line(line)
        if is_step {
            if section != 1 && section != 2 && section != 3 { ret Invalid }
            try push_step(d, Step { keyword: keyword, text: text, cell_start: 0usize, rows: 0usize, cols: 0usize, line: line_no })
            last_step = true
            if section == 1 { bg_count = d.n_steps - bg_start }
            continue
        }
        // Anything else is description under the feature, and an error elsewhere.
        if section != 0 { ret Invalid }
    }
    if have_cur && section == 2 {
        try push_scenario(d, Scenario { name: cur_name, tag_start: cur_tag_start, tag_count: cur_tag_count, step_start: cur_step_start, step_count: d.n_steps - cur_step_start, line: cur_line })
    }
    if !seen_feature { ret Invalid }
    ret ok
}

// A scenario's own tags are `d.tags[tag_start..tag_start + tag_count]`; the feature's
// are `d.tags[0..d.feature_tag_count]`.
fn has_tag(d: *const Document, scenario: usize, tag: str) -> bool {
    var i = 0usize
    while i < d.feature_tag_count {
        if str.eq(d.tags[i], tag) { ret true }
        i += 1usize
    }
    let s = &d.scenarios[scenario]
    i = 0usize
    while i < s.tag_count {
        if str.eq(d.tags[s.tag_start + i], tag) { ret true }
        i += 1usize
    }
    ret false
}

fn selected(d: *const Document, scenario: usize, filter: Filter) -> bool {
    var i = 0usize
    while i < filter.exclude.len {
        if has_tag(d, scenario, filter.exclude[i]) { ret false }
        i += 1usize
    }
    if filter.include.len == 0usize { ret true }
    i = 0usize
    while i < filter.include.len {
        if has_tag(d, scenario, filter.include[i]) { ret true }
        i += 1usize
    }
    ret false
}

// The words of a step; a `"quoted"` run is one word flagged as such, quotes dropped.
fn split_words(text: str, out: []Word) -> usize {
    var n = 0usize
    var at = 0usize
    while at < text.len && n < out.len {
        while at < text.len && str.is_ascii_space(text[at]) { at += 1usize }
        if at >= text.len { break }
        if text[at] == 34u8 {
            var end = at + 1usize
            while end < text.len && text[end] != 34u8 { end += 1usize }
            out[n] = Word { text: text[at + 1usize..end], quoted: true }
            at = end + 1usize
        } else {
            var end = at
            while end < text.len && !str.is_ascii_space(text[end]) { end += 1usize }
            out[n] = Word { text: text[at..end], quoted: false }
            at = end
        }
        n += 1usize
    }
    ret n
}

// Does the step pattern `name` (words joined by `_`) bind these words? Captures go
// into `args`.
fn matches_pattern(name: str, words: []const Word, args: *Args) -> bool {
    var wi = 0usize
    var at = 0usize
    while at < name.len {
        var end = at
        while end < name.len && name[end] != 95u8 { end += 1usize }
        let token = name[at..end]
        at = end + 1usize
        if token.len == 0usize { continue }
        if wi >= words.len { ret false }
        let w = words[wi]
        wi += 1usize
        if str.eq(token, "int") {
            if w.quoted { ret false }
            let (n, parse_error) = str.parse_i64(w.text)
            if parse_error != ok { ret false }
            if args.count >= 4usize { ret false }
            args.values[args.count] = w.text
            args.count += 1usize
        } else {
            if str.eq(token, "word") {
                if w.quoted || args.count >= 4usize { ret false }
                args.values[args.count] = w.text
                args.count += 1usize
            } else {
                if str.eq(token, "quoted") {
                    if !w.quoted || args.count >= 4usize { ret false }
                    args.values[args.count] = w.text
                    args.count += 1usize
                } else {
                    if w.quoted || str.compare_ascii_fold(token, w.text) != 0i32 { ret false }
                }
            }
        }
    }
    ret wi == words.len
}

// The i-th capture as an integer (0 when it is not one).
fn int_at(args: *const Args, i: usize) -> i64 {
    if i >= args.count { ret 0i64 }
    let (n, parse_error) = str.parse_i64(args.values[i])
    if parse_error != ok { ret 0i64 }
    ret n
}

fn cell(args: *const Args, row: usize, col: usize) -> str {
    if row >= args.rows || col >= args.cols { ret "" }
    ret args.cells[row * args.cols + col]
}

// Bind and run one step of `d`.
fn dispatch[W: type, S: type](world: *W, steps: *const S, d: *const Document, index: usize) -> Outcome {
    let st = &d.steps[index]
    var words: [24]Word = zero
    let n = split_words(st.text, words[0..])
    var outcome: Outcome = .Pending
    var found = false
    for f in meta.fields[S]() {
        if !found {
            var args: Args = zero
            args.text = st.text
            if matches_pattern(f.name, words[0..n], &args) {
                found = true
                args.rows = st.rows
                args.cols = st.cols
                if st.rows != 0usize { args.cells = d.cells[st.cell_start..st.cell_start + st.rows * st.cols] }
                let handler = meta.get[f, S](steps)
                let result = handler(world, &args)
                if result == ok {
                    outcome = .Passed
                } else {
                    if result == Pending { outcome = .Pending } else { outcome = .Failed }
                }
            }
        }
    }
    ret outcome
}

// Run every selected scenario: `reset` the world before each, run its steps in order
// and skip the rest after the first that is not `Passed`. `results` has an entry per
// document step and `scenario_results` one per scenario.
fn run[W: type, S: type](world: *W, reset: fn(*W), steps: *const S, d: *const Document, filter: Filter, results: []Outcome, scenario_results: []Outcome) -> (Summary, err) {
    var sum: Summary = zero
    if results.len < d.n_steps || scenario_results.len < d.n_scenarios { ret (sum, TooSmall) }
    var i = 0usize
    while i < d.n_scenarios {
        let sc = &d.scenarios[i]
        sum.scenarios += 1usize
        if !selected(d, i, filter) {
            scenario_results[i] = .Filtered
            sum.filtered += 1usize
            var s = 0usize
            while s < sc.step_count {
                results[sc.step_start + s] = .Filtered
                s += 1usize
            }
            i += 1usize
            continue
        }
        reset(world)
        var scenario_outcome: Outcome = .Passed
        var s = 0usize
        while s < sc.step_count {
            let at = sc.step_start + s
            if scenario_outcome != .Passed {
                results[at] = .Skipped
                sum.steps_skipped += 1usize
            } else {
                let o = dispatch[W, S](world, steps, d, at)
                results[at] = o
                if o == .Passed { sum.steps_passed += 1usize }
                if o == .Failed { sum.steps_failed += 1usize }
                if o == .Pending { sum.steps_pending += 1usize }
                scenario_outcome = o
            }
            s += 1usize
        }
        scenario_results[i] = scenario_outcome
        if scenario_outcome == .Passed { sum.passed += 1usize }
        if scenario_outcome == .Failed { sum.failed += 1usize }
        if scenario_outcome == .Pending { sum.pending += 1usize }
        i += 1usize
    }
    ret (sum, ok)
}

fn outcome_name(o: Outcome) -> str {
    if o == .Passed { ret "passed" }
    if o == .Failed { ret "failed" }
    if o == .Pending { ret "pending" }
    if o == .Skipped { ret "skipped" }
    ret "filtered"
}

fn keyword_name(k: Keyword) -> str {
    if k == .Given { ret "Given" }
    if k == .When { ret "When" }
    if k == .Then { ret "Then" }
    if k == .And { ret "And" }
    ret "But"
}

fn put(b: *str.Builder, s: str) {
    let discarded = str.push(b, s)
}

fn put_count(b: *str.Builder, n: usize) {
    let discarded = str.push_usize(b, n)
}

// A plain-text report in `out` (cut when short): every failed or pending scenario with
// the steps that failed or are pending, then the totals. The pending list is what a
// team reads to find what has no step definition yet.
fn report(d: *const Document, scenario_results: []const Outcome, results: []const Outcome, sum: Summary, out: []u8) -> str {
    var holder = mem.arena_from(out)
    let (built, builder_error) = str.builder(&holder, out.len)
    if builder_error != ok { ret "" }
    var b = built
    var i = 0usize
    while i < d.n_scenarios {
        let o = scenario_results[i]
        if o == .Failed || o == .Pending {
            put(&b, outcome_name(o))
            put(&b, " scenario: ")
            put(&b, d.scenarios[i].name)
            put(&b, "\n")
            let sc = &d.scenarios[i]
            var s = 0usize
            while s < sc.step_count {
                let r = results[sc.step_start + s]
                if r == .Failed || r == .Pending {
                    put(&b, "  ")
                    put(&b, keyword_name(d.steps[sc.step_start + s].keyword))
                    put(&b, " ")
                    put(&b, d.steps[sc.step_start + s].text)
                    put(&b, ": ")
                    put(&b, outcome_name(r))
                    put(&b, "\n")
                }
                s += 1usize
            }
        }
        i += 1usize
    }
    put_count(&b, sum.scenarios)
    put(&b, " scenarios (")
    put_count(&b, sum.passed)
    put(&b, " passed, ")
    put_count(&b, sum.failed)
    put(&b, " failed, ")
    put_count(&b, sum.pending)
    put(&b, " pending, ")
    put_count(&b, sum.filtered)
    put(&b, " filtered), ")
    put_count(&b, sum.steps_passed + sum.steps_failed + sum.steps_pending + sum.steps_skipped)
    put(&b, " steps (")
    put_count(&b, sum.steps_passed)
    put(&b, " passed, ")
    put_count(&b, sum.steps_failed)
    put(&b, " failed, ")
    put_count(&b, sum.steps_pending)
    put(&b, " pending, ")
    put_count(&b, sum.steps_skipped)
    put(&b, " skipped)\n")
    ret str.done(&b)
}
