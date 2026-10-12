// POSIX shell word splitting and quoting, the semantics of Python's `shlex.split` (posix mode,
// no comment character) and `shlex.quote`: words are separated by ASCII whitespace; `'...'`
// is literal; inside `"..."` a backslash escapes only `"` and `\`; outside quotes a backslash
// escapes the next byte; adjacent quoted and bare pieces join into one word; `''` is an
// empty word. No variable, tilde, glob or command expansion happens here.
//
// The caller owns both buffers: words are written back to back into `buf`, and
// `words[i]` is a slice of `buf`, so they live as long as `buf` does.

error Unterminated
error TooSmall

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

// Returns the number of words. `Unterminated` for an open quote or a trailing backslash;
// `TooSmall` when `buf` or `words` cannot hold the result.
fn split(input: str, buf: []u8, words: []str) -> (usize, err) {
    var n = 0usize
    var count = 0usize
    var i = 0usize
    while i < input.len {
        while i < input.len && is_space(input[i]) { i += 1usize }
        if i >= input.len { break }
        let start = n
        while i < input.len && !is_space(input[i]) {
            let c = input[i]
            if c == 39u8 {
                i += 1usize
                while i < input.len && input[i] != 39u8 {
                    if n >= buf.len { ret (0usize, TooSmall) }
                    buf[n] = input[i]
                    n += 1usize
                    i += 1usize
                }
                if i >= input.len { ret (0usize, Unterminated) }
                i += 1usize
            } else if c == 34u8 {
                i += 1usize
                while i < input.len && input[i] != 34u8 {
                    var b = input[i]
                    if b == 92u8 && i + 1usize < input.len && (input[i + 1usize] == 34u8 || input[i + 1usize] == 92u8) {
                        i += 1usize
                        b = input[i]
                    }
                    if n >= buf.len { ret (0usize, TooSmall) }
                    buf[n] = b
                    n += 1usize
                    i += 1usize
                }
                if i >= input.len { ret (0usize, Unterminated) }
                i += 1usize
            } else if c == 92u8 {
                if i + 1usize >= input.len { ret (0usize, Unterminated) }
                if n >= buf.len { ret (0usize, TooSmall) }
                buf[n] = input[i + 1usize]
                n += 1usize
                i += 2usize
            } else {
                if n >= buf.len { ret (0usize, TooSmall) }
                buf[n] = c
                n += 1usize
                i += 1usize
            }
        }
        if count >= words.len { ret (0usize, TooSmall) }
        words[count] = buf[start..n]
        count += 1usize
    }
    ret (count, ok)
}

fn is_safe(c: u8) -> bool {
    if c >= 97u8 && c <= 122u8 { ret true }
    if c >= 65u8 && c <= 90u8 { ret true }
    if c >= 48u8 && c <= 57u8 { ret true }
    ret c == 95u8 || c == 64u8 || c == 37u8 || c == 43u8 || c == 61u8 || c == 58u8 || c == 44u8 || c == 46u8 || c == 47u8 || c == 45u8
}

// `shlex.quote`: unchanged when every byte is safe, `''` when empty, otherwise single
// quoted with each embedded `'` written as `'"'"'`.
fn quote(word: str, dst: []u8) -> (str, err) {
    var safe = word.len > 0usize
    var i = 0usize
    while i < word.len {
        if !is_safe(word[i]) { safe = false }
        i += 1usize
    }
    var n = 0usize
    if safe {
        if word.len > dst.len { ret ("", TooSmall) }
        i = 0usize
        while i < word.len {
            dst[i] = word[i]
            i += 1usize
        }
        ret (dst[..word.len], ok)
    }
    if dst.len < 2usize { ret ("", TooSmall) }
    dst[0usize] = 39u8
    n = 1usize
    i = 0usize
    while i < word.len {
        if word[i] == 39u8 {
            if n + 5usize > dst.len { ret ("", TooSmall) }
            dst[n] = 39u8
            dst[n + 1usize] = 34u8
            dst[n + 2usize] = 39u8
            dst[n + 3usize] = 34u8
            dst[n + 4usize] = 39u8
            n += 5usize
        } else {
            if n >= dst.len { ret ("", TooSmall) }
            dst[n] = word[i]
            n += 1usize
        }
        i += 1usize
    }
    if n >= dst.len { ret ("", TooSmall) }
    dst[n] = 39u8
    n += 1usize
    ret (dst[..n], ok)
}

// `shlex.join`: each word quoted, joined by one space.
fn join(words: []const str, dst: []u8) -> (str, err) {
    var n = 0usize
    var k = 0usize
    while k < words.len {
        if k > 0usize {
            if n >= dst.len { ret ("", TooSmall) }
            dst[n] = 32u8
            n += 1usize
        }
        let (q, q_error) = quote(words[k], dst[n..dst.len])
        if q_error != ok { ret ("", q_error) }
        n += q.len
        k += 1usize
    }
    ret (dst[..n], ok)
}
