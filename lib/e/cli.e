// Command-line parsing over a declared `Command` tree: `--long value`, `--long=value`,
// `-s value`, bare `--flag` for a bool (`--flag=false` to clear it), `--` to end the
// options, the first bare word naming a subcommand to descend into it and every other
// bare word a positional. A required option absent from the arguments is read from
// its `env` variable, and `Missing` if that is unset too. `parse_into` reads a struct's
// fields as `--name` options by their `meta` kind -- bool, integer, float, string --
// with no `Command` in between. `help` renders usage, options and subcommands, the
// help text word-wrapped to `width`.
use e.mem
use e.meta
use e.os
use e.str

type ValueKind = enum u8 { Bool, I64, U64, F64, String }
type Option = struct { long: str, short: u8, kind: ValueKind, required: bool, repeated: bool, env: str, help: str }
type Command = struct { name: str, help: str, options: []const Option, subcommands: []const Command }
type Value = union enum u8 { Bool: bool, I64: i64, U64: u64, F64: f64, String: str }
type ParsedOption = struct { name: str, values: []const Value }
type Result = struct { command: str, options: []const ParsedOption, positionals: []const str }
error InvalidSpec
error InvalidArgument
error Missing
error Unknown

fn validate(command: *const Command) -> err {
    if command.name.len == 0usize { ret InvalidSpec }
    var i = 0usize
    while i < command.options.len {
        let o = command.options[i]
        if o.long.len == 0usize { ret InvalidSpec }
        if o.kind == .Bool && o.required { ret InvalidSpec }
        var j = 0usize
        while j < i {
            if str.eq(command.options[j].long, o.long) { ret InvalidSpec }
            if o.short != 0u8 && command.options[j].short == o.short { ret InvalidSpec }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < command.subcommands.len {
        var j = 0usize
        while j < i {
            if str.eq(command.subcommands[j].name, command.subcommands[i].name) { ret InvalidSpec }
            j += 1usize
        }
        try validate(&command.subcommands[i])
        i += 1usize
    }
    ret ok
}

fn parse_value(kind: ValueKind, text: str) -> (Value, err) {
    if kind == .Bool {
        if str.eq(text, "true") || str.eq(text, "1") || str.eq(text, "yes") { ret (Value{ Bool: true }, ok) }
        if str.eq(text, "false") || str.eq(text, "0") || str.eq(text, "no") { ret (Value{ Bool: false }, ok) }
        ret (zero, InvalidArgument)
    }
    if kind == .I64 {
        let (number, number_error) = str.parse_i64(text)
        if number_error != ok { ret (zero, InvalidArgument) }
        ret (Value{ I64: number }, ok)
    }
    if kind == .U64 {
        let (number, number_error) = str.parse_u64(text)
        if number_error != ok { ret (zero, InvalidArgument) }
        ret (Value{ U64: number }, ok)
    }
    if kind == .F64 {
        let (number, number_error) = str.parse_f64(text)
        if number_error != ok { ret (zero, InvalidArgument) }
        ret (Value{ F64: number }, ok)
    }
    ret (Value{ String: text }, ok)
}

fn find_option(command: *const Command, long: str, short: u8) -> (usize, bool) {
    var i = 0usize
    while i < command.options.len {
        if long.len > 0usize && str.eq(command.options[i].long, long) { ret (i, true) }
        if short != 0u8 && command.options[i].short == short { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// Values per option are collected in a scratch table of at most 8 per option, then
// copied out; a `Result` borrows the argument strings.
fn parse(a: *mem.Arena, command: *const Command, args: []const str) -> (Result, err) {
    let spec_error = validate(command)
    if spec_error != ok { ret (zero, spec_error) }
    var current = command
    var at = 0usize
    // Find the command first: the first bare word that names a subcommand descends.
    var positional_count = 0usize
    var options_done = false
    let (counts, counts_error) = mem.alloc[usize](a, 256usize)
    if counts_error != ok { ret (zero, counts_error) }
    let (values, values_error) = mem.alloc[Value](a, 256usize * 8usize)
    if values_error != ok { ret (zero, values_error) }
    let (positionals, positionals_error) = mem.alloc[str](a, args.len)
    if positionals_error != ok { ret (zero, positionals_error) }
    var i = 0usize
    while i < 256usize {
        counts[i] = 0usize
        i += 1usize
    }
    while at < args.len {
        let arg = args[at]
        at += 1usize
        if !options_done && str.eq(arg, "--") {
            options_done = true
            continue
        }
        if !options_done && arg.len > 1usize && arg[0] == 45u8 {
            var long = ""
            var short = 0u8
            var inline_value = ""
            var has_inline = false
            if arg[1] == 45u8 {
                let (name, rest, split) = str.split_once(arg[2usize..], "=")
                long = name
                inline_value = rest
                has_inline = split
            } else {
                if arg.len != 2usize { ret (zero, InvalidArgument) }
                short = arg[1]
            }
            let (index, found) = find_option(current, long, short)
            if !found { ret (zero, Unknown) }
            if index >= 256usize { ret (zero, InvalidSpec) }
            let o = current.options[index]
            var text = ""
            if o.kind == .Bool {
                text = "true"
                if has_inline { text = inline_value }
            } else {
                if has_inline {
                    text = inline_value
                } else {
                    if at >= args.len { ret (zero, InvalidArgument) }
                    text = args[at]
                    at += 1usize
                }
            }
            let (value, value_error) = parse_value(o.kind, text)
            if value_error != ok { ret (zero, value_error) }
            if counts[index] > 0usize && !o.repeated { ret (zero, InvalidArgument) }
            if counts[index] >= 8usize { ret (zero, InvalidArgument) }
            values[index * 8usize + counts[index]] = value
            counts[index] += 1usize
            continue
        }
        if positional_count == 0usize && !options_done {
            var sub = 0usize
            var descended = false
            while sub < current.subcommands.len {
                if str.eq(current.subcommands[sub].name, arg) {
                    current = &current.subcommands[sub]
                    descended = true
                    break
                }
                sub += 1usize
            }
            if descended {
                // The subcommand starts its own option table.
                i = 0usize
                while i < 256usize {
                    counts[i] = 0usize
                    i += 1usize
                }
                continue
            }
        }
        positionals[positional_count] = arg
        positional_count += 1usize
    }
    // Required options absent from the arguments come from the environment.
    var present = 0usize
    i = 0usize
    while i < current.options.len && i < 256usize {
        let o = current.options[i]
        if counts[i] == 0usize && o.env.len > 0usize {
            let (from_env, env_error) = os.env(a, o.env)
            if env_error == ok {
                let (value, value_error) = parse_value(o.kind, from_env)
                if value_error != ok { ret (zero, value_error) }
                values[i * 8usize] = value
                counts[i] = 1usize
            }
        }
        if counts[i] == 0usize && o.required { ret (zero, Missing) }
        if counts[i] > 0usize { present += 1usize }
        i += 1usize
    }
    let (parsed, parsed_error) = mem.alloc[ParsedOption](a, present)
    if parsed_error != ok { ret (zero, parsed_error) }
    var out = 0usize
    i = 0usize
    while i < current.options.len && i < 256usize {
        if counts[i] > 0usize {
            let (copy, copy_error) = mem.alloc[Value](a, counts[i])
            if copy_error != ok { ret (zero, copy_error) }
            mem.copy[Value](copy, values[i * 8usize..i * 8usize + counts[i]])
            parsed[out].name = current.options[i].long
            parsed[out].values = copy
            out += 1usize
        }
        i += 1usize
    }
    var result: Result = zero
    result.command = current.name
    result.options = parsed
    result.positionals = positionals[..positional_count]
    ret (result, ok)
}

fn option(result: *const Result, name: str) -> (ParsedOption, bool) {
    var i = 0usize
    while i < result.options.len {
        if str.eq(result.options[i].name, name) { ret (result.options[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn kind_name(kind: ValueKind) -> str {
    if kind == .Bool { ret "" }
    if kind == .I64 { ret " <int>" }
    if kind == .U64 { ret " <uint>" }
    if kind == .F64 { ret " <float>" }
    ret " <string>"
}

// Words of `text` wrapped at `width`, each continuation line indented by `indent`.
fn push_wrapped(b: *str.Builder, text: str, indent: usize, width: usize, column_in: usize) -> err {
    var column = column_in
    let (words0, words_error) = str.split(text, " ")
    if words_error != ok { ret words_error }
    var words = words0
    var first = true
    while true {
        let (word, more) = str.split_next(&words)
        if !more { break }
        if word.len == 0usize { continue }
        if !first && column + 1usize + word.len > width && width > 0usize {
            try str.push(b, "\n")
            var pad = 0usize
            while pad < indent {
                try str.push(b, " ")
                pad += 1usize
            }
            column = indent
        } else {
            if !first {
                try str.push(b, " ")
                column += 1usize
            }
        }
        try str.push(b, word)
        column += word.len
        first = false
    }
    ret ok
}

fn help(a: *mem.Arena, command: *const Command, width: u16) -> (str, err) {
    let (b0, builder_error) = str.builder(a, 4096usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    let render_error = render_help(&b, command, usize(width))
    if render_error != ok { ret ("", render_error) }
    ret (str.done(&b), ok)
}

fn render_help(b: *str.Builder, command: *const Command, w: usize) -> err {
    try str.push(b, "usage: ")
    try str.push(b, command.name)
    if command.options.len > 0usize { try str.push(b, " [options]") }
    if command.subcommands.len > 0usize { try str.push(b, " <command>") }
    try str.push(b, "\n")
    if command.help.len > 0usize {
        try str.push(b, "\n")
        try push_wrapped(b, command.help, 0usize, w, 0usize)
        try str.push(b, "\n")
    }
    if command.options.len > 0usize {
        try str.push(b, "\noptions:\n")
        var i = 0usize
        while i < command.options.len {
            let o = command.options[i]
            try str.push(b, "  ")
            var column = 2usize
            if o.short != 0u8 {
                try str.push(b, "-")
                var one: [1]u8 = zero
                one[0] = o.short
                try str.push(b, one[0..])
                try str.push(b, ", ")
                column += 4usize
            }
            try str.push(b, "--")
            try str.push(b, o.long)
            try str.push(b, kind_name(o.kind))
            column += 2usize + o.long.len + kind_name(o.kind).len
            if o.help.len > 0usize {
                try str.push(b, "  ")
                column += 2usize
                try push_wrapped(b, o.help, 6usize, w, column)
            }
            if o.required { try str.push(b, " (required)") }
            if o.env.len > 0usize {
                try str.push(b, " [env: ")
                try str.push(b, o.env)
                try str.push(b, "]")
            }
            try str.push(b, "\n")
            i += 1usize
        }
    }
    if command.subcommands.len > 0usize {
        try str.push(b, "\ncommands:\n")
        var i = 0usize
        while i < command.subcommands.len {
            try str.push(b, "  ")
            try str.push(b, command.subcommands[i].name)
            if command.subcommands[i].help.len > 0usize {
                try str.push(b, "  ")
                try push_wrapped(b, command.subcommands[i].help, 4usize, w, 4usize + command.subcommands[i].name.len)
            }
            try str.push(b, "\n")
            i += 1usize
        }
    }
    ret ok
}

// A struct's fields as `--name` options; a missing field keeps its zero.
fn parse_into[T: type](a: *mem.Arena, args: []const str) -> (T, err) {
    var out: T = zero
    var at = 0usize
    while at < args.len {
        let arg = args[at]
        at += 1usize
        if arg.len < 3usize || arg[0] != 45u8 || arg[1] != 45u8 { ret (out, InvalidArgument) }
        let (name, inline_value, has_inline) = str.split_once(arg[2usize..], "=")
        var matched = false
        for f in meta.fields[T]() {
            if str.eq(f.name, name) {
                matched = true
                var text = inline_value
                if meta.kind[f.ty]() == .Bool {
                    if !has_inline { text = "true" }
                    let (value, value_error) = parse_value(.Bool, text)
                    if value_error != ok { ret (out, value_error) }
                    var flag = false
                    switch value {
                    case .Bool as written:
                        flag = written
                    default:
                        flag = false
                    }
                    meta.set[f, T](&out, flag)
                } else {
                    if !has_inline {
                        if at >= args.len { ret (out, InvalidArgument) }
                        text = args[at]
                        at += 1usize
                    }
                    if meta.kind[f.ty]() == .Slice {
                        meta.set[f, T](&out, text)
                    } else {
                    if meta.kind[f.ty]() == .Int {
                        let (number, number_error) = str.parse_i64(text)
                        if number_error != ok { ret (out, InvalidArgument) }
                        var slot: f.ty = zero
                        slot = f.ty(number)
                        meta.set[f, T](&out, slot)
                    } else {
                    if meta.kind[f.ty]() == .Float {
                        let (number, number_error) = str.parse_f64(text)
                        if number_error != ok { ret (out, InvalidArgument) }
                        var slot: f.ty = zero
                        slot = f.ty(number)
                        meta.set[f, T](&out, slot)
                    } else {
                        ret (out, InvalidSpec)
                    }
                    }
                    }
                }
            }
        }
        if !matched { ret (out, Unknown) }
    }
    ret (out, ok)
}
