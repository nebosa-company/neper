// Long enough in source and NIR to stay out of the inlining oracle (D207), so each caller
// holds a signature edge to its function and not a body edge.
fn fixed() -> i64 {
    let a = 0i64 + 0i64
    let b = a + 0i64
    let c = b + 0i64
    let d = c + 0i64
    let e = d + 0i64
    let f = e + 0i64
    let g = f + 0i64
    let h = g + 0i64
    let i = h + 0i64
    let j = i + 0i64
    let k = j + 0i64
    let l = k + 0i64
    let m = l + 0i64
    let n = m + 0i64
    let o = n + 0i64
    let p = o + 0i64
    let q = p + 0i64
    let r = q + 0i64
    let s = r + 0i64
    let t = s + 0i64
    let u = t + 0i64
    let v = u + 0i64
    let w = v + 0i64
    ret w + 3i64
}

fn widened() -> i32 {
    let a = 0i32 + 0i32
    let b = a + 0i32
    let c = b + 0i32
    let d = c + 0i32
    let e = d + 0i32
    let f = e + 0i32
    let g = f + 0i32
    let h = g + 0i32
    let i = h + 0i32
    let j = i + 0i32
    let k = j + 0i32
    let l = k + 0i32
    let m = l + 0i32
    let n = m + 0i32
    let o = n + 0i32
    let p = o + 0i32
    let q = p + 0i32
    let r = q + 0i32
    let s = r + 0i32
    let t = s + 0i32
    let u = t + 0i32
    let v = u + 0i32
    let w = v + 0i32
    ret w + 4i32
}
