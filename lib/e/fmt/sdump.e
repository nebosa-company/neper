// S-PLUS text dump reader as foreign::data.restore reads it (the files data.dump(oldStyle = TRUE) writes): every object is its name, its mode and its length on
// three lines, then its values one per line (N for NA) or, for a list or structure, that many objects. parse() gives a summary of each top-level object rather
// than the object: its length, the sum of its values and the sum of them weighted by their 1-based position in their own vector (a character counts its code
// units; a factor its codes; NA is left out), the number of NAs, the levels of a factor (.Label), the dim attribute (.Dim) and the names of a list.
//
// Modes read: logical, integer, numeric, single, double, character, complex, name, missing, list and structure (the .Data, .Dim, .Label and .Tsp members; a data
// frame, factor or time series is such a structure), NULL and every S language mode, each as foreign builds it: a list element of NULL is not stored (an
// unnamed one leaves a NULL gap when a later one is), a call mode makes a call of the elements, expression an expression, function a function (a list whose
// elements but the last are named), and the modes R has no as.<mode> for stay a plain list. The summary of what is not a vector has ty (1 complex, 2 name,
// 3 NULL, 4 call, 5 function, 6 expression) and its length; complex adds the sum of its imaginary parts (isum). Duplicate names, which R resolves by assignment,
// and a .Data of a mode other than a vector under .Tsp, are refused with Unsupported. What R stops at is Malformed: a missing mode or length, a length that is
// not a number, a mode that is no S mode, an object that is cut off, a structure without .Data or with a .Dim that does not fit it, an empty top-level name,
// a name object with no usable first line, a call(...), internal or comment.expression with nothing in it.
//
// The attributes other than .Dim, .Label and .Tsp (class, row.names, ...) are taken as they come: R would stop at a class that does not fit its data.

use e.fmt.epiinfo as epi
use e.math
use e.mem
use e.str

error Malformed
error Unsupported

type Item = struct { name: str, kind: u8, ty: u8, len: usize, sum: f64, wsum: f64, isum: f64, prod: f64, nna: usize, nlev: usize, levs: f64, ndim: usize, dimprod: f64, nnames: usize, elh: f64, nhash: f64, vals: []f64, nas: []u8 }

// the stored elements of a list as R builds it, with the gaps a late unnamed element leaves (ty 3)
type ListV = struct { slots: []Item, n: usize, named: bool }

type Restore = struct { n: usize, items: []Item }

// kind: 0 numeric, logical or integer, 1 character, 2 list or structure
type R = struct { a: *mem.Arena, lines: []str, at: usize, n: usize, bad: u8 }

fn line_end(t: str, at: usize) -> usize {
    var e = at
    while e < t.len && t[e] != 10u8 { e += 1usize }
    ret e
}

fn byte_hash(x: str) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += f64(x[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn code_sum(x: str) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += f64(x[i])
        i += 1usize
    }
    ret s
}

// the S modes of Sread.R's SModeNames, one per entry
fn is_smode(code: str) -> bool {
    var k = 0usize
    while k < 65usize {
        if str.eq(smode_name(k), code) { ret true }
        k += 1usize
    }
    ret false
}

// the 0-based entry k of the table; empty past the end
fn smode_name(k: usize) -> str {
    let names ="name\nstring\nliteral\ncompiled\n(\n)\n[\n]\n{\n}\n,\n=\n!\n:\naddop\n*/\n<dummy>\n^\n-\n$\nlogop\n&|\n<-\n->\nsp.op\n \nrepeat\nif\nelse\nbreak\n;\nnext\nwhile\nfor\nin\nrecursive.return\nreturn\nargument\nsystem\nend.of.file\nexpression\nsystem.function\nmissing\ncall\nfunction\n?\nunbalanced\n[[\nunknown\n]]\nquit\ncontinue\ncomment.expression\nvector\ncall(...)\n<<-\ngraphics\narg.lvalue\ninternal\nS.call\nS.data\ncomment\ncomment(leftover)\nevaluation.frame\ndestination\n"
    var s = 0usize
    var n = 0usize
    while s < names.len {
        var e = s
        while e < names.len && names[e] != 10u8 { e += 1usize }
        if n == k { ret names[s..e] }
        n += 1usize
        s = e + 1usize
    }
    ret names[0usize..0usize]
}

// as.integer of a string: whole values within +-2^31, truncated toward zero; false for NA
fn as_int(a: *mem.Arena, s: str) -> (f64, bool) {
    let (x, good) = epi.as_num(a, s)
    if !good { ret (0.0f64, false) }
    if x >= 2147483648.0f64 || x <= 0.0f64 - 2147483648.0f64 { ret (0.0f64, false) }
    ret (f64(i64(x)), true)
}

fn fail(r: *R, why: u8) -> Item {
    var it: Item = zero
    if r.bad == 0u8 { r.bad = why }
    ret it
}

// the length line: a non-negative whole number, else R stops
fn read_len(r: *R) -> usize {
    if r.at >= r.n {
        r.bad = 1u8
        ret 0usize
    }
    let l = r.lines[r.at]
    r.at += 1usize
    let (x, good) = as_int(r.a, l)
    if !good || x < 0.0f64 {
        r.bad = 1u8
        ret 0usize
    }
    ret usize(x)
}

// as.complex of a string: false for NA. A real, an imaginary (ends in i) or a real followed by a signed imaginary
fn parse_complex(a: *mem.Arena, s: str) -> (f64, f64, bool) {
    var hi = s.len
    while hi > 0usize && (s[hi - 1usize] == 32u8 || s[hi - 1usize] == 9u8 || s[hi - 1usize] == 13u8) { hi -= 1usize }
    if hi > 0usize && s[hi - 1usize] == 105u8 {
        let body = s[0usize..hi - 1usize]
        let (im, good) = epi.as_num(a, body)
        if good { ret (0.0f64, im, true) }
        var j = body.len
        while j > 1usize {
            j -= 1usize
            if body[j] == 43u8 || body[j] == 45u8 {
                let (re2, g1) = epi.as_num(a, body[0usize..j])
                let (im2, g2) = epi.as_num(a, body[j..body.len])
                if g1 && g2 { ret (re2, im2, true) }
            }
        }
        ret (0.0f64, 0.0f64, false)
    }
    let (re, good) = epi.as_num(a, s)
    ret (re, 0.0f64, good)
}

fn atomic(r: *R, name: str, code: str, len: usize) -> Item {
    var it: Item = zero
    it.name = name
    var avail = r.n - r.at
    if len < avail { avail = len }
    it.len = avail
    it.prod = 1.0f64
    let (vs, ve) = mem.alloc[f64](r.a, avail + 1usize)
    let (ns, ne) = mem.alloc[u8](r.a, avail + 1usize)
    if ve != ok || ne != ok {
        r.bad = 2u8
        ret it
    }
    it.vals = vs[0usize..avail]
    it.nas = ns[0usize..avail]
    var chars = str.eq(code, "character")
    if chars { it.kind = 1u8 }
    let lg = str.eq(code, "logical")
    let ig = str.eq(code, "integer")
    let cx = str.eq(code, "complex")
    if cx { it.ty = 1u8 }
    var i = 0usize
    while i < avail {
        let l = r.lines[r.at + i]
        var na = str.eq(l, "N")
        var v = 0.0f64
        var iv = 0.0f64
        if chars {
            v = code_sum(l)
        } else if !na {
            if cx {
                let (x, y, good) = parse_complex(r.a, l)
                if good {
                    v = x
                    iv = y
                } else {
                    na = true
                }
            } else if lg || ig {
                let (x, good) = as_int(r.a, l)
                if good { v = x } else { na = true }
                if lg && !na {
                    if v != 0.0f64 { v = 1.0f64 }
                }
            } else {
                let (x, good) = epi.as_num(r.a, l)
                if good { v = x } else { na = true }
            }
        }
        it.nas[i] = 0u8
        it.vals[i] = 0.0f64
        if na {
            it.nna += 1usize
            it.nas[i] = 1u8
        } else {
            it.vals[i] = v
            it.sum += v
            it.wsum += v * f64(i + 1usize)
            it.isum += iv
            it.prod = it.prod * v
        }
        i += 1usize
    }
    r.at += avail
    ret it
}

// an object that is not a vector: its type and length
fn mk(name: str, ty: u8, len: usize) -> Item {
    var it: Item = zero
    it.name = name
    it.ty = ty
    it.len = len
    it.nhash = byte_hash(name)
    ret it
}

fn renamed(s: Item, name: str) -> Item {
    var c = s
    c.name = name
    c.nhash = byte_hash(name)
    ret c
}

// value[[name or i]] <- element for each element in turn: NULL is not stored, a named element is appended, an unnamed one lands at its own position. 2 for a
// duplicate name or no memory
fn list_value(a: *mem.Arena, kids: []Item) -> (ListV, u8) {
    var lv: ListV = zero
    let (sl, e) = mem.alloc[Item](a, kids.len + 2usize)
    if e != ok { ret (lv, 2u8) }
    lv.slots = sl
    var i = 0usize
    while i < kids.len {
        let k = kids[i]
        if k.name.len > 0usize {
            var j = 0usize
            while j < i {
                if str.eq(kids[j].name, k.name) { ret (lv, 2u8) }
                j += 1usize
            }
        }
        if k.ty != 3u8 {
            if k.name.len > 0usize {
                lv.slots[lv.n] = k
                lv.n += 1usize
                lv.named = true
            } else {
                var g = lv.n
                var gap: Item = zero
                gap.ty = 3u8
                while g < i {
                    lv.slots[g] = gap
                    g += 1usize
                }
                lv.slots[i] = k
                lv.n = i + 1usize
            }
        }
        i += 1usize
    }
    ret (lv, 0u8)
}

fn list_item(name: str, lv: ListV) -> Item {
    var it: Item = zero
    it.name = name
    it.nhash = byte_hash(name)
    it.kind = 2u8
    it.len = lv.n
    var i = 0usize
    while i < lv.n {
        let s = lv.slots[i]
        if s.ty != 3u8 {
            it.sum += s.sum
            it.wsum += s.wsum
            it.isum += s.isum
            it.nna += s.nna
            if lv.named { it.elh += code_sum(s.name) * f64(i + 1usize) }
        }
        i += 1usize
    }
    if lv.named { it.nnames = lv.n }
    ret it
}

// the names of a call or expression built from the list, `shift` entries in (the function of a call)
fn name_stats(it: Item, lv: ListV, shift: usize) -> Item {
    var o = it
    if !lv.named { ret o }
    o.nnames = lv.n + shift
    var i = 0usize
    while i < lv.n {
        o.elh += code_sum(lv.slots[i].name) * f64(i + 1usize + shift)
        i += 1usize
    }
    ret o
}

fn first_present(lv: ListV) -> usize {
    var i = 0usize
    while i < lv.n {
        if lv.slots[i].ty != 3u8 { ret i }
        i += 1usize
    }
    ret lv.n
}

// what foreign makes of the list under an S language mode (or NULL); 1 when R stops, else 0
fn apply_code(name: str, code: str, lv: ListV) -> (Item, u8) {
    if str.eq(code, "NULL") {
        if name.len > 0usize { ret (mk(name, 2u8, 1usize), 0u8) }
        ret (mk(name, 3u8, 0usize), 0u8)
    }
    if str.eq(code, "comment") { ret (mk(name, 3u8, 0usize), 0u8) }
    if str.eq(code, "function") {
        if lv.n > 0usize {
            var good = true
            var i = 0usize
            while i + 1usize < lv.n {
                if lv.slots[i].name.len == 0usize { good = false }
                i += 1usize
            }
            if good { ret (mk(name, 5u8, 1usize), 0u8) }
        }
        ret (list_item(name, lv), 0u8)
    }
    if str.eq(code, "break") || str.eq(code, "if") || str.eq(code, "for") || str.eq(code, "return") || str.eq(code, "S.call") || str.eq(code, "while") || str.eq(code, "<-") || str.eq(code, "<<-") || str.eq(code, "(") || str.eq(code, "{") {
        ret (name_stats(mk(name, 4u8, lv.n + 1usize), lv, 1usize), 0u8)
    }
    if str.eq(code, "call(...)") {
        if lv.n == 0usize { ret (mk(name, 3u8, 0usize), 1u8) }
        if lv.slots[0usize].ty == 3u8 { ret (mk(name, 3u8, 0usize), 0u8) }
        ret (renamed(lv.slots[0usize], name), 0u8)
    }
    if str.eq(code, "comment.expression") {
        let f = first_present(lv)
        if f >= lv.n { ret (mk(name, 3u8, 0usize), 1u8) }
        ret (renamed(lv.slots[f], name), 0u8)
    }
    if str.eq(code, "internal") {
        if lv.n == 0usize { ret (mk(name, 3u8, 0usize), 1u8) }
        ret (mk(name, 4u8, 2usize), 0u8)
    }
    if str.eq(code, "expression") { ret (name_stats(mk(name, 6u8, lv.n), lv, 0usize), 0u8) }
    if str.eq(code, "call") {
        if lv.n > 0usize { ret (name_stats(mk(name, 4u8, lv.n), lv, 0usize), 0u8) }
    }
    ret (list_item(name, lv), 0u8)
}

fn abs_f(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// stats::ts(c(value), tsp[1], tsp[2], tsp[3]) under try(): the data recycled or cut to the number of observations; the item as it was when ts stops. 2 when too big
fn ts_apply(a: *mem.Arena, it: Item, tsp: Item) -> (Item, u8) {
    var out = it
    let nd = it.len
    if nd == 0usize || tsp.len < 3usize { ret (out, 0u8) }
    var k = 0usize
    while k < 3usize {
        if tsp.nas[k] != 0u8 { ret (out, 0u8) }
        let x = tsp.vals[k]
        if x - x != 0.0f64 { ret (out, 0u8) }
        k += 1usize
    }
    let start = tsp.vals[0usize]
    let end = tsp.vals[1usize]
    var freq = tsp.vals[2usize]
    if freq > 1.0f64 {
        let rf = math.floor[f64](freq + 0.5f64)
        let d = abs_f(freq - rf)
        if d > 0.0f64 && d < 0.00001f64 { freq = rf }
    }
    if start > end || freq <= 0.0f64 { ret (out, 0u8) }
    let cycles = (end - start) * freq
    let rc = math.floor[f64](cycles + 0.5f64)
    var mx = cycles
    if mx < 1.0f64 { mx = 1.0f64 }
    if abs_f(rc - cycles) > 0.00001f64 * mx { ret (out, 0u8) }
    let nobsf = math.floor[f64](cycles + 1.01f64)
    if nobsf > 10000000.0f64 { ret (out, 2u8) }
    let nobs = usize(nobsf)
    if abs_f(end - start - f64(nobs - 1usize) / freq) > 0.00001f64 { ret (out, 0u8) }
    let (vs, ve) = mem.alloc[f64](a, nobs + 1usize)
    let (ns, ne) = mem.alloc[u8](a, nobs + 1usize)
    if ve != ok || ne != ok { ret (out, 2u8) }
    out.vals = vs[0usize..nobs]
    out.nas = ns[0usize..nobs]
    out.len = nobs
    out.sum = 0.0f64
    out.wsum = 0.0f64
    out.nna = 0usize
    out.prod = 1.0f64
    out.ndim = 0usize
    out.dimprod = 0.0f64
    out.nlev = 0usize
    out.levs = 0.0f64
    var j = 0usize
    while j < nobs {
        let s = j % nd
        out.nas[j] = it.nas[s]
        out.vals[j] = it.vals[s]
        if it.nas[s] != 0u8 {
            out.nna += 1usize
        } else {
            out.sum += it.vals[s]
            out.wsum += it.vals[s] * f64(j + 1usize)
            out.prod = out.prod * it.vals[s]
        }
        j += 1usize
    }
    ret (out, 1u8)
}

// the structure read.S and data.restore make: .Data with .Dim, .Label and (text dumps only, ts_ok) .Tsp. 1 when R stops, 2 when refused
fn structure_value(a: *mem.Arena, name: str, lv: ListV, ts_ok: bool) -> (Item, u8) {
    var none: Item = zero
    var di = lv.n
    var dim_i = lv.n
    var lab_i = lv.n
    var tsp_i = lv.n
    var i = 0usize
    while i < lv.n {
        let s = lv.slots[i]
        if s.ty != 3u8 {
            if str.eq(s.name, ".Data") { di = i }
            if str.eq(s.name, ".Dim") { dim_i = i }
            if str.eq(s.name, ".Label") { lab_i = i }
            if str.eq(s.name, ".Tsp") { tsp_i = i }
        }
        i += 1usize
    }
    var d: Item = zero
    if di == lv.n {
        // no .Data: the value is list() (attributes<- on NULL) that takes the other members as attributes
        var empty: ListV = zero
        d = list_item(name, empty)
    } else {
        d = lv.slots[di]
    }
    if d.ty >= 2u8 { ret (none, 2u8) }
    var it = renamed(d, name)
    if lab_i < lv.n {
        it.nlev = lv.slots[lab_i].len
        it.levs = lv.slots[lab_i].sum
    }
    if dim_i < lv.n {
        let dm = lv.slots[dim_i]
        if dm.nna > 0usize || dm.prod != f64(d.len) { ret (none, 1u8) }
        it.ndim = dm.len
        it.dimprod = dm.prod
    }
    if tsp_i < lv.n && ts_ok {
        let tp = lv.slots[tsp_i]
        if d.ty != 0u8 || d.kind == 2u8 || tp.ty != 0u8 || tp.kind != 0u8 { ret (none, 2u8) }
        let (t2, st) = ts_apply(a, it, tp)
        if st == 2u8 { ret (none, 2u8) }
        if st == 1u8 { it = t2 }
    }
    ret (it, 0u8)
}

fn read_item(r: *R) -> Item {
    if r.at + 1usize >= r.n {
        r.bad = 1u8
        ret fail(r, 1u8)
    }
    let name = r.lines[r.at]
    let code = r.lines[r.at + 1usize]
    r.at += 2usize
    let len = read_len(r)
    if r.bad != 0u8 { ret fail(r, 1u8) }
    if str.eq(code, "logical") || str.eq(code, "numeric") || str.eq(code, "integer") || str.eq(code, "single") || str.eq(code, "double") || str.eq(code, "character") || str.eq(code, "complex") {
        var it = atomic(r, name, code, len)
        it.nhash = byte_hash(name)
        ret it
    }
    if str.eq(code, "name") || str.eq(code, "missing") {
        let first = r.at
        let it = atomic(r, name, "character", len)
        if str.eq(code, "missing") { ret mk(name, 4u8, 2usize) }
        if it.len == 0usize || r.lines[first].len == 0usize { ret fail(r, 1u8) }
        ret mk(name, 2u8, 1usize)
    }
    let is_list = str.eq(code, "list")
    let is_struct = str.eq(code, "structure")
    if !is_list && !is_struct && !str.eq(code, "NULL") && !is_smode(code) { ret fail(r, 1u8) }
    // the elements
    let (kids, ke) = mem.alloc[Item](r.a, len + 1usize)
    if ke != ok { ret fail(r, 2u8) }
    var i = 0usize
    while i < len && r.bad == 0u8 {
        kids[i] = read_item(r)
        i += 1usize
    }
    if r.bad != 0u8 { ret fail(r, 1u8) }
    let (lv, ls) = list_value(r.a, kids[0usize..len])
    if ls != 0u8 { ret fail(r, ls) }
    if is_list { ret list_item(name, lv) }
    var res: Item = zero
    var st = 0u8
    if is_struct {
        let (x, s2) = structure_value(r.a, name, lv, true)
        res = x
        st = s2
    } else {
        let (x, s2) = apply_code(name, code, lv)
        res = x
        st = s2
    }
    if st != 0u8 { ret fail(r, st) }
    ret res
}

fn parse(a: *mem.Arena, t: str) -> (Restore, err) {
    var out: Restore = zero
    var nl = 0usize
    var i = 0usize
    while i < t.len {
        nl += 1usize
        i = line_end(t, i) + 1usize
    }
    let (lines, e1) = mem.alloc[str](a, nl + 1usize)
    if e1 != ok { ret (out, e1) }
    var k = 0usize
    i = 0usize
    while i < t.len {
        let le = line_end(t, i)
        var le2 = le
        if le2 > i && t[le2 - 1usize] == 13u8 { le2 -= 1usize }
        lines[k] = t[i..le2]
        k += 1usize
        i = le + 1usize
    }
    let (items, e2) = mem.alloc[Item](a, nl + 1usize)
    if e2 != ok { ret (out, e2) }
    var r: R = zero
    r.a = a
    r.lines = lines[0usize..k]
    r.n = k
    var n = 0usize
    while r.at < r.n && r.bad == 0u8 {
        let it = read_item(&r)
        if r.bad != 0u8 { break }
        if it.name.len == 0usize {
            r.bad = 1u8
            break
        }
        var j = 0usize
        while j < n {
            if str.eq(items[j].name, it.name) { r.bad = 2u8 }
            j += 1usize
        }
        items[n] = it
        n += 1usize
    }
    if r.bad == 1u8 { ret (out, Malformed) }
    if r.bad == 2u8 { ret (out, Unsupported) }
    out.n = n
    out.items = items[0usize..n]
    ret (out, ok)
}
