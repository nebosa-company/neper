// Line breaking over bytes in caller storage: words are runs of bytes other
// than space, a line is the byte range from its first word to its last, and
// both breakers answer lines as (start, end) pairs. `greedy` fills each line
// as far as `width` allows; `optimal` is Knuth's minimum-raggedness dynamic
// programme (the sum over all lines but the last of the squared slack); a
// word longer than `width` stands alone on its line. `justify` spreads a
// line's words to exactly `width` columns, the extra spaces from the left.

error TooSmall
error Invalid

// Word bounds as (start, end) pairs; `bounds.len >= 2 * count`.
fn words(text: str, bounds: []usize) -> (usize, err) {
    var count = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 32u8 {
            i += 1usize
        } else {
            let start = i
            while i < text.len && text[i] != 32u8 { i += 1usize }
            if 2usize * count + 1usize >= bounds.len { ret (count, TooSmall) }
            bounds[2usize * count] = start
            bounds[2usize * count + 1usize] = i
            count += 1usize
        }
    }
    ret (count, ok)
}

// Greedy filling; `lines.len >= 2 * count`, `scratch.len >= 2 * words`.
fn greedy(text: str, width: usize, lines: []usize, scratch: []usize) -> (usize, err) {
    if width == 0usize { ret (0usize, Invalid) }
    let (count, split_error) = words(text, scratch)
    if split_error != ok { ret (0usize, split_error) }
    var line = 0usize
    var w = 0usize
    while w < count {
        let start = scratch[2usize * w]
        var end = scratch[2usize * w + 1usize]
        w += 1usize
        while w < count && scratch[2usize * w + 1usize] - start <= width {
            end = scratch[2usize * w + 1usize]
            w += 1usize
        }
        if 2usize * line + 1usize >= lines.len { ret (line, TooSmall) }
        lines[2usize * line] = start
        lines[2usize * line + 1usize] = end
        line += 1usize
    }
    ret (line, ok)
}

// The Knuth minimum-raggedness break: `lines.len >= 2 * count` and
// `scratch.len >= 4 * words + 2`.
fn optimal(text: str, width: usize, lines: []usize, scratch: []usize) -> (usize, err) {
    if width == 0usize { ret (0usize, Invalid) }
    let (count, split_error) = words(text, scratch)
    if split_error != ok { ret (0usize, split_error) }
    if scratch.len < 4usize * count + 2usize { ret (0usize, TooSmall) }
    var bounds = scratch[..2usize * count]
    var cost = scratch[2usize * count..3usize * count + 1usize]
    var parent = scratch[3usize * count + 1usize..4usize * count + 2usize]
    let unreachable_cost = 0usize -% 1usize
    cost[0usize] = 0usize
    var j = 1usize
    while j <= count {
        cost[j] = unreachable_cost
        parent[j] = j - 1usize
        // The line holds words i..j; try every start i.
        var i = j
        while i > 0usize {
            i -= 1usize
            let length = bounds[2usize * (j - 1usize) + 1usize] - bounds[2usize * i]
            if length > width && i + 1usize != j { i = 0usize } else if cost[i] != unreachable_cost {
                var slack = 0usize
                if length < width && j != count { slack = (width - length) * (width - length) }
                var total = cost[i] + slack
                if length > width { total = cost[i] + width * width * (length - width) }
                if total < cost[j] {
                    cost[j] = total
                    parent[j] = i
                }
            }
        }
        j += 1usize
    }
    // Count the lines back from the end, then fill them forward.
    var line_count = 0usize
    j = count
    while j > 0usize {
        j = parent[j]
        line_count += 1usize
    }
    if lines.len < 2usize * line_count { ret (line_count, TooSmall) }
    var line = line_count
    j = count
    while j > 0usize {
        let i = parent[j]
        line -= 1usize
        lines[2usize * line] = bounds[2usize * i]
        lines[2usize * line + 1usize] = bounds[2usize * (j - 1usize) + 1usize]
        j = i
    }
    ret (line_count, ok)
}

// Spread `line`'s words to `width` columns; a single word is left as is.
// `out.len >= width` (or the line's length when longer), `scratch.len >= 2 * words`.
fn justify(line: str, width: usize, out: []u8, scratch: []usize) -> (str, err) {
    let (count, split_error) = words(line, scratch)
    if split_error != ok { ret ("", split_error) }
    var letters = 0usize
    var w = 0usize
    while w < count {
        letters += scratch[2usize * w + 1usize] - scratch[2usize * w]
        w += 1usize
    }
    if count < 2usize || letters + (count - 1usize) >= width {
        // Nothing to spread: the words with single spaces.
        if count == 0usize { ret ("", ok) }
        if out.len < letters + count - 1usize { ret ("", TooSmall) }
        var n = 0usize
        w = 0usize
        while w < count {
            if w > 0usize {
                out[n] = 32u8
                n += 1usize
            }
            var i = scratch[2usize * w]
            while i < scratch[2usize * w + 1usize] {
                out[n] = line[i]
                n += 1usize
                i += 1usize
            }
            w += 1usize
        }
        ret (out[..n], ok)
    }
    if out.len < width { ret ("", TooSmall) }
    let gaps = count - 1usize
    let spaces = width - letters
    let each = spaces / gaps
    let extra = spaces % gaps
    var n = 0usize
    w = 0usize
    while w < count {
        if w > 0usize {
            var pad = each
            if w <= extra { pad += 1usize }
            while pad > 0usize {
                out[n] = 32u8
                n += 1usize
                pad -= 1usize
            }
        }
        var i = scratch[2usize * w]
        while i < scratch[2usize * w + 1usize] {
            out[n] = line[i]
            n += 1usize
            i += 1usize
        }
        w += 1usize
    }
    ret (out[..n], ok)
}
