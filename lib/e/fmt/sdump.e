// S-PLUS text dump reader as foreign::data.restore reads it (the files data.dump(oldStyle = TRUE) writes): every object is its name, its mode and its length on
// three lines, then its values one per line (N for NA) or, for a list or structure, that many objects. parse() gives a summary of each top-level object rather
// than the object: its length, the sum of its values and the sum of them weighted by their 1-based position in their own vector (a character counts its code
// units; a factor its codes; NA is left out), the number of NAs, the levels of a factor (.Label), the dim attribute (.Dim) and the names of a list.
//
// Modes read: logical, integer, numeric, single, double, character, list and structure (the .Data, .Dim and .Label members; a data frame or factor is such a
// structure). The other S modes (expressions, functions, name, complex, NULL, ...) and a structure holding .Tsp are refused with Unsupported, as are
// duplicate names, which R resolves by assignment. What R stops at is Malformed: a missing mode or length, a length that is not a number, a mode that is no S
// mode, an object that is cut off, a structure without .Data or with a .Dim that does not fit it, an empty top-level name.
//
// The attributes other than .Dim and .Label (class, row.names, ...) are taken as they come: R would stop at a class that does not fit its data.

use e.fmt.epiinfo as epi
use e.mem
use e.str

error Malformed
error Unsupported

type Item = struct { name: str, kind: u8, len: usize, sum: f64, wsum: f64, prod: f64, nna: usize, nlev: usize, levs: f64, ndim: usize, dimprod: f64, nnames: usize, elh: f64, nhash: f64 }

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
    let names = "name\nstring\nliteral\ncompiled\n(\n)\n[\n]\n{\n}\n,\n=\n!\n:\naddop\n*/\n<dummy>\n^\n-\n$\nlogop\n&|\n<-\n->\nsp.op\n \nrepeat\nif\nelse\nbreak\n;\nnext\nwhile\nfor\nin\nrecursive.return\nreturn\nargument\nsystem\nend.of.file\nexpression\nsystem.function\nmissing\ncall\nfunction\n?\nunbalanced\n[[\nunknown\n]]\nquit\ncontinue\ncomment.expression\nvector\ncall(...)\n<<-\ngraphics\narg.lvalue\ninternal\nS.call\nS.data\ncomment\ncomment(leftover)\nevaluation.frame\ndestination\n"
    var s = 0usize
    while s < names.len {
        var e = s
        while e < names.len && names[e] != 10u8 { e += 1usize }
        if str.eq(names[s..e], code) { ret true }
        s = e + 1usize
    }
    ret false
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

fn atomic(r: *R, name: str, code: str, len: usize) -> Item {
    var it: Item = zero
    it.name = name
    var avail = r.n - r.at
    if len < avail { avail = len }
    it.len = avail
    it.prod = 1.0f64
    var chars = str.eq(code, "character")
    if chars { it.kind = 1u8 }
    let lg = str.eq(code, "logical")
    let ig = str.eq(code, "integer")
    var i = 0usize
    while i < avail {
        let l = r.lines[r.at + i]
        var na = str.eq(l, "N")
        var v = 0.0f64
        if chars {
            v = code_sum(l)
        } else if !na {
            if lg || ig {
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
        if na {
            it.nna += 1usize
        } else {
            it.sum += v
            it.wsum += v * f64(i + 1usize)
            it.prod = it.prod * v
        }
        i += 1usize
    }
    r.at += avail
    ret it
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
    if str.eq(code, "logical") || str.eq(code, "numeric") || str.eq(code, "integer") || str.eq(code, "single") || str.eq(code, "double") || str.eq(code, "character") {
        var it = atomic(r, name, code, len)
        it.nhash = byte_hash(name)
        ret it
    }
    let is_list = str.eq(code, "list")
    let is_struct = str.eq(code, "structure")
    if !is_list && !is_struct {
        if is_smode(code) { ret fail(r, 2u8) }
        ret fail(r, 1u8)
    }
    // the elements
    var kids: []Item = zero
    let (ks, ke) = mem.alloc[Item](r.a, len + 1usize)
    if ke != ok { ret fail(r, 2u8) }
    kids = ks
    var i = 0usize
    while i < len && r.bad == 0u8 {
        kids[i] = read_item(r)
        i += 1usize
    }
    if r.bad != 0u8 { ret fail(r, 1u8) }
    var named = false
    i = 0usize
    while i < len {
        if kids[i].name.len > 0usize {
            named = true
            var j = 0usize
            while j < i {
                if str.eq(kids[j].name, kids[i].name) { ret fail(r, 2u8) }
                j += 1usize
            }
        }
        i += 1usize
    }
    var it: Item = zero
    it.name = name
    it.nhash = byte_hash(name)
    if is_list {
        it.kind = 2u8
        it.len = len
        i = 0usize
        while i < len {
            it.sum += kids[i].sum
            it.wsum += kids[i].wsum
            it.nna += kids[i].nna
            if named { it.elh += code_sum(kids[i].name) * f64(i + 1usize) }
            i += 1usize
        }
        if named { it.nnames = len }
        ret it
    }
    // a structure: .Data with .Dim and .Label
    var di = len
    var dim_i = len
    var lab_i = len
    i = 0usize
    while i < len {
        if str.eq(kids[i].name, ".Data") { di = i }
        if str.eq(kids[i].name, ".Dim") { dim_i = i }
        if str.eq(kids[i].name, ".Label") { lab_i = i }
        if str.eq(kids[i].name, ".Tsp") { ret fail(r, 2u8) }
        i += 1usize
    }
    if di == len { ret fail(r, 1u8) }
    let d = kids[di]
    it = d
    it.name = name
    it.nhash = byte_hash(name)
    if lab_i < len {
        it.nlev = kids[lab_i].len
        it.levs = kids[lab_i].sum
    }
    if dim_i < len {
        let dm = kids[dim_i]
        if dm.nna > 0usize || dm.prod != f64(d.len) { ret fail(r, 1u8) }
        it.ndim = dm.len
        it.dimprod = dm.prod
    }
    ret it
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
