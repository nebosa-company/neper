// `answer` is long enough -- in text and in NIR -- to stay out of the inlining oracle
// (D207), so `main` holds only a signature edge to it; `tiny` is inlined into `main`,
// which gives `main` a body edge to it.
fn answer(x: i32) -> i32 {
    let a = x + 0i32
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
    let xx = w + 0i32
    let y = xx + 0i32
    ret y + 4i32
}

fn tiny(x: i32) -> i32 { ret x + 0i32 }
