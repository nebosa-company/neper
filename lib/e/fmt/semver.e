// Semantic versions (SemVer 2.0.0): `parse`, `cmp` with the spec's precedence, `format`, and
// `satisfies` over node-style ranges -- comparators, `^`, `~`, `x`/`*` wildcards, hyphen ranges,
// space-separated AND and `||` OR -- with node's rule that a prerelease version only satisfies a
// range when some comparator names that same `major.minor.patch` with a prerelease of its own.
//
// A `Version` borrows its prerelease and build from the text it was parsed from; nothing here
// allocates. A range is never stored: each comparator is desugared and tested as it is read.

use e.str

type Version = struct { major: u64, minor: u64, patch: u64, prerelease: str, build: str }

error Invalid
error TooSmall

const DOT: u8 = 46u8
const DASH: u8 = 45u8
const PLUS: u8 = 43u8
const ZERO: u8 = 48u8
const NINE: u8 = 57u8
const LOWER_X: u8 = 120u8
const UPPER_X: u8 = 88u8
const STAR: u8 = 42u8
const LOWER_V: u8 = 118u8
const EQUALS: u8 = 61u8
const LESS: u8 = 60u8
const GREATER: u8 = 62u8
const CARET: u8 = 94u8
const TILDE: u8 = 126u8
const BAR: u8 = 124u8

const OP_ANY: u8 = 0u8
const OP_EQ: u8 = 1u8
const OP_LT: u8 = 2u8
const OP_LE: u8 = 3u8
const OP_GT: u8 = 4u8
const OP_GE: u8 = 5u8
const OP_CARET: u8 = 6u8
const OP_TILDE: u8 = 7u8

// A range's version: a `Version` with each component possibly a wildcard, absent ones included.
// `x_major` implies `x_minor` implies `x_patch`; a number after a wildcard is refused.
// ponytail: node lets `^1.x.3` and `~1.x.3` through (regex leftovers) and accepts `>  =1.2.3`;
// neither is worth a branch until a real range needs it.
type Partial = struct { major: u64, minor: u64, patch: u64, prerelease: str, x_major: bool, x_minor: bool, x_patch: bool }

fn is_digit(b: u8) -> bool { ret b >= ZERO && b <= NINE }

fn is_ident_byte(b: u8) -> bool {
    ret is_digit(b) || str.is_ascii_alpha(b) || b == DASH
}

// A numeric identifier: digits, no leading zero (RFC and node's strict regex agree).
fn is_numeric(s: str) -> bool {
    if s.len == 0usize { ret false }
    var at = 0usize
    while at < s.len {
        if !is_digit(s[at]) { ret false }
        at += 1usize
    }
    ret s[0usize] != ZERO || s.len == 1usize
}

fn parse_number(s: str) -> (u64, err) {
    if !is_numeric(s) { ret (0u64, Invalid) }
    let (value, parse_error) = str.parse_u64(s)
    if parse_error != ok { ret (0u64, Invalid) }
    ret (value, ok)
}

// `identifiers`: dot-separated, each non-empty and of `[0-9A-Za-z-]`; numeric ones may not have
// a leading zero when `strict` (prerelease), and may when not (build).
fn valid_identifiers(s: str, strict: bool) -> bool {
    if s.len == 0usize { ret false }
    var start = 0usize
    var at = 0usize
    while at <= s.len {
        if at == s.len || s[at] == DOT {
            let part = s[start..at]
            if part.len == 0usize { ret false }
            var i = 0usize
            var all_digits = true
            while i < part.len {
                if !is_ident_byte(part[i]) { ret false }
                if !is_digit(part[i]) { all_digits = false }
                i += 1usize
            }
            if strict && all_digits && !is_numeric(part) { ret false }
            start = at + 1usize
        }
        at += 1usize
    }
    ret true
}

// Where the core `MAJOR.MINOR.PATCH` (or a partial) ends: the first `-` or `+`.
fn core_end(s: str) -> usize {
    var at = 0usize
    while at < s.len && s[at] != DASH && s[at] != PLUS { at += 1usize }
    ret at
}

// The `-prerelease` and `+build` tails behind a core, validated. Both borrow `s`.
fn parse_tails(s: str, from: usize) -> (str, str, err) {
    var prerelease = ""
    var build = ""
    var at = from
    if at < s.len && s[at] == DASH {
        var stop = at + 1usize
        while stop < s.len && s[stop] != PLUS { stop += 1usize }
        prerelease = s[at + 1usize..stop]
        if !valid_identifiers(prerelease, true) { ret ("", "", Invalid) }
        at = stop
    }
    if at < s.len && s[at] == PLUS {
        build = s[at + 1usize..s.len]
        if !valid_identifiers(build, false) { ret ("", "", Invalid) }
        at = s.len
    }
    if at != s.len { ret ("", "", Invalid) }
    ret (prerelease, build, ok)
}

// `MAJOR.MINOR.PATCH[-prerelease][+build]`, with an optional leading `v` as node allows.
fn parse(text: str) -> (Version, err) {
    var out: Version = zero
    var s = str.trim(text)
    if s.len != 0usize && s[0usize] == LOWER_V { s = s[1usize..s.len] }
    let end = core_end(s)
    let core = s[0usize..end]
    let (major_text, rest, has_minor) = str.split_once(core, ".")
    if !has_minor { ret (out, Invalid) }
    let (minor_text, patch_text, has_patch) = str.split_once(rest, ".")
    if !has_patch { ret (out, Invalid) }
    let (major, major_error) = parse_number(major_text)
    if major_error != ok { ret (out, major_error) }
    let (minor, minor_error) = parse_number(minor_text)
    if minor_error != ok { ret (out, minor_error) }
    let (patch, patch_error) = parse_number(patch_text)
    if patch_error != ok { ret (out, patch_error) }
    let (prerelease, build, tail_error) = parse_tails(s, end)
    if tail_error != ok { ret (out, tail_error) }
    out.major = major
    out.minor = minor
    out.patch = patch
    out.prerelease = prerelease
    out.build = build
    ret (out, ok)
}

fn cmp_u64(a: u64, b: u64) -> i32 {
    if a < b { ret -1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// Two numeric identifiers without leading zeros order by length first, so no width limits them.
fn cmp_identifier(a: str, b: str) -> i32 {
    let a_numeric = is_numeric(a)
    let b_numeric = is_numeric(b)
    if a_numeric && b_numeric {
        if a.len != b.len { ret cmp_u64(u64(a.len), u64(b.len)) }
        ret str.compare(a, b)
    }
    if a_numeric { ret -1i32 }
    if b_numeric { ret 1i32 }
    ret str.compare(a, b)
}

fn next_identifier(s: str, at: usize) -> (str, usize) {
    var stop = at
    while stop < s.len && s[stop] != DOT { stop += 1usize }
    ret (s[at..stop], stop + 1usize)
}

fn cmp_prerelease(a: str, b: str) -> i32 {
    if a.len == 0usize && b.len == 0usize { ret 0i32 }
    if a.len == 0usize { ret 1i32 }
    if b.len == 0usize { ret -1i32 }
    var a_at = 0usize
    var b_at = 0usize
    while a_at < a.len && b_at < b.len {
        let (a_part, a_after) = next_identifier(a, a_at)
        let (b_part, b_after) = next_identifier(b, b_at)
        let order = cmp_identifier(a_part, b_part)
        if order != 0i32 { ret order }
        a_at = a_after
        b_at = b_after
    }
    if a_at < a.len { ret 1i32 }
    if b_at < b.len { ret -1i32 }
    ret 0i32
}

// SemVer precedence: numeric core, then a release above any prerelease, then identifiers
// left to right (numeric below alphanumeric, fewer below more). Build metadata is ignored.
fn cmp(a: Version, b: Version) -> i32 {
    var order = cmp_u64(a.major, b.major)
    if order != 0i32 { ret order }
    order = cmp_u64(a.minor, b.minor)
    if order != 0i32 { ret order }
    order = cmp_u64(a.patch, b.patch)
    if order != 0i32 { ret order }
    ret cmp_prerelease(a.prerelease, b.prerelease)
}

fn put_byte(out: []u8, at: *usize, b: u8) -> err {
    if *at >= out.len { ret TooSmall }
    out[*at] = b
    *at += 1usize
    ret ok
}

fn put_text(out: []u8, at: *usize, s: str) -> err {
    var i = 0usize
    while i < s.len {
        try put_byte(out, at, s[i])
        i += 1usize
    }
    ret ok
}

fn put_number(out: []u8, at: *usize, value: u64) -> err {
    var digits: [20]u8 = zero
    var n = 0usize
    var v = value
    while true {
        digits[n] = ZERO + u8(v % 10u64)
        n += 1usize
        v = v / 10u64
        if v == 0u64 { break }
    }
    while n > 0usize {
        n -= 1usize
        try put_byte(out, at, digits[n])
    }
    ret ok
}

// The version as text into `out`; the byte count written, or `TooSmall`.
fn format(v: Version, out: []u8) -> (usize, err) {
    var at = 0usize
    let put_error = put_version(v, out, &at)
    if put_error != ok { ret (0usize, put_error) }
    ret (at, ok)
}

fn put_version(v: Version, out: []u8, at: *usize) -> err {
    try put_number(out, at, v.major)
    try put_byte(out, at, DOT)
    try put_number(out, at, v.minor)
    try put_byte(out, at, DOT)
    try put_number(out, at, v.patch)
    if v.prerelease.len != 0usize {
        try put_byte(out, at, DASH)
        try put_text(out, at, v.prerelease)
    }
    if v.build.len != 0usize {
        try put_byte(out, at, PLUS)
        try put_text(out, at, v.build)
    }
    ret ok
}

// --- Ranges.

fn is_x(s: str) -> bool {
    ret s.len == 1usize && (s[0usize] == LOWER_X || s[0usize] == UPPER_X || s[0usize] == STAR)
}

// One component of a partial: a number, a wildcard, or absent (also a wildcard).
fn partial_component(s: str, present: bool) -> (u64, bool, err) {
    if !present || is_x(s) { ret (0u64, true, ok) }
    let (value, parse_error) = parse_number(s)
    if parse_error != ok { ret (0u64, false, parse_error) }
    ret (value, false, ok)
}

// `1`, `1.2`, `1.2.3`, `1.x`, `*`, `1.2.3-beta+build`, with an optional `v` or `=` prefix.
fn parse_partial(text: str) -> (Partial, err) {
    var out: Partial = zero
    var s = text
    while s.len != 0usize && (s[0usize] == LOWER_V || s[0usize] == EQUALS) { s = s[1usize..s.len] }
    if s.len == 0usize {
        out.x_major = true
        out.x_minor = true
        out.x_patch = true
        ret (out, ok)
    }
    let end = core_end(s)
    let core = s[0usize..end]
    let (major_text, rest, has_minor) = str.split_once(core, ".")
    let (minor_text, patch_text, has_patch) = str.split_once(rest, ".")
    if has_patch && str.contains(patch_text, ".") { ret (out, Invalid) }
    let (major, x_major, major_error) = partial_component(major_text, true)
    if major_error != ok { ret (out, major_error) }
    let (minor, x_minor, minor_error) = partial_component(minor_text, has_minor)
    if minor_error != ok { ret (out, minor_error) }
    let (patch, x_patch, patch_error) = partial_component(patch_text, has_patch)
    if patch_error != ok { ret (out, patch_error) }
    // node's grammar: a wildcard is not followed by a number, and a tail needs three components.
    if (x_major && has_minor && !x_minor) || (x_minor && has_patch && !x_patch) { ret (out, Invalid) }
    if end < s.len && !has_patch { ret (out, Invalid) }
    let (prerelease, build, tail_error) = parse_tails(s, end)
    if tail_error != ok { ret (out, tail_error) }
    out.major = major
    out.minor = minor
    out.patch = patch
    out.prerelease = prerelease
    out.x_major = x_major
    out.x_minor = x_major || x_minor
    out.x_patch = out.x_minor || x_patch
    ret (out, ok)
}

fn version_of(major: u64, minor: u64, patch: u64, prerelease: str) -> Version {
    var v: Version = zero
    v.major = major
    v.minor = minor
    v.patch = patch
    v.prerelease = prerelease
    ret v
}

// One desugared comparator against `v`. `bound` is the comparator's version, which the
// prerelease rule later needs too, so it is returned alongside.
fn test_op(op: u8, bound: Version, v: Version) -> bool {
    if op == OP_ANY { ret true }
    let order = cmp(v, bound)
    if op == OP_EQ { ret order == 0i32 }
    if op == OP_LT { ret order < 0i32 }
    if op == OP_LE { ret order <= 0i32 }
    if op == OP_GT { ret order > 0i32 }
    ret order >= 0i32
}

// The running state of one `||` alternative: whether every comparator so far held, and whether
// one of them named `v`'s own core with a prerelease, which is what lets a prerelease in.
type SetState = struct { all: bool, prerelease_allowed: bool }

fn apply(s: *SetState, op: u8, bound: Version, v: Version) {
    if !test_op(op, bound, v) { s.all = false }
    if op != OP_ANY && bound.prerelease.len != 0usize && bound.major == v.major && bound.minor == v.minor && bound.patch == v.patch {
        s.prerelease_allowed = true
    }
}

// node's `replaceCaret`.
fn apply_caret(s: *SetState, p: Partial, v: Version) {
    if p.x_major { ret }
    if p.x_minor {
        apply(s, OP_GE, version_of(p.major, 0u64, 0u64, ""), v)
        apply(s, OP_LT, version_of(p.major + 1u64, 0u64, 0u64, "0"), v)
        ret
    }
    if p.x_patch {
        apply(s, OP_GE, version_of(p.major, p.minor, 0u64, ""), v)
        if p.major == 0u64 {
            apply(s, OP_LT, version_of(0u64, p.minor + 1u64, 0u64, "0"), v)
        } else {
            apply(s, OP_LT, version_of(p.major + 1u64, 0u64, 0u64, "0"), v)
        }
        ret
    }
    apply(s, OP_GE, version_of(p.major, p.minor, p.patch, p.prerelease), v)
    if p.major == 0u64 {
        if p.minor == 0u64 {
            apply(s, OP_LT, version_of(0u64, 0u64, p.patch + 1u64, "0"), v)
        } else {
            apply(s, OP_LT, version_of(0u64, p.minor + 1u64, 0u64, "0"), v)
        }
    } else {
        apply(s, OP_LT, version_of(p.major + 1u64, 0u64, 0u64, "0"), v)
    }
}

// node's `replaceTilde`.
fn apply_tilde(s: *SetState, p: Partial, v: Version) {
    if p.x_major { ret }
    if p.x_minor {
        apply(s, OP_GE, version_of(p.major, 0u64, 0u64, ""), v)
        apply(s, OP_LT, version_of(p.major + 1u64, 0u64, 0u64, "0"), v)
        ret
    }
    apply(s, OP_GE, version_of(p.major, p.minor, p.patch, p.prerelease), v)
    apply(s, OP_LT, version_of(p.major, p.minor + 1u64, 0u64, "0"), v)
}

// node's `replaceXRange`: a plain or relational comparator whose version may have wildcards.
fn apply_xrange(s: *SetState, op: u8, p: Partial, v: Version) {
    if p.x_major {
        if op == OP_GT || op == OP_LT { apply(s, OP_LT, version_of(0u64, 0u64, 0u64, "0"), v) }
        ret
    }
    if !p.x_patch {
        apply(s, op, version_of(p.major, p.minor, p.patch, p.prerelease), v)
        ret
    }
    if op == OP_EQ || op == OP_ANY {
        apply(s, OP_GE, version_of(p.major, p.minor, 0u64, ""), v)
        if p.x_minor {
            apply(s, OP_LT, version_of(p.major + 1u64, 0u64, 0u64, "0"), v)
        } else {
            apply(s, OP_LT, version_of(p.major, p.minor + 1u64, 0u64, "0"), v)
        }
        ret
    }
    if op == OP_GT {
        if p.x_minor {
            apply(s, OP_GE, version_of(p.major + 1u64, 0u64, 0u64, ""), v)
        } else {
            apply(s, OP_GE, version_of(p.major, p.minor + 1u64, 0u64, ""), v)
        }
        ret
    }
    if op == OP_LE {
        if p.x_minor {
            apply(s, OP_LT, version_of(p.major + 1u64, 0u64, 0u64, "0"), v)
        } else {
            apply(s, OP_LT, version_of(p.major, p.minor + 1u64, 0u64, "0"), v)
        }
        ret
    }
    if op == OP_LT {
        apply(s, OP_LT, version_of(p.major, p.minor, 0u64, "0"), v)
        ret
    }
    apply(s, OP_GE, version_of(p.major, p.minor, 0u64, ""), v)
}

// node's `hyphenReplace`: `from - to`, each end a partial.
fn apply_hyphen(s: *SetState, from: Partial, to: Partial, v: Version) {
    if !from.x_major {
        if from.x_minor {
            apply(s, OP_GE, version_of(from.major, 0u64, 0u64, ""), v)
        } else {
            if from.x_patch {
                apply(s, OP_GE, version_of(from.major, from.minor, 0u64, ""), v)
            } else {
                apply(s, OP_GE, version_of(from.major, from.minor, from.patch, from.prerelease), v)
            }
        }
    }
    if to.x_major { ret }
    if to.x_minor {
        apply(s, OP_LT, version_of(to.major + 1u64, 0u64, 0u64, "0"), v)
        ret
    }
    if to.x_patch {
        apply(s, OP_LT, version_of(to.major, to.minor + 1u64, 0u64, "0"), v)
        ret
    }
    apply(s, OP_LE, version_of(to.major, to.minor, to.patch, to.prerelease), v)
}

// The operator at the head of a comparator, and where its version begins.
fn split_op(token: str) -> (u8, usize) {
    if token.len == 0usize { ret (OP_ANY, 0usize) }
    let first = token[0usize]
    if first == CARET { ret (OP_CARET, 1usize) }
    if first == TILDE { ret (OP_TILDE, 1usize) }
    if first == EQUALS { ret (OP_EQ, 1usize) }
    if first == LESS {
        if token.len > 1usize && token[1usize] == EQUALS { ret (OP_LE, 2usize) }
        ret (OP_LT, 1usize)
    }
    if first == GREATER {
        if token.len > 1usize && token[1usize] == EQUALS { ret (OP_GE, 2usize) }
        ret (OP_GT, 1usize)
    }
    ret (OP_ANY, 0usize)
}

fn next_token(s: str, at: *usize) -> (str, bool) {
    while *at < s.len && str.is_ascii_space(s[*at]) { *at += 1usize }
    if *at >= s.len { ret ("", false) }
    let start = *at
    while *at < s.len && !str.is_ascii_space(s[*at]) { *at += 1usize }
    ret (s[start..*at], true)
}

// One `||` alternative: whitespace-separated comparators, all of which must hold. An operator
// may be separated from its version by spaces (`>= 1.2.3`), as node tolerates.
fn satisfies_set(v: Version, set: str) -> (bool, err) {
    var state: SetState = zero
    state.all = true
    var at = 0usize
    var pending: Partial = zero
    var has_pending = false
    while true {
        let (token, more) = next_token(set, &at)
        if !more { break }
        if token.len == 1usize && token[0usize] == DASH {
            if !has_pending { ret (false, Invalid) }
            let (to_text, has_to) = next_token(set, &at)
            if !has_to { ret (false, Invalid) }
            let (to, to_error) = parse_partial(to_text)
            if to_error != ok { ret (false, to_error) }
            apply_hyphen(&state, pending, to, v)
            has_pending = false
            continue
        }
        if has_pending {
            apply_xrange(&state, OP_EQ, pending, v)
            has_pending = false
        }
        let (op, skip) = split_op(token)
        var version_text = token[skip..token.len]
        if version_text.len == 0usize && op != OP_ANY {
            let (following, has_following) = next_token(set, &at)
            if !has_following { ret (false, Invalid) }
            version_text = following
        }
        let (p, partial_error) = parse_partial(version_text)
        if partial_error != ok { ret (false, partial_error) }
        if op == OP_ANY {
            pending = p
            has_pending = true
            continue
        }
        if op == OP_CARET {
            apply_caret(&state, p, v)
            continue
        }
        if op == OP_TILDE {
            apply_tilde(&state, p, v)
            continue
        }
        apply_xrange(&state, op, p, v)
    }
    if has_pending { apply_xrange(&state, OP_EQ, pending, v) }
    if !state.all { ret (false, ok) }
    if v.prerelease.len != 0usize && !state.prerelease_allowed { ret (false, ok) }
    ret (true, ok)
}

// Whether `v` is in `range`: `||`-separated alternatives of space-separated comparators.
fn satisfies(v: Version, range: str) -> (bool, err) {
    var at = 0usize
    var any = false
    while at <= range.len {
        var stop = at
        while stop + 1usize < range.len && !(range[stop] == BAR && range[stop + 1usize] == BAR) { stop += 1usize }
        if stop + 1usize >= range.len { stop = range.len }
        let (matched, set_error) = satisfies_set(v, range[at..stop])
        if set_error != ok { ret (false, set_error) }
        if matched { any = true }
        at = stop + 2usize
    }
    ret (any, ok)
}
