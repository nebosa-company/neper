use e.mem

error Failed

type Pair = struct {
    left: usize,
    right: usize,
}

fn split() -> (usize, bool) {
    ret (7usize, true)
}

fn pair() -> Pair {
    ret Pair { left: 11usize, right: 13usize }
}

fn sum7(a: usize, b: usize, c: usize, d: usize, e: usize, f: usize, g: usize) -> usize {
    ret a + b + c + d + e + f + g
}

fn main(a: *mem.Arena, args: []str) -> err {
    var number = 0usize
    var present = false
    (number, present) = split()
    if number != 7usize || !present { ret Failed }

    let made = pair()
    if made.left != 11usize || made.right != 13usize { ret Failed }
    if sum7(1usize, 2usize, 3usize, 4usize, 5usize, 6usize, 7usize) != 28usize { ret Failed }

    let escaped = "A\nB"
    if escaped.len != 3usize || escaped[0usize] != 65u8 || escaped[1usize] != 10u8 || escaped[2usize] != 66u8 { ret Failed }
    let raw = r#"x\ny"#
    if raw.len != 4usize || raw[1usize] != 92u8 { ret Failed }

    let values = [4]usize { 2usize, 3usize, 5usize, 7usize }
    var total = 0usize
    for index, value in values {
        total = total + index + value
    }
    let middle = values[1usize..3usize]
    for value in middle {
        total = total + value
    }
    for value in 1usize..4usize {
        total = total + value
    }
    if total != 37usize { ret Failed }
    ret ok
}
