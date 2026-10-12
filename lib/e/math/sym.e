// Symbolic mathematics over exact rationals: expression trees in an arena pool, a parser and
// printer, numeric evaluation over `e.math`, differentiation, integration and equation
// solving. The set is deliberately small -- SymPy's core in miniature -- and simplification is
// only what the smart constructors do (fold constants, drop identities, merge a numeric
// factor), so two equal expressions need not print alike; compare them by evaluating.
//
// Rationals are `i64` pairs; a product that would pass 2^62 sets `failed` on the pool
// instead of wrapping, and every entry point that builds reports it as `TooLarge`.
//
// What it does: + - * / ^ with integer and rational exponents, sin cos tan exp ln atan and
// sqrt (a power of 1/2); `diff` of anything it can build; `integrate` of polynomials, sums,
// constant multiples, powers and elementary functions of a linear argument, 1/(a x + b), and
// polynomial times exp, sin or cos of a linear argument; `solve` of polynomials with rational
// coefficients (exact rational roots by the rational-root theorem, quadratic formula for the
// rest, real roots only). What it does not: factoring, trigonometric identities, definite
// integrals with symbolic limits, systems, inequalities, limits and series.
use e.math
use e.mem
use e.str

type Q = struct { n: i64, d: i64 }
type Node = struct { kind: u8, f: u8, a: u32, b: u32, n: i64, d: i64 }
type Pool = struct { nodes: []Node, count: u32, names: []str, name_count: u32, failed: bool }
type Poly = struct { c: [20]Q, deg: i32 }
error TooLarge
error Syntax
error Unsupported

const K_NUM: u8 = 0u8
const K_SYM: u8 = 1u8
const K_ADD: u8 = 2u8
const K_MUL: u8 = 3u8
const K_POW: u8 = 4u8
const K_FUN: u8 = 5u8
const F_SIN: u8 = 0u8
const F_COS: u8 = 1u8
const F_TAN: u8 = 2u8
const F_EXP: u8 = 3u8
const F_LN: u8 = 4u8
const F_ATAN: u8 = 5u8
const LIMIT: i64 = 2147483648i64

// ---- the pool --------------------------------------------------------------------------

fn pool(a: *mem.Arena, capacity: usize) -> (Pool, err) {
    var p: Pool = zero
    let (nodes, ne) = mem.alloc[Node](a, capacity + 1usize)
    if ne != ok { ret (p, ne) }
    let (names, me) = mem.alloc[str](a, 32usize)
    if me != ok { ret (p, me) }
    p.nodes = nodes[0usize..capacity]
    p.names = names[0usize..32usize]
    ret (p, ok)
}

fn mk(p: *Pool, kind: u8, f: u8, a: u32, b: u32, n: i64, d: i64) -> u32 {
    if usize(p.count) >= p.nodes.len {
        p.failed = true
        ret 0u32
    }
    let at = p.count
    p.nodes[usize(at)] = Node{ kind: kind, f: f, a: a, b: b, n: n, d: d }
    p.count += 1u32
    ret at
}

fn abs64(v: i64) -> i64 {
    if v < 0i64 { ret 0i64 - v }
    ret v
}

fn gcd64(x: i64, y: i64) -> i64 {
    var a = abs64(x)
    var b = abs64(y)
    while b != 0i64 {
        let t = a % b
        a = b
        b = t
    }
    ret a
}

fn q(n: i64, d: i64) -> Q {
    var nn = n
    var dd = d
    if dd < 0i64 {
        nn = 0i64 - nn
        dd = 0i64 - dd
    }
    let g = gcd64(nn, dd)
    if g > 1i64 {
        nn = nn / g
        dd = dd / g
    }
    ret Q{ n: nn, d: dd }
}

fn big(p: *Pool, v: i64) -> bool {
    if abs64(v) >= LIMIT * LIMIT / 2i64 {
        p.failed = true
        ret true
    }
    ret false
}

fn q_add(p: *Pool, x: Q, y: Q) -> Q {
    if abs64(x.n) >= LIMIT || abs64(y.n) >= LIMIT || x.d >= LIMIT || y.d >= LIMIT {
        p.failed = true
        ret Q{ n: 0i64, d: 1i64 }
    }
    ret q(x.n * y.d + y.n * x.d, x.d * y.d)
}

fn q_mul(p: *Pool, x: Q, y: Q) -> Q {
    if abs64(x.n) >= LIMIT || abs64(y.n) >= LIMIT || x.d >= LIMIT || y.d >= LIMIT {
        p.failed = true
        ret Q{ n: 0i64, d: 1i64 }
    }
    ret q(x.n * y.n, x.d * y.d)
}

fn q_neg(x: Q) -> Q { ret Q{ n: 0i64 - x.n, d: x.d } }

fn q_inv(p: *Pool, x: Q) -> Q {
    if x.n == 0i64 {
        p.failed = true
        ret Q{ n: 0i64, d: 1i64 }
    }
    ret q(x.d, x.n)
}

fn q_zero() -> Q { ret Q{ n: 0i64, d: 1i64 } }
fn q_one() -> Q { ret Q{ n: 1i64, d: 1i64 } }

fn q_pow(p: *Pool, x: Q, e: i64) -> Q {
    var r = q_one()
    var i = 0i64
    var base = x
    var k = e
    if k < 0i64 {
        base = q_inv(p, x)
        k = 0i64 - k
    }
    while i < k {
        r = q_mul(p, r, base)
        i += 1i64
    }
    ret r
}

fn num(p: *Pool, n: i64, d: i64) -> u32 {
    let r = q(n, d)
    ret mk(p, K_NUM, 0u8, 0u32, 0u32, r.n, r.d)
}

fn int(p: *Pool, n: i64) -> u32 { ret mk(p, K_NUM, 0u8, 0u32, 0u32, n, 1i64) }

fn qnode(p: *Pool, v: Q) -> u32 { ret mk(p, K_NUM, 0u8, 0u32, 0u32, v.n, v.d) }

fn is_num(p: *Pool, e: u32) -> bool { ret p.nodes[usize(e)].kind == K_NUM }

fn q_of(p: *Pool, e: u32) -> Q { ret Q{ n: p.nodes[usize(e)].n, d: p.nodes[usize(e)].d } }

fn is_int(p: *Pool, e: u32) -> bool { ret p.nodes[usize(e)].kind == K_NUM && p.nodes[usize(e)].d == 1i64 }

fn is_value(p: *Pool, e: u32, n: i64) -> bool {
    ret p.nodes[usize(e)].kind == K_NUM && p.nodes[usize(e)].n == n && p.nodes[usize(e)].d == 1i64
}

// The symbol named `name`, reusing an existing one.
fn sym(p: *Pool, name: str) -> u32 {
    var i = 0u32
    while i < p.name_count {
        if str.eq(p.names[usize(i)], name) { break }
        i += 1u32
    }
    if i == p.name_count {
        if usize(i) >= p.names.len {
            p.failed = true
            ret 0u32
        }
        p.names[usize(i)] = name
        p.name_count += 1u32
    }
    // one node per use is fine; identity is the name index in `a`
    ret mk(p, K_SYM, 0u8, i, 0u32, 0i64, 1i64)
}

fn same(p: *Pool, x: u32, y: u32) -> bool {
    if x == y { ret true }
    let nx = p.nodes[usize(x)]
    let ny = p.nodes[usize(y)]
    if nx.kind != ny.kind { ret false }
    if nx.kind == K_NUM { ret nx.n == ny.n && nx.d == ny.d }
    if nx.kind == K_SYM { ret nx.a == ny.a }
    if nx.kind == K_FUN { ret nx.f == ny.f && same(p, nx.a, ny.a) }
    ret same(p, nx.a, ny.a) && same(p, nx.b, ny.b)
}

// ---- smart constructors -----------------------------------------------------------------

fn add(p: *Pool, x: u32, y: u32) -> u32 {
    if is_num(p, x) && is_num(p, y) { ret qnode(p, q_add(p, q_of(p, x), q_of(p, y))) }
    if is_value(p, x, 0i64) { ret y }
    if is_value(p, y, 0i64) { ret x }
    if same(p, x, y) { ret mul(p, int(p, 2i64), x) }
    // fold a numeric tail: (t + c1) + c2
    if is_num(p, y) && p.nodes[usize(x)].kind == K_ADD && is_num(p, p.nodes[usize(x)].b) {
        let c = q_add(p, q_of(p, p.nodes[usize(x)].b), q_of(p, y))
        ret add(p, p.nodes[usize(x)].a, qnode(p, c))
    }
    ret mk(p, K_ADD, 0u8, x, y, 0i64, 1i64)
}

fn mul(p: *Pool, x: u32, y: u32) -> u32 {
    if is_num(p, x) && is_num(p, y) { ret qnode(p, q_mul(p, q_of(p, x), q_of(p, y))) }
    if is_value(p, x, 0i64) || is_value(p, y, 0i64) { ret int(p, 0i64) }
    if is_value(p, x, 1i64) { ret y }
    if is_value(p, y, 1i64) { ret x }
    // a numeric factor goes first and merges with another
    if is_num(p, y) { ret mul(p, y, x) }
    if is_num(p, x) && p.nodes[usize(y)].kind == K_MUL && is_num(p, p.nodes[usize(y)].a) {
        let c = q_mul(p, q_of(p, x), q_of(p, p.nodes[usize(y)].a))
        ret mul(p, qnode(p, c), p.nodes[usize(y)].b)
    }
    if same(p, x, y) { ret pow(p, x, int(p, 2i64)) }
    // x * x^n and x^m * x^n with a numeric exponent
    let nx = p.nodes[usize(x)]
    let ny = p.nodes[usize(y)]
    if ny.kind == K_POW && is_num(p, ny.b) && same(p, x, ny.a) { ret pow(p, x, add(p, int(p, 1i64), ny.b)) }
    if nx.kind == K_POW && is_num(p, nx.b) && same(p, y, nx.a) { ret pow(p, y, add(p, int(p, 1i64), nx.b)) }
    if nx.kind == K_POW && ny.kind == K_POW && is_num(p, nx.b) && is_num(p, ny.b) && same(p, nx.a, ny.a) { ret pow(p, nx.a, add(p, nx.b, ny.b)) }
    ret mk(p, K_MUL, 0u8, x, y, 0i64, 1i64)
}

fn neg(p: *Pool, x: u32) -> u32 { ret mul(p, int(p, -1i64), x) }
fn sub(p: *Pool, x: u32, y: u32) -> u32 { ret add(p, x, neg(p, y)) }

fn pow(p: *Pool, x: u32, y: u32) -> u32 {
    if is_value(p, y, 0i64) { ret int(p, 1i64) }
    if is_value(p, y, 1i64) { ret x }
    if is_value(p, x, 1i64) { ret int(p, 1i64) }
    if is_num(p, x) && is_int(p, y) {
        let e = p.nodes[usize(y)].n
        if e >= -64i64 && e <= 64i64 && !(e < 0i64 && is_value(p, x, 0i64)) { ret qnode(p, q_pow(p, q_of(p, x), e)) }
    }
    // exact roots of a rational: (a/b)^(1/2) when both are squares
    if is_num(p, x) && is_num(p, y) && p.nodes[usize(y)].n == 1i64 && p.nodes[usize(y)].d == 2i64 {
        let v = q_of(p, x)
        if v.n >= 0i64 {
            let rn = isqrt(v.n)
            let rd = isqrt(v.d)
            if rn * rn == v.n && rd * rd == v.d { ret num(p, rn, rd) }
        }
    }
    let nx = p.nodes[usize(x)]
    // (a^m)^n = a^(m n) for an integer n
    if nx.kind == K_POW && is_num(p, nx.b) && is_int(p, y) { ret pow(p, nx.a, qnode(p, q_mul(p, q_of(p, nx.b), q_of(p, y)))) }
    ret mk(p, K_POW, 0u8, x, y, 0i64, 1i64)
}

fn div(p: *Pool, x: u32, y: u32) -> u32 { ret mul(p, x, pow(p, y, int(p, -1i64))) }

fn isqrt(v: i64) -> i64 {
    if v <= 0i64 { ret 0i64 }
    var r = i64(math.sqrt[f64](f64(v)))
    while r * r > v { r -= 1i64 }
    while (r + 1i64) * (r + 1i64) <= v { r += 1i64 }
    ret r
}

fn func(p: *Pool, f: u8, x: u32) -> u32 {
    if f == F_SIN && is_value(p, x, 0i64) { ret int(p, 0i64) }
    if f == F_COS && is_value(p, x, 0i64) { ret int(p, 1i64) }
    if f == F_TAN && is_value(p, x, 0i64) { ret int(p, 0i64) }
    if f == F_ATAN && is_value(p, x, 0i64) { ret int(p, 0i64) }
    if f == F_EXP && is_value(p, x, 0i64) { ret int(p, 1i64) }
    if f == F_LN && is_value(p, x, 1i64) { ret int(p, 0i64) }
    ret mk(p, K_FUN, f, x, 0u32, 0i64, 1i64)
}

// ---- analysis ---------------------------------------------------------------------------

// Whether symbol `s` (a name index) occurs in `e`.
fn has(p: *Pool, e: u32, s: u32) -> bool {
    let n = p.nodes[usize(e)]
    if n.kind == K_NUM { ret false }
    if n.kind == K_SYM { ret n.a == s }
    if n.kind == K_FUN { ret has(p, n.a, s) }
    ret has(p, n.a, s) || has(p, n.b, s)
}

// The name index of a symbol node, or 0xFFFFFFFF.
fn symbol_index(p: *Pool, e: u32) -> u32 {
    if p.nodes[usize(e)].kind == K_SYM { ret p.nodes[usize(e)].a }
    ret 4294967295u32
}

fn index_of(p: *Pool, name: str) -> u32 {
    var i = 0u32
    while i < p.name_count {
        if str.eq(p.names[usize(i)], name) { ret i }
        i += 1u32
    }
    ret 4294967295u32
}

// ---- parser -----------------------------------------------------------------------------

type Parser = struct { src: str, at: usize, pool: *Pool, bad: bool }

fn skip_blanks(s: *Parser) {
    while s.at < s.src.len && (s.src[s.at] == 32u8 || s.src[s.at] == 9u8) { s.at += 1usize }
}

fn peek(s: *Parser) -> u8 {
    skip_blanks(s)
    if s.at >= s.src.len { ret 0u8 }
    ret s.src[s.at]
}

fn is_alpha(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || c == 95u8 }
fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn parse_number(s: *Parser) -> u32 {
    var n = 0i64
    var d = 1i64
    var seen_point = false
    var digits = 0usize
    while s.at < s.src.len {
        let c = s.src[s.at]
        if is_digit(c) {
            if digits >= 15usize {
                s.bad = true
                ret 0u32
            }
            n = n * 10i64 + i64(c - 48u8)
            if seen_point { d = d * 10i64 }
            digits += 1usize
            s.at += 1usize
        } else if c == 46u8 && !seen_point {
            seen_point = true
            s.at += 1usize
        } else {
            break
        }
    }
    if digits == 0usize {
        s.bad = true
        ret 0u32
    }
    ret num(s.pool, n, d)
}

fn function_id(name: str) -> i32 {
    if str.eq(name, "sin") { ret 0i32 }
    if str.eq(name, "cos") { ret 1i32 }
    if str.eq(name, "tan") { ret 2i32 }
    if str.eq(name, "exp") { ret 3i32 }
    if str.eq(name, "ln") || str.eq(name, "log") { ret 4i32 }
    if str.eq(name, "atan") { ret 5i32 }
    if str.eq(name, "sqrt") { ret 6i32 }
    ret -1i32
}

fn parse_atom(s: *Parser, depth: u32) -> u32 {
    if depth > 200u32 {
        s.bad = true
        ret 0u32
    }
    let c = peek(s)
    if c == 40u8 {
        s.at += 1usize
        let inner = parse_sum(s, depth + 1u32)
        if peek(s) != 41u8 {
            s.bad = true
            ret 0u32
        }
        s.at += 1usize
        ret inner
    }
    if is_digit(c) || c == 46u8 { ret parse_number(s) }
    if is_alpha(c) {
        let start = s.at
        while s.at < s.src.len && (is_alpha(s.src[s.at]) || is_digit(s.src[s.at])) { s.at += 1usize }
        let name = s.src[start..s.at]
        let f = function_id(name)
        if f >= 0i32 && peek(s) == 40u8 {
            s.at += 1usize
            let arg = parse_sum(s, depth + 1u32)
            if peek(s) != 41u8 {
                s.bad = true
                ret 0u32
            }
            s.at += 1usize
            if f == 6i32 { ret pow(s.pool, arg, num(s.pool, 1i64, 2i64)) }
            ret func(s.pool, u8(f), arg)
        }
        ret sym(s.pool, name)
    }
    s.bad = true
    ret 0u32
}

// Unary minus binds looser than `^` (-x^2 is -(x^2)) and tighter than `*`.
fn parse_unary(s: *Parser, depth: u32) -> u32 {
    let c = peek(s)
    if c == 45u8 {
        s.at += 1usize
        ret neg(s.pool, parse_unary(s, depth + 1u32))
    }
    if c == 43u8 {
        s.at += 1usize
        ret parse_unary(s, depth + 1u32)
    }
    ret parse_power(s, depth)
}

fn parse_power(s: *Parser, depth: u32) -> u32 {
    let base = parse_atom(s, depth)
    skip_blanks(s)
    if s.at < s.src.len && s.src[s.at] == 94u8 {
        s.at += 1usize
        let e = parse_unary(s, depth + 1u32)
        ret pow(s.pool, base, e)
    }
    if s.at + 1usize < s.src.len && s.src[s.at] == 42u8 && s.src[s.at + 1usize] == 42u8 {
        s.at += 2usize
        let e = parse_unary(s, depth + 1u32)
        ret pow(s.pool, base, e)
    }
    ret base
}

fn parse_product(s: *Parser, depth: u32) -> u32 {
    var left = parse_unary(s, depth)
    while true {
        skip_blanks(s)
        if s.at >= s.src.len { break }
        let c = s.src[s.at]
        let double_star = c == 42u8 && s.at + 1usize < s.src.len && s.src[s.at + 1usize] == 42u8
        if c == 42u8 && !double_star {
            s.at += 1usize
            left = mul(s.pool, left, parse_unary(s, depth + 1u32))
        } else if c == 47u8 {
            s.at += 1usize
            left = div(s.pool, left, parse_unary(s, depth + 1u32))
        } else {
            break
        }
    }
    ret left
}

fn parse_sum(s: *Parser, depth: u32) -> u32 {
    var left = parse_product(s, depth)
    while true {
        let c = peek(s)
        if c == 43u8 {
            s.at += 1usize
            left = add(s.pool, left, parse_product(s, depth + 1u32))
        } else if c == 45u8 {
            s.at += 1usize
            left = sub(s.pool, left, parse_product(s, depth + 1u32))
        } else {
            break
        }
    }
    ret left
}

// `3*x^2 + sin(2*x) - 1/2`: numbers (decimals are exact), names, `+ - * / ^ **`, functions.
fn parse(p: *Pool, src: str) -> (u32, err) {
    var s = Parser{ src: src, at: 0usize, pool: p, bad: false }
    let e = parse_sum(&s, 0u32)
    if p.failed { ret (0u32, TooLarge) }
    if s.bad { ret (0u32, Syntax) }
    skip_blanks(&s)
    if s.at != src.len { ret (0u32, Syntax) }
    ret (e, ok)
}

// ---- printing ---------------------------------------------------------------------------

fn prec(p: *Pool, e: u32) -> u8 {
    let n = p.nodes[usize(e)]
    if n.kind == K_ADD { ret 1u8 }
    if n.kind == K_MUL { ret 2u8 }
    if n.kind == K_POW { ret 3u8 }
    if n.kind == K_NUM && (n.n < 0i64 || n.d != 1i64) { ret 1u8 }
    ret 4u8
}

fn function_name(f: u8) -> str {
    if f == F_SIN { ret "sin" }
    if f == F_COS { ret "cos" }
    if f == F_TAN { ret "tan" }
    if f == F_EXP { ret "exp" }
    if f == F_LN { ret "ln" }
    ret "atan"
}

fn push_expr(b: *str.Builder, p: *Pool, e: u32, parent: u8) -> err {
    let n = p.nodes[usize(e)]
    let mine = prec(p, e)
    let wrap = mine < parent
    if wrap { try str.push_byte(b, 40u8) }
    if n.kind == K_NUM {
        try str.push_i64(b, n.n)
        if n.d != 1i64 {
            try str.push_byte(b, 47u8)
            try str.push_i64(b, n.d)
        }
    } else if n.kind == K_SYM {
        try str.push(b, p.names[usize(n.a)])
    } else if n.kind == K_FUN {
        try str.push(b, function_name(n.f))
        try str.push_byte(b, 40u8)
        try push_expr(b, p, n.a, 0u8)
        try str.push_byte(b, 41u8)
    } else if n.kind == K_ADD {
        try push_expr(b, p, n.a, 1u8)
        // a negative right operand prints as a subtraction
        let r = p.nodes[usize(n.b)]
        var minus = false
        var shown = n.b
        if r.kind == K_NUM && r.n < 0i64 {
            minus = true
            shown = qnode(p, Q{ n: 0i64 - r.n, d: r.d })
        } else if r.kind == K_MUL && is_num(p, r.a) && p.nodes[usize(r.a)].n < 0i64 {
            minus = true
            shown = mul(p, qnode(p, q_neg(q_of(p, r.a))), r.b)
        }
        if minus {
            try str.push(b, " - ")
            try push_expr(b, p, shown, 2u8)
        } else {
            try str.push(b, " + ")
            try push_expr(b, p, n.b, 1u8)
        }
    } else if n.kind == K_MUL {
        if is_value(p, n.a, -1i64) {
            try str.push_byte(b, 45u8)
            try push_expr(b, p, n.b, 3u8)
        } else {
            try push_expr(b, p, n.a, 2u8)
            try str.push_byte(b, 42u8)
            try push_expr(b, p, n.b, 2u8)
        }
    } else {
        let ex = p.nodes[usize(n.b)]
        if ex.kind == K_NUM && ex.n == 1i64 && ex.d == 2i64 {
            try str.push(b, "sqrt(")
            try push_expr(b, p, n.a, 0u8)
            try str.push_byte(b, 41u8)
        } else {
            try push_expr(b, p, n.a, 4u8)
            try str.push_byte(b, 94u8)
            try push_expr(b, p, n.b, 4u8)
        }
    }
    if wrap { try str.push_byte(b, 41u8) }
    ret ok
}

fn to_string(a: *mem.Arena, p: *Pool, e: u32) -> (str, err) {
    let (b0, be) = str.builder(a, 4096usize)
    if be != ok { ret ("", be) }
    var b = b0
    try push_expr(&b, p, e, 0u8)
    ret (str.done(&b), ok)
}

// ---- evaluation ---------------------------------------------------------------------------

// A value for each name in `names`; an unbound symbol is NaN. `pi` is itself.
fn eval(p: *Pool, e: u32, names: []const str, values: []const f64) -> f64 {
    let n = p.nodes[usize(e)]
    if n.kind == K_NUM { ret f64(n.n) / f64(n.d) }
    if n.kind == K_SYM {
        let name = p.names[usize(n.a)]
        var i = 0usize
        while i < names.len && i < values.len {
            if str.eq(names[i], name) { ret values[i] }
            i += 1usize
        }
        if str.eq(name, "pi") { ret 3.141592653589793f64 }
        ret mem.bitcast[f64](9221120237041090560u64)
    }
    if n.kind == K_FUN {
        let x = eval(p, n.a, names, values)
        if n.f == F_SIN { ret math.sin64(x) }
        if n.f == F_COS { ret math.cos64(x) }
        if n.f == F_TAN { ret math.tan64(x) }
        if n.f == F_EXP { ret math.exp64(x) }
        if n.f == F_LN { ret math.log64(x) }
        ret math.atan64(x)
    }
    let l = eval(p, n.a, names, values)
    let r = eval(p, n.b, names, values)
    if n.kind == K_ADD { ret l + r }
    if n.kind == K_MUL { ret l * r }
    // an integer exponent keeps the sign of a negative base
    let whole = p.nodes[usize(n.b)]
    if whole.kind == K_NUM && whole.d == 1i64 && whole.n >= -64i64 && whole.n <= 64i64 {
        var acc = 1.0f64
        var k = abs64(whole.n)
        while k > 0i64 {
            acc = acc * l
            k -= 1i64
        }
        if whole.n < 0i64 { ret 1.0f64 / acc }
        ret acc
    }
    ret math.pow64(l, r)
}

// ---- differentiation ---------------------------------------------------------------------

fn diff(p: *Pool, e: u32, s: u32) -> u32 {
    let n = p.nodes[usize(e)]
    if n.kind == K_NUM { ret int(p, 0i64) }
    if n.kind == K_SYM {
        if n.a == s { ret int(p, 1i64) }
        ret int(p, 0i64)
    }
    if n.kind == K_ADD { ret add(p, diff(p, n.a, s), diff(p, n.b, s)) }
    if n.kind == K_MUL {
        let da = diff(p, n.a, s)
        let db = diff(p, n.b, s)
        ret add(p, mul(p, da, n.b), mul(p, n.a, db))
    }
    if n.kind == K_POW {
        let da = diff(p, n.a, s)
        if !has(p, n.b, s) {
            // d(u^c) = c u^(c-1) u'
            ret mul(p, mul(p, n.b, pow(p, n.a, sub(p, n.b, int(p, 1i64)))), da)
        }
        let db = diff(p, n.b, s)
        // d(u^v) = u^v (v' ln u + v u' / u)
        let inner = add(p, mul(p, db, func(p, F_LN, n.a)), div(p, mul(p, n.b, da), n.a))
        ret mul(p, e, inner)
    }
    let inner = diff(p, n.a, s)
    if n.f == F_SIN { ret mul(p, func(p, F_COS, n.a), inner) }
    if n.f == F_COS { ret mul(p, neg(p, func(p, F_SIN, n.a)), inner) }
    if n.f == F_TAN { ret mul(p, add(p, int(p, 1i64), pow(p, func(p, F_TAN, n.a), int(p, 2i64))), inner) }
    if n.f == F_EXP { ret mul(p, e, inner) }
    if n.f == F_LN { ret div(p, inner, n.a) }
    ret div(p, inner, add(p, int(p, 1i64), pow(p, n.a, int(p, 2i64))))
}

// ---- polynomials --------------------------------------------------------------------------

fn poly_zero() -> Poly {
    var r: Poly = zero
    var i = 0usize
    while i < 20usize {
        r.c[i] = Q{ n: 0i64, d: 1i64 }
        i += 1usize
    }
    r.deg = -1i32
    ret r
}

fn poly_const(v: Q) -> Poly {
    var r = poly_zero()
    r.c[0] = v
    if v.n != 0i64 { r.deg = 0i32 }
    ret r
}

fn poly_trim(r: *Poly) {
    while r.deg >= 0i32 && r.c[usize(r.deg)].n == 0i64 { r.deg -= 1i32 }
}

fn poly_add(p: *Pool, x: Poly, y: Poly) -> Poly {
    var r = poly_zero()
    var i = 0usize
    while i < 20usize {
        r.c[i] = q_add(p, x.c[i], y.c[i])
        i += 1usize
    }
    r.deg = 19i32
    poly_trim(&r)
    ret r
}

fn poly_mul(p: *Pool, x: Poly, y: Poly) -> (Poly, bool) {
    var r = poly_zero()
    if x.deg < 0i32 || y.deg < 0i32 { ret (r, true) }
    if x.deg + y.deg > 19i32 { ret (r, false) }
    var i = 0i32
    while i <= x.deg {
        var j = 0i32
        while j <= y.deg {
            r.c[usize(i + j)] = q_add(p, r.c[usize(i + j)], q_mul(p, x.c[usize(i)], y.c[usize(j)]))
            j += 1i32
        }
        i += 1i32
    }
    r.deg = x.deg + y.deg
    poly_trim(&r)
    ret (r, true)
}

// `e` as a polynomial in the symbol `s` with rational coefficients, or false.
fn poly_of(p: *Pool, e: u32, s: u32) -> (Poly, bool) {
    let n = p.nodes[usize(e)]
    var r = poly_zero()
    if n.kind == K_NUM { ret (poly_const(q_of(p, e)), true) }
    if n.kind == K_SYM {
        if n.a != s { ret (r, false) }
        r.c[1] = q_one()
        r.deg = 1i32
        ret (r, true)
    }
    if n.kind == K_FUN { ret (r, false) }
    if n.kind == K_ADD {
        let (l, lg) = poly_of(p, n.a, s)
        let (rr, rg) = poly_of(p, n.b, s)
        if !lg || !rg { ret (r, false) }
        ret (poly_add(p, l, rr), true)
    }
    if n.kind == K_MUL {
        let (l, lg) = poly_of(p, n.a, s)
        let (rr, rg) = poly_of(p, n.b, s)
        if !lg || !rg { ret (r, false) }
        let (prod, good) = poly_mul(p, l, rr)
        ret (prod, good)
    }
    // a power: a polynomial to a non-negative integer power
    let ex = p.nodes[usize(n.b)]
    if ex.kind != K_NUM || ex.d != 1i64 || ex.n < 0i64 || ex.n > 19i64 { ret (r, false) }
    let (base, bg) = poly_of(p, n.a, s)
    if !bg { ret (r, false) }
    var acc = poly_const(q_one())
    var k = 0i64
    while k < ex.n {
        let (next, good) = poly_mul(p, acc, base)
        if !good { ret (r, false) }
        acc = next
        k += 1i64
    }
    ret (acc, true)
}

// c0 + c1 x + ... as an expression in the symbol node `x`.
fn poly_expr(p: *Pool, f: Poly, x: u32) -> u32 {
    var out = int(p, 0i64)
    var k = f.deg
    while k >= 0i32 {
        let c = f.c[usize(k)]
        if c.n != 0i64 {
            var term = qnode(p, c)
            if k > 0i32 { term = mul(p, term, pow(p, x, int(p, i64(k)))) }
            out = add(p, out, term)
        }
        k -= 1i32
    }
    ret out
}

fn poly_derivative(p: *Pool, f: Poly) -> Poly {
    var r = poly_zero()
    var k = 1i32
    while k <= f.deg {
        r.c[usize(k - 1i32)] = q_mul(p, f.c[usize(k)], Q{ n: i64(k), d: 1i64 })
        k += 1i32
    }
    r.deg = f.deg - 1i32
    poly_trim(&r)
    ret r
}

// ---- integration ----------------------------------------------------------------------------

// The antiderivative of `e` in the symbol `s`, with no constant; false when out of reach.
fn integrate(p: *Pool, e: u32, s: u32) -> (u32, bool) {
    let x = mk(p, K_SYM, 0u8, s, 0u32, 0i64, 1i64)
    if !has(p, e, s) { ret (mul(p, e, x), true) }
    let (poly, is_poly) = poly_of(p, e, s)
    if is_poly {
        var anti = poly_zero()
        var k = 0i32
        while k <= poly.deg {
            anti.c[usize(k + 1i32)] = q_mul(p, poly.c[usize(k)], Q{ n: 1i64, d: i64(k) + 1i64 })
            k += 1i32
        }
        anti.deg = poly.deg + 1i32
        ret (poly_expr(p, anti, x), true)
    }
    let n = p.nodes[usize(e)]
    if n.kind == K_ADD {
        let (l, lg) = integrate(p, n.a, s)
        let (r, rg) = integrate(p, n.b, s)
        if !lg || !rg { ret (0u32, false) }
        ret (add(p, l, r), true)
    }
    if n.kind == K_MUL {
        // a factor free of the symbol comes out
        if !has(p, n.a, s) {
            let (r, g) = integrate(p, n.b, s)
            if !g { ret (0u32, false) }
            ret (mul(p, n.a, r), true)
        }
        if !has(p, n.b, s) {
            let (l, g) = integrate(p, n.a, s)
            if !g { ret (0u32, false) }
            ret (mul(p, n.b, l), true)
        }
        // polynomial times exp, sin or cos of a linear argument, by parts
        let (pl, plg) = poly_of(p, n.a, s)
        let fb = p.nodes[usize(n.b)]
        if plg && fb.kind == K_FUN && fb.f <= F_EXP {
            let (lin, ling) = poly_of(p, fb.a, s)
            if ling && lin.deg == 1i32 {
                let (r, g) = by_parts(p, pl, fb.f, fb.a, lin.c[1], x)
                ret (r, g)
            }
        }
        let (pr, prg) = poly_of(p, n.b, s)
        let fa = p.nodes[usize(n.a)]
        if prg && fa.kind == K_FUN && fa.f <= F_EXP {
            let (lin, ling) = poly_of(p, fa.a, s)
            if ling && lin.deg == 1i32 {
                let (r, g) = by_parts(p, pr, fa.f, fa.a, lin.c[1], x)
                ret (r, g)
            }
        }
        ret (0u32, false)
    }
    if n.kind == K_FUN {
        let (lin, ling) = poly_of(p, n.a, s)
        if !ling || lin.deg != 1i32 { ret (0u32, false) }
        let m = qnode(p, lin.c[1])
        if n.f == F_SIN { ret (div(p, neg(p, func(p, F_COS, n.a)), m), true) }
        if n.f == F_COS { ret (div(p, func(p, F_SIN, n.a), m), true) }
        if n.f == F_EXP { ret (div(p, e, m), true) }
        if n.f == F_TAN { ret (div(p, neg(p, func(p, F_LN, func(p, F_COS, n.a))), m), true) }
        if n.f == F_LN && same(p, n.a, x) { ret (sub(p, mul(p, x, e), x), true) }
        ret (0u32, false)
    }
    if n.kind == K_POW {
        let ex = p.nodes[usize(n.b)]
        if ex.kind != K_NUM { ret (0u32, false) }
        let (lin, ling) = poly_of(p, n.a, s)
        if !ling || lin.deg != 1i32 { ret (0u32, false) }
        let m = qnode(p, lin.c[1])
        if ex.n == -1i64 && ex.d == 1i64 { ret (div(p, func(p, F_LN, n.a), m), true) }
        let np1 = q_add(p, q_of(p, n.b), q_one())
        let top = pow(p, n.a, qnode(p, np1))
        ret (div(p, top, mul(p, m, qnode(p, np1))), true)
    }
    ret (0u32, false)
}

// The antiderivative of P(x) f(u), u = a x + b, `slope` = a, for f in {sin, cos, exp}.
fn by_parts(p: *Pool, poly: Poly, f: u8, u: u32, slope: Q, x: u32) -> (u32, bool) {
    let inv = q_inv(p, slope)
    if f == F_EXP {
        // e^u (P/a - P'/a^2 + P''/a^3 - ...)
        var total = poly_zero()
        var cur = poly
        var scale = inv
        var sign = q_one()
        while cur.deg >= 0i32 {
            var term = cur
            let factor = q_mul(p, scale, sign)
            var i = 0i32
            while i <= term.deg {
                term.c[usize(i)] = q_mul(p, term.c[usize(i)], factor)
                i += 1i32
            }
            total = poly_add(p, total, term)
            cur = poly_derivative(p, cur)
            scale = q_mul(p, scale, inv)
            sign = q_neg(sign)
        }
        ret (mul(p, poly_expr(p, total, x), func(p, F_EXP, u)), true)
    }
    // sin and cos: with P^(k) the k-th derivative,
    //   ∫P sin u = -cos u (P/a - P''/a^3 + ...) + sin u (P'/a^2 - P'''/a^4 + ...)
    //   ∫P cos u =  sin u (P/a - P''/a^3 + ...) + cos u (P'/a^2 - P'''/a^4 + ...)
    var even = poly_zero()
    var odd = poly_zero()
    var cur = poly
    var k = 0i32
    var scale = inv
    var sign = q_one()
    while cur.deg >= 0i32 {
        var term = cur
        let factor = q_mul(p, scale, sign)
        var i = 0i32
        while i <= term.deg {
            term.c[usize(i)] = q_mul(p, term.c[usize(i)], factor)
            i += 1i32
        }
        if k % 2i32 == 0i32 {
            even = poly_add(p, even, term)
        } else {
            odd = poly_add(p, odd, term)
            sign = q_neg(sign)
        }
        cur = poly_derivative(p, cur)
        scale = q_mul(p, scale, inv)
        k += 1i32
    }
    let s_u = func(p, F_SIN, u)
    let c_u = func(p, F_COS, u)
    if f == F_SIN {
        let first = neg(p, mul(p, poly_expr(p, even, x), c_u))
        ret (add(p, first, mul(p, poly_expr(p, odd, x), s_u)), true)
    }
    let first = mul(p, poly_expr(p, even, x), s_u)
    ret (add(p, first, mul(p, poly_expr(p, odd, x), c_u)), true)
}

// ---- solving ----------------------------------------------------------------------------------

fn divides(d: i64, v: i64) -> bool {
    if d == 0i64 { ret false }
    ret v % d == 0i64
}

fn horner(p: *Pool, f: Poly, r: Q) -> Q {
    var acc = q_zero()
    var k = f.deg
    while k >= 0i32 {
        acc = q_add(p, q_mul(p, acc, r), f.c[usize(k)])
        k -= 1i32
    }
    ret acc
}

// Divides `f` by (x - r) (synthetic division); `r` must be a root.
fn deflate(p: *Pool, f: Poly, r: Q) -> Poly {
    var out = poly_zero()
    var carry = q_zero()
    var k = f.deg
    while k >= 1i32 {
        carry = q_add(p, q_mul(p, carry, r), f.c[usize(k)])
        out.c[usize(k - 1i32)] = carry
        k -= 1i32
    }
    out.deg = f.deg - 1i32
    poly_trim(&out)
    ret out
}

// The distinct real roots of `e` = 0 in the symbol `s`, as expressions, into `out`: the count
// and `Unsupported` when `e` is not a polynomial with rational coefficients (or has a factor
// of degree three or more with no rational root), `TooLarge` past the pool or `out`.
fn solve(p: *Pool, e: u32, s: u32, out: []u32) -> (usize, err) {
    var (f, good) = poly_of(p, e, s)
    if !good { ret (0usize, Unsupported) }
    if p.failed { ret (0usize, TooLarge) }
    if f.deg < 0i32 { ret (0usize, Unsupported) }
    var n = 0usize
    var left = f
    // rational roots by the rational-root theorem on the integer-scaled polynomial
    var lcm = 1i64
    var k = 0i32
    while k <= left.deg {
        let dd = left.c[usize(k)].d
        lcm = lcm / gcd64(lcm, dd) * dd
        if lcm >= LIMIT { ret (0usize, TooLarge) }
        k += 1i32
    }
    while left.deg >= 3i32 {
        // integer coefficients c_k * lcm
        var lead = left.c[usize(left.deg)].n * (lcm / left.c[usize(left.deg)].d)
        var tail = 0i64
        var t = 0i32
        while t <= left.deg {
            tail = left.c[usize(t)].n * (lcm / left.c[usize(t)].d)
            if tail != 0i64 { break }
            t += 1i32
        }
        if t > 0i32 {
            // x = 0 is a root
            if n == out.len { ret (n, TooLarge) }
            out[n] = int(p, 0i64)
            n += 1usize
            var shifted = poly_zero()
            var j = 1i32
            while j <= left.deg {
                shifted.c[usize(j - 1i32)] = left.c[usize(j)]
                j += 1i32
            }
            shifted.deg = left.deg - 1i32
            left = shifted
            continue
        }
        var found = false
        lead = abs64(lead)
        tail = abs64(tail)
        if lead > 100000i64 || tail > 1000000i64 { ret (n, Unsupported) }
        var pn = 1i64
        while pn <= tail && !found {
            if divides(pn, tail) {
                var qd = 1i64
                while qd <= lead && !found {
                    if divides(qd, lead) {
                        var sgn = 0i32
                        while sgn < 2i32 && !found {
                            var cand = q(pn, qd)
                            if sgn == 1i32 { cand = q_neg(cand) }
                            if horner(p, left, cand).n == 0i64 {
                                found = true
                                // a repeated root is one root
                                var seen_before = false
                                var w = 0usize
                                while w < n {
                                    if is_num(p, out[w]) && q_of(p, out[w]).n == cand.n && q_of(p, out[w]).d == cand.d { seen_before = true }
                                    w += 1usize
                                }
                                if !seen_before {
                                    if n == out.len { ret (n, TooLarge) }
                                    out[n] = qnode(p, cand)
                                    n += 1usize
                                }
                                left = deflate(p, left, cand)
                            }
                            sgn += 1i32
                        }
                    }
                    qd += 1i64
                }
            }
            pn += 1i64
        }
        if !found { ret (n, Unsupported) }
    }
    if left.deg == 1i32 {
        if n == out.len { ret (n, TooLarge) }
        out[n] = qnode(p, q_neg(q_mul(p, left.c[0], q_inv(p, left.c[1]))))
        n += 1usize
    }
    if left.deg == 2i32 {
        let a2 = left.c[2]
        let b1 = left.c[1]
        let c0 = left.c[0]
        let disc = q_add(p, q_mul(p, b1, b1), q_neg(q_mul(p, q(4i64, 1i64), q_mul(p, a2, c0))))
        if disc.n >= 0i64 {
            let two_a = q_mul(p, q(2i64, 1i64), a2)
            let nb = q_neg(b1)
            let rn = isqrt(disc.n)
            let rd = isqrt(disc.d)
            if disc.n == 0i64 {
                if n == out.len { ret (n, TooLarge) }
                out[n] = qnode(p, q_mul(p, nb, q_inv(p, two_a)))
                n += 1usize
            } else if rn * rn == disc.n && rd * rd == disc.d {
                let root = q(rn, rd)
                if n + 2usize > out.len { ret (n, TooLarge) }
                out[n] = qnode(p, q_mul(p, q_add(p, nb, root), q_inv(p, two_a)))
                out[n + 1usize] = qnode(p, q_mul(p, q_add(p, nb, q_neg(root)), q_inv(p, two_a)))
                n += 2usize
            } else {
                if n + 2usize > out.len { ret (n, TooLarge) }
                let sq = pow(p, qnode(p, disc), num(p, 1i64, 2i64))
                let inv = qnode(p, q_inv(p, two_a))
                out[n] = mul(p, inv, add(p, qnode(p, nb), sq))
                out[n + 1usize] = mul(p, inv, add(p, qnode(p, nb), neg(p, sq)))
                n += 2usize
            }
        }
    }
    // distinct roots: drop a later rational equal to an earlier one
    var kept = 0usize
    var r = 0usize
    while r < n {
        var dup = false
        var w = 0usize
        while w < kept {
            if is_num(p, out[w]) && is_num(p, out[r]) && q_of(p, out[w]).n == q_of(p, out[r]).n && q_of(p, out[w]).d == q_of(p, out[r]).d { dup = true }
            w += 1usize
        }
        if !dup {
            out[kept] = out[r]
            kept += 1usize
        }
        r += 1usize
    }
    n = kept
    if p.failed { ret (n, TooLarge) }
    ret (n, ok)
}
