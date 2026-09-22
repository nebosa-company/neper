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

type Number = struct { lexeme: str }

type Member = struct { key: str, value: Value }

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

type Reader = struct { state: *void }

type Options = struct { allow_duplicate_keys: bool, max_depth: u16 }

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
    // `str.parse_f64` spells the exponent marker `e` only; JSON allows `E` too.
    var lowered: [64]u8 = zero
    var spelling = value.lexeme
    if value.lexeme.len <= lowered.len {
        mem.copy[u8](lowered[..value.lexeme.len], value.lexeme)
        str.ascii_lower_in_place(lowered[..value.lexeme.len])
        spelling = lowered[..value.lexeme.len]
    }
    let (parsed, failure) = str.parse_f64(spelling)
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
type Parser = struct { source: str, at: usize, arena: *mem.Arena, stack: []Member, height: usize, max_depth: u16, allow_duplicate_keys: bool }

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
// --- RFC 6902 patch.
//
// Every operation produces a new tree. `root` is copied once on the way in -- strings and number
// lexemes included, which is what makes the result arena-owned and what keeps `root` untouched --
// and each operation afterwards rebuilds the spine down to what it changes, sharing the branches
// it does not. A failure resets the arena to where it started and answers zero, so a patch that
// does not apply leaves nothing behind.
//
// Numbers are compared as `test` requires: exact mathematical equality. `1.0`, `1` and `1e0` are
// the same number written three ways, and `f64` equality would agree with that by luck and
// disagree elsewhere, so the lexemes are normalised and compared instead.

const OP_ADD: u8 = 0u8
const OP_REMOVE: u8 = 1u8
const OP_REPLACE: u8 = 2u8
const OP_MOVE: u8 = 3u8
const OP_COPY: u8 = 4u8
const OP_TEST: u8 = 5u8

const DEFAULT_MAX_OPERATIONS: usize = 1024usize
// A path has one token per level, so it is bounded by the same depth the tree is.
const MAX_PATH_TOKENS: usize = 256usize

fn copy_text(a: *mem.Arena, text: str) -> (str, err) {
    if text.len == 0usize { ret ("", ok) }
    let (buffer, allocation_error) = mem.alloc[u8](a, text.len)
    if allocation_error != ok { ret ("", allocation_error) }
    mem.copy[u8](buffer, text)
    ret (buffer, ok)
}

// A whole subtree into this arena. Nothing of the original is shared, so the result outlives it
// and cannot be changed by anyone still holding it.
fn copy_value(a: *mem.Arena, value: *const Value, depth: u16, limit: u16) -> (Value, err) {
    var out: Value = .Null
    if depth > limit { ret (out, TooDeep) }
    switch *value {
    case .Null:
        ret (out, ok)
    case .Bool as flag:
        ret (Value{ Bool: flag }, ok)
    case .Number as written:
        let (lexeme, lexeme_error) = copy_text(a, written.lexeme)
        if lexeme_error != ok { ret (out, lexeme_error) }
        ret (Value{ Number: Number { lexeme: lexeme } }, ok)
    case .String as text:
        let (copied, copied_error) = copy_text(a, text)
        if copied_error != ok { ret (out, copied_error) }
        ret (Value{ String: copied }, ok)
    case .Array as items:
        let (elements, elements_error) = mem.alloc[Value](a, items.len)
        if elements_error != ok { ret (out, elements_error) }
        var at = 0usize
        while at < items.len {
            let (element, element_error) = copy_value(a, &items[at], depth + 1u16, limit)
            if element_error != ok { ret (out, element_error) }
            elements[at] = element
            at += 1usize
        }
        ret (Value{ Array: elements }, ok)
    case .Object as members:
        let (entries, entries_error) = mem.alloc[Member](a, members.len)
        if entries_error != ok { ret (out, entries_error) }
        var at = 0usize
        while at < members.len {
            let (key, key_error) = copy_text(a, members[at].key)
            if key_error != ok { ret (out, key_error) }
            let (element, element_error) = copy_value(a, &members[at].value, depth + 1u16, limit)
            if element_error != ok { ret (out, element_error) }
            entries[at].key = key
            entries[at].value = element
            at += 1usize
        }
        ret (Value{ Object: entries }, ok)
    default:
        ret (out, Invalid)
    }
}

// Exact mathematical equality over two validated lexemes. Each is reduced to a sign, a run of
// significant digits and a power of ten, and the three are compared -- so `1.0`, `1` and `1e0`
// agree and `0.1` and `0.1000000000000000055511151231257827` do not.
fn number_parts(lexeme: str) -> (bool, str, i64, bool) {
    if lexeme.len == 0usize { ret (false, "", 0i64, false) }
    var at = 0usize
    var negative = false
    if lexeme[at] == 45u8 {
        negative = true
        at += 1usize
    }
    let digits_start = at
    while at < lexeme.len && str.is_ascii_digit(lexeme[at]) { at += 1usize }
    let integer_part = lexeme[digits_start..at]
    var fraction = ""
    if at < lexeme.len && lexeme[at] == 46u8 {
        at += 1usize
        let fraction_start = at
        while at < lexeme.len && str.is_ascii_digit(lexeme[at]) { at += 1usize }
        fraction = lexeme[fraction_start..at]
    }
    var exponent = 0i64
    if at < lexeme.len && (lexeme[at] == 101u8 || lexeme[at] == 69u8) {
        at += 1usize
        var exponent_negative = false
        if at < lexeme.len && (lexeme[at] == 43u8 || lexeme[at] == 45u8) {
            exponent_negative = lexeme[at] == 45u8
            at += 1usize
        }
        let exponent_start = at
        while at < lexeme.len && str.is_ascii_digit(lexeme[at]) { at += 1usize }
        let (magnitude, magnitude_error) = str.parse_i64(lexeme[exponent_start..at])
        if magnitude_error != ok { ret (false, "", 0i64, false) }
        exponent = magnitude
        if exponent_negative { exponent = -exponent }
    }
    if at != lexeme.len { ret (false, "", 0i64, false) }
    ret (negative, integer_part, exponent - i64(fraction.len), true)
}

// The digits of a number with its point already folded into the exponent, then trimmed: leading
// zeros carry no value and trailing ones move into the exponent.
fn normalised_digits(integer_part: str, fraction: str, scale: i64) -> (usize, usize, i64, bool) {
    var total = integer_part.len + fraction.len
    var lead = 0usize
    while lead < total {
        var digit = 48u8
        if lead < integer_part.len {
            digit = integer_part[lead]
        } else {
            digit = fraction[lead - integer_part.len]
        }
        if digit != 48u8 { break }
        lead += 1usize
    }
    if lead == total { ret (0usize, 0usize, 0i64, true) }
    var trail = total
    var power = scale
    while trail > lead {
        var digit = 48u8
        if trail - 1usize < integer_part.len {
            digit = integer_part[trail - 1usize]
        } else {
            digit = fraction[trail - 1usize - integer_part.len]
        }
        if digit != 48u8 { break }
        trail -= 1usize
        power += 1i64
    }
    ret (lead, trail, power, false)
}

fn digit_at(integer_part: str, fraction: str, index: usize) -> u8 {
    if index < integer_part.len { ret integer_part[index] }
    ret fraction[index - integer_part.len]
}

fn numbers_equal(left: Number, right: Number) -> bool {
    let (left_negative, left_integer, left_scale, left_valid) = number_parts(left.lexeme)
    let (right_negative, right_integer, right_scale, right_valid) = number_parts(right.lexeme)
    if !left_valid || !right_valid { ret false }
    let left_fraction = fraction_of(left.lexeme)
    let right_fraction = fraction_of(right.lexeme)
    let (left_lead, left_trail, left_power, left_zero) = normalised_digits(left_integer, left_fraction, left_scale)
    let (right_lead, right_trail, right_power, right_zero) = normalised_digits(right_integer, right_fraction, right_scale)
    // Zero is zero however it is spelled, sign included: `-0` and `0` are the same number even
    // though the module keeps them apart as lexemes.
    if left_zero || right_zero { ret left_zero && right_zero }
    if left_negative != right_negative { ret false }
    if left_power != right_power { ret false }
    if left_trail - left_lead != right_trail - right_lead { ret false }
    var at = 0usize
    while at < left_trail - left_lead {
        if digit_at(left_integer, left_fraction, left_lead + at) != digit_at(right_integer, right_fraction, right_lead + at) { ret false }
        at += 1usize
    }
    ret true
}

// The fractional digits of a lexeme, which `number_parts` folds into its scale rather than
// returning; both halves are needed to compare digit by digit.
fn fraction_of(lexeme: str) -> str {
    var at = 0usize
    if at < lexeme.len && lexeme[at] == 45u8 { at += 1usize }
    while at < lexeme.len && str.is_ascii_digit(lexeme[at]) { at += 1usize }
    if at >= lexeme.len || lexeme[at] != 46u8 { ret "" }
    at += 1usize
    let start = at
    while at < lexeme.len && str.is_ascii_digit(lexeme[at]) { at += 1usize }
    ret lexeme[start..at]
}

fn values_equal(left: *const Value, right: *const Value) -> bool {
    switch *left {
    case .Null:
        switch *right {
        case .Null:
            ret true
        default:
            ret false
        }
    case .Bool as flag:
        let (other, is_bool) = bool_of(*right)
        ret is_bool && other == flag
    case .Number as written:
        let (other, is_number) = number_of(*right)
        ret is_number && numbers_equal(written, other)
    case .String as text:
        let (other, is_string) = string_of(*right)
        ret is_string && str.eq(other, text)
    case .Array as items:
        let (other, is_array) = array_of(*right)
        if !is_array || other.len != items.len { ret false }
        var at = 0usize
        while at < items.len {
            if !values_equal(&items[at], &other[at]) { ret false }
            at += 1usize
        }
        ret true
    case .Object as members:
        let (other, is_object) = object_of(*right)
        if !is_object || other.len != members.len { ret false }
        // Order is not part of what an object means to `test`, so each member is looked up.
        var at = 0usize
        while at < members.len {
            let (found, present) = member_of(other, members[at].key)
            if !present { ret false }
            var held = found
            if !values_equal(&members[at].value, &held) { ret false }
            at += 1usize
        }
        ret true
    default:
        ret false
    }
}

fn array_of(value: Value) -> ([]const Value, bool) {
    var none: []const Value = zero
    switch value {
    case .Array as items:
        ret (items, true)
    default:
        ret (none, false)
    }
}

// A pointer split into its tokens, unescaped. The empty pointer is the root and has none.
fn path_tokens(path: str, into: []str) -> (usize, err) {
    if path.len == 0usize { ret (0usize, ok) }
    if path[0usize] != 47u8 { ret (0usize, InvalidPointer) }
    var count = 0usize
    var at = 1usize
    while true {
        var end = at
        while end < path.len && path[end] != 47u8 { end += 1usize }
        if count == into.len { ret (0usize, TooLarge) }
        into[count] = path[at..end]
        count += 1usize
        if end >= path.len { break }
        at = end + 1usize
    }
    ret (count, ok)
}

// A token names a member of this object, if any does. Tokens carry `~0`/`~1` escapes, so the
// comparison is `token_eq` rather than plain equality.
fn member_index(members: []const Member, token: str) -> (usize, bool) {
    var at = 0usize
    while at < members.len {
        if token_eq(token, members[at].key) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// The unescaped spelling of a token, which becomes a key when `add` creates one.
fn token_key(a: *mem.Arena, token: str) -> (str, err) {
    let (buffer, allocation_error) = mem.alloc[u8](a, token.len)
    if allocation_error != ok { ret ("", allocation_error) }
    var written = 0usize
    var at = 0usize
    while at < token.len {
        var byte = token[at]
        at += 1usize
        if byte == 126u8 {
            if at >= token.len { ret ("", InvalidPointer) }
            let escaped = token[at]
            at += 1usize
            if escaped == 48u8 {
                byte = 126u8
            } else {
                if escaped != 49u8 { ret ("", InvalidPointer) }
                byte = 47u8
            }
        }
        buffer[written] = byte
        written += 1usize
    }
    ret (buffer[0usize..written], ok)
}

// What an operation does where the path ends. `payload` is the value `add` and `replace` put
// there; `removed` comes back out so `move` can carry it to its destination.
fn edit_here(a: *mem.Arena, container: *const Value, token: str, action: u8, payload: *const Value) -> (Value, Value, err) {
    var out: Value = .Null
    var taken: Value = .Null
    let (members, is_object) = object_of(*container)
    if is_object {
        let (found, present) = member_index(members, token)
        if action == OP_REMOVE || action == OP_REPLACE {
            if !present { ret (out, taken, PatchFailed) }
        }
        if present { taken = members[found].value }
        if action == OP_REMOVE {
            let (entries, entries_error) = mem.alloc[Member](a, members.len - 1usize)
            if entries_error != ok { ret (out, taken, entries_error) }
            var at = 0usize
            var written = 0usize
            while at < members.len {
                if at != found {
                    entries[written] = members[at]
                    written += 1usize
                }
                at += 1usize
            }
            ret (Value{ Object: entries }, taken, ok)
        }
        if present {
            // `add` over an existing member replaces it, and order is kept: RFC 6902 says the
            // member's position is not what changed.
            let (entries, entries_error) = mem.alloc[Member](a, members.len)
            if entries_error != ok { ret (out, taken, entries_error) }
            mem.copy[Member](entries, members)
            entries[found].value = *payload
            ret (Value{ Object: entries }, taken, ok)
        }
        let (entries, entries_error) = mem.alloc[Member](a, members.len + 1usize)
        if entries_error != ok { ret (out, taken, entries_error) }
        mem.copy[Member](entries, members)
        let (key, key_error) = token_key(a, token)
        if key_error != ok { ret (out, taken, key_error) }
        entries[members.len].key = key
        entries[members.len].value = *payload
        ret (Value{ Object: entries }, taken, ok)
    }
    let (items, is_array) = array_of(*container)
    if !is_array { ret (out, taken, PatchFailed) }
    // `-` is the position after the last element: somewhere to add and nowhere to find.
    var index = items.len
    if !(token.len == 1usize && token[0usize] == 45u8) {
        let (parsed, valid) = array_index(token)
        if !valid { ret (out, taken, InvalidPointer) }
        index = parsed
    } else {
        if action != OP_ADD { ret (out, taken, InvalidPointer) }
    }
    if action == OP_REMOVE || action == OP_REPLACE {
        if index >= items.len { ret (out, taken, PatchFailed) }
        taken = items[index]
    }
    if action == OP_REMOVE {
        let (elements, elements_error) = mem.alloc[Value](a, items.len - 1usize)
        if elements_error != ok { ret (out, taken, elements_error) }
        var at = 0usize
        var written = 0usize
        while at < items.len {
            if at != index {
                elements[written] = items[at]
                written += 1usize
            }
            at += 1usize
        }
        ret (Value{ Array: elements }, taken, ok)
    }
    if action == OP_REPLACE {
        let (elements, elements_error) = mem.alloc[Value](a, items.len)
        if elements_error != ok { ret (out, taken, elements_error) }
        mem.copy[Value](elements, items)
        elements[index] = *payload
        ret (Value{ Array: elements }, taken, ok)
    }
    // `add` inserts, so an index one past the end is the append and anything beyond it is not a
    // position in this array at all.
    if index > items.len { ret (out, taken, PatchFailed) }
    let (elements, elements_error) = mem.alloc[Value](a, items.len + 1usize)
    if elements_error != ok { ret (out, taken, elements_error) }
    var at = 0usize
    while at < index {
        elements[at] = items[at]
        at += 1usize
    }
    elements[index] = *payload
    while at < items.len {
        elements[at + 1usize] = items[at]
        at += 1usize
    }
    ret (Value{ Array: elements }, taken, ok)
}

// The spine down to the edit, rebuilt. Everything off the path is shared, which is sound because
// nothing in this tree is ever written through again.
fn edit_at(a: *mem.Arena, node: *const Value, tokens: []const str, at: usize, action: u8, payload: *const Value) -> (Value, Value, err) {
    if at + 1usize == tokens.len {
        let (edited, taken, edit_error) = edit_here(a, node, tokens[at], action, payload)
        ret (edited, taken, edit_error)
    }
    var out: Value = .Null
    var taken: Value = .Null
    let (members, is_object) = object_of(*node)
    if is_object {
        let (found, present) = member_index(members, tokens[at])
        if !present { ret (out, taken, PatchFailed) }
        let (entries, entries_error) = mem.alloc[Member](a, members.len)
        if entries_error != ok { ret (out, taken, entries_error) }
        mem.copy[Member](entries, members)
        let (child, child_taken, child_error) = edit_at(a, &members[found].value, tokens, at + 1usize, action, payload)
        if child_error != ok { ret (out, taken, child_error) }
        entries[found].value = child
        ret (Value{ Object: entries }, child_taken, ok)
    }
    let (items, is_array) = array_of(*node)
    if !is_array { ret (out, taken, PatchFailed) }
    let (index, valid) = array_index(tokens[at])
    if !valid { ret (out, taken, InvalidPointer) }
    if index >= items.len { ret (out, taken, PatchFailed) }
    let (elements, elements_error) = mem.alloc[Value](a, items.len)
    if elements_error != ok { ret (out, taken, elements_error) }
    mem.copy[Value](elements, items)
    let (child, child_taken, child_error) = edit_at(a, &items[index], tokens, at + 1usize, action, payload)
    if child_error != ok { ret (out, taken, child_error) }
    elements[index] = child
    ret (Value{ Array: elements }, child_taken, ok)
}

fn operation_code(name: str) -> (u8, bool) {
    if str.eq(name, "add") { ret (OP_ADD, true) }
    if str.eq(name, "remove") { ret (OP_REMOVE, true) }
    if str.eq(name, "replace") { ret (OP_REPLACE, true) }
    if str.eq(name, "move") { ret (OP_MOVE, true) }
    if str.eq(name, "copy") { ret (OP_COPY, true) }
    if str.eq(name, "test") { ret (OP_TEST, true) }
    ret (0u8, false)
}

// A `from` that is a prefix of `path` at a token boundary would move a subtree inside itself.
fn is_prefix_of(from_tokens: []const str, from_count: usize, path_tokens_list: []const str, path_count: usize) -> bool {
    if from_count > path_count { ret false }
    var at = 0usize
    while at < from_count {
        if !str.eq(from_tokens[at], path_tokens_list[at]) { ret false }
        at += 1usize
    }
    ret true
}

// Duplicate keys anywhere in the patch input make the operation it describes ambiguous, so the
// whole input is refused rather than the object that carries them.
fn free_of_duplicates(value: *const Value) -> bool {
    switch *value {
    case .Array as items:
        var at = 0usize
        while at < items.len {
            if !free_of_duplicates(&items[at]) { ret false }
            at += 1usize
        }
        ret true
    case .Object as members:
        var at = 0usize
        while at < members.len {
            var against = at + 1usize
            while against < members.len {
                if str.eq(members[at].key, members[against].key) { ret false }
                against += 1usize
            }
            if !free_of_duplicates(&members[at].value) { ret false }
            at += 1usize
        }
        ret true
    default:
        ret true
    }
}

fn patch(a: *mem.Arena, root: *const Value, operations: *const Value, max_operations: usize, max_depth: u16) -> (Value, err) {
    var out: Value = .Null
    let start = mem.mark(a)
    var limit = max_depth
    if limit == 0u16 { limit = DEFAULT_MAX_DEPTH }
    var allowed = max_operations
    if allowed == 0usize { allowed = DEFAULT_MAX_OPERATIONS }
    let (list, is_array) = array_of(*operations)
    if !is_array {
        mem.reset(a, start)
        ret (out, Invalid)
    }
    if list.len > allowed {
        mem.reset(a, start)
        ret (out, TooLarge)
    }
    if !free_of_duplicates(operations) {
        mem.reset(a, start)
        ret (out, DuplicateKey)
    }
    // The one copy that makes the result this arena's. Every rebuild after it shares within what
    // this produced, so nothing of `root` is ever reachable from the answer.
    let (working, copy_error) = copy_value(a, root, 0u16, limit)
    if copy_error != ok {
        mem.reset(a, start)
        ret (out, copy_error)
    }
    var current = working
    var path_store: [MAX_PATH_TOKENS]str = zero
    var from_store: [MAX_PATH_TOKENS]str = zero
    var index = 0usize
    while index < list.len {
        let (fields, is_object) = object_of(list[index])
        if !is_object {
            mem.reset(a, start)
            ret (out, Invalid)
        }
        let (op_value, has_op) = member_of(fields, "op")
        if !has_op {
            mem.reset(a, start)
            ret (out, Invalid)
        }
        let (op_name, op_is_string) = string_of(op_value)
        if !op_is_string {
            mem.reset(a, start)
            ret (out, Invalid)
        }
        let (action, known) = operation_code(op_name)
        if !known {
            mem.reset(a, start)
            ret (out, Invalid)
        }
        let (path_value, has_path) = member_of(fields, "path")
        if !has_path {
            mem.reset(a, start)
            ret (out, Invalid)
        }
        let (path, path_is_string) = string_of(path_value)
        if !path_is_string {
            mem.reset(a, start)
            ret (out, Invalid)
        }
        let (path_count, path_error) = path_tokens(path, path_store[..])
        if path_error != ok {
            mem.reset(a, start)
            ret (out, path_error)
        }
        if usize(limit) < path_count {
            mem.reset(a, start)
            ret (out, TooDeep)
        }
        var payload: Value = .Null
        var from_count = 0usize
        if action == OP_MOVE || action == OP_COPY {
            let (from_value, has_from) = member_of(fields, "from")
            if !has_from {
                mem.reset(a, start)
                ret (out, Invalid)
            }
            let (from_path, from_is_string) = string_of(from_value)
            if !from_is_string {
                mem.reset(a, start)
                ret (out, Invalid)
            }
            let (counted, from_error) = path_tokens(from_path, from_store[..])
            if from_error != ok {
                mem.reset(a, start)
                ret (out, from_error)
            }
            from_count = counted
            // Moving a subtree into itself would build a tree that contains itself.
            if action == OP_MOVE && is_prefix_of(from_store[..], from_count, path_store[..], path_count) {
                mem.reset(a, start)
                ret (out, PatchFailed)
            }
            let (source, source_error) = pointer(&current, from_path)
            if source_error != ok {
                mem.reset(a, start)
                ret (out, source_error)
            }
            let (lifted, lifted_error) = copy_value(a, source, 0u16, limit)
            if lifted_error != ok {
                mem.reset(a, start)
                ret (out, lifted_error)
            }
            payload = lifted
            if action == OP_MOVE {
                if from_count == 0usize {
                    mem.reset(a, start)
                    ret (out, PatchFailed)
                }
                let (without, taken, remove_error) = edit_at(a, &current, from_store[0usize..from_count], 0usize, OP_REMOVE, &payload)
                if remove_error != ok {
                    mem.reset(a, start)
                    ret (out, remove_error)
                }
                current = without
            }
        }
        if action == OP_ADD || action == OP_REPLACE || action == OP_TEST {
            let (given, has_value) = member_of(fields, "value")
            if !has_value {
                mem.reset(a, start)
                ret (out, Invalid)
            }
            let (copied, copied_error) = copy_value(a, &given, 0u16, limit)
            if copied_error != ok {
                mem.reset(a, start)
                ret (out, copied_error)
            }
            payload = copied
        }
        if action == OP_TEST {
            let (found, found_error) = pointer(&current, path)
            if found_error != ok {
                mem.reset(a, start)
                ret (out, found_error)
            }
            if !values_equal(found, &payload) {
                mem.reset(a, start)
                ret (out, PatchFailed)
            }
            index += 1usize
            continue
        }
        // The root is not inside any container, so there is nothing to rebuild: it is replaced
        // outright, and removing it is not something a tree can express.
        if path_count == 0usize {
            if action == OP_REMOVE {
                mem.reset(a, start)
                ret (out, PatchFailed)
            }
            current = payload
            index += 1usize
            continue
        }
        var effect = action
        if action == OP_MOVE || action == OP_COPY { effect = OP_ADD }
        let (edited, taken, edit_error) = edit_at(a, &current, path_store[0usize..path_count], 0usize, effect, &payload)
        if edit_error != ok {
            mem.reset(a, start)
            ret (out, edit_error)
        }
        current = edited
        index += 1usize
    }
    ret (current, ok)
}

// --- The streaming reader.
//
// The same grammar as `parse`, over a source that arrives a piece at a time and a document that
// is never held whole. What it costs is that a caller sees the shape rather than the value: an
// object is `BeginObject`, then a `Key` and whatever that key's value turns out to be, then
// `EndObject`. What it buys is that the document may be larger than memory.
//
// Every string and every number lexeme borrows one buffer the reader owns, so an event is good
// until the next call and no further -- which is the fence's rule and the reason nothing here
// allocates per event.

const OPEN_ARRAY: u8 = 0u8
const OPEN_OBJECT: u8 = 1u8

const READ_CAPACITY: usize = 4096usize
// The longest string or number a single event may carry. A document past it is `TooLarge`
// rather than a truncated value.
const EVENT_TEXT: usize = 65536usize
// ponytail: duplicate detection keeps the keys of every open object, so it is a linear scan per
// key and capped rather than unbounded. `e.data.map` is the upgrade once that module exists.
const OPEN_KEYS: usize = 4096usize

type ReaderState = struct { source: io.Reader, options: Options, arena: *mem.Arena, input: []u8, input_at: usize, input_len: usize, text: []u8, stack_kind: []u8, stack_count: []usize, stack_keys: []usize, depth: usize, keys: []str, key_count: usize, pending_value: bool, started: bool, finished: bool, spent: bool }

// One byte, or `false` at the end of the source.
fn stream_take(s: *ReaderState) -> (u8, bool, err) {
    if s.input_at == s.input_len {
        if s.spent { ret (0u8, false, ok) }
        let (count, read_error) = io.read(&s.source, s.input)
        if read_error == io.End {
            s.spent = true
            ret (0u8, false, ok)
        }
        if read_error != ok { ret (0u8, false, read_error) }
        s.input_len = count
        s.input_at = 0usize
    }
    let byte = s.input[s.input_at]
    s.input_at += 1usize
    ret (byte, true, ok)
}

// The byte a decision is made on, left where it was. Every caller either consumes it next or
// hands it to whoever does.
fn stream_peek(s: *ReaderState) -> (u8, bool, err) {
    let (byte, more, take_error) = stream_take(s)
    if take_error != ok { ret (0u8, false, take_error) }
    if !more { ret (0u8, false, ok) }
    s.input_at -= 1usize
    ret (byte, true, ok)
}

fn stream_skip_space(s: *ReaderState) -> err {
    while true {
        let (byte, more, take_error) = stream_take(s)
        if take_error != ok { ret take_error }
        if !more { ret ok }
        if !is_space(byte) {
            s.input_at -= 1usize
            ret ok
        }
    }
    ret ok
}

fn stream_expect(s: *ReaderState, wanted: u8) -> err {
    let (byte, more, take_error) = stream_take(s)
    if take_error != ok { ret take_error }
    if !more || byte != wanted { ret Invalid }
    ret ok
}

fn keep_byte(s: *ReaderState, at: usize, byte: u8) -> (usize, err) {
    if at == s.text.len { ret (at, TooLarge) }
    s.text[at] = byte
    ret (at + 1usize, ok)
}

// A `\u` escape's four digits, taken from the stream rather than from a slice.
fn stream_hex4(s: *ReaderState) -> (u32, bool, err) {
    var value = 0u32
    var index = 0usize
    while index < 4usize {
        let (byte, more, take_error) = stream_take(s)
        if take_error != ok { ret (0u32, false, take_error) }
        if !more { ret (0u32, false, ok) }
        let (digit, valid) = hex_value(byte)
        if !valid { ret (0u32, false, ok) }
        value = value * 16u32 + digit
        index += 1usize
    }
    ret (value, true, ok)
}

// A string into the reader's buffer, the opening quote already behind. Unlike `parse_string`
// there is no borrowing to be done: the bytes are gone from the stream once read, so every
// string is decoded, escaped or not.
fn stream_string(s: *ReaderState) -> (str, err) {
    var at = 0usize
    while true {
        let (byte, more, take_error) = stream_take(s)
        if take_error != ok { ret ("", take_error) }
        if !more { ret ("", Invalid) }
        if byte == 34u8 { break }
        if byte < 32u8 { ret ("", Invalid) }
        if byte != 92u8 {
            let (kept, keep_error) = keep_byte(s, at, byte)
            if keep_error != ok { ret ("", keep_error) }
            at = kept
            continue
        }
        let (escape, escaped, escape_error) = stream_take(s)
        if escape_error != ok { ret ("", escape_error) }
        if !escaped { ret ("", Invalid) }
        var decoded = 0u8
        var simple = true
        if escape == 34u8 { decoded = 34u8 } else {
        if escape == 92u8 { decoded = 92u8 } else {
        if escape == 47u8 { decoded = 47u8 } else {
        if escape == 98u8 { decoded = 8u8 } else {
        if escape == 102u8 { decoded = 12u8 } else {
        if escape == 110u8 { decoded = 10u8 } else {
        if escape == 114u8 { decoded = 13u8 } else {
        if escape == 116u8 { decoded = 9u8 } else {
        if escape == 117u8 { simple = false } else { ret ("", Invalid) }
        }
        }
        }
        }
        }
        }
        }
        }
        if simple {
            let (kept, keep_error) = keep_byte(s, at, decoded)
            if keep_error != ok { ret ("", keep_error) }
            at = kept
            continue
        }
        let (first, first_valid, first_error) = stream_hex4(s)
        if first_error != ok { ret ("", first_error) }
        if !first_valid { ret ("", Invalid) }
        var point = first
        // A leading surrogate is only half a character, and the half that follows it is written
        // as a second escape -- so the pair is read here rather than left to whoever gets the
        // bytes.
        if first >= 55296u32 && first <= 56319u32 {
            let backslash_error = stream_expect(s, 92u8)
            if backslash_error != ok { ret ("", Invalid) }
            let marker_error = stream_expect(s, 117u8)
            if marker_error != ok { ret ("", Invalid) }
            let (second, second_valid, second_error) = stream_hex4(s)
            if second_error != ok { ret ("", second_error) }
            if !second_valid { ret ("", Invalid) }
            if second < 56320u32 || second > 57343u32 { ret ("", Invalid) }
            point = 65536u32 + ((first - 55296u32) << 10u8) + (second - 56320u32)
        } else {
            // A trailing surrogate with nothing before it is not a character.
            if first >= 56320u32 && first <= 57343u32 { ret ("", Invalid) }
        }
        if at + 4usize > s.text.len { ret ("", TooLarge) }
        at = encode_utf8(s.text, at, point)
    }
    ret (s.text[0usize..at], ok)
}

// A number into the reader's buffer, then through the same validator a parsed one goes through,
// so the two agree about what a number is.
fn stream_number(s: *ReaderState) -> (Number, err) {
    var empty: Number = zero
    var at = 0usize
    while true {
        let (byte, more, take_error) = stream_take(s)
        if take_error != ok { ret (empty, take_error) }
        if !more { break }
        if str.is_ascii_digit(byte) || byte == 45u8 || byte == 43u8 || byte == 46u8 || byte == 101u8 || byte == 69u8 {
            let (kept, keep_error) = keep_byte(s, at, byte)
            if keep_error != ok { ret (empty, keep_error) }
            at = kept
            continue
        }
        s.input_at -= 1usize
        break
    }
    let (checked, checked_error) = number(s.text[0usize..at])
    ret (checked, checked_error)
}

// The word a literal is, its first byte still unread: the caller decided on that byte by
// peeking at it, so consuming it is this function's to do.
fn stream_literal(s: *ReaderState, word: str) -> err {
    s.input_at += 1usize
    var at = 1usize
    while at < word.len {
        let error_code = stream_expect(s, word[at])
        if error_code != ok { ret error_code }
        at += 1usize
    }
    ret ok
}

fn stream_push(s: *ReaderState, kind: u8) -> err {
    if s.depth == s.stack_kind.len { ret TooDeep }
    if usize(s.options.max_depth) != 0usize && s.depth == usize(s.options.max_depth) { ret TooDeep }
    s.stack_kind[s.depth] = kind
    s.stack_count[s.depth] = 0usize
    s.stack_keys[s.depth] = s.key_count
    s.depth += 1usize
    ret ok
}

// A key is remembered only while its object is open; closing one takes the whole run off.
fn stream_remember(s: *ReaderState, key: str) -> err {
    if s.options.allow_duplicate_keys { ret ok }
    let level = s.depth - 1usize
    var at = s.stack_keys[level]
    while at < s.key_count {
        if str.eq(s.keys[at], key) { ret DuplicateKey }
        at += 1usize
    }
    if s.key_count == s.keys.len { ret TooLarge }
    // The text buffer is the next event's, so what is remembered has to be a copy.
    let (kept, copy_error) = mem.alloc[u8](s.arena, key.len)
    if copy_error != ok { ret copy_error }
    mem.copy[u8](kept, key)
    s.keys[s.key_count] = kept
    s.key_count += 1usize
    ret ok
}

// The value a token begins. Containers push and announce themselves; scalars are the event.
fn stream_value(s: *ReaderState) -> (Event, bool, err) {
    var event: Event = .Null
    let (byte, more, peek_error) = stream_peek(s)
    if peek_error != ok { ret (event, false, peek_error) }
    if !more { ret (event, false, Invalid) }
    if byte == 123u8 {
        s.input_at += 1usize
        let push_error = stream_push(s, OPEN_OBJECT)
        if push_error != ok { ret (event, false, push_error) }
        var opened: Event = .BeginObject
        ret (opened, true, ok)
    }
    if byte == 91u8 {
        s.input_at += 1usize
        let push_error = stream_push(s, OPEN_ARRAY)
        if push_error != ok { ret (event, false, push_error) }
        var opened: Event = .BeginArray
        ret (opened, true, ok)
    }
    if byte == 34u8 {
        s.input_at += 1usize
        let (text, text_error) = stream_string(s)
        if text_error != ok { ret (event, false, text_error) }
        ret (Event{ String: text }, true, ok)
    }
    if byte == 116u8 {
        let literal_error = stream_literal(s, "true")
        if literal_error != ok { ret (event, false, Invalid) }
        ret (Event{ Bool: true }, true, ok)
    }
    if byte == 102u8 {
        let literal_error = stream_literal(s, "false")
        if literal_error != ok { ret (event, false, Invalid) }
        ret (Event{ Bool: false }, true, ok)
    }
    if byte == 110u8 {
        let literal_error = stream_literal(s, "null")
        if literal_error != ok { ret (event, false, Invalid) }
        ret (event, true, ok)
    }
    if byte == 45u8 || str.is_ascii_digit(byte) {
        let (parsed, parsed_error) = stream_number(s)
        if parsed_error != ok { ret (event, false, parsed_error) }
        ret (Event{ Number: parsed }, true, ok)
    }
    ret (event, false, Invalid)
}

fn reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Reader, err) {
    var handle: Reader = zero
    let (state, state_error) = mem.alloc[ReaderState](a, 1usize)
    if state_error != ok { ret (handle, state_error) }
    let (input, input_error) = mem.alloc[u8](a, READ_CAPACITY)
    if input_error != ok { ret (handle, input_error) }
    let (text, text_error) = mem.alloc[u8](a, EVENT_TEXT)
    if text_error != ok { ret (handle, text_error) }
    var levels = usize(options.max_depth)
    if levels == 0usize { levels = usize(DEFAULT_MAX_DEPTH) }
    let (kinds, kinds_error) = mem.alloc[u8](a, levels)
    if kinds_error != ok { ret (handle, kinds_error) }
    let (counts, counts_error) = mem.alloc[usize](a, levels)
    if counts_error != ok { ret (handle, counts_error) }
    let (key_marks, key_marks_error) = mem.alloc[usize](a, levels)
    if key_marks_error != ok { ret (handle, key_marks_error) }
    state[0usize].source = source
    state[0usize].options = options
    state[0usize].arena = a
    state[0usize].input = input
    state[0usize].input_at = 0usize
    state[0usize].input_len = 0usize
    state[0usize].text = text
    state[0usize].stack_kind = kinds
    state[0usize].stack_count = counts
    state[0usize].stack_keys = key_marks
    state[0usize].depth = 0usize
    state[0usize].key_count = 0usize
    state[0usize].pending_value = false
    state[0usize].started = false
    state[0usize].finished = false
    state[0usize].spent = false
    if !options.allow_duplicate_keys {
        let (keys, keys_error) = mem.alloc[str](a, OPEN_KEYS)
        if keys_error != ok { ret (handle, keys_error) }
        state[0usize].keys = keys
    }
    handle.state = mem.cast[*void](&state[0usize])
    ret (handle, ok)
}

// One event per call, `false` when the document is complete. Everything an event carries borrows
// the reader's own buffer and is good until the next call.
fn reader_next_err(r: *Reader) -> (Event, bool, err) {
    let s = mem.cast[*ReaderState](r.state)
    var event: Event = .Null
    if s.finished { ret (event, false, ok) }
    let space_error = stream_skip_space(s)
    if space_error != ok { ret (event, false, space_error) }
    if s.depth == 0usize {
        if s.started {
            // A document is one value. Whatever follows it is not part of it, and silence about
            // that would let two documents in a row look like one.
            let (trailing, has_trailing, trailing_error) = stream_peek(s)
            if trailing_error != ok { ret (event, false, trailing_error) }
            if has_trailing { ret (event, false, Invalid) }
            s.finished = true
            ret (event, false, ok)
        }
        s.started = true
        let (first, first_more, first_error) = stream_value(s)
        ret (first, first_more, first_error)
    }
    let level = s.depth - 1usize
    if s.stack_kind[level] == OPEN_OBJECT {
        if s.pending_value {
            s.pending_value = false
            let (member, member_more, member_error) = stream_value(s)
            ret (member, member_more, member_error)
        }
        let (byte, more, peek_error) = stream_peek(s)
        if peek_error != ok { ret (event, false, peek_error) }
        if !more { ret (event, false, Invalid) }
        if byte == 125u8 {
            s.input_at += 1usize
            s.key_count = s.stack_keys[level]
            s.depth -= 1usize
            var closed: Event = .EndObject
            ret (closed, true, ok)
        }
        if s.stack_count[level] != 0usize {
            let comma_error = stream_expect(s, 44u8)
            if comma_error != ok { ret (event, false, Invalid) }
            let after_error = stream_skip_space(s)
            if after_error != ok { ret (event, false, after_error) }
        }
        let quote_error = stream_expect(s, 34u8)
        if quote_error != ok { ret (event, false, Invalid) }
        let (key, key_error) = stream_string(s)
        if key_error != ok { ret (event, false, key_error) }
        let duplicate_error = stream_remember(s, key)
        if duplicate_error != ok { ret (event, false, duplicate_error) }
        let before_error = stream_skip_space(s)
        if before_error != ok { ret (event, false, before_error) }
        let colon_error = stream_expect(s, 58u8)
        if colon_error != ok { ret (event, false, Invalid) }
        let value_error = stream_skip_space(s)
        if value_error != ok { ret (event, false, value_error) }
        s.stack_count[level] += 1usize
        s.pending_value = true
        ret (Event{ Key: key }, true, ok)
    }
    let (byte, more, peek_error) = stream_peek(s)
    if peek_error != ok { ret (event, false, peek_error) }
    if !more { ret (event, false, Invalid) }
    if byte == 93u8 {
        s.input_at += 1usize
        s.key_count = s.stack_keys[level]
        s.depth -= 1usize
        var closed: Event = .EndArray
        ret (closed, true, ok)
    }
    if s.stack_count[level] != 0usize {
        let comma_error = stream_expect(s, 44u8)
        if comma_error != ok { ret (event, false, Invalid) }
        let after_error = stream_skip_space(s)
        if after_error != ok { ret (event, false, after_error) }
    }
    s.stack_count[level] += 1usize
    let (element, element_more, element_error) = stream_value(s)
    ret (element, element_more, element_error)
}

// --- The typed codec.
//
// A struct is an object: one member per field, named as the field is named, in declaration
// order. Nesting is a struct inside a struct, which is the recursion this cannot do, so a field
// that is not a number, a bool or a `str` is `Invalid` rather than quietly skipped.
//
// The walk over `meta.fields` is unrolled, so each copy sees one concrete field type and the arm
// chosen by `meta.kind[f.ty]()` is the only one that has to check (D138). It is what lets one
// walk hold an arm that reads an integer beside one that reads a string.

const MINUS_BYTE: u8 = 45u8

// Enough for any integer or float `e.str` will render, with room for the builder's own claim.
const NUMBER_TEXT: usize = 128usize

// A `Value` is asked what it is one shape at a time, so the codec below stays flat. A `switch`
// per field would nest a match inside an unrolled loop inside a match.
fn string_of(value: Value) -> (str, bool) {
    switch value {
    case .String as text:
        ret (text, true)
    default:
        ret ("", false)
    }
}

fn bool_of(value: Value) -> (bool, bool) {
    switch value {
    case .Bool as flag:
        ret (flag, true)
    default:
        ret (false, false)
    }
}

fn number_of(value: Value) -> (Number, bool) {
    var empty: Number = zero
    switch value {
    case .Number as written:
        ret (written, true)
    default:
        ret (empty, false)
    }
}

fn object_of(value: Value) -> ([]const Member, bool) {
    var none: []const Member = zero
    switch value {
    case .Object as members:
        ret (members, true)
    default:
        ret (none, false)
    }
}

fn member_of(members: []const Member, name: str) -> (Value, bool) {
    var empty: Value = .Null
    var at = 0usize
    while at < members.len {
        if str.eq(members[at].key, name) { ret (members[at].value, true) }
        at += 1usize
    }
    ret (empty, false)
}

fn decode[T: type](a: *mem.Arena, source: str, options: Options) -> (T, err) {
    var out: T = zero
    let (root, parse_error) = parse(a, source, options)
    if parse_error != ok { ret (out, parse_error) }
    // Only an object can be a struct: an array is positional and a scalar is not a record, and
    // which field either meant is not something a decoder should guess.
    let (members, is_object) = object_of(root)
    if !is_object { ret (out, Invalid) }
    for f in meta.fields[T]() {
        let (found, present) = member_of(members, f.name)
        // A member the document does not carry leaves its field as it was, so adding a field to
        // a program does not break the documents already written for it.
        if present {
            if meta.kind[f.ty]() == .Slice {
                // The text is already the parser's own copy in this arena, so it outlives the
                // decode without being copied again.
                let (text, is_string) = string_of(found)
                if !is_string { ret (out, Invalid) }
                meta.set[f, T](&out, text)
            } else {
            if meta.kind[f.ty]() == .Bool {
                let (flag, is_bool) = bool_of(found)
                if !is_bool { ret (out, Invalid) }
                meta.set[f, T](&out, flag)
            } else {
            if meta.kind[f.ty]() == .Int {
                let (written, is_number) = number_of(found)
                if !is_number { ret (out, Invalid) }
                var slot: f.ty = zero
                // Read through whichever of the two the lexeme fits, so a `u64` past the signed
                // maximum and a negative are both exact -- the fence's rule that a typed integer
                // never takes a floating-point detour.
                if written.lexeme.len != 0usize && written.lexeme[0usize] == MINUS_BYTE {
                    let (signed, signed_error) = number_i64(written)
                    if signed_error != ok { ret (out, signed_error) }
                    slot = f.ty(signed)
                } else {
                    let (unsigned, unsigned_error) = number_u64(written)
                    if unsigned_error != ok { ret (out, unsigned_error) }
                    slot = f.ty(unsigned)
                }
                meta.set[f, T](&out, slot)
            } else {
            if meta.kind[f.ty]() == .Float {
                let (written, is_number) = number_of(found)
                if !is_number { ret (out, Invalid) }
                let (number_value, number_error) = number_f64(written)
                if number_error != ok { ret (out, number_error) }
                var slot: f.ty = zero
                slot = f.ty(number_value)
                meta.set[f, T](&out, slot)
            } else {
                ret (out, Invalid)
            }
            }
            }
            }
        }
    }
    ret (out, ok)
}

fn encode[T: type](writer: *io.Writer, value: *const T) -> err {
    try io.write_all(writer, "{")
    var written = 0usize
    for f in meta.fields[T]() {
        if written != 0usize { try io.write_all(writer, ",") }
        try write_string(writer, f.name)
        try io.write_all(writer, ":")
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        // A buffer per field and an arena over it, so `e.str` does the rendering and this module
        // carries no number formatting of its own. `encode` is given no arena and needs none:
        // nothing it builds outlives the field it was built for.
        var scratch: [NUMBER_TEXT]u8 = zero
        var holder = mem.arena_from(scratch[..])
        if meta.kind[f.ty]() == .Slice {
            try write_string(writer, slot)
        } else {
        if meta.kind[f.ty]() == .Bool {
            if slot {
                try io.write_all(writer, "true")
            } else {
                try io.write_all(writer, "false")
            }
        } else {
        if meta.kind[f.ty]() == .Int {
            let (rendered, builder_error) = str.builder(&holder, NUMBER_TEXT / 2usize)
            if builder_error != ok { ret builder_error }
            var built = rendered
            // Signedness is not a question reflection answers and the value is, so it is asked
            // of the value: only a signed type holds anything below zero.
            if slot < 0 {
                try str.push_i64(&built, i64(slot))
            } else {
                try str.push_u64(&built, u64(slot))
            }
            try io.write_all(writer, str.done(&built))
        } else {
        if meta.kind[f.ty]() == .Float {
            let (rendered, builder_error) = str.builder(&holder, NUMBER_TEXT / 2usize)
            if builder_error != ok { ret builder_error }
            var built = rendered
            try str.push_f64(&built, f64(slot))
            let text = str.done(&built)
            // JSON has no spelling for a non-finite number, and writing one produces a document
            // no reader can take back. `e.str` renders those as words, so a leading letter is
            // what one looks like here.
            if text.len == 0usize { ret Invalid }
            if !str.is_ascii_digit(text[0usize]) && text[0usize] != MINUS_BYTE { ret Invalid }
            try io.write_all(writer, text)
        } else {
            ret Invalid
        }
        }
        }
        }
        written += 1usize
    }
    ret io.write_all(writer, "}")
}

// --- RFC 8785 canonical form.
//
// One byte sequence per value: no whitespace, `write_string`'s escapes (which are the JCS
// ones: the short forms, then lower-case `\u00xx`), object members in the order of their
// keys as UTF-16 code units, and every number as ES6 `Number.prototype.toString` writes the
// double it names -- which is what `str.push_f64`'s shortest digits are, laid out by the
// ES6 rule rather than `e.str`'s.

// The next UTF-16 code unit of `text` from byte `at`: (unit, next byte, low surrogate to
// follow). A supplementary character yields its high surrogate and leaves the low one pending.
fn utf16_unit(text: str, at: usize) -> (u32, usize, u32) {
    let b0 = u32(text[at])
    if b0 < 128u32 { ret (b0, at + 1usize, 0u32) }
    var need = 1usize
    var scalar = b0 & 31u32
    if b0 >= 240u32 {
        need = 3usize
        scalar = b0 & 7u32
    } else {
        if b0 >= 224u32 {
            need = 2usize
            scalar = b0 & 15u32
        }
    }
    var k = 1usize
    while k <= need && at + k < text.len {
        scalar = (scalar << 6u32) | (u32(text[at + k]) & 63u32)
        k += 1usize
    }
    if scalar < 65536u32 { ret (scalar, at + k, 0u32) }
    let offset = scalar - 65536u32
    ret (55296u32 + (offset >> 10u32), at + k, 56320u32 + (offset & 1023u32))
}

// Whether `x` sorts before `y` by UTF-16 code units.
fn utf16_less(x: str, y: str) -> bool {
    var x_at = 0usize
    var y_at = 0usize
    var x_pending = 0u32
    var y_pending = 0u32
    while true {
        var x_unit = 0u32
        var y_unit = 0u32
        var x_done = false
        var y_done = false
        if x_pending != 0u32 {
            x_unit = x_pending
            x_pending = 0u32
        } else {
            if x_at >= x.len { x_done = true } else {
                let (unit, next_at, pending) = utf16_unit(x, x_at)
                x_unit = unit
                x_at = next_at
                x_pending = pending
            }
        }
        if y_pending != 0u32 {
            y_unit = y_pending
            y_pending = 0u32
        } else {
            if y_at >= y.len { y_done = true } else {
                let (unit, next_at, pending) = utf16_unit(y, y_at)
                y_unit = unit
                y_at = next_at
                y_pending = pending
            }
        }
        if x_done { ret !y_done }
        if y_done { ret false }
        if x_unit != y_unit { ret x_unit < y_unit }
    }
    ret false
}

fn put_digits(w: *io.Writer, value: i64) -> err {
    var scratch: [24]u8 = zero
    var holder = mem.arena_from(scratch[..])
    let (b, builder_failure) = str.builder(&holder, 22usize)
    if builder_failure != ok { ret builder_failure }
    var built = b
    try str.push_i64(&built, value)
    ret io.write_all(w, str.done(&built))
}

// The ES6 spelling of the double `value` names. Anything JSON can write is finite.
fn write_es6_number(w: *io.Writer, value: f64) -> err {
    if !finite(value) { ret Invalid }
    if value == 0.0f64 { ret io.write_all(w, "0") }
    var scratch: [64]u8 = zero
    var holder = mem.arena_from(scratch[..])
    let (b, builder_failure) = str.builder(&holder, 40usize)
    if builder_failure != ok { ret builder_failure }
    var built = b
    try str.push_f64(&built, value)
    let spelled = str.done(&built)
    // The shortest digits `s` (k of them) and the point position `n`: value = s * 10^(n-k).
    var digits: [24]u8 = zero
    var k = 0usize
    var n = 0i64
    var seen_point = false
    var at = 0usize
    if spelled[0usize] == 45u8 {
        try io.write_all(w, "-")
        at = 1usize
    }
    while at < spelled.len && spelled[at] != 101u8 {
        let c = spelled[at]
        if c == 46u8 {
            seen_point = true
        } else {
            if k == 0usize && c == 48u8 {
                if seen_point { n -= 1i64 }
            } else {
                digits[k] = c
                k += 1usize
                if !seen_point { n += 1i64 }
            }
        }
        at += 1usize
    }
    if at < spelled.len {
        let (power, power_failure) = str.parse_i64(spelled[at + 1usize..])
        if power_failure != ok { ret Invalid }
        n += power
    }
    while k > 0usize && digits[k - 1usize] == 48u8 { k -= 1usize }
    let count = i64(k)
    if count <= n && n <= 21i64 {
        try io.write_all(w, digits[..k])
        var zeros = n - count
        while zeros > 0i64 {
            try io.write_all(w, "0")
            zeros -= 1i64
        }
        ret ok
    }
    if 0i64 < n && n <= 21i64 {
        try io.write_all(w, digits[..usize(n)])
        try io.write_all(w, ".")
        ret io.write_all(w, digits[usize(n)..k])
    }
    if -6i64 < n && n <= 0i64 {
        try io.write_all(w, "0.")
        var zeros = 0i64 - n
        while zeros > 0i64 {
            try io.write_all(w, "0")
            zeros -= 1i64
        }
        ret io.write_all(w, digits[..k])
    }
    try io.write_all(w, digits[..1usize])
    if k > 1usize {
        try io.write_all(w, ".")
        try io.write_all(w, digits[1usize..k])
    }
    try io.write_all(w, "e")
    if n - 1i64 >= 0i64 { try io.write_all(w, "+") }
    ret put_digits(w, n - 1i64)
}

// ponytail: members go out by repeated selection of the next key, O(n^2) comparisons and no
// storage; an object with thousands of members would want an index sorted once.
fn canonicalize(w: *io.Writer, value: *const Value) -> err {
    switch *value {
    case .Null:
        ret io.write_all(w, "null")
    case .Bool as flag:
        if flag { ret io.write_all(w, "true") }
        ret io.write_all(w, "false")
    case .Number as literal_number:
        let (parsed, failure) = number_f64(literal_number)
        if failure != ok { ret failure }
        ret write_es6_number(w, parsed)
    case .String as text:
        ret write_string(w, text)
    case .Array as items:
        try io.write_all(w, "[")
        var at = 0usize
        while at < items.len {
            if at > 0usize { try io.write_all(w, ",") }
            try canonicalize(w, &items[at])
            at += 1usize
        }
        ret io.write_all(w, "]")
    case .Object as members:
        try io.write_all(w, "{")
        var written = 0usize
        var last = 0usize
        while written < members.len {
            // The least (key, index) above the one written last.
            var pick = members.len
            var at = 0usize
            while at < members.len {
                var above = written == 0usize
                if !above {
                    above = utf16_less(members[last].key, members[at].key) || (at > last && str.eq(members[last].key, members[at].key))
                }
                if above {
                    if pick == members.len || utf16_less(members[at].key, members[pick].key) { pick = at }
                }
                at += 1usize
            }
            if pick == members.len { ret Invalid }
            if written > 0usize { try io.write_all(w, ",") }
            try write_string(w, members[pick].key)
            try io.write_all(w, ":")
            try canonicalize(w, &members[pick].value)
            last = pick
            written += 1usize
        }
        ret io.write_all(w, "}")
    default:
        ret Invalid
    }
}

// --- RFC 7396 merge patch.

fn is_null(value: *const Value) -> bool {
    switch *value {
    case .Null:
        ret true
    default:
        ret false
    }
}

// `target` with `patch` applied: a patch that is not an object replaces the target; one that
// is walks its members, a null removing the member and anything else merged into it. The
// result shares what it can with both inputs; only the member arrays it makes are new.
fn merge_patch(a: *mem.Arena, original: *const Value, delta: *const Value) -> (Value, err) {
    let (patch_members, patch_is_object) = object_of(*delta)
    if !patch_is_object { ret (*delta, ok) }
    var base: []const Member = zero
    let (original_members, original_is_object) = object_of(*original)
    if original_is_object { base = original_members }
    // Members of the target the delta does not name survive; the delta's non-null members
    // follow, in the delta's order.
    var count = 0usize
    var at = 0usize
    while at < base.len {
        let (index, named) = member_index(patch_members, base[at].key)
        if !named { count += 1usize }
        at += 1usize
    }
    at = 0usize
    while at < patch_members.len {
        if !is_null(&patch_members[at].value) { count += 1usize }
        at += 1usize
    }
    let (members, members_failure) = mem.alloc[Member](a, count)
    if members_failure != ok { ret (zero, members_failure) }
    var filled = 0usize
    at = 0usize
    while at < base.len {
        let (index, named) = member_index(patch_members, base[at].key)
        if !named {
            members[filled] = base[at]
            filled += 1usize
        }
        at += 1usize
    }
    at = 0usize
    while at < patch_members.len {
        if !is_null(&patch_members[at].value) {
            var existing: Value = .Null
            let (index, named) = member_index(base, patch_members[at].key)
            if named { existing = base[index].value }
            let (merged, merge_failure) = merge_patch(a, &existing, &patch_members[at].value)
            if merge_failure != ok { ret (zero, merge_failure) }
            members[filled] = Member { key: patch_members[at].key, value: merged }
            filled += 1usize
        }
        at += 1usize
    }
    ret (Value{ Object: members[0usize..filled] }, ok)
}

// --- The tokenizer.
//
// Lexemes off the source one at a time and nothing built: the punctuation, a string as it was
// written (quotes and escapes included), a number validated as `number` validates it, and the
// three literals. `End` once the source is spent; a byte that starts nothing is `Invalid`.

type TokenKind = enum u8 { End, BeginObject, EndObject, BeginArray, EndArray, Colon, Comma, String, Number, True, False, Null }
type Tokenizer = struct { source: str, at: usize }

fn tokenizer(source: str) -> Tokenizer {
    ret Tokenizer { source: source, at: 0usize }
}

fn next_token(t: *Tokenizer) -> (TokenKind, str, err) {
    while t.at < t.source.len && is_space(t.source[t.at]) { t.at += 1usize }
    if t.at >= t.source.len { ret (.End, "", ok) }
    let start = t.at
    let byte = t.source[start]
    var kind: TokenKind = .End
    if byte == 123u8 { kind = .BeginObject }
    if byte == 125u8 { kind = .EndObject }
    if byte == 91u8 { kind = .BeginArray }
    if byte == 93u8 { kind = .EndArray }
    if byte == 58u8 { kind = .Colon }
    if byte == 44u8 { kind = .Comma }
    if kind != .End {
        t.at += 1usize
        ret (kind, t.source[start..t.at], ok)
    }
    if byte == 34u8 {
        var at = start + 1usize
        while at < t.source.len {
            let c = t.source[at]
            if c == 34u8 { break }
            if c < 32u8 { ret (.End, "", Invalid) }
            if c == 92u8 { at += 1usize }
            at += 1usize
        }
        if at >= t.source.len { ret (.End, "", Invalid) }
        t.at = at + 1usize
        ret (.String, t.source[start..t.at], ok)
    }
    if byte == 45u8 || str.is_ascii_digit(byte) {
        var p: Parser = zero
        p.source = t.source
        p.at = start
        let (parsed, failure) = parse_number(&p)
        if failure != ok { ret (.End, "", failure) }
        t.at = p.at
        ret (.Number, parsed.lexeme, ok)
    }
    var p: Parser = zero
    p.source = t.source
    p.at = start
    if literal(&p, "true") {
        t.at = p.at
        ret (.True, t.source[start..t.at], ok)
    }
    if literal(&p, "false") {
        t.at = p.at
        ret (.False, t.source[start..t.at], ok)
    }
    if literal(&p, "null") {
        t.at = p.at
        ret (.Null, t.source[start..t.at], ok)
    }
    ret (.End, "", Invalid)
}
