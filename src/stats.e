// `--stats` (D308): what a build was, measured after it, printed as a table.
//
// Everything that costs anything -- counting lines, parsing every module once more for
// its nodes and attributes, sorting module sizes -- happens after the image is written,
// so the phase times are the build's own. The timings, the pool sizes and the run
// result are recorded by the driver as it goes, at the cost of a store each.

use e.io
use e.mem
use e.os
use check
use graph
use nir
use parse
use resolve
use syntax

error Stopped

// Pool indexes into `Build.pools`, recorded where each pool is allocated.
const POOL_SYMBOLS: usize = 0usize
const POOL_RESOLVER_TOKENS: usize = 1usize
const POOL_RESOLVER_LOCALS: usize = 2usize
const POOL_RESOLVER_INDEX: usize = 3usize
const POOL_FUNCTIONS: usize = 4usize
const POOL_PARAMETERS: usize = 5usize
const POOL_RETURN_TYPES: usize = 6usize
const POOL_TYPES: usize = 7usize
const POOL_AGGREGATES: usize = 8usize
const POOL_AGGREGATE_FIELDS: usize = 9usize
const POOL_ALIASES: usize = 10usize
const POOL_CONSTANTS: usize = 11usize
const POOL_CONSTANT_EXPRS: usize = 12usize
const POOL_GLOBALS: usize = 13usize
const POOL_GENERIC_ARGUMENTS: usize = 14usize
const POOL_COMPTIME_PARAMETERS: usize = 15usize
const POOL_CHECKED_SWITCHES: usize = 16usize
const POOL_DIAGNOSTICS: usize = 17usize
const POOL_CHECKER_TOKENS: usize = 18usize
const POOL_CHECKER_LOCALS: usize = 19usize
const POOL_CHECKER_INDEX: usize = 20usize
const POOL_NIR_FUNCTIONS: usize = 21usize
const POOL_NIR_BLOCKS: usize = 22usize
const POOL_NIR_INSTRUCTIONS: usize = 23usize
const POOL_NIR_OPERANDS: usize = 24usize
const POOL_NIR_REFS: usize = 25usize
const POOL_NIR_STRINGS: usize = 26usize
const POOL_NIR_GLOBALS: usize = 27usize
const POOL_NIR_INDEX: usize = 28usize
const POOL_BINDINGS: usize = 29usize
const POOL_MACHINE: usize = 30usize
const POOL_IMAGE: usize = 31usize
const POOL_LINE_ENTRIES: usize = 32usize
const POOL_RELOCATIONS: usize = 33usize
const POOL_COUNT: usize = 34usize

type Build = struct {
    on: bool,
    full: bool,
    release: bool,
    arch: str,
    target_os: str,
    started: usize,
    wall_ms: usize,
    phase_names: [12]str,
    phase_ms: [12]usize,
    phase_count: usize,
    pools: [34]usize,
    image_bytes: usize,
    ran: bool,
    run_ms: usize,
    exit_code: i32,
}

fn record_phase(b: *Build, name: str, ms: usize) {
    if b.phase_count >= 12usize { ret }
    b.phase_names[b.phase_count] = name
    b.phase_ms[b.phase_count] = ms
    b.phase_count += 1usize
}

// --- printing ---------------------------------------------------------------------------

// The table goes to stderr, where `--time` goes, so `run --json`'s stream stays clean.
fn out(text: str) -> err {
    let file = os.stderr()
    var at = 0usize
    while at < text.len {
        let (written, write_error) = os.write(file, text[at..])
        if write_error != ok { ret write_error }
        if written == 0usize { ret Stopped }
        at += written
    }
    ret ok
}

fn digit(d: usize) -> err {
    if d == 0usize { ret out("0") }
    if d == 1usize { ret out("1") }
    if d == 2usize { ret out("2") }
    if d == 3usize { ret out("3") }
    if d == 4usize { ret out("4") }
    if d == 5usize { ret out("5") }
    if d == 6usize { ret out("6") }
    if d == 7usize { ret out("7") }
    if d == 8usize { ret out("8") }
    ret out("9")
}

// Thousands apart with an apostrophe: 2'000'000.
fn number(value: usize) -> err {
    var divisor = 1usize
    var remaining = value
    var digits = 1usize
    while remaining >= 10usize {
        remaining = remaining / 10usize
        divisor = divisor * 10usize
        digits += 1usize
    }
    remaining = value
    while divisor != 0usize {
        try digit(remaining / divisor)
        remaining = remaining % divisor
        divisor = divisor / 10usize
        digits = digits - 1usize
        if digits != 0usize && digits % 3usize == 0usize { try out("'") }
    }
    ret ok
}

fn row(name: str) -> err {
    try out(name)
    ret out(" | ")
}

fn row_number(name: str, value: usize) -> err {
    try row(name)
    try number(value)
    ret out("\n")
}

fn row_ms(name: str, ms: usize) -> err {
    try row(name)
    try number(ms)
    ret out(" ms\n")
}

fn row_text(name: str, value: str) -> err {
    try row(name)
    try out(value)
    ret out("\n")
}

fn row_blank(name: str) -> err {
    try row(name)
    ret out("\n")
}

// --- the post pass ------------------------------------------------------------------------

type Lines = struct {
    total: usize,
    code: usize,
    comment: usize,
    blank: usize,
}

// A line is blank, a comment when its first non-space bytes are `//`, else code.
fn count_lines(text: str) -> Lines {
    var lines: Lines = zero
    var at = 0usize
    while at < text.len {
        var start = at
        while at < text.len && text[at] != 10u8 { at += 1usize }
        var first = start
        while first < at && (text[first] == 32u8 || text[first] == 9u8 || text[first] == 13u8) { first += 1usize }
        if first >= at {
            lines.blank += 1usize
        } else {
            if first + 1usize < at && text[first] == 47u8 && text[first + 1usize] == 47u8 {
                lines.comment += 1usize
            } else {
                lines.code += 1usize
            }
        }
        lines.total += 1usize
        if at < text.len { at += 1usize }
    }
    ret lines
}

fn insertion_sort(values: []usize) {
    var at = 1usize
    while at < values.len {
        let held = values[at]
        var back = at
        while back > 0usize && values[back - 1usize] > held {
            values[back] = values[back - 1usize]
            back = back - 1usize
        }
        values[back] = held
        at += 1usize
    }
}

type Counts = struct {
    nodes: usize,
    externs: usize,
    tests: usize,
    gpus: usize,
    imports: usize,
    nochecks: usize,
}

// Every module parsed once more, for what only the tree knows.
fn count_nodes(r: *resolve.Resolver, g: *graph.Graph) -> (Counts, err) {
    var counts: Counts = zero
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        let parse_error = graph.parse_module(g, module_index, &tree)
        if parse_error != ok { ret (counts, parse_error) }
        let tokens_error = resolve.tokenize_module(r, g, module_index)
        if tokens_error != ok { ret (counts, tokens_error) }
        counts.nodes += tree.count
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.kind == .ExternDecl { counts.externs += 1usize }
            if node.kind == .Attribute {
                let name = resolve.attribute_name(r, g, module_index, node)
                if resolve.same(name, "test") { counts.tests += 1usize }
                if resolve.same(name, "gpu") { counts.gpus += 1usize }
                if resolve.same(name, "import") { counts.imports += 1usize }
                if resolve.same(name, "nocheck") { counts.nochecks += 1usize }
            }
            node_index += 1usize
        }
        module_index += 1usize
    }
    ret (counts, ok)
}

// Probed from the standard-handle value, as the driver does: a Linux fd is 2.
fn host_name() -> str {
    if os.stderr().raw == 2usize { ret "Linux x64" }
    ret "Windows x64"
}

fn print(a: *mem.Arena, b: *Build, g: *graph.Graph, r: *resolve.Resolver, c: *check.Checker, builder: *nir.Builder) -> err {
    // Lines, per module and in all.
    var all: Lines = zero
    let (sizes, sizes_error) = mem.alloc[usize](a, g.count + 1usize)
    if sizes_error != ok { ret sizes_error }
    var module_index = 0usize
    while module_index < g.count {
        let lines = count_lines(g.modules[module_index].text)
        all.total += lines.total
        all.code += lines.code
        all.comment += lines.comment
        all.blank += lines.blank
        sizes[module_index] = lines.total
        module_index += 1usize
    }
    insertion_sort(sizes[0usize..g.count])
    // Hot modules have a function in the lowered program; cold ones were loaded and never reached.
    let (hot, hot_error) = mem.alloc[bool](a, g.count + 1usize)
    if hot_error != ok { ret hot_error }
    module_index = 0usize
    while module_index < g.count {
        hot[module_index] = false
        module_index += 1usize
    }
    var function_at = 0usize
    while function_at < builder.function_count {
        let owner = builder.functions[function_at].module_index
        if owner < g.count { hot[owner] = true }
        function_at += 1usize
    }
    var hot_count = 0usize
    module_index = 0usize
    while module_index < g.count {
        if hot[module_index] { hot_count += 1usize }
        module_index += 1usize
    }
    var errors = 0usize
    var symbol_at = 0usize
    while symbol_at < r.count {
        if r.symbols[symbol_at].kind == .Error { errors += 1usize }
        symbol_at += 1usize
    }
    let (counts, counts_error) = count_nodes(r, g)
    if counts_error != ok { ret counts_error }

    try out("Metric | Value\n")
    try row_number("files", g.count)
    try row_number("LoC", all.total)
    try row_number("MLoC", all.code)
    try row_number("comments", all.comment)
    try row_number("blank", all.blank)
    try row("module sizes LoC (min / median / max)")
    if g.count != 0usize {
        try number(sizes[0usize])
        try out(" / ")
        try number(sizes[g.count / 2usize])
        try out(" / ")
        try number(sizes[g.count - 1usize])
    }
    try out("\n")
    try row_number("functions", c.signature_function_count)
    try row_number("function instances", c.function_count - c.signature_function_count)
    try row_number("imports", g.import_count)
    try row_number("types", c.aggregate_count + c.alias_count)
    try row_number("constants", c.constant_count)
    try row_number("vars", c.global_count)
    try row_number("errors", errors)
    try row_number("nodes", counts.nodes)
    try row_number("externs", counts.externs)
    try row_number("@tests", counts.tests)
    try row_number("@gpus", counts.gpus)
    try row_number("@imports", counts.imports)
    try row_number("@nochecks", counts.nochecks)
    try row("source")
    try number(g.total_bytes)
    try out(" bytes\n")
    try row("largest module")
    try number(g.largest_bytes)
    try out(" bytes\n")
    if b.release { try row_text("compile mode", "RELEASE") } else { try row_text("compile mode", "DEBUG") }
    try row_text("compiler version", "0.1.0")
    try row_text("host", host_name())
    try row("target")
    try out(b.arch)
    try out(" ")
    try out(b.target_os)
    try out("\n")
    try row_number("hot modules", hot_count)
    try row_number("cold modules", g.count - hot_count)
    try row_number("compile threads", 1usize)
    try row("executable size")
    try number(b.image_bytes)
    try out(" bytes\n")
    try row_text("compiler peak working set", "n/a (no os intrinsic yet)")
    try row_ms("wall time", b.wall_ms)
    var phase = 0usize
    while phase < b.phase_count {
        try row(b.phase_names[phase])
        try number(b.phase_ms[phase])
        try out(" ms\n")
        phase += 1usize
    }
    if b.ran {
        try row_ms("execution time", b.run_ms)
        try row_text("executable peak working set", "n/a (no os intrinsic yet)")
        try row("exit code")
        if b.exit_code < 0i32 {
            try out("-")
            try number(usize(0i32 - b.exit_code))
        } else {
            try number(usize(b.exit_code))
        }
        try out("\n")
    } else {
        try row_blank("execution time")
        try row_blank("executable peak working set")
        try row_blank("exit code")
    }
    if !b.full { ret ok }

    try out("\nPool | Capacity | Used\n")
    try pool_row("resolver symbols", b.pools[POOL_SYMBOLS], r.count)
    try pool_row("resolver tokens (per module)", b.pools[POOL_RESOLVER_TOKENS], 0usize)
    try pool_row("resolver locals", b.pools[POOL_RESOLVER_LOCALS], 0usize)
    try pool_row("resolver name index entries", b.pools[POOL_RESOLVER_INDEX], r.names.count)
    try pool_row("checker functions", b.pools[POOL_FUNCTIONS], c.function_count)
    try pool_row("checker parameters", b.pools[POOL_PARAMETERS], c.parameter_count)
    try pool_row("checker return types", b.pools[POOL_RETURN_TYPES], c.return_type_count)
    try pool_row("checker types", b.pools[POOL_TYPES], c.type_count)
    try pool_row("checker aggregates", b.pools[POOL_AGGREGATES], c.aggregate_count)
    try pool_row("checker aggregate fields", b.pools[POOL_AGGREGATE_FIELDS], c.aggregate_field_count)
    try pool_row("checker aliases", b.pools[POOL_ALIASES], c.alias_count)
    try pool_row("checker constants", b.pools[POOL_CONSTANTS], c.constant_count)
    try pool_row("checker constant exprs", b.pools[POOL_CONSTANT_EXPRS], c.constant_expr_count)
    try pool_row("checker globals", b.pools[POOL_GLOBALS], c.global_count)
    try pool_row("checker generic arguments", b.pools[POOL_GENERIC_ARGUMENTS], c.generic_argument_count)
    try pool_row("checker comptime parameters", b.pools[POOL_COMPTIME_PARAMETERS], c.comptime_parameter_count)
    try pool_row("checker checked switches", b.pools[POOL_CHECKED_SWITCHES], 0usize)
    try pool_row("checker diagnostics", b.pools[POOL_DIAGNOSTICS], c.diagnostic_count)
    try pool_row("checker tokens (per module)", b.pools[POOL_CHECKER_TOKENS], 0usize)
    try pool_row("checker locals", b.pools[POOL_CHECKER_LOCALS], 0usize)
    try pool_row("checker declaration index entries", b.pools[POOL_CHECKER_INDEX], c.names.count)
    try pool_row("nir functions", b.pools[POOL_NIR_FUNCTIONS], builder.function_count)
    try pool_row("nir blocks", b.pools[POOL_NIR_BLOCKS], builder.block_count)
    try pool_row("nir instructions", b.pools[POOL_NIR_INSTRUCTIONS], builder.instruction_count)
    try pool_row("nir operands", b.pools[POOL_NIR_OPERANDS], builder.operand_count)
    try pool_row("nir function refs", b.pools[POOL_NIR_REFS], builder.function_ref_count)
    try pool_row("nir strings", b.pools[POOL_NIR_STRINGS], builder.string_count)
    try pool_row("nir globals", b.pools[POOL_NIR_GLOBALS], builder.global_count)
    try pool_row("nir ref index entries", b.pools[POOL_NIR_INDEX], builder.ref_names.count)
    try pool_row("lowering bindings", b.pools[POOL_BINDINGS], 0usize)
    try pool_row("machine code buffer bytes", b.pools[POOL_MACHINE], 0usize)
    try pool_row("image buffer bytes", b.pools[POOL_IMAGE], b.image_bytes)
    try pool_row("line entries", b.pools[POOL_LINE_ENTRIES], 0usize)
    try pool_row("relocations", b.pools[POOL_RELOCATIONS], 0usize)
    ret ok
}

fn pool_row(name: str, capacity: usize, used: usize) -> err {
    try row(name)
    try number(capacity)
    try out(" | ")
    if used != 0usize { try number(used) }
    ret out("\n")
}
