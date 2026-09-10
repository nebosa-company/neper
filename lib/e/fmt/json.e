// RFC 8259 JSON, as a value tree and as a stream of events.
//
// The whole of this module turns on one decision: a number is kept as the lexeme that was
// written. JSON's grammar admits numbers no binary float can hold -- an integer past 2^53, an
// exponent spelling that matters to whoever wrote it, a negative zero -- and a parser that
// rounds them into an `f64` on the way in has thrown that away before the caller is asked.
// So `Number` is a validated `str`, every conversion out of it is explicit, and a value that
// travels in and back out again is written exactly as it arrived.

use e.io
use e.mem
use e.meta
use e.str

type Number = struct {
    lexeme: str,
}

type Member = struct {
    key: str,
    value: Value,
}

// The tags are in declaration order and the order is JSON's own: `Null` first so that a zero
// `Value` is null rather than a bool nobody set.
type Value = union enum u8 {
    Null,
    Bool: bool,
    Number: Number,
    String: str,
    Array: []const Value,
    Object: []const Member,
}

type Event = union enum u8 {
    Null,
    Bool: bool,
    Number: Number,
    String: str,
    Key: str,
    BeginArray,
    EndArray,
    BeginObject,
    EndObject,
}

type Reader = struct {
    state: *void,
}

type Options = struct {
    allow_duplicate_keys: bool,
    max_depth: u16,
}

error Invalid
error TooDeep
error DuplicateKey
error TooLarge

// A `zero` Options is the one a caller writes without thinking about it, and unbounded
// recursion on input from elsewhere is not what that should mean. Zero is therefore this
// rather than no limit, which is the opposite of `e.path`'s globs -- there a zero limit costs
// a caller nothing, here it costs them the stack.
const DEFAULT_MAX_DEPTH: u16 = 128u16

// The value stack a parse builds through. It holds the elements of every container that is
// open, so it is the total element count in the worst case (`[1,1,1,...]`) and the nesting
// depth in the best.
//
// ponytail: sized from the source and allocated in the caller's arena, where it outlives the
// parse it was for. Two arenas -- one for the tree, one to reset -- would reclaim it, and the
// surface takes one.
const MAX_STACK: usize = 1048576usize

// --- Numbers.

// RFC 8259's grammar: an optional minus, an integer part with no leading zero, an optional
// fraction of at least one digit, an optional exponent of at least one digit. Nothing else --
// no leading plus, no bare `.5`, no `1.`, no hexadecimal, no `Infinity`.
fn number(source: str) -> (Number, err) {
    var result: Number = zero
    var at = 0usize
    if at < source.len && source[at] == 45u8 { at += 1usize }
    if at >= source.len { ret (result, Invalid) }
    if source[at] == 48u8 {
        at += 1usize
    } else {
        if !str.is_ascii_digit(source[at]) { ret (result, Invalid) }
        while at < source.len && str.is_ascii_digit(source[at]) { at += 1usize }
    }
    if at < source.len && source[at] == 46u8 {
        at += 1usize
        if at >= source.len || !str.is_ascii_digit(source[at]) { ret (result, Invalid) }
        while at < source.len && str.is_ascii_digit(source[at]) { at += 1usize }
    }
    if at < source.len && (source[at] == 101u8 || source[at] == 69u8) {
        at += 1usize
        if at < source.len && (source[at] == 43u8 || source[at] == 45u8) { at += 1usize }
        if at >= source.len || !str.is_ascii_digit(source[at]) { ret (result, Invalid) }
        while at < source.len && str.is_ascii_digit(source[at]) { at += 1usize }
    }
    if at != source.len { ret (result, Invalid) }
    result.lexeme = source
    ret (result, ok)
}

// The lexeme taken apart with nothing rounded: the digits are `lexeme[start..end]` with at most
// one `.` among them to step over, and the value is exactly those digits read as an integer
// times ten to the `exponent`. Leading and trailing zeros are folded away first, so a value
// that is integral has a non-negative exponent and one that is not cannot pretend to be.
fn decompose(lexeme: str) -> (bool, usize, usize, i64, err) {
    let (checked, valid) = number(lexeme)
    if valid != ok { ret (false, 0usize, 0usize, 0i64, valid) }
    var at = 0usize
    var negative = false
    if lexeme[at] == 45u8 {
        negative = true
        at += 1usize
    }
    var start = at
    while at < lexeme.len && str.is_ascii_digit(lexeme[at]) { at += 1usize }
    var fraction = 0i64
    if at < lexeme.len && lexeme[at] == 46u8 {
        at += 1usize
        while at < lexeme.len && str.is_ascii_digit(lexeme[at]) {
            at += 1usize
            fraction += 1i64
        }
    }
    var end = at
    var exponent = 0i64
    if at < lexeme.len {
        at += 1usize
        var exponent_negative = false
        if lexeme[at] == 43u8 {
            at += 1usize
        } else {
            if lexeme[at] == 45u8 {
                exponent_negative = true
                at += 1usize
            }
        }
        while at < lexeme.len {
            // An exponent past this is far outside every range here whichever way it points,
            // so clamping it cannot change an answer, and it keeps the count in range.
            if exponent < 1000000i64 { exponent = exponent * 10i64 + i64(lexeme[at] - 48u8) }
            at += 1usize
        }
        if exponent_negative { exponent = 0i64 - exponent }
    }
    exponent -= fraction

    // A leading zero leaves the digits' value alone; a trailing one divides it by ten, so the
    // exponent climbs to pay for it.
    while start < end && (lexeme[start] == 48u8 || lexeme[start] == 46u8) { start += 1usize }
    while end > start {
        if lexeme[end - 1usize] == 46u8 {
            end -= 1usize
        } else {
            if lexeme[end - 1usize] != 48u8 { break }
            end -= 1usize
            exponent += 1i64
        }
    }
    ret (negative, start, end, exponent, ok)
}

// The digits of a decomposed lexeme as a u64, refusing what does not fit rather than wrapping.
// A `.` is stepped over; the caller has already established there is at most one.
fn digits_u64(lexeme: str, start: usize, end: usize) -> (u64, err) {
    var value = 0u64
    var at = start
    while at < end {
        let byte = lexeme[at]
        at += 1usize
        if byte != 46u8 {
            let digit = u64(byte - 48u8)
            if value > (18446744073709551615u64 - digit) / 10u64 { ret (0u64, TooLarge) }
            value = value * 10u64 + digit
        }
    }
    ret (value, ok)
}

// `digits * 10^exponent` as a u64, exactly. A negative exponent has already been paid off by
// the trailing zeros `decompose` folded away, so one that survives here means a fraction, and
// a fraction is not an integer however it is spelled.
fn scaled_u64(value: u64, exponent: i64) -> (u64, err) {
    if exponent < 0i64 { ret (0u64, Invalid) }
    var scaled = value
    var remaining = exponent
    while remaining > 0i64 {
        if scaled > 18446744073709551615u64 / 10u64 { ret (0u64, TooLarge) }
        scaled = scaled * 10u64
        remaining -= 1i64
    }
    ret (scaled, ok)
}

fn number_u64(value: Number) -> (u64, err) {
    let (negative, start, end, exponent, failure) = decompose(value.lexeme)
    if failure != ok { ret (0u64, failure) }
    // Every digit fell away, so the value is zero however it was spelled -- `0`, `0.000`,
    // `-0`, `0e9`. Only then is a minus sign something a u64 can answer.
    if start == end { ret (0u64, ok) }
    if negative { ret (0u64, Invalid) }
    let (digits, digits_failure) = digits_u64(value.lexeme, start, end)
    if digits_failure != ok { ret (0u64, digits_failure) }
    let (scaled, scale_failure) = scaled_u64(digits, exponent)
    ret (scaled, scale_failure)
}

fn number_i64(value: Number) -> (i64, err) {
    let (negative, start, end, exponent, failure) = decompose(value.lexeme)
    if failure != ok { ret (0i64, failure) }
    if start == end { ret (0i64, ok) }
    let (digits, digits_failure) = digits_u64(value.lexeme, start, end)
    if digits_failure != ok { ret (0i64, digits_failure) }
    let (magnitude, scale_failure) = scaled_u64(digits, exponent)
    if scale_failure != ok { ret (0i64, scale_failure) }
    if negative {
        if magnitude > 9223372036854775808u64 { ret (0i64, TooLarge) }
        if magnitude == 9223372036854775808u64 { ret (0i64 - 9223372036854775807i64 - 1i64, ok) }
        ret (0i64 - i64(magnitude), ok)
    }
    if magnitude > 9223372036854775807u64 { ret (0i64, TooLarge) }
    ret (i64(magnitude), ok)
}

// The exponent field is all ones for an infinity and for a NaN, and for nothing else.
fn finite(value: f64) -> bool {
    let exponent_bits = mem.bitcast[u64](value) & 9218868437227405312u64
    ret exponent_bits != 9218868437227405312u64
}

fn number_f64(value: Number) -> (f64, err) {
    let (checked, valid) = number(value.lexeme)
    if valid != ok { ret (0.0f64, valid) }
    let (parsed, failure) = str.parse_f64(value.lexeme)
    // A lexeme this rejects is a valid JSON number too far out for the format to name, which
    // is the one thing `TooLarge` says here.
    if failure != ok { ret (0.0f64, TooLarge) }
    if !finite(parsed) { ret (0.0f64, TooLarge) }
    ret (parsed, ok)
}

fn number_from_i64(a: *mem.Arena, value: i64) -> (Number, err) {
    var result: Number = zero
    var (b, builder_failure) = str.builder(a, 24usize)
    if builder_failure != ok { ret (result, builder_failure) }
    let push_failure = str.push_i64(&b, value)
    if push_failure != ok { ret (result, push_failure) }
    result.lexeme = str.done(&b)
    ret (result, ok)
}

fn number_from_u64(a: *mem.Arena, value: u64) -> (Number, err) {
    var result: Number = zero
    var (b, builder_failure) = str.builder(a, 24usize)
    if builder_failure != ok { ret (result, builder_failure) }
    let push_failure = str.push_u64(&b, value)
    if push_failure != ok { ret (result, push_failure) }
    result.lexeme = str.done(&b)
    ret (result, ok)
}

// JSON has no spelling for an infinity or a NaN, so there is nothing to write and the honest
// answer is to refuse rather than to invent a `null`.
fn number_from_f64(a: *mem.Arena, value: f64) -> (Number, err) {
    var result: Number = zero
    if !finite(value) { ret (result, Invalid) }
    var (b, builder_failure) = str.builder(a, 32usize)
    if builder_failure != ok { ret (result, builder_failure) }
    let push_failure = str.push_f64(&b, value)
    if push_failure != ok { ret (result, push_failure) }
    // `push_f64` writes the shortest spelling that reads back as the same f64. That it is
    // also a JSON number is established here rather than assumed, since a lexeme that
    // survives validation is the one thing this module promises about a `Number`.
    let (checked, checked_failure) = number(str.done(&b))
    ret (checked, checked_failure)
}

// --- Parsing into a tree.

// One stack serves both containers: an array element is a member whose key is empty. What is
// on it is every element of every container still open, so closing one is a copy of a run off
// the top rather than a walk of anything.
type Parser = struct {
    source: str,
    at: usize,
    arena: *mem.Arena,
    stack: []Member,
    height: usize,
    max_depth: u16,
    allow_duplicate_keys: bool,
}

fn is_space(byte: u8) -> bool {
    ret byte == 32u8 || byte == 9u8 || byte == 10u8 || byte == 13u8
}

fn skip_space(p: *Parser) {
    while p.at < p.source.len && is_space(p.source[p.at]) { p.at += 1usize }
}

fn hex_value(byte: u8) -> (u32, bool) {
    if byte >= 48u8 && byte <= 57u8 { ret (u32(byte - 48u8), true) }
    if byte >= 97u8 && byte <= 102u8 { ret (u32(byte - 97u8) + 10u32, true) }
    if byte >= 65u8 && byte <= 70u8 { ret (u32(byte - 65u8) + 10u32, true) }
    ret (0u32, false)
}

// The four hex digits of a `\u` escape, which the caller has positioned at.
fn hex4(source: str, at: usize) -> (u32, bool) {
    if at + 4usize > source.len { ret (0u32, false) }
    var value = 0u32
    var index = 0usize
    while index < 4usize {
        let (digit, valid) = hex_value(source[at + index])
        if !valid { ret (0u32, false) }
        value = value * 16u32 + digit
        index += 1usize
    }
    ret (value, true)
}

fn encode_utf8(into: []u8, at: usize, point: u32) -> usize {
    if point < 128u32 {
        into[at] = u8(point)
        ret at + 1usize
    }
    if point < 2048u32 {
        into[at] = u8(192u32 | (point >> 6u8))
        into[at + 1usize] = u8(128u32 | (point & 63u32))
        ret at + 2usize
    }
    if point < 65536u32 {
        into[at] = u8(224u32 | (point >> 12u8))
        into[at + 1usize] = u8(128u32 | ((point >> 6u8) & 63u32))
        into[at + 2usize] = u8(128u32 | (point & 63u32))
        ret at + 3usize
    }
    into[at] = u8(240u32 | (point >> 18u8))
    into[at + 1usize] = u8(128u32 | ((point >> 12u8) & 63u32))
    into[at + 2usize] = u8(128u32 | ((point >> 6u8) & 63u32))
    into[at + 3usize] = u8(128u32 | (point & 63u32))
    ret at + 4usize
}

// A string, with the opening quote already behind. One that carries no escape is the source's
// own bytes and is borrowed; one that does is decoded into the arena, and since every escape
// is longer than what it stands for, the raw span is always room enough.
fn parse_string(p: *Parser) -> (str, err) {
    let start = p.at
    var escaped = false
    var at = p.at
    while at < p.source.len {
        let byte = p.source[at]
        if byte == 34u8 { break }
        if byte < 32u8 { ret ("", Invalid) }
        if byte == 92u8 {
            escaped = true
            at += 1usize
            if at >= p.source.len { ret ("", Invalid) }
        }
        at += 1usize
    }
    if at >= p.source.len { ret ("", Invalid) }
    let raw = p.source[start..at]
    if !escaped {
        p.at = at + 1usize
        ret (raw, ok)
    }
    let (buffer, allocation_failure) = mem.alloc[u8](p.arena, raw.len)
    if allocation_failure != ok { ret ("", allocation_failure) }
    var written = 0usize
    var read = 0usize
    while read < raw.len {
        let byte = raw[read]
        if byte != 92u8 {
            buffer[written] = byte
            written += 1usize
            read += 1usize
        } else {
            read += 1usize
            if read >= raw.len { ret ("", Invalid) }
            let escape = raw[read]
            read += 1usize
            if escape == 34u8 || escape == 92u8 || escape == 47u8 {
                buffer[written] = escape
                written += 1usize
            } else {
                if escape == 98u8 {
                    buffer[written] = 8u8
                    written += 1usize
                } else {
                    if escape == 102u8 {
                        buffer[written] = 12u8
                        written += 1usize
                    } else {
                        if escape == 110u8 {
                            buffer[written] = 10u8
                            written += 1usize
                        } else {
                            if escape == 114u8 {
                                buffer[written] = 13u8
                                written += 1usize
                            } else {
                                if escape == 116u8 {
                                    buffer[written] = 9u8
                                    written += 1usize
                                } else {
                                    if escape != 117u8 { ret ("", Invalid) }
                                    let (unit, valid) = hex4(raw, read)
                                    if !valid { ret ("", Invalid) }
                                    read += 4usize
                                    var point = unit
                                    // A high surrogate is half a code point and means
                                    // nothing without the low one that follows it.
                                    if unit >= 55296u32 && unit < 56320u32 {
                                        if read + 2usize > raw.len { ret ("", Invalid) }
                                        if raw[read] != 92u8 { ret ("", Invalid) }
                                        if raw[read + 1usize] != 117u8 { ret ("", Invalid) }
                                        let (low, low_valid) = hex4(raw, read + 2usize)
                                        if !low_valid { ret ("", Invalid) }
                                        if low < 56320u32 || low >= 57344u32 { ret ("", Invalid) }
                                        read += 6usize
                                        point = 65536u32 + ((unit - 55296u32) << 10u8) + (low - 56320u32)
                                    } else {
                                        // A low surrogate on its own is the same half a
                                        // code point from the other end.
                                        if unit >= 56320u32 && unit < 57344u32 { ret ("", Invalid) }
                                    }
                                    written = encode_utf8(buffer, written, point)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    p.at = at + 1usize
    ret (buffer[0usize..written], ok)
}

// The number's span in the source, validated as a whole rather than as it is walked: the
// lexeme this borrows is what every later conversion reads, so it has to be exactly what
// `number` would accept and nothing looser.
fn parse_number(p: *Parser) -> (Number, err) {
    let start = p.at
    var at = p.at
    if at < p.source.len && p.source[at] == 45u8 { at += 1usize }
    while at < p.source.len {
        let byte = p.source[at]
        if str.is_ascii_digit(byte) || byte == 46u8 || byte == 101u8 || byte == 69u8 {
            at += 1usize
        } else {
            if byte == 43u8 || byte == 45u8 {
                // A sign belongs to an exponent, and an exponent has just been read.
                let previous = p.source[at - 1usize]
                if previous != 101u8 && previous != 69u8 { break }
                at += 1usize
            } else {
                break
            }
        }
    }
    let (parsed, failure) = number(p.source[start..at])
    if failure != ok {
        var empty: Number = zero
        ret (empty, failure)
    }
    p.at = at
    ret (parsed, ok)
}

fn literal(p: *Parser, word: str) -> bool {
    if p.at + word.len > p.source.len { ret false }
    if !str.eq(p.source[p.at..p.at + word.len], word) { ret false }
    p.at += word.len
    ret true
}

fn push_element(p: *Parser, key: str, value: Value) -> err {
    if p.height >= p.stack.len { ret TooLarge }
    p.stack[p.height].key = key
    p.stack[p.height].value = value
    p.height += 1usize
    ret ok
}

// ponytail: a quadratic scan over the members of one object. Linear would want a set, and
// `e.data.map` is not written; the depth limit bounds what this can cost.
fn duplicate_key(p: *Parser, base: usize, key: str) -> bool {
    var at = base
    while at < p.height {
        if str.eq(p.stack[at].key, key) { ret true }
        at += 1usize
    }
    ret false
}

fn parse_value(p: *Parser, depth: u16) -> (Value, err) {
    var result: Value = .Null
    skip_space(p)
    if p.at >= p.source.len { ret (result, Invalid) }
    let byte = p.source[p.at]
    if byte == 110u8 {
        if !literal(p, "null") { ret (result, Invalid) }
        ret (result, ok)
    }
    if byte == 116u8 {
        if !literal(p, "true") { ret (result, Invalid) }
        ret (Value{ Bool: true }, ok)
    }
    if byte == 102u8 {
        if !literal(p, "false") { ret (result, Invalid) }
        ret (Value{ Bool: false }, ok)
    }
    if byte == 34u8 {
        p.at += 1usize
        let (text, text_failure) = parse_string(p)
        if text_failure != ok { ret (result, text_failure) }
        ret (Value{ String: text }, ok)
    }
    if byte == 45u8 || str.is_ascii_digit(byte) {
        let (parsed, failure) = parse_number(p)
        if failure != ok { ret (result, failure) }
        ret (Value{ Number: parsed }, ok)
    }
    if byte == 91u8 {
        // The limit counts containers, because that is what nesting is: a scalar inside the
        // innermost array is not another level of anything, and it is the containers that
        // this function recurses through.
        if depth > p.max_depth { ret (result, TooDeep) }
        p.at += 1usize
        let base = p.height
        skip_space(p)
        if p.at < p.source.len && p.source[p.at] == 93u8 {
            p.at += 1usize
            let (none, none_failure) = mem.alloc[Value](p.arena, 0usize)
            if none_failure != ok { ret (result, none_failure) }
            ret (Value{ Array: none }, ok)
        }
        while true {
            let (element, element_failure) = parse_value(p, depth + 1u16)
            if element_failure != ok { ret (result, element_failure) }
            let push_failure = push_element(p, "", element)
            if push_failure != ok { ret (result, push_failure) }
            skip_space(p)
            if p.at >= p.source.len { ret (result, Invalid) }
            if p.source[p.at] == 44u8 {
                p.at += 1usize
            } else {
                if p.source[p.at] != 93u8 { ret (result, Invalid) }
                p.at += 1usize
                break
            }
        }
        let count = p.height - base
        let (items, items_failure) = mem.alloc[Value](p.arena, count)
        if items_failure != ok { ret (result, items_failure) }
        var index = 0usize
        while index < count {
            items[index] = p.stack[base + index].value
            index += 1usize
        }
        p.height = base
        ret (Value{ Array: items }, ok)
    }
    if byte == 123u8 {
        if depth > p.max_depth { ret (result, TooDeep) }
        p.at += 1usize
        let base = p.height
        skip_space(p)
        if p.at < p.source.len && p.source[p.at] == 125u8 {
            p.at += 1usize
            let (none, none_failure) = mem.alloc[Member](p.arena, 0usize)
            if none_failure != ok { ret (result, none_failure) }
            ret (Value{ Object: none }, ok)
        }
        while true {
            skip_space(p)
            if p.at >= p.source.len || p.source[p.at] != 34u8 { ret (result, Invalid) }
            p.at += 1usize
            let (key, key_failure) = parse_string(p)
            if key_failure != ok { ret (result, key_failure) }
            if !p.allow_duplicate_keys && duplicate_key(p, base, key) { ret (result, DuplicateKey) }
            skip_space(p)
            if p.at >= p.source.len || p.source[p.at] != 58u8 { ret (result, Invalid) }
            p.at += 1usize
            let (member, member_failure) = parse_value(p, depth + 1u16)
            if member_failure != ok { ret (result, member_failure) }
            let push_failure = push_element(p, key, member)
            if push_failure != ok { ret (result, push_failure) }
            skip_space(p)
            if p.at >= p.source.len { ret (result, Invalid) }
            if p.source[p.at] == 44u8 {
                p.at += 1usize
            } else {
                if p.source[p.at] != 125u8 { ret (result, Invalid) }
                p.at += 1usize
                break
            }
        }
        let count = p.height - base
        let (members, members_failure) = mem.alloc[Member](p.arena, count)
        if members_failure != ok { ret (result, members_failure) }
        var index = 0usize
        while index < count {
            members[index] = p.stack[base + index]
            index += 1usize
        }
        p.height = base
        ret (Value{ Object: members }, ok)
    }
    ret (result, Invalid)
}

fn parse(a: *mem.Arena, source: str, options: Options) -> (Value, err) {
    var result: Value = .Null
    var room = source.len / 2usize + 4usize
    if room > MAX_STACK { room = MAX_STACK }
    let (stack, stack_failure) = mem.alloc[Member](a, room)
    if stack_failure != ok { ret (result, stack_failure) }
    var p: Parser = zero
    p.source = source
    p.at = 0usize
    p.arena = a
    p.stack = stack
    p.height = 0usize
    p.max_depth = options.max_depth
    if p.max_depth == 0u16 { p.max_depth = DEFAULT_MAX_DEPTH }
    p.allow_duplicate_keys = options.allow_duplicate_keys
    let (value, failure) = parse_value(&p, 1u16)
    if failure != ok { ret (result, failure) }
    skip_space(&p)
    // A document is one value. Anything after it is not this document's.
    if p.at != source.len { ret (result, Invalid) }
    ret (value, ok)
}

// --- Writing a tree back out.

// ponytail: arithmetic rather than a lookup table, because a module-scope `const` of type
// `str` does not type check today -- `str` is `[]const u8` and the checker has no comptime
// value for a slice. A literal in an expression is fine, which is what the writers below use.
fn hex_digit(nibble: u8) -> u8 {
    if nibble < 10u8 { ret 48u8 + nibble }
    ret 87u8 + nibble
}

// The bytes JSON insists on an escape for are the quote, the backslash and everything below a
// space. Everything else goes out as it came in, which is what keeps a round trip a round trip
// rather than a re-encoding.
fn write_string(w: *io.Writer, text: str) -> err {
    try io.write_all(w, "\"")
    var run = 0usize
    var at = 0usize
    while at < text.len {
        let byte = text[at]
        if byte == 34u8 || byte == 92u8 || byte < 32u8 {
            if at > run { try io.write_all(w, text[run..at]) }
            var escape: [6]u8 = zero
            escape[0usize] = 92u8
            var length = 2usize
            if byte == 34u8 {
                escape[1usize] = 34u8
            } else {
                if byte == 92u8 {
                    escape[1usize] = 92u8
                } else {
                    if byte == 8u8 {
                        escape[1usize] = 98u8
                    } else {
                        if byte == 12u8 {
                            escape[1usize] = 102u8
                        } else {
                            if byte == 10u8 {
                                escape[1usize] = 110u8
                            } else {
                                if byte == 13u8 {
                                    escape[1usize] = 114u8
                                } else {
                                    if byte == 9u8 {
                                        escape[1usize] = 116u8
                                    } else {
                                        escape[1usize] = 117u8
                                        escape[2usize] = 48u8
                                        escape[3usize] = 48u8
                                        escape[4usize] = hex_digit(byte >> 4u8)
                                        escape[5usize] = hex_digit(byte & 15u8)
                                        length = 6usize
                                    }
                                }
                            }
                        }
                    }
                }
            }
            try io.write_all(w, escape[0usize..length])
            run = at + 1usize
        }
        at += 1usize
    }
    if text.len > run { try io.write_all(w, text[run..text.len]) }
    ret io.write_all(w, "\"")
}

// A `Number` that reached here from outside was never checked by anything: it is a public
// struct over a public `str`, so a caller can build one by hand. Revalidating is what keeps
// this from writing a document that will not read back.
fn write_number(w: *io.Writer, value: Number) -> err {
    let (checked, failure) = number(value.lexeme)
    if failure != ok { ret failure }
    ret io.write_all(w, checked.lexeme)
}

fn write_indent(w: *io.Writer, spaces: usize) -> err {
    let run = "                                "
    var remaining = spaces
    while remaining > 0usize {
        var take = remaining
        if take > run.len { take = run.len }
        try io.write_all(w, run[0usize..take])
        remaining -= take
    }
    ret ok
}

fn write_value(w: *io.Writer, value: *const Value, indent: u8, depth: usize) -> err {
    switch *value {
    case .Null:
        ret io.write_all(w, "null")
    case .Bool as flag:
        if flag { ret io.write_all(w, "true") }
        ret io.write_all(w, "false")
    case .Number as literal_number:
        ret write_number(w, literal_number)
    case .String as text:
        ret write_string(w, text)
    case .Array as items:
        if items.len == 0usize { ret io.write_all(w, "[]") }
        try io.write_all(w, "[")
        var at = 0usize
        while at < items.len {
            if at > 0usize { try io.write_all(w, ",") }
            if indent != 0u8 {
                try io.write_all(w, "\n")
                try write_indent(w, usize(indent) * (depth + 1usize))
            }
            try write_value(w, &items[at], indent, depth + 1usize)
            at += 1usize
        }
        if indent != 0u8 {
            try io.write_all(w, "\n")
            try write_indent(w, usize(indent) * depth)
        }
        ret io.write_all(w, "]")
    case .Object as members:
        if members.len == 0usize { ret io.write_all(w, "{}") }
        try io.write_all(w, "{")
        var at = 0usize
        while at < members.len {
            if at > 0usize { try io.write_all(w, ",") }
            if indent != 0u8 {
                try io.write_all(w, "\n")
                try write_indent(w, usize(indent) * (depth + 1usize))
            }
            try write_string(w, members[at].key)
            try io.write_all(w, ":")
            if indent != 0u8 { try io.write_all(w, " ") }
            try write_value(w, &members[at].value, indent, depth + 1usize)
            at += 1usize
        }
        if indent != 0u8 {
            try io.write_all(w, "\n")
            try write_indent(w, usize(indent) * depth)
        }
        ret io.write_all(w, "}")
    default:
        ret Invalid
    }
}

fn write(writer: *io.Writer, value: *const Value) -> err {
    ret write_value(writer, value, 0u8, 0usize)
}

// An indent of zero is the compact form, which makes this `write` with a knob rather than a
// second spelling of it that has to be kept in step.
fn write_pretty(writer: *io.Writer, value: *const Value, indent: u8) -> err {
    ret write_value(writer, value, indent, 0usize)
}

// --- RFC 6901 pointers.

error InvalidPointer
error PatchFailed

// A reference token against a member key, with `~1` standing for `/` and `~0` for `~`, decoded
// as the comparison walks rather than into a buffer first -- the escapes only ever shrink, so
// there is nothing a copy would settle that this does not.
fn token_eq(token: str, key: str) -> bool {
    var at = 0usize
    var against = 0usize
    while at < token.len {
        if against >= key.len { ret false }
        var byte = token[at]
        at += 1usize
        if byte == 126u8 {
            if at >= token.len { ret false }
            let escaped = token[at]
            at += 1usize
            if escaped == 48u8 {
                byte = 126u8
            } else {
                if escaped != 49u8 { ret false }
                byte = 47u8
            }
        }
        if key[against] != byte { ret false }
        against += 1usize
    }
    ret against == key.len
}

// An array index is decimal, has no leading zero, and is not `-`: `-` names the position after
// the last element, which is somewhere to add and nowhere to find.
fn array_index(token: str) -> (usize, bool) {
    if token.len == 0usize { ret (0usize, false) }
    if token.len > 1usize && token[0usize] == 48u8 { ret (0usize, false) }
    var value = 0usize
    var at = 0usize
    while at < token.len {
        if !str.is_ascii_digit(token[at]) { ret (0usize, false) }
        let digit = usize(token[at] - 48u8)
        if value > (18446744073709551615usize - digit) / 10usize { ret (0usize, false) }
        value = value * 10usize + digit
        at += 1usize
    }
    ret (value, true)
}

// The empty pointer is the root, and every other one starts with `/` -- so `""` and `"/"` are
// different pointers, the second naming a member whose key is empty.
fn pointer(root: *const Value, path: str) -> (*const Value, err) {
    if path.len == 0usize { ret (root, ok) }
    if path[0usize] != 47u8 { ret (root, InvalidPointer) }
    var here = root
    var at = 1usize
    while true {
        var end = at
        while end < path.len && path[end] != 47u8 { end += 1usize }
        let token = path[at..end]
        var stepped = false
        switch *here {
        case .Object as members:
            var index = 0usize
            while index < members.len {
                if token_eq(token, members[index].key) {
                    here = &members[index].value
                    stepped = true
                    break
                }
                index += 1usize
            }
        case .Array as items:
            let (index, valid) = array_index(token)
            if valid && index < items.len {
                here = &items[index]
                stepped = true
            }
        default:
            stepped = false
        }
        if !stepped { ret (root, InvalidPointer) }
        if end >= path.len { break }
        at = end + 1usize
    }
    ret (here, ok)
}
