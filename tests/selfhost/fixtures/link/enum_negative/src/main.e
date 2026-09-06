// A negative enum member is stored as its backing integer's two's complement at
// the backing width, so it compares, matches and orders like the integer it is.
// Auto-increment walks up through zero from a negative member.

error Failed

type Signed = enum i32 {
    Under = 0i32 - 3i32,
    Next,
    Also,
    Middle,
    Over = 5i32,
}

type Tiny = enum i8 {
    Least = 0i8 - 127i8 - 1i8,
    Minus = 0i8 - 1i8,
    None,
    Most = 127i8,
}

type Wide = enum i64 {
    Deep = 0i64 - 9223372036854775807i64 - 1i64,
    High = 9223372036854775807i64,
}

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn classify(s: Signed) -> i64 {
    switch s {
    case .Under:
        ret 10i64
    case .Middle:
        ret 20i64
    default:
        ret 30i64
    }
}

fn main() -> err {
    let under = Signed.Under
    let over = Signed.Over
    let middle = Signed.Middle
    if !(under < over) { ret Failed }
    if over < under { ret Failed }
    if !(under < middle) { ret Failed }
    if !(middle < over) { ret Failed }
    if under == over { ret Failed }
    if !(under == Signed.Under) { ret Failed }
    // -3, -2, -1, 0: `Also` is -1 and `Middle` is 0.
    if Signed.Also == Signed.Middle { ret Failed }
    if !(Signed.Also < Signed.Middle) { ret Failed }
    if !(Signed.Next < Signed.Also) { ret Failed }
    if classify(under) != 10i64 { ret Failed }
    if classify(middle) != 20i64 { ret Failed }
    if classify(over) != 30i64 { ret Failed }
    // Both extremes of the narrowest and the widest signed backing type.
    let least = Tiny.Least
    let most = Tiny.Most
    let minus = Tiny.Minus
    if !(least < minus) { ret Failed }
    if !(minus < Tiny.None) { ret Failed }
    if !(Tiny.None < most) { ret Failed }
    if most < least { ret Failed }
    if least == most { ret Failed }
    let deep = Wide.Deep
    let high = Wide.High
    if !(deep < high) { ret Failed }
    if high < deep { ret Failed }
    // Spec section 9 rule 4 supplies `cmp`, which orders through the same path.
    if order[Signed](under, over) != 0i32 - 1i32 { ret Failed }
    if order[Signed](over, under) != 1i32 { ret Failed }
    if order[Signed](under, under) != 0i32 { ret Failed }
    if order[Tiny](least, most) != 0i32 - 1i32 { ret Failed }
    if order[Tiny](most, least) != 1i32 { ret Failed }
    if order[Wide](deep, high) != 0i32 - 1i32 { ret Failed }
    if order[Wide](high, deep) != 1i32 { ret Failed }
    ret ok
}
