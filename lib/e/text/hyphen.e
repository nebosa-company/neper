// Liang's hyphenation over a caller pattern table: `break_points` answers
// the positions a word may break at, applying the patterns (one `str` of
// space-separated TeX patterns such as `.hy3ph 1na n2at`, digits marking the
// inter-letter levels, odd meaning break) to `.word.`, keeping the odd
// levels that leave `left_min` letters before and `right_min` after, unless
// the word is listed in `exceptions` (space-separated hyphenated words such
// as `hy-phen-a-tion`, whose hyphens are then the whole answer); `hyphenate`
// writes the word with a hyphen at each break; `english` is a built-in
// subset of the en_US patterns. ASCII letters are folded to lowercase for
// matching; a word longer than 64 bytes is refused.

error Invalid
error TooSmall
error TooLong

const MAX_WORD: usize = 64usize

// The en_US patterns reaching hyphenation, computer, algorithm,
// concatenation, programming, dictionary, information, beautiful,
// philosophy, university, project and associate.
fn english() -> str {
    ret ".1co .3di2c1t .a2s1s .a4l1g4 .as1so .as9s8o9c8i8a8te. .asso1ci .asso3c2i1a .co2n .co4m1p .dic1t2io5 .in1 .in3f .ph4il2 .philo2so .philos2oph .philos4op .pr2 .pr8o8j8e8ct. .pro1gr .pro1je .pro5j .program1m .proje2c1t 1ca 1ci 1co 1fo 1go 1gr 1je 1ma 1na 1phy 1so 1t2io 1ty 2a2r 2c1t 2i1a 2io 2ith 2iv 2oph 2ss 3c2i1a 3di2c1t 3fu 4h1m 4l1g4 4m1p 4rs2 4te. 4u1t2i 5los5o1phy 5pute a1t2io a2ss atio2n co2n e1na e2c1t e4r1s2 fo2r h4il2 he1na4 he2n hen5at hy3ph i2c1t io1n1a io2n ive4r1s2 l1go3 lo2so los2oph los4op m1m n1ca n2a2r n2at n3f o1ci o1gr o1n1a o2n o2so o4m1p o5j on1c or1m phe2n pr2 pu2t put3er r1m r1ma r1si s2oph s4op s5o1phy te1na tif2 tio2n u1ni un2i3v ve4r1s2"
}

fn fold(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// The next space-separated token of `s` from `at`: (start, end, next).
fn token(s: str, at: usize) -> (usize, usize, usize) {
    var start = at
    while start < s.len && s[start] == 32u8 { start += 1usize }
    var end = start
    while end < s.len && s[end] != 32u8 { end += 1usize }
    ret (start, end, end)
}

// Does the exception `e` (hyphenated) spell the folded `w` (dotted)?
fn exception_matches(e: str, w: []const u8) -> bool {
    var i = 0usize
    var k = 1usize
    while i < e.len {
        if e[i] != 45u8 {
            if k + 1usize >= w.len || fold(e[i]) != w[k] { ret false }
            k += 1usize
        }
        i += 1usize
    }
    ret k + 1usize == w.len
}

// The break positions of `word` in ascending order (a position `p` means
// between `word[p - 1]` and `word[p]`); answers how many.
fn break_points(patterns: str, exceptions: str, word: str, left_min: usize, right_min: usize, out: []usize) -> (usize, err) {
    if word.len == 0usize { ret (0usize, Invalid) }
    if word.len > MAX_WORD { ret (0usize, TooLong) }
    var w: [66]u8 = zero
    w[0usize] = 46u8
    var i = 0usize
    while i < word.len {
        w[i + 1usize] = fold(word[i])
        i += 1usize
    }
    w[word.len + 1usize] = 46u8
    let dotted = w[..word.len + 2usize]

    var at = 0usize
    while at < exceptions.len {
        let (start, end, next_at) = token(exceptions, at)
        if start == end { break }
        at = next_at
        let e = exceptions[start..end]
        if !exception_matches(e, dotted) { continue }
        var count = 0usize
        var letters = 0usize
        i = 0usize
        while i < e.len {
            if e[i] == 45u8 {
                if count >= out.len { ret (count, TooSmall) }
                out[count] = letters
                count += 1usize
            } else {
                letters += 1usize
            }
            i += 1usize
        }
        ret (count, ok)
    }

    // ponytail: every pattern is tried at every position, O(P * W * L);
    // a trie over the patterns if tables grow past a few thousand.
    var levels: [67]u8 = zero
    at = 0usize
    while at < patterns.len {
        let (start, end, next_at) = token(patterns, at)
        if start == end { break }
        at = next_at
        let p = patterns[start..end]
        var letters = 0usize
        i = 0usize
        while i < p.len {
            if !is_digit(p[i]) { letters += 1usize }
            i += 1usize
        }
        if letters == 0usize || letters > dotted.len { continue }
        var pos = 0usize
        while pos + letters <= dotted.len {
            var k = 0usize
            var matched = true
            i = 0usize
            while i < p.len {
                if !is_digit(p[i]) {
                    if p[i] != dotted[pos + k] {
                        matched = false
                        break
                    }
                    k += 1usize
                }
                i += 1usize
            }
            if matched {
                k = 0usize
                i = 0usize
                while i < p.len {
                    if is_digit(p[i]) {
                        let level = p[i] - 48u8
                        if level > levels[pos + k] { levels[pos + k] = level }
                    } else {
                        k += 1usize
                    }
                    i += 1usize
                }
            }
            pos += 1usize
        }
    }

    var count = 0usize
    var j = 2usize
    while j + 1usize < dotted.len {
        let p = j - 1usize
        if levels[j] % 2u8 == 1u8 && p >= left_min && word.len - p >= right_min {
            if count >= out.len { ret (count, TooSmall) }
            out[count] = p
            count += 1usize
        }
        j += 1usize
    }
    ret (count, ok)
}

// `word` with `hyphen` at each break, into `out`; answers the length.
fn hyphenate(patterns: str, exceptions: str, word: str, left_min: usize, right_min: usize, hyphen: u8, out: []u8) -> (usize, err) {
    var points: [64]usize = zero
    let (count, e) = break_points(patterns, exceptions, word, left_min, right_min, points[..])
    if e != ok { ret (0usize, e) }
    if out.len < word.len + count { ret (0usize, TooSmall) }
    var n = 0usize
    var next_point = 0usize
    var i = 0usize
    while i < word.len {
        if next_point < count && points[next_point] == i {
            out[n] = hyphen
            n += 1usize
            next_point += 1usize
        }
        out[n] = word[i]
        n += 1usize
        i += 1usize
    }
    ret (n, ok)
}
