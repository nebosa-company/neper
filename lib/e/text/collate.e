// Locale-independent text ordering. Code-point order decodes valid UTF-8 and treats
// each malformed byte as U+FFFD, matching the lossy iterator contract. Natural order
// additionally compares ASCII digit runs by magnitude without integer conversion;
// case-insensitive mode folds ASCII only, leaving locale/Unicode folding to locale.

use e.text.utf8

type Options = struct { case_sensitive: bool, numeric: bool }

fn codepoint_cmp(a: str, b: str) -> i32 {
    var left = utf8.iterator(a)
    var right = utf8.iterator(b)
    while true {
        let (ac, has_a) = utf8.iterator_next(&left)
        let (bc, has_b) = utf8.iterator_next(&right)
        if !has_a || !has_b {
            if has_a { ret 1i32 }
            if has_b { ret -1i32 }
            ret 0i32
        }
        if ac < bc { ret -1i32 }
        if ac > bc { ret 1i32 }
    }
}

fn natural_cmp(a: str, b: str, options: Options) -> i32 {
    var left = 0usize
    var right = 0usize
    while left < a.len && right < b.len {
        let a_digit = a[left] >= 48u8 && a[left] <= 57u8
        let b_digit = b[right] >= 48u8 && b[right] <= 57u8
        if options.numeric && a_digit && b_digit {
            let a_start = left
            let b_start = right
            while left < a.len && a[left] >= 48u8 && a[left] <= 57u8 { left += 1usize }
            while right < b.len && b[right] >= 48u8 && b[right] <= 57u8 { right += 1usize }
            var a_number = a_start
            var b_number = b_start
            while a_number < left && a[a_number] == 48u8 { a_number += 1usize }
            while b_number < right && b[b_number] == 48u8 { b_number += 1usize }
            let a_length = left - a_number
            let b_length = right - b_number
            if a_length < b_length { ret -1i32 }
            if a_length > b_length { ret 1i32 }
            var digit = 0usize
            while digit < a_length {
                if a[a_number + digit] < b[b_number + digit] { ret -1i32 }
                if a[a_number + digit] > b[b_number + digit] { ret 1i32 }
                digit += 1usize
            }
            let a_run = left - a_start
            let b_run = right - b_start
            if a_run < b_run { ret -1i32 }
            if a_run > b_run { ret 1i32 }
            continue
        }
        let (decoded_a, error_a) = utf8.decode(a, left)
        let (decoded_b, error_b) = utf8.decode(b, right)
        var ac = 65533u32
        var bc = 65533u32
        var a_width = 1usize
        var b_width = 1usize
        if error_a == ok {
            ac = decoded_a.scalar
            a_width = usize(decoded_a.width)
        }
        if error_b == ok {
            bc = decoded_b.scalar
            b_width = usize(decoded_b.width)
        }
        if !options.case_sensitive {
            if ac >= 65u32 && ac <= 90u32 { ac += 32u32 }
            if bc >= 65u32 && bc <= 90u32 { bc += 32u32 }
        }
        if ac < bc { ret -1i32 }
        if ac > bc { ret 1i32 }
        left += a_width
        right += b_width
    }
    if left < a.len { ret 1i32 }
    if right < b.len { ret -1i32 }
    ret 0i32
}

// The collation comparison: -1, 0 or 1 for `a` against `b` under `options` (the
// natural order with digit runs by magnitude when `numeric`, ASCII case folded when
// not `case_sensitive`); equal under the options, the two are ordered by code point
// so the order stays total. ponytail: this is the module's locale-independent
// ordering, not UCA weights; `e.text.locale` is where a tailoring would live.
fn compare(a: str, b: str, options: Options) -> i32 {
    let primary = natural_cmp(a, b, options)
    if primary != 0i32 { ret primary }
    ret codepoint_cmp(a, b)
}
