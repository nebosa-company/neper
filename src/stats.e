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

// The stream rendering (D476): with `--json` the same rows are one `stats` record on
// stdout, `"key":value` per row, the key the row's name in snake_case with the unit
// as its suffix; the row helpers below read `Build.json`.
type Build = struct {
    on: bool,
    full: bool,
    json: bool,
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
    // The image the build did not have to write (D332): it was already the file at the
    // output path, so the write was skipped and the manifest reused its digest.
    image_unchanged: bool,
    // What the build did rather than kept (D405, H14): the modules whose bodies were
    // checked, the modules lowered and the functions lowered in them; a warm build
    // over a stable cache does none of it.
    bodies_checked: usize,
    declarations_checked: usize,
    modules_lowered: usize,
    functions_lowered: usize,
    ran: bool,
    run_ms: usize,
    exit_code: i32,
    // The child's peak working set in bytes (D311), from the same wait as its exit code.
    run_peak: usize,
    // `run --json` (D370): the child's whole stream sizes and the record's bound.
    stdout_bytes: usize,
    stderr_bytes: usize,
    capture_limit: usize,
    // The link's drop count (D334): functions no call chain from `main` reaches, and their code bytes.
    unreached_functions: usize,
    unreached_bytes: usize,
    // Index checks the lowering left out under a `while i < x.len` proof (D356).
    bounds_elided: usize,
    // By-value arguments copied for their call, and passed by address (D358).
    snapshots_copied: usize,
    snapshots_elided: usize,
    values_allocated: usize,
    values_spilled: usize,
    functions_spilling: usize,
}

fn record_phase(b: *Build, name: str, ms: usize) {
    if b.phase_count >= 12usize { ret }
    b.phase_names[b.phase_count] = name
    b.phase_ms[b.phase_count] = ms
    b.phase_count += 1usize
}

// --- printing ---------------------------------------------------------------------------

// The table goes to stderr, where `--time` goes, so `run --json`'s stream stays clean;
// the record is a line of that stream (D476).
fn out(b: *Build, text: str) -> err {
    if b.json {
        let stream = os.stdout()
        ret write_text(stream, text)
    }
    let file = os.stderr()
    ret write_text(file, text)
}

fn write_text(file: os.File, text: str) -> err {
    var at = 0usize
    while at < text.len {
        let (written, write_error) = os.write(file, text[at..])
        if write_error != ok { ret write_error }
        if written == 0usize { ret Stopped }
        at += written
    }
    ret ok
}

fn digit(b: *Build, d: usize) -> err {
    if d == 0usize { ret out(b, "0") }
    if d == 1usize { ret out(b, "1") }
    if d == 2usize { ret out(b, "2") }
    if d == 3usize { ret out(b, "3") }
    if d == 4usize { ret out(b, "4") }
    if d == 5usize { ret out(b, "5") }
    if d == 6usize { ret out(b, "6") }
    if d == 7usize { ret out(b, "7") }
    if d == 8usize { ret out(b, "8") }
    ret out(b, "9")
}

// Thousands apart with an apostrophe: 2'000'000.
fn number(b: *Build, value: usize) -> err {
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
        try digit(b, remaining / divisor)
        remaining = remaining % divisor
        divisor = divisor / 10usize
        digits = digits - 1usize
        if digits != 0usize && digits % 3usize == 0usize && !b.json { try out(b, "'") }
    }
    ret ok
}

// A row's key (D476): the name lowered, a space or dash an underscore, `@` spelled `at_`,
// anything else dropped, between a prefix and a suffix -- `phase_front_end_ms`.
fn out_key(b: *Build, prefix: str, name: str, suffix: str) -> err {
    var storage: [96]u8 = zero
    var count = 0usize
    var part = 0usize
    while part < 3usize {
        var text = name
        if part == 0usize { text = prefix }
        if part == 2usize { text = suffix }
        var at = 0usize
        while at < text.len {
            let byte = text[at]
            if count + 3usize >= storage.len { ret Stopped }
            if (byte >= 97u8 && byte <= 122u8) || (byte >= 48u8 && byte <= 57u8) || byte == 95u8 {
                storage[count] = byte
                count += 1usize
            }
            if byte >= 65u8 && byte <= 90u8 {
                storage[count] = byte + 32u8
                count += 1usize
            }
            if byte == 32u8 || byte == 45u8 {
                storage[count] = 95u8
                count += 1usize
            }
            if byte == 64u8 {
                storage[count] = 97u8
                storage[count + 1usize] = 116u8
                storage[count + 2usize] = 95u8
                count += 3usize
            }
            at += 1usize
        }
        part += 1usize
    }
    ret out(b, storage[0usize..count])
}

// A row's start: the name and a bar, or the record's key with its unit suffix.
fn row_named(b: *Build, prefix: str, name: str, suffix: str) -> err {
    if !b.json {
        try out(b, name)
        ret out(b, " | ")
    }
    try out(b, ",")
    try out(b, "\"")
    try out_key(b, prefix, name, suffix)
    ret out(b, "\":")
}

fn row(b: *Build, name: str) -> err {
    ret row_named(b, "", name, "")
}

// A row's end: the unit and the line, or nothing -- the next key brings its comma.
fn end_row(b: *Build, unit: str) -> err {
    if b.json { ret ok }
    if unit.len != 0usize {
        try out(b, " ")
        try out(b, unit)
    }
    ret out(b, "\n")
}

fn row_number(b: *Build, name: str, value: usize) -> err {
    try row(b, name)
    try number(b, value)
    ret end_row(b, "")
}

// A row with a unit: the unit after the value in the table, the key's suffix in the record.
fn row_unit(b: *Build, prefix: str, name: str, value: usize, unit: str, suffix: str) -> err {
    try row_named(b, prefix, name, suffix)
    try number(b, value)
    ret end_row(b, unit)
}

fn row_ms(b: *Build, name: str, ms: usize) -> err {
    ret row_unit(b, "", name, ms, "ms", "_ms")
}

fn row_bytes(b: *Build, name: str, bytes: usize) -> err {
    ret row_unit(b, "", name, bytes / 1048576usize, "MB", "_mb")
}

fn row_text(b: *Build, name: str, value: str) -> err {
    try row(b, name)
    if b.json { try out(b, "\"") }
    try out(b, value)
    if b.json { try out(b, "\"") }
    ret end_row(b, "")
}

// A blank cell: `null` under its unit's key in the record.
fn row_blank(b: *Build, name: str, suffix: str) -> err {
    try row_named(b, "", name, suffix)
    if b.json { try out(b, "null") }
    ret end_row(b, "")
}

// The record's end (D476); the table has none.
fn close(b: *Build) -> err {
    if b.json { ret out(b, "}\n") }
    ret ok
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
fn count_nodes(a: *mem.Arena, r: *resolve.Resolver, g: *graph.Graph) -> (Counts, err) {
    var counts: Counts = zero
    var module_index = 0usize
    while module_index < g.count {
        // A module a hot build kept was neither lexed nor parsed (D322); the counts
        // are the program's, so it is here (D412), for `--stats` alone.
        if !g.modules[module_index].has_tree && g.modules[module_index].tokens.len == 0usize {
            let front_error = graph.scan_and_parse(a, g, module_index)
            if front_error != ok { ret (counts, front_error) }
        }
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

// The host by the shape of its current directory, as the driver tells it (D348).
fn host_name(a: *mem.Arena) -> str {
    let (cwd, cwd_error) = os.current_dir(a)
    if cwd_error == ok && cwd.len != 0usize && cwd[0usize] == 47u8 { ret "Linux x64" }
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
    // A reached module has a function in the lowered program; an unreached one was loaded and never called.
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
    let (counts, counts_error) = count_nodes(a, r, g)
    if counts_error != ok { ret counts_error }

    if b.json { try out(b, "{\"record\":\"stats\"") } else { try out(b, "Metric | Value\n") }
    try row_number(b, "files", g.count)
    try row_number(b, "LoC", all.total)
    try row_number(b, "MLoC", all.code)
    try row_number(b, "comments", all.comment)
    try row_number(b, "blank", all.blank)
    if b.json {
        var size_min = 0usize
        var size_median = 0usize
        var size_max = 0usize
        if g.count != 0usize {
            size_min = sizes[0usize]
            size_median = sizes[g.count / 2usize]
            size_max = sizes[g.count - 1usize]
        }
        try row_number(b, "module size min", size_min)
        try row_number(b, "module size median", size_median)
        try row_number(b, "module size max", size_max)
    } else {
        try row(b, "module sizes LoC (min / median / max)")
        if g.count != 0usize {
            try number(b, sizes[0usize])
            try out(b, " / ")
            try number(b, sizes[g.count / 2usize])
            try out(b, " / ")
            try number(b, sizes[g.count - 1usize])
        }
        try out(b, "\n")
    }
    try row_number(b, "functions", c.signature_function_count)
    try row_number(b, "function instances", c.function_count - c.signature_function_count)
    try row_number(b, "imports", g.import_count)
    try row_number(b, "types", c.aggregate_count + c.alias_count)
    try row_number(b, "constants", c.constant_count)
    try row_number(b, "vars", c.global_count)
    try row_number(b, "errors", errors)
    try row_number(b, "nodes", counts.nodes)
    try row_number(b, "externs", counts.externs)
    try row_number(b, "@tests", counts.tests)
    try row_number(b, "@gpus", counts.gpus)
    try row_number(b, "@imports", counts.imports)
    try row_number(b, "@nochecks", counts.nochecks)
    try row_unit(b, "", "source", g.total_bytes, "bytes", "_bytes")
    try row_unit(b, "", "largest module", g.largest_bytes, "bytes", "_bytes")
    if b.release { try row_text(b, "compile mode", "RELEASE") } else { try row_text(b, "compile mode", "DEBUG") }
    try row_text(b, "compiler version", "0.1.0")
    try row_text(b, "host", host_name(a))
    if b.json {
        try row_text(b, "target arch", b.arch)
        try row_text(b, "target os", b.target_os)
    } else {
        try row(b, "target")
        try out(b, b.arch)
        try out(b, " ")
        try out(b, b.target_os)
        try out(b, "\n")
    }
    try row_number(b, "reached modules", hot_count)
    try row_number(b, "unreached modules", g.count - hot_count)
    try row_number(b, "reached functions", builder.function_count)
    try row_number(b, "unreached functions", b.unreached_functions)
    try row_unit(b, "", "unreached code", b.unreached_bytes, "bytes", "_bytes")
    try row_number(b, "declarations checked", b.declarations_checked)
    try row_number(b, "bodies checked", b.bodies_checked)
    try row_number(b, "modules lowered", b.modules_lowered)
    try row_number(b, "functions lowered", b.functions_lowered)
    try row_number(b, "bounds checks elided", b.bounds_elided)
    try row_number(b, "by-value copies", b.snapshots_copied)
    try row_number(b, "by-value copies elided", b.snapshots_elided)
    // Register pressure (D450, H20): what the allocator could not keep in a register.
    try row_number(b, "values allocated", b.values_allocated)
    try row_number(b, "values spilled", b.values_spilled)
    try row_number(b, "functions spilling", b.functions_spilling)
    // The worker arenas' high-water marks summed (D339): every phase's workers, what
    // each allocated, rounded to the runtime's chunk -- what the pools were sized to,
    // not what was committed, which is the pages touched and the peak below; the
    // front end's workers are still held by the graph.
    var worker_bytes = g.worker_bytes
    var worker_at = 0usize
    while worker_at < g.workers.len {
        worker_bytes += graph.arena_touched(&g.workers[worker_at].arena)
        worker_at += 1usize
    }
    try row_bytes(b, "worker arenas reached", worker_bytes)
    try row_unit(b, "", "executable size", b.image_bytes, "bytes", "_bytes")
    // Read here, after everything the build allocated: the process's peak so far is its
    // peak (D311).
    let (peak, peak_error) = os.peak_memory()
    if peak_error != ok { ret peak_error }
    try row_bytes(b, "compiler peak working set", peak)
    try row_ms(b, "wall time", b.wall_ms)
    var phase = 0usize
    while phase < b.phase_count {
        try row_unit(b, "phase ", b.phase_names[phase], b.phase_ms[phase], "ms", "_ms")
        phase += 1usize
    }
    if b.ran {
        try row_ms(b, "execution time", b.run_ms)
        try row_bytes(b, "executable peak working set", b.run_peak)
        try row(b, "exit code")
        if b.exit_code < 0i32 {
            try out(b, "-")
            try number(b, usize(0i32 - b.exit_code))
        } else {
            try number(b, usize(b.exit_code))
        }
        try end_row(b, "")
    } else {
        try row_blank(b, "execution time", "_ms")
        try row_blank(b, "executable peak working set", "_mb")
        try row_blank(b, "exit code", "")
    }
    if !b.full { ret close(b) }

    if !b.json { try out(b, "\nPool | Capacity | Used\n") }
    try pool_row(b, "resolver symbols", b.pools[POOL_SYMBOLS], r.count)
    try pool_row(b, "resolver tokens (per module)", b.pools[POOL_RESOLVER_TOKENS], 0usize)
    try pool_row(b, "resolver locals", b.pools[POOL_RESOLVER_LOCALS], 0usize)
    try pool_row(b, "resolver name index entries", b.pools[POOL_RESOLVER_INDEX], r.names.count)
    try pool_row(b, "checker functions", b.pools[POOL_FUNCTIONS], c.function_count)
    try pool_row(b, "checker parameters", b.pools[POOL_PARAMETERS], c.parameter_count)
    try pool_row(b, "checker return types", b.pools[POOL_RETURN_TYPES], c.return_type_count)
    try pool_row(b, "checker types", b.pools[POOL_TYPES], c.type_count)
    try pool_row(b, "checker aggregates", b.pools[POOL_AGGREGATES], c.aggregate_count)
    try pool_row(b, "checker aggregate fields", b.pools[POOL_AGGREGATE_FIELDS], c.aggregate_field_count)
    try pool_row(b, "checker aliases", b.pools[POOL_ALIASES], c.alias_count)
    try pool_row(b, "checker constants", b.pools[POOL_CONSTANTS], c.constant_count)
    try pool_row(b, "checker constant exprs", b.pools[POOL_CONSTANT_EXPRS], c.constant_expr_count)
    try pool_row(b, "checker globals", b.pools[POOL_GLOBALS], c.global_count)
    try pool_row(b, "checker generic arguments", b.pools[POOL_GENERIC_ARGUMENTS], c.generic_argument_count)
    try pool_row(b, "checker comptime parameters", b.pools[POOL_COMPTIME_PARAMETERS], c.comptime_parameter_count)
    try pool_row(b, "checker checked switches", b.pools[POOL_CHECKED_SWITCHES], 0usize)
    try pool_row(b, "checker diagnostics", b.pools[POOL_DIAGNOSTICS], c.diagnostic_count)
    try pool_row(b, "checker tokens (per module)", b.pools[POOL_CHECKER_TOKENS], 0usize)
    try pool_row(b, "checker locals", b.pools[POOL_CHECKER_LOCALS], 0usize)
    try pool_row(b, "checker declaration index entries", b.pools[POOL_CHECKER_INDEX], c.names.count)
    try pool_row(b, "nir functions", b.pools[POOL_NIR_FUNCTIONS], builder.function_count)
    // The body pools hold one module at a time on the executable path (D314): the
    // capacity is per module, the used column is the whole program's.
    try pool_row(b, "nir blocks", b.pools[POOL_NIR_BLOCKS], builder.block_count + builder.block_total)
    try pool_row(b, "nir instructions", b.pools[POOL_NIR_INSTRUCTIONS], builder.instruction_count + builder.instruction_total)
    try pool_row(b, "nir instructions, largest module", b.pools[POOL_NIR_INSTRUCTIONS], builder.instruction_peak)
    try pool_row(b, "nir operands", b.pools[POOL_NIR_OPERANDS], builder.operand_count + builder.operand_total)
    try pool_row(b, "nir function refs", b.pools[POOL_NIR_REFS], builder.function_ref_count)
    try pool_row(b, "nir strings", b.pools[POOL_NIR_STRINGS], builder.string_count)
    try pool_row(b, "nir globals", b.pools[POOL_NIR_GLOBALS], builder.global_count)
    try pool_row(b, "nir ref index entries", b.pools[POOL_NIR_INDEX], builder.ref_names.count)
    try pool_row(b, "lowering bindings", b.pools[POOL_BINDINGS], 0usize)
    try pool_row(b, "machine code buffer bytes", b.pools[POOL_MACHINE], 0usize)
    try pool_row(b, "image buffer bytes", b.pools[POOL_IMAGE], b.image_bytes)
    try pool_row(b, "line entries", b.pools[POOL_LINE_ENTRIES], 0usize)
    try pool_row(b, "relocations", b.pools[POOL_RELOCATIONS], 0usize)
    ret close(b)
}

// A pool's two columns, or its two keys (D476): `pool_<name>_capacity` and
// `pool_<name>_used`, the second `null` where the table leaves it blank.
fn pool_row(b: *Build, name: str, capacity: usize, used: usize) -> err {
    if b.json {
        try row_unit(b, "pool ", name, capacity, "", "_capacity")
        try row_named(b, "pool ", name, "_used")
        if used != 0usize { try number(b, used) } else { try out(b, "null") }
        ret ok
    }
    try row(b, name)
    try number(b, capacity)
    try out(b, " | ")
    if used != 0usize { try number(b, used) }
    ret out(b, "\n")
}
