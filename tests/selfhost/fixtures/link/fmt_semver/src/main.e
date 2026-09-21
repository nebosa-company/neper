// `e.fmt.semver`: the precedence chain from the spec (and a numeric one), `format` reading
// back what `parse` read, the parse refusals, and `satisfies` over 168 version/range pairs whose
// answers are node's own `semver.satisfies` (npm's bundled copy, 7.8.4). Each check exits with
// its own code; a mismatching pair prints its index first.

use e.fmt.semver as semver
use e.io
use e.mem
use e.os
use e.str

// A module-scope `const` of type `str` does not type check (D134), so the tables are calls.
fn chain() -> str {
    ret "0.9.9 1.0.0-0 1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0 1.0.1 1.1.0-x.7.z.92 1.1.0 2.0.0-0 2.0.0 10.0.0"
}

fn cases() -> str {
    ret "1.2.3|^1.0.0|1\n2.0.0|^1.0.0|0\n2.0.0-alpha|^1.0.0|0\n1.5.0-beta|^1.0.0|0\n1.5.0-beta|^1.5.0-alpha|1\n1.5.0-beta|>=1.5.0-alpha|1\n1.5.1-beta|>=1.5.0-alpha|0\n0.1.5|^0.1.2|1\n0.2.0|^0.1.2|0\n0.0.3|^0.0.3|1\n0.0.4|^0.0.3|0\n0.5.0|^0.x|1\n1.0.0|^0.x|0\n0.0.9|^0.0.x|1\n0.1.0|^0.0.x|0\n1.9.9|^1.x|1\n1.2.9|^1.2|1\n1.3.0|^1.2|1\n1.2.9|~1.2.3|1\n1.3.0|~1.2.3|0\n1.2.2|~1.2.3|0\n1.4.0|~1.2|0\n1.0.0|~1|1\n2.0.0|~1|0\n1.2.3|1.2.x|1\n1.3.0|1.2.x|0\n1.2.3|1.x|1\n3.0.0|*|1\n3.0.0-rc.1|*|0\n3.0.0||1\n1.2.3|1.2.3|1\n1.2.3|=1.2.3|1\n1.2.3|v1.2.3|1\n1.2.4|1.2.3|0\n1.2.3|>1.2.3|0\n1.2.4|>1.2.3|1\n1.2.3|>=1.2.3|1\n1.2.3|<1.2.3|0\n1.2.3|<=1.2.3|1\n1.5.0|1.2.3 - 2.3.4|1\n2.3.4|1.2.3 - 2.3.4|1\n2.3.5|1.2.3 - 2.3.4|0\n1.2.2|1.2.3 - 2.3.4|0\n2.9.9|1.2 - 2.3|0\n2.4.0|1.2 - 2.3|0\n2.9.9|1.2 - 2|1\n3.0.0|1.2 - 2|0\n1.2.3|>=1.2.3 <2.0.0|1\n2.0.0|>=1.2.3 <2.0.0|0\n1.2.3|>= 1.2.3 < 2.0.0|1\n1.2.3|1.0.0 || 3.0.0|0\n3.0.0|1.0.0 || 3.0.0|1\n2.0.0|1.0.0 || 3.0.0|0\n3.5.0|<2 || >=3|1\n1.2.3|>1.x|0\n2.0.0|>1.x|1\n1.9.0|<=1.x|1\n2.0.0|<=1.x|0\n1.2.0|<1.2.x|0\n1.1.9|<1.2.x|1\n1.3.0|>1.2.x|1\n1.2.9|>1.2.x|0\n1.2.9|<=1.2.x|1\n1.3.0|<=1.2.x|0\n1.0.0|>*|0\n1.0.0|<*|0\n1.0.0-alpha|1.0.0-alpha|1\n1.0.0-alpha|>=1.0.0-alpha|1\n1.0.0-beta|>=1.0.0-alpha|1\n1.0.0-alpha|~1.0.0-alpha|1\n1.0.1-alpha|~1.0.0-alpha|0\n1.0.1|~1.0.0-alpha|1\n1.2.3+build.7|1.2.3|1\n1.2.3|1.2.3+other|1\n2.0.0-0|<2.0.0-0|0\n2.0.0-0|<=2.0.0-0|1\n2.0.0-0|^1.0.0 || 2.0.0-0|1\n1.2.3|^1.2.3||^2.0.0|1\n2.5.0|^1.2.3||^2.0.0|1\n3.0.0|^1.2.3||^2.0.0|0\n0.0.0|^0|1\n0.9.9|^0|1\n1.0.0|^0|0\n0.0.0|~0|1\n0.3.1|~0.3|1\n0.4.0|~0.3|0\n2.3.9|1.2 - 2.3|1\n2.0.5|1.2.3 - 2.0.x|1\n2.1.0|1.2.3 - 2.0.x|0\n2.5.0|1.2.3 - 2.x|1\n1.2.0|1.2.x - 2.0.0|1\n1.1.9|1.2.x - 2.0.0|0\n2.0.0-rc.1|1.2.3 - 2.0.0-rc.1|1\n2.0.0-rc.2|1.2.3 - 2.0.0-rc.1|0\n1.2.3-rc.1|1.2.3-rc.1 - 2.0.0|1\n1.2.3|1.2.x-rc.1|1\n1.2.3|=v1.2.3|1\n3.0.0|1.2.3 - x|1\n1.0.0|x - 2.0.0|1\n1.2.3|1.2.3 1.2.3|1\n1.2.3|1.2.3-a.b.c|0\n1.2.3-a.b.c|1.2.3-a.b.c|1\n1.2.3-a.b|1.2.3-a.b.c|0\n1.2.3|x|1\n1.2.3|X|1\n1.2.3|1.X|1\n1.2.3|^1.x.x|1\n1.2.3|~1.x|1\n1.3.2|^0.3.2|0\n2.1.0|>0.3 || 0.3.x|1\n1.1.1-rc.1|<=2.1.1|0\n1.3.2|<1.2 || 0.1.x|0\n1.2.2-rc.1|1.2.0|0\n0.3.1-rc.0|^0|0\n0.3.3|~1|0\n2.2.1-rc.1|>=2|0\n2.2.3|~0.0.0|0\n2.0.2|>1.2.3 || 2.3.x|1\n0.3.0|^0|1\n2.3.2|<0.1.3 || 2.1.x|0\n2.0.2-rc.1|^0.1|0\n1.1.1|2|0\n1.0.3-rc.0|<2|0\n0.1.0|~2|0\n1.1.0|^0.1|0\n1.2.3|<2.1|1\n2.2.0-rc.2|2 || 0.2.x|0\n1.1.0|<2|1\n0.2.3|<=1.2 || 2.2.x|1\n0.0.0-rc.1|^2 || 0.1.x|0\n0.2.0-rc.2|>=1 || 2.2.x|0\n0.2.1|0 || 0.2.x|1\n2.3.2-rc.0|^2.1.1 || 0.3.x|0\n2.0.0-rc.2|<=2.2.2|0\n0.1.3|2|0\n0.1.3|^0.1.2|1\n0.2.2|^1.0|0\n2.3.2-rc.1|>=0|0\n2.0.3-rc.0|^0|0\n0.0.1|<0|0\n2.3.1-rc.2|>=2.3.1-rc.0|1\n2.1.2|<2.3|1\n0.1.3|~1.0|0\n0.2.3-rc.1|~1.2.3 || 0.1.x|0\n0.2.3|^1.0|0\n1.3.0|1.1.2-rc.2|0\n0.2.2|<0.3.2 || 1.2.x|1\n0.0.0|>=1.3.2|0\n2.2.1|>=2.3|0\n1.2.1-rc.2|^2.3 || 1.0.x|0\n2.1.0|2.1.1 || 2.0.x|0\n0.0.1|2.3|0\n0.0.2|>2.1.1 || 1.3.x|0\n0.2.0-rc.1|~1|0\n2.3.0|<0.1.2|0\n1.0.2|1.0.0 || 1.2.x|0\n0.1.1|<0.2|1\n0.3.1|>=0|1\n1.0.0|<0.1 || 0.2.x|0\n1.1.2|~1 || 0.2.x|1\n1.3.0|<=1|1\n2.1.3|<=1.0|0\n1.1.0|>0.3.1 || 2.0.x|1\n1.1.1-rc.1|>=0.2 || 1.1.x|0\n2.0.3|<1.3.2 || 0.3.x|0\n2.2.1|~1.2|0\n1.2.0|<=0.0.0-rc.1|0\n0.3.0|<1.2.0 || 0.3.x|1\n"
}

fn bad_versions() -> str {
    ret "1.2 1.2.3.4 01.2.3 1.2.3-01 1.2.3- 1.2.3+ 1.2.3-a..b a.b.c 1.2.3-a+ 1.2.3-rc.1+b_c"
}

fn bad_ranges() -> str {
    ret "~1-rc.2|1.x.3|1.2.3 -|- 2.0.0|>=1.2.3 - 2.0.0|1.2.3 -2.0.0|1.2.3 - 2.0.0 - 3.0.0|x.2|01.2.3|1.2.3-01|>|^"
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: every version in the chain parses and formats back to itself; the pairs order.
    var parsed: [16]semver.Version = zero
    var count = 0usize
    var it = words(chain(), " ")
    while true {
        let (word, more) = str.split_next(&it)
        if !more { break }
        let (v, parse_error) = semver.parse(word)
        if parse_error != ok { os.exit(1i32) }
        var out: [64]u8 = zero
        let (n, format_error) = semver.format(v, out[..])
        if format_error != ok || !str.eq(out[..n], word) { os.exit(2i32) }
        parsed[count] = v
        count += 1usize
    }
    if count != 16usize { os.exit(3i32) }
    var i = 0usize
    while i < count {
        if semver.cmp(parsed[i], parsed[i]) != 0i32 { os.exit(4i32) }
        var j = i + 1usize
        while j < count {
            if semver.cmp(parsed[i], parsed[j]) >= 0i32 { os.exit(5i32) }
            if semver.cmp(parsed[j], parsed[i]) <= 0i32 { os.exit(6i32) }
            j += 1usize
        }
        i += 1usize
    }

    // 2: fields, build metadata carried but ignored by `cmp`, and a `v` prefix.
    let (full, full_error) = semver.parse("v1.2.3-rc.1+build.5")
    if full_error != ok { os.exit(7i32) }
    if full.major != 1u64 || full.minor != 2u64 || full.patch != 3u64 { os.exit(8i32) }
    if !str.eq(full.prerelease, "rc.1") || !str.eq(full.build, "build.5") { os.exit(9i32) }
    let (other, other_error) = semver.parse("1.2.3-rc.1+other")
    if other_error != ok || semver.cmp(full, other) != 0i32 { os.exit(10i32) }
    var small: [8]u8 = zero
    let (written, small_error) = semver.format(full, small[..])
    if small_error != semver.TooSmall { os.exit(11i32) }
    let (big, big_error) = semver.parse("18446744073709551615.0.0")
    if big_error != ok || big.major != 18446744073709551615u64 { os.exit(12i32) }
    let (huge_pre, huge_error) = semver.parse("1.0.0-99999999999999999999")
    if huge_error != ok { os.exit(13i32) }
    let (small_pre, small_pre_error) = semver.parse("1.0.0-9")
    if small_pre_error != ok || semver.cmp(small_pre, huge_pre) >= 0i32 { os.exit(14i32) }

    // 3: refusals.
    var bad = words(bad_versions(), " ")
    while true {
        let (word, more) = str.split_next(&bad)
        if !more { break }
        let (v, parse_error) = semver.parse(word)
        if parse_error != semver.Invalid { os.exit(15i32) }
    }
    let (one, one_error) = semver.parse("1.0.0")
    if one_error != ok { os.exit(16i32) }
    var bad_r = words(bad_ranges(), "|")
    while true {
        let (range, more) = str.split_next(&bad_r)
        if !more { break }
        let (matched, range_error) = semver.satisfies(one, range)
        if range_error != semver.Invalid { os.exit(17i32) }
    }

    // 4: `satisfies` against node.
    var lines = str.lines(cases())
    var index = 0usize
    while true {
        let (line, more) = str.split_next(&lines)
        if !more { break }
        if line.len == 0usize { continue }
        let (version_text, rest, has_rest) = str.split_once(line, "|")
        let (bar_at, has_expect) = str.rfind(rest, "|")
        if !has_rest || !has_expect { os.exit(18i32) }
        let range = rest[0usize..bar_at]
        let expect = rest[bar_at + 1usize..rest.len]
        let (v, parse_error) = semver.parse(version_text)
        if parse_error != ok { os.exit(19i32) }
        let (matched, range_error) = semver.satisfies(v, range)
        if range_error != ok {
            try io.print("range error at case ")
            try print_index(index)
            os.exit(20i32)
        }
        let want = expect[0usize] == 49u8
        if matched != want {
            try io.print("mismatch at case ")
            try print_index(index)
            os.exit(21i32)
        }
        index += 1usize
    }
    if index != 168usize { os.exit(22i32) }

    try io.print("fmt semver ok\n")
    ret ok
}

fn words(text: str, separator: str) -> str.Split {
    let (it, split_error) = str.split(text, separator)
    ret it
}

fn print_index(index: usize) -> err {
    var digits: [24]u8 = zero
    var n = 0usize
    var v = index
    while true {
        digits[n] = 48u8 + u8(v % 10usize)
        n += 1usize
        v = v / 10usize
        if v == 0usize { break }
    }
    while n > 0usize {
        n -= 1usize
        try io.print(digits[n..n + 1usize])
    }
    ret io.print("\n")
}
