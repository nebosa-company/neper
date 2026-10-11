// PEP 440 versions, specifiers and requirement lines, after python's `packaging`:
// `parse` normalizes the spellings (`alpha`/`beta`/`c`/`pre`/`rev`/`r`, `-N` posts, any of
// `._-` separators, a leading `v`, case), `cmp` is the PEP 440 total order (epoch, release
// with trailing zeros ignored, dev < a < b < rc < final < post, local after public),
// `contains` tests a version against a specifier set (`~= == != <= >= < > ===`, `.*`
// prefixes, the prerelease and post/local exclusions), and `parse_requirement` splits a
// `name[extras] specifiers ; marker` line.
//
// A `Version` borrows its local part from the text it was parsed from; nothing here
// allocates. The release holds up to sixteen numbers and each number must fit 64 bits.
// ponytail: an environment marker is kept as text and not evaluated or validated, and a
// `name @ url` requirement keeps its url unchecked.

use e.fmt.semver

type Version = struct {
    epoch: u64,
    release: [16]u64,
    release_len: usize,
    pre_kind: u8,
    pre_num: u64,
    has_post: bool,
    post_num: u64,
    has_dev: bool,
    dev_num: u64,
    local: str,
}

// op: 1 `~=`, 2 `==`, 3 `!=`, 4 `<=`, 5 `>=`, 6 `<`, 7 `>`, 8 `===`.
type Specifier = struct { op: u8, version: Version, wildcard: bool, raw: str }
type Requirement = struct { name: str, extras: str, specifiers: str, url: str, marker: str }

error Invalid
error TooSmall

const PRE_NONE: u8 = 0u8
const PRE_A: u8 = 1u8
const PRE_B: u8 = 2u8
const PRE_RC: u8 = 3u8

fn lower(b: u8) -> u8 {
    if b >= 65u8 && b <= 90u8 { ret b + 32u8 }
    ret b
}

fn is_digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

fn is_alnum(b: u8) -> bool {
    ret is_digit(b) || (b >= 97u8 && b <= 122u8) || (b >= 65u8 && b <= 90u8)
}

fn is_sep(b: u8) -> bool { ret b == 46u8 || b == 95u8 || b == 45u8 }

fn is_ws(b: u8) -> bool { ret b == 32u8 || b == 9u8 || b == 10u8 || b == 13u8 || b == 12u8 || b == 11u8 }

fn trim(s: str) -> str {
    var start = 0usize
    var end = s.len
    while start < end && is_ws(s[start]) { start += 1usize }
    while end > start && is_ws(s[end - 1usize]) { end -= 1usize }
    ret s[start..end]
}

fn lit_at(s: str, at: usize, lit: str) -> bool {
    if at + lit.len > s.len { ret false }
    var i = 0usize
    while i < lit.len {
        if lower(s[at + i]) != lit[i] { ret false }
        i += 1usize
    }
    ret true
}

fn digits_at(s: str, at: usize) -> usize {
    var n = 0usize
    while at + n < s.len && is_digit(s[at + n]) { n += 1usize }
    ret n
}

fn read_number(s: str, at: usize, n: usize) -> (u64, bool) {
    var value = 0u64
    var i = 0usize
    while i < n {
        let digit = u64(s[at + i] - 48u8)
        if value > 1844674407370955161u64 || (value == 1844674407370955161u64 && digit > 5u64) { ret (0u64, false) }
        value = value * 10u64 + digit
        i += 1usize
    }
    ret (value, true)
}

// The pre-release word at `at`, in packaging's alternation order: its kind and length.
fn pre_word(s: str, at: usize) -> (u8, usize) {
    if lit_at(s, at, "alpha") { ret (PRE_A, 5usize) }
    if lit_at(s, at, "a") { ret (PRE_A, 1usize) }
    if lit_at(s, at, "beta") { ret (PRE_B, 4usize) }
    if lit_at(s, at, "b") { ret (PRE_B, 1usize) }
    if lit_at(s, at, "preview") { ret (PRE_RC, 7usize) }
    if lit_at(s, at, "pre") { ret (PRE_RC, 3usize) }
    if lit_at(s, at, "c") { ret (PRE_RC, 1usize) }
    if lit_at(s, at, "rc") { ret (PRE_RC, 2usize) }
    ret (PRE_NONE, 0usize)
}

fn parse(text: str) -> (Version, err) {
    let s = trim(text)
    var v: Version = zero
    var at = 0usize
    if lit_at(s, 0usize, "v") { at = 1usize }
    var n = digits_at(s, at)
    if n == 0usize { ret (zero, Invalid) }
    if at + n < s.len && s[at + n] == 33u8 {
        let (epoch, epoch_ok) = read_number(s, at, n)
        if !epoch_ok { ret (zero, Invalid) }
        v.epoch = epoch
        at += n + 1usize
        n = digits_at(s, at)
        if n == 0usize { ret (zero, Invalid) }
    }
    while true {
        let (part, part_ok) = read_number(s, at, n)
        if !part_ok || v.release_len == 16usize { ret (zero, Invalid) }
        v.release[v.release_len] = part
        v.release_len += 1usize
        at += n
        if at < s.len && s[at] == 46u8 && digits_at(s, at + 1usize) > 0usize {
            at += 1usize
            n = digits_at(s, at)
            continue
        }
        break
    }
    // Pre-release: [._-]? word [._-]? digits?
    var p = at
    if p < s.len && is_sep(s[p]) { p += 1usize }
    let (kind, word_len) = pre_word(s, p)
    if kind != PRE_NONE {
        p += word_len
        if p < s.len && is_sep(s[p]) { p += 1usize }
        let pn = digits_at(s, p)
        if pn > 0usize {
            let (num, num_ok) = read_number(s, p, pn)
            if !num_ok { ret (zero, Invalid) }
            v.pre_num = num
            p += pn
        }
        v.pre_kind = kind
        at = p
    }
    // Post-release: -N, or [._-]? (post|rev|r) [._-]? digits?
    if at < s.len && s[at] == 45u8 && digits_at(s, at + 1usize) > 0usize {
        let pn = digits_at(s, at + 1usize)
        let (num, num_ok) = read_number(s, at + 1usize, pn)
        if !num_ok { ret (zero, Invalid) }
        v.has_post = true
        v.post_num = num
        at += 1usize + pn
    } else {
        var q = at
        if q < s.len && is_sep(s[q]) { q += 1usize }
        var word = 0usize
        if lit_at(s, q, "post") {
            word = 4usize
        } else if lit_at(s, q, "rev") {
            word = 3usize
        } else if lit_at(s, q, "r") {
            word = 1usize
        }
        if word > 0usize {
            q += word
            if q < s.len && is_sep(s[q]) { q += 1usize }
            let pn = digits_at(s, q)
            if pn > 0usize {
                let (num, num_ok) = read_number(s, q, pn)
                if !num_ok { ret (zero, Invalid) }
                v.post_num = num
                q += pn
            }
            v.has_post = true
            at = q
        }
    }
    // Dev release: [._-]? dev [._-]? digits?
    var d = at
    if d < s.len && is_sep(s[d]) { d += 1usize }
    if lit_at(s, d, "dev") {
        d += 3usize
        if d < s.len && is_sep(s[d]) { d += 1usize }
        let pn = digits_at(s, d)
        if pn > 0usize {
            let (num, num_ok) = read_number(s, d, pn)
            if !num_ok { ret (zero, Invalid) }
            v.dev_num = num
            d += pn
        }
        v.has_dev = true
        at = d
    }
    if at < s.len && s[at] == 43u8 {
        let start = at + 1usize
        var e = start
        var expect_alnum = true
        while e < s.len {
            if is_alnum(s[e]) {
                expect_alnum = false
                e += 1usize
            } else if is_sep(s[e]) && !expect_alnum && e + 1usize < s.len && is_alnum(s[e + 1usize]) {
                expect_alnum = true
                e += 1usize
            } else {
                break
            }
        }
        if e == start || expect_alnum { ret (zero, Invalid) }
        v.local = s[start..e]
        at = e
    }
    if at != s.len { ret (zero, Invalid) }
    ret (v, ok)
}

fn is_prerelease(v: Version) -> bool { ret v.pre_kind != PRE_NONE || v.has_dev }

fn is_postrelease(v: Version) -> bool { ret v.has_post }

// Epoch and release only.
fn base_version(v: Version) -> Version {
    var out: Version = zero
    out.epoch = v.epoch
    out.release = v.release
    out.release_len = v.release_len
    ret out
}

// Without the local part.
fn public(v: Version) -> Version {
    var out = v
    out.local = ""
    ret out
}

fn cmp_u64(a: u64, b: u64) -> i32 {
    if a < b { ret -1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

fn trimmed_release_len(v: Version) -> usize {
    var n = v.release_len
    while n > 0usize && v.release[n - 1usize] == 0u64 { n -= 1usize }
    ret n
}

// Pre rank: dev-only -1, a 0, b 1, rc 2, none 3.
fn pre_rank(v: Version) -> i64 {
    if v.pre_kind == PRE_NONE && !v.has_post && v.has_dev { ret -1i64 }
    if v.pre_kind == PRE_NONE { ret 3i64 }
    ret i64(v.pre_kind) - 1i64
}

fn cmp_i64(a: i64, b: i64) -> i32 {
    if a < b { ret -1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// The next `._-` separated segment of a local version: it and where the next starts.
fn local_segment(s: str, at: usize) -> (str, usize) {
    var end = at
    while end < s.len && !is_sep(s[end]) { end += 1usize }
    ret (s[at..end], end + 1usize)
}

fn all_digits(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if !is_digit(s[i]) { ret false }
        i += 1usize
    }
    ret s.len > 0usize
}

// Numbers by value without a width limit; strings below numbers, bytewise after folding.
fn cmp_local_segment(a: str, b: str) -> i32 {
    let a_num = all_digits(a)
    let b_num = all_digits(b)
    if a_num && !b_num { ret 1i32 }
    if !a_num && b_num { ret -1i32 }
    if a_num {
        var x = 0usize
        while x + 1usize < a.len && a[x] == 48u8 { x += 1usize }
        var y = 0usize
        while y + 1usize < b.len && b[y] == 48u8 { y += 1usize }
        let la = a.len - x
        let lb = b.len - y
        if la != lb {
            if la < lb { ret -1i32 }
            ret 1i32
        }
        var i = 0usize
        while i < la {
            if a[x + i] != b[y + i] {
                if a[x + i] < b[y + i] { ret -1i32 }
                ret 1i32
            }
            i += 1usize
        }
        ret 0i32
    }
    var i = 0usize
    while i < a.len && i < b.len {
        let l = lower(a[i])
        let r = lower(b[i])
        if l != r {
            if l < r { ret -1i32 }
            ret 1i32
        }
        i += 1usize
    }
    if a.len < b.len { ret -1i32 }
    if a.len > b.len { ret 1i32 }
    ret 0i32
}

fn cmp_local(a: str, b: str) -> i32 {
    if a.len == 0usize && b.len == 0usize { ret 0i32 }
    if a.len == 0usize { ret -1i32 }
    if b.len == 0usize { ret 1i32 }
    var pa = 0usize
    var pb = 0usize
    while pa < a.len && pb < b.len {
        let (sa, next_a) = local_segment(a, pa)
        let (sb, next_b) = local_segment(b, pb)
        let c = cmp_local_segment(sa, sb)
        if c != 0i32 { ret c }
        pa = next_a
        pb = next_b
    }
    if pa >= a.len && pb >= b.len { ret 0i32 }
    if pa >= a.len { ret -1i32 }
    ret 1i32
}

fn cmp(a: Version, b: Version) -> i32 {
    let epoch = cmp_u64(a.epoch, b.epoch)
    if epoch != 0i32 { ret epoch }
    let la = trimmed_release_len(a)
    let lb = trimmed_release_len(b)
    var i = 0usize
    while i < la && i < lb {
        let c = cmp_u64(a.release[i], b.release[i])
        if c != 0i32 { ret c }
        i += 1usize
    }
    if la != lb {
        if la < lb { ret -1i32 }
        ret 1i32
    }
    let pre = cmp_i64(pre_rank(a), pre_rank(b))
    if pre != 0i32 { ret pre }
    if a.pre_kind != PRE_NONE {
        let n = cmp_u64(a.pre_num, b.pre_num)
        if n != 0i32 { ret n }
    }
    var post_a = 0i64
    var post_b = 0i64
    if a.has_post { post_a = 1i64 }
    if b.has_post { post_b = 1i64 }
    let post = cmp_i64(post_a, post_b)
    if post != 0i32 { ret post }
    if a.has_post {
        let n = cmp_u64(a.post_num, b.post_num)
        if n != 0i32 { ret n }
    }
    var dev_a = 1i64
    var dev_b = 1i64
    if a.has_dev { dev_a = 0i64 }
    if b.has_dev { dev_b = 0i64 }
    let dev = cmp_i64(dev_a, dev_b)
    if dev != 0i32 { ret dev }
    if a.has_dev {
        let n = cmp_u64(a.dev_num, b.dev_num)
        if n != 0i32 { ret n }
    }
    ret cmp_local(a.local, b.local)
}

// The normalized spelling: `1!2.0a1.post3.dev4+local.1`.
fn format(v: Version, out: []u8) -> (usize, err) {
    var at = 0usize
    if v.epoch != 0u64 {
        let e1 = semver.put_number(out, &at, v.epoch)
        if e1 != ok { ret (0usize, e1) }
        let e2 = semver.put_byte(out, &at, 33u8)
        if e2 != ok { ret (0usize, e2) }
    }
    var i = 0usize
    while i < v.release_len {
        if i > 0usize {
            let d = semver.put_byte(out, &at, 46u8)
            if d != ok { ret (0usize, d) }
        }
        let r = semver.put_number(out, &at, v.release[i])
        if r != ok { ret (0usize, r) }
        i += 1usize
    }
    if v.pre_kind != PRE_NONE {
        var word = "a"
        if v.pre_kind == PRE_B { word = "b" }
        if v.pre_kind == PRE_RC { word = "rc" }
        let w = semver.put_text(out, &at, word)
        if w != ok { ret (0usize, w) }
        let n = semver.put_number(out, &at, v.pre_num)
        if n != ok { ret (0usize, n) }
    }
    if v.has_post {
        let w = semver.put_text(out, &at, ".post")
        if w != ok { ret (0usize, w) }
        let n = semver.put_number(out, &at, v.post_num)
        if n != ok { ret (0usize, n) }
    }
    if v.has_dev {
        let w = semver.put_text(out, &at, ".dev")
        if w != ok { ret (0usize, w) }
        let n = semver.put_number(out, &at, v.dev_num)
        if n != ok { ret (0usize, n) }
    }
    if v.local.len > 0usize {
        let plus = semver.put_byte(out, &at, 43u8)
        if plus != ok { ret (0usize, plus) }
        var k = 0usize
        while k < v.local.len {
            let (segment, next) = local_segment(v.local, k)
            var from = 0usize
            if all_digits(segment) {
                while from + 1usize < segment.len && segment[from] == 48u8 { from += 1usize }
            }
            var m = from
            while m < segment.len {
                let put = semver.put_byte(out, &at, lower(segment[m]))
                if put != ok { ret (0usize, put) }
                m += 1usize
            }
            if next < v.local.len {
                let dot = semver.put_byte(out, &at, 46u8)
                if dot != ok { ret (0usize, dot) }
            }
            k = next
        }
    }
    ret (at, ok)
}

fn parse_specifier(text: str) -> (Specifier, err) {
    let s = trim(text)
    var spec: Specifier = zero
    var at = 0usize
    if lit_at(s, 0usize, "===") {
        spec.op = 8u8
        at = 3usize
    } else if lit_at(s, 0usize, "~=") {
        spec.op = 1u8
        at = 2usize
    } else if lit_at(s, 0usize, "==") {
        spec.op = 2u8
        at = 2usize
    } else if lit_at(s, 0usize, "!=") {
        spec.op = 3u8
        at = 2usize
    } else if lit_at(s, 0usize, "<=") {
        spec.op = 4u8
        at = 2usize
    } else if lit_at(s, 0usize, ">=") {
        spec.op = 5u8
        at = 2usize
    } else if lit_at(s, 0usize, "<") {
        spec.op = 6u8
        at = 1usize
    } else if lit_at(s, 0usize, ">") {
        spec.op = 7u8
        at = 1usize
    } else {
        ret (zero, Invalid)
    }
    while at < s.len && is_ws(s[at]) { at += 1usize }
    var body = s[at..s.len]
    if body.len == 0usize { ret (zero, Invalid) }
    if spec.op == 8u8 {
        var i = 0usize
        while i < body.len {
            if is_ws(body[i]) || body[i] == 59u8 || body[i] == 41u8 { ret (zero, Invalid) }
            i += 1usize
        }
        spec.raw = body
        ret (spec, ok)
    }
    if (spec.op == 2u8 || spec.op == 3u8) && body.len >= 2usize && body[body.len - 2usize] == 46u8 && body[body.len - 1usize] == 42u8 {
        spec.wildcard = true
        body = body[0usize..body.len - 2usize]
    }
    let (version, version_error) = parse(body)
    if version_error != ok { ret (zero, Invalid) }
    // Inside the text there is no space: `1.0 .0` would have been read as one version.
    var k = 0usize
    while k < body.len {
        if is_ws(body[k]) { ret (zero, Invalid) }
        k += 1usize
    }
    if spec.wildcard && (version.pre_kind != PRE_NONE || version.has_post || version.has_dev || version.local.len > 0usize) { ret (zero, Invalid) }
    if spec.op != 2u8 && spec.op != 3u8 && version.local.len > 0usize { ret (zero, Invalid) }
    if spec.op == 1u8 && version.release_len < 2usize { ret (zero, Invalid) }
    spec.version = version
    ret (spec, ok)
}

// The same epoch and release prefix, the shorter release padded with zeros.
fn prefix_matches(prospective: Version, prefix: Version, prefix_len: usize) -> bool {
    if prospective.epoch != prefix.epoch { ret false }
    var i = 0usize
    while i < prefix_len {
        var have = 0u64
        if i < prospective.release_len { have = prospective.release[i] }
        if have != prefix.release[i] { ret false }
        i += 1usize
    }
    ret true
}

fn equal_spec(s: Specifier, v: Version) -> bool {
    if s.wildcard { ret prefix_matches(v, s.version, s.version.release_len) }
    var candidate = v
    if s.version.local.len == 0usize { candidate = public(v) }
    ret cmp(candidate, s.version) == 0i32
}

// The operator alone: no pre-release filtering, which `contains` does for the set.
fn matches(s: Specifier, v: Version) -> bool {
    if s.op == 2u8 { ret equal_spec(s, v) }
    if s.op == 3u8 { ret !equal_spec(s, v) }
    if s.op == 1u8 {
        if cmp(public(v), s.version) < 0i32 { ret false }
        ret prefix_matches(v, s.version, s.version.release_len - 1usize)
    }
    if s.op == 4u8 { ret cmp(public(v), s.version) <= 0i32 }
    if s.op == 5u8 { ret cmp(public(v), s.version) >= 0i32 }
    if s.op == 6u8 {
        // `<V` leaves out the pre-releases of V unless V is one: the bound is V.dev0.
        var bound = s.version
        if !is_prerelease(bound) {
            bound.has_dev = true
            bound.dev_num = 0u64
        }
        ret cmp(v, bound) < 0i32
    }
    if s.op == 7u8 {
        var low = s.version
        if low.has_dev {
            low.dev_num += 1u64
            ret cmp(v, low) >= 0i32
        }
        if low.has_post {
            low.post_num += 1u64
            low.has_dev = true
            low.dev_num = 0u64
            ret cmp(v, low) >= 0i32
        }
        if cmp(v, s.version) <= 0i32 { ret false }
        // `>V` leaves out V's post-releases and local versions.
        let family = cmp(base_version(v), base_version(s.version)) == 0i32 && v.pre_kind == s.version.pre_kind && v.pre_num == s.version.pre_num
        if family && (v.has_post || v.local.len > 0usize) { ret false }
        ret true
    }
    // `===`: the normalized text, folded, against the spelling given.
    var buffer: [128]u8 = zero
    let (n, format_error) = format(v, buffer[0usize..128usize])
    if format_error != ok { ret false }
    if n != s.raw.len { ret false }
    var i = 0usize
    while i < n {
        if buffer[i] != lower(s.raw[i]) { ret false }
        i += 1usize
    }
    ret true
}

// `version` against the comma-separated `specifiers` (empty entries ignored).
fn contains(version: str, specifiers: str, prereleases: bool) -> (bool, err) {
    let (v, v_error) = parse(version)
    if v_error != ok { ret (false, Invalid) }
    var specs: [16]Specifier = zero
    var count = 0usize
    var at = 0usize
    while at <= specifiers.len {
        var end = at
        while end < specifiers.len && specifiers[end] != 44u8 { end += 1usize }
        let part = trim(specifiers[at..end])
        if part.len > 0usize {
            if count == 16usize { ret (false, TooSmall) }
            let (spec, spec_error) = parse_specifier(part)
            if spec_error != ok { ret (false, Invalid) }
            specs[count] = spec
            count += 1usize
        }
        at = end + 1usize
    }
    if is_prerelease(v) && !prereleases { ret (false, ok) }
    var i = 0usize
    while i < count {
        if !matches(specs[i], v) { ret (false, ok) }
        i += 1usize
    }
    ret (true, ok)
}

fn is_name_char(b: u8) -> bool { ret is_alnum(b) || b == 45u8 || b == 95u8 || b == 46u8 }

// `[A-Za-z0-9]([-_.A-Za-z0-9]*[A-Za-z0-9])?`
fn valid_name(s: str) -> bool {
    if s.len == 0usize { ret false }
    if !is_alnum(s[0usize]) || !is_alnum(s[s.len - 1usize]) { ret false }
    var i = 0usize
    while i < s.len {
        if !is_name_char(s[i]) { ret false }
        i += 1usize
    }
    ret true
}

// `name[extra,extra] (specifiers) ; marker`, or `name @ url ; marker`.
fn parse_requirement(text: str) -> (Requirement, err) {
    let s = trim(text)
    var r: Requirement = zero
    var at = 0usize
    while at < s.len && is_name_char(s[at]) { at += 1usize }
    r.name = s[0usize..at]
    if !valid_name(r.name) { ret (zero, Invalid) }
    while at < s.len && is_ws(s[at]) { at += 1usize }
    if at < s.len && s[at] == 91u8 {
        var close = at + 1usize
        while close < s.len && s[close] != 93u8 { close += 1usize }
        if close >= s.len { ret (zero, Invalid) }
        r.extras = trim(s[at + 1usize..close])
        // Each extra is a name; the list is comma separated.
        var start = 0usize
        var k = 0usize
        while k <= r.extras.len {
            if k == r.extras.len || r.extras[k] == 44u8 {
                if k > start || r.extras.len > 0usize {
                    if !valid_name(trim(r.extras[start..k])) { ret (zero, Invalid) }
                }
                start = k + 1usize
            }
            k += 1usize
        }
        at = close + 1usize
        while at < s.len && is_ws(s[at]) { at += 1usize }
    }
    // The marker is whatever follows the first `;`.
    var semi = at
    while semi < s.len && s[semi] != 59u8 { semi += 1usize }
    var rest = trim(s[at..semi])
    if semi < s.len {
        r.marker = trim(s[semi + 1usize..s.len])
        if r.marker.len == 0usize { ret (zero, Invalid) }
    }
    if rest.len > 0usize && rest[0usize] == 64u8 {
        let url = trim(rest[1usize..rest.len])
        if url.len == 0usize { ret (zero, Invalid) }
        var j = 0usize
        while j < url.len {
            if is_ws(url[j]) { ret (zero, Invalid) }
            j += 1usize
        }
        r.url = url
        ret (r, ok)
    }
    if rest.len > 0usize && rest[0usize] == 40u8 {
        if rest[rest.len - 1usize] != 41u8 { ret (zero, Invalid) }
        rest = trim(rest[1usize..rest.len - 1usize])
        if rest.len == 0usize { ret (zero, Invalid) }
    }
    // Validate the set; one trailing comma is tolerated, as packaging's grammar does.
    if rest.len > 1usize && rest[rest.len - 1usize] == 44u8 { rest = trim(rest[0usize..rest.len - 1usize]) }
    var piece = 0usize
    var m = 0usize
    while m <= rest.len && rest.len > 0usize {
        if m == rest.len || rest[m] == 44u8 {
            let part = trim(rest[piece..m])
            if part.len == 0usize { ret (zero, Invalid) }
            let (_, spec_error) = parse_specifier(part)
            if spec_error != ok { ret (zero, Invalid) }
            piece = m + 1usize
        }
        m += 1usize
    }
    r.specifiers = rest
    ret (r, ok)
}
