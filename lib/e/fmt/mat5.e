// MATLAB MAT-file reader (level 4 and level 5, either byte order, miCOMPRESSED v7 elements) and a level 5 writer, matching what R.matlab's
// readMat and writeMat do. A variable is a `Var` tree: numeric and character arrays hold their elements as f64 (characters as code units), cells and
// structs hold `kids` (a struct array keeps its fields fastest), a sparse matrix is expanded to dense as readMat does by default.
//
// Not here: objects (class 3), function handles and opaque classes, big sparse expansion limits, v7.3 (HDF5) files, and complex sparse matrices.

use e.mem
use e.io
use e.fmt.zlib as zlib

error Malformed
error Unsupported
error TooMany

// class: the MATLAB class code (1 cell, 2 struct, 4 char, 5 sparse, 6 double, 7 single, 8..13 int8..uint32, 14 int64, 15 uint64); 0 is an empty element.
// count: product of the dimensions. fnames holds nf names of flen bytes each (NUL padded).
type Var = struct {
    class: u8,
    complex: bool,
    logical: bool,
    global: bool,
    name: []const u8,
    nd: usize,
    dims: []usize,
    count: usize,
    re: []f64,
    im: []f64,
    nf: usize,
    flen: usize,
    fnames: []const u8,
    kids: []Var,
}

type Mat = struct { level: usize, big: bool, nvars: usize, vars: []Var }

type Rd = struct { b: []const u8, big: bool }

type Tag = struct { ty: usize, n: usize, at: usize, next: usize }

fn un(r: Rd, p: usize, sz: usize) -> usize {
    var v = 0usize
    var k = 0usize
    while k < sz {
        var x = 0usize
        if r.big { x = usize(r.b[p + k]) } else { x = usize(r.b[p + sz - 1usize - k]) }
        v = v * 256usize + x
        k += 1usize
    }
    ret v
}

fn size_of_type(ty: usize) -> usize {
    if ty == 1usize || ty == 2usize || ty == 16usize { ret 1usize }
    if ty == 3usize || ty == 4usize || ty == 17usize { ret 2usize }
    if ty == 5usize || ty == 6usize || ty == 7usize || ty == 18usize { ret 4usize }
    if ty == 9usize || ty == 12usize || ty == 13usize { ret 8usize }
    ret 0usize
}

// element i of a numeric block of MAT type `ty` at `p`
fn num_at(r: Rd, ty: usize, p: usize, i: usize) -> f64 {
    let sz = size_of_type(ty)
    let q = p + sz * i
    if ty == 1usize {
        var v = f64(un(r, q, 1usize))
        if v > 127.0f64 { v -= 256.0f64 }
        ret v
    }
    if ty == 2usize || ty == 16usize { ret f64(un(r, q, 1usize)) }
    if ty == 3usize {
        var v = f64(un(r, q, 2usize))
        if v > 32767.0f64 { v -= 65536.0f64 }
        ret v
    }
    if ty == 4usize || ty == 17usize { ret f64(un(r, q, 2usize)) }
    if ty == 5usize {
        var v = f64(un(r, q, 4usize))
        if v > 2147483647.0f64 { v -= 4294967296.0f64 }
        ret v
    }
    if ty == 6usize || ty == 18usize { ret f64(un(r, q, 4usize)) }
    if ty == 7usize { ret f64(mem.bitcast[f32](u32(un(r, q, 4usize)))) }
    var w0 = 0usize
    var w1 = 0usize
    if ty == 9usize || ty == 12usize || ty == 13usize {
        w0 = un(r, q, 4usize)
        w1 = un(r, q + 4usize, 4usize)
    }
    var hi = w1
    var lo = w0
    if r.big {
        hi = w0
        lo = w1
    }
    if ty == 9usize { ret mem.bitcast[f64](u64(hi) * 4294967296u64 + u64(lo)) }
    var v = f64(hi) * 4294967296.0f64 + f64(lo)
    if ty == 12usize && hi >= 2147483648usize { v -= 18446744073709551616.0f64 }
    ret v
}

fn read_tag(r: Rd, p: usize, end: usize) -> (Tag, err) {
    var t: Tag = zero
    if p + 8usize > end { ret (t, Malformed) }
    let w = un(r, p, 4usize)
    if w >= 65536usize {
        t.ty = w & 65535usize
        t.n = w >> 16usize
        t.at = p + 4usize
        t.next = p + 8usize
    } else {
        t.ty = w
        t.n = un(r, p + 4usize, 4usize)
        t.at = p + 8usize
        t.next = t.at + ((t.n + 7usize) / 8usize) * 8usize
    }
    if t.at + t.n > end { ret (t, Malformed) }
    if t.next > end { t.next = end }
    ret (t, ok)
}

// up to `want` numeric values of the block `t`
fn read_values(a: *mem.Arena, r: Rd, t: Tag, want: usize) -> ([]f64, err) {
    let sz = size_of_type(t.ty)
    if sz == 0usize { ret (zero, Unsupported) }
    var total = t.n / sz
    if total < want { ret (zero, Malformed) }
    total = want
    let (out, e1) = mem.alloc[f64](a, total + 1usize)
    if e1 != ok { ret (zero, e1) }
    var i = 0usize
    while i < total {
        out[i] = num_at(r, t.ty, t.at, i)
        i += 1usize
    }
    ret (out[0usize..total], ok)
}

fn parse_matrix(a: *mem.Arena, r: Rd, at0: usize, end: usize) -> (Var, err) {
    var v: Var = zero
    let (ft, e1) = read_tag(r, at0, end)
    if e1 != ok { ret (v, e1) }
    if ft.ty != 6usize || ft.n < 8usize { ret (v, Malformed) }
    let w = un(r, ft.at, 4usize)
    v.class = u8(w & 255usize)
    let fl = (w >> 8usize) & 255usize
    v.logical = (fl & 2usize) != 0usize
    v.global = (fl & 4usize) != 0usize
    v.complex = (fl & 8usize) != 0usize
    let nzmax = un(r, ft.at + 4usize, 4usize)
    let (dt, e2) = read_tag(r, ft.next, end)
    if e2 != ok { ret (v, e2) }
    if dt.ty != 5usize { ret (v, Unsupported) }
    v.nd = dt.n / 4usize
    let (dims, e3) = mem.alloc[usize](a, v.nd + 1usize)
    if e3 != ok { ret (v, e3) }
    v.dims = dims[0usize..v.nd]
    var cnt = 0usize
    if v.nd > 0usize { cnt = 1usize }
    var d = 0usize
    while d < v.nd {
        let dd = un(r, dt.at + 4usize * d, 4usize)
        v.dims[d] = dd
        cnt = cnt * dd
        d += 1usize
    }
    v.count = cnt
    let (nt, e4) = read_tag(r, dt.next, end)
    if e4 != ok { ret (v, e4) }
    v.name = r.b[nt.at..nt.at + nt.n]
    var q = nt.next
    let cls = usize(v.class)
    if cls == 1usize || cls == 2usize {
        var nk = cnt
        if cls == 2usize {
            let (lt, e5) = read_tag(r, q, end)
            if e5 != ok { ret (v, e5) }
            if lt.ty != 5usize || lt.n < 4usize { ret (v, Malformed) }
            v.flen = un(r, lt.at, 4usize)
            let (st, e6) = read_tag(r, lt.next, end)
            if e6 != ok { ret (v, e6) }
            if v.flen == 0usize { ret (v, Malformed) }
            v.nf = st.n / v.flen
            v.fnames = r.b[st.at..st.at + st.n]
            nk = cnt * v.nf
            q = st.next
        }
        let (kids, e7) = mem.alloc[Var](a, nk + 1usize)
        if e7 != ok { ret (v, e7) }
        v.kids = kids[0usize..nk]
        var k = 0usize
        while k < nk {
            let (kt, e8) = read_tag(r, q, end)
            if e8 != ok { ret (v, e8) }
            if kt.ty != 14usize { ret (v, Malformed) }
            var empty: Var = zero
            v.kids[k] = empty
            if kt.n > 0usize {
                let (kv, e9) = parse_matrix(a, r, kt.at, kt.at + kt.n)
                if e9 != ok { ret (v, e9) }
                v.kids[k] = kv
            }
            q = kt.next
            k += 1usize
        }
        ret (v, ok)
    }
    if cls == 5usize {
        let nr = v.dims[0usize]
        let nc = v.dims[1usize]
        let (re, e10) = mem.alloc[f64](a, cnt + 1usize)
        if e10 != ok { ret (v, e10) }
        v.re = re[0usize..cnt]
        let (im, e11) = mem.alloc[f64](a, cnt + 1usize)
        if e11 != ok { ret (v, e11) }
        v.im = im[0usize..cnt]
        var i = 0usize
        while i < cnt {
            v.re[i] = 0.0f64
            v.im[i] = 0.0f64
            i += 1usize
        }
        if nzmax > 0usize {
            let (t1, e12) = read_tag(r, q, end)
            if e12 != ok { ret (v, e12) }
            let (ir, e13) = read_values(a, r, t1, t1.n / size_of_type(t1.ty))
            if e13 != ok { ret (v, e13) }
            let (t2, e14) = read_tag(r, t1.next, end)
            if e14 != ok { ret (v, e14) }
            if t2.n / 4usize != nc + 1usize { ret (v, Malformed) }
            let (jc, e15) = read_values(a, r, t2, nc + 1usize)
            if e15 != ok { ret (v, e15) }
            let (t3, e16) = read_tag(r, t2.next, end)
            if e16 != ok { ret (v, e16) }
            let (pr, e17) = read_values(a, r, t3, t3.n / size_of_type(t3.ty))
            if e17 != ok { ret (v, e17) }
            var pim: []f64 = zero
            if v.complex {
                let (t4, e18) = read_tag(r, t3.next, end)
                if e18 != ok { ret (v, e18) }
                let (pi_values, e19) = read_values(a, r, t4, t4.n / size_of_type(t4.ty))
                if e19 != ok { ret (v, e19) }
                pim = pi_values
            }
            var nzm = nzmax
            if usize(jc[nc]) < nzm { nzm = usize(jc[nc]) }
            var j = 0usize
            while j < nc {
                var k = usize(jc[j])
                while k < usize(jc[j + 1usize]) {
                    if k < nzm && k < ir.len && k < pr.len {
                        let pos = j * nr + usize(ir[k])
                        if pos >= cnt { ret (v, Malformed) }
                        v.re[pos] = pr[k]
                        if v.complex && k < pim.len { v.im[pos] = pim[k] }
                    }
                    k += 1usize
                }
                j += 1usize
            }
        }
        ret (v, ok)
    }
    // numeric and character arrays
    let (vt, e20) = read_tag(r, q, end)
    if e20 != ok { ret (v, e20) }
    let (re2, e21) = read_values(a, r, vt, cnt)
    if e21 != ok { ret (v, e21) }
    v.re = re2
    if v.complex {
        let (it, e22) = read_tag(r, vt.next, end)
        if e22 != ok { ret (v, e22) }
        let (im2, e23) = read_values(a, r, it, cnt)
        if e23 != ok { ret (v, e23) }
        v.im = im2
    }
    ret (v, ok)
}

// inflates a zlib stream; the second result is true when `cap` was too small
fn inflate_try(a: *mem.Arena, src: []const u8, cap: usize) -> ([]u8, bool, err) {
    let (storage, se) = mem.alloc[u8](a, zlib.storage_required(.Fast))
    if se != ok { ret (zero, false, se) }
    var st = io.SliceReader { data: src, off: 0usize }
    let (z, ze) = zlib.reader(storage, io.slice_reader(&st), u64(cap) + 1u64)
    if ze != ok { ret (zero, false, ze) }
    var zr = z
    let (out, oe) = mem.alloc[u8](a, cap)
    if oe != ok { ret (zero, false, oe) }
    var filled = 0usize
    var running = true
    var failure: err = ok
    while running && filled < out.len {
        let (n, re) = zlib.read(&zr, out[filled..])
        if re != ok {
            failure = re
            running = false
        } else { filled += n }
        if re == ok && n == 0usize { running = false }
    }
    if failure != ok && failure != io.End { ret (zero, false, Malformed) }
    if filled == out.len {
        var probe: [1]u8 = zero
        let (more, me) = zlib.read(&zr, probe[0usize..])
        if more > 0usize { ret (zero, true, ok) }
        if me != ok && me != io.End { ret (zero, false, Malformed) }
    }
    ret (out[0usize..filled], false, ok)
}

fn inflate(a: *mem.Arena, src: []const u8) -> ([]u8, err) {
    var cap = 65536usize
    if src.len * 8usize > cap { cap = src.len * 8usize }
    var tries = 0usize
    while tries < 8usize {
        let m = mem.mark(a)
        let (out, full, e) = inflate_try(a, src, cap)
        if e != ok { ret (zero, e) }
        if !full { ret (out, ok) }
        mem.reset(a, m)
        cap = cap * 4usize
        tries += 1usize
    }
    ret (zero, Malformed)
}

// the elements of a level 5 data region (miMATRIX and miCOMPRESSED), appended to vars from `n`
fn parse_elements(a: *mem.Arena, r: Rd, p0: usize, end: usize, vars: []Var, n0: usize) -> (usize, err) {
    var n = n0
    var p = p0
    while p + 8usize <= end {
        let (t, e1) = read_tag(r, p, end)
        if e1 != ok { ret (n, e1) }
        if t.ty == 15usize {
            let (raw, e2) = inflate(a, r.b[t.at..t.at + t.n])
            if e2 != ok { ret (n, e2) }
            let inner = Rd { b: raw, big: r.big }
            let (n2, e3) = parse_elements(a, inner, 0usize, raw.len, vars, n)
            if e3 != ok { ret (n, e3) }
            n = n2
            p = t.at + t.n
        } else {
            if t.ty != 14usize { ret (n, Unsupported) }
            if t.n > 0usize {
                if n >= vars.len { ret (n, TooMany) }
                let (v, e4) = parse_matrix(a, r, t.at, t.at + t.n)
                if e4 != ok { ret (n, e4) }
                vars[n] = v
                n += 1usize
            }
            p = t.next
        }
    }
    ret (n, ok)
}

fn level4_ok(w: usize) -> bool {
    ret w / 1000usize <= 1usize && (w / 100usize) % 10usize == 0usize && (w / 10usize) % 10usize <= 5usize && w % 10usize <= 2usize
}

fn parse4(a: *mem.Arena, b: []const u8, vars: []Var) -> (usize, bool, err) {
    var big = false
    let le = Rd { b: b, big: false }
    if !level4_ok(un(le, 0usize, 4usize)) { big = true }
    let r = Rd { b: b, big: big }
    if !level4_ok(un(r, 0usize, 4usize)) { ret (0usize, big, Malformed) }
    var n = 0usize
    var p = 0usize
    while p + 20usize <= b.len {
        let w = un(r, p, 4usize)
        let mr = un(r, p + 4usize, 4usize)
        let nc = un(r, p + 8usize, 4usize)
        let imagf = un(r, p + 12usize, 4usize)
        let namlen = un(r, p + 16usize, 4usize)
        if namlen == 0usize || p + 20usize + namlen > b.len { ret (n, big, Malformed) }
        let prec = (w / 10usize) % 10usize
        let kind = w % 10usize
        var ty = 9usize
        var cls = 6usize
        if prec == 1usize {
            ty = 7usize
            cls = 7usize
        }
        if prec == 2usize {
            ty = 5usize
            cls = 12usize
        }
        if prec == 3usize {
            ty = 3usize
            cls = 10usize
        }
        if prec == 4usize {
            ty = 4usize
            cls = 11usize
        }
        if prec == 5usize {
            ty = 2usize
            cls = 9usize
        }
        var v: Var = zero
        v.name = b[p + 20usize..p + 19usize + namlen]
        v.nd = 2usize
        let (dims, e1) = mem.alloc[usize](a, 2usize)
        if e1 != ok { ret (n, big, e1) }
        dims[0usize] = mr
        dims[1usize] = nc
        v.dims = dims
        let cnt = mr * nc
        v.count = cnt
        let sz = size_of_type(ty)
        var parts = 1usize
        if imagf != 0usize { parts = 2usize }
        let at = p + 20usize + namlen
        if at + cnt * sz * parts > b.len { ret (n, big, Malformed) }
        let (re, e2) = mem.alloc[f64](a, cnt + 1usize)
        if e2 != ok { ret (n, big, e2) }
        v.re = re[0usize..cnt]
        var i = 0usize
        while i < cnt {
            v.re[i] = num_at(r, ty, at, i)
            i += 1usize
        }
        if imagf != 0usize {
            v.complex = true
            let (im, e3) = mem.alloc[f64](a, cnt + 1usize)
            if e3 != ok { ret (n, big, e3) }
            v.im = im[0usize..cnt]
            i = 0usize
            while i < cnt {
                v.im[i] = num_at(r, ty, at + cnt * sz, i)
                i += 1usize
            }
        }
        v.class = u8(cls)
        if kind == 1usize { v.class = 4u8 }
        if kind == 2usize {
            // rows of (i, j, value); the last row repeats the size, as readMat expects
            var rows = 0usize
            var cols = 0usize
            i = 0usize
            while i < mr {
                if usize(v.re[i]) > rows { rows = usize(v.re[i]) }
                if usize(v.re[mr + i]) > cols { cols = usize(v.re[mr + i]) }
                i += 1usize
            }
            var last = mr
            if mr > 1usize && v.re[mr - 1usize] == v.re[mr - 2usize] && v.re[2usize * mr - 1usize] == v.re[2usize * mr - 2usize] { last = mr - 1usize }
            let (dense, e4) = mem.alloc[f64](a, rows * cols + 1usize)
            if e4 != ok { ret (n, big, e4) }
            i = 0usize
            while i < rows * cols {
                dense[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < last {
                dense[(usize(v.re[mr + i]) - 1usize) * rows + usize(v.re[i]) - 1usize] = v.re[2usize * mr + i]
                i += 1usize
            }
            v.class = 5u8
            v.complex = false
            v.re = dense[0usize..rows * cols]
            dims[0usize] = rows
            dims[1usize] = cols
            v.count = rows * cols
        }
        if n >= vars.len { ret (n, big, TooMany) }
        vars[n] = v
        n += 1usize
        p = at + cnt * sz * parts
    }
    ret (n, big, ok)
}

fn parse(a: *mem.Arena, b: []const u8) -> (Mat, err) {
    var out: Mat = zero
    if b.len < 20usize { ret (out, Malformed) }
    let (vars, e1) = mem.alloc[Var](a, 1024usize)
    if e1 != ok { ret (out, e1) }
    out.vars = vars
    if b[0usize] == 77u8 && b[1usize] == 65u8 && b[2usize] == 84u8 && b[3usize] == 76u8 {
        if b.len < 132usize { ret (out, Malformed) }
        out.level = 5usize
        if b[126usize] == 73u8 && b[127usize] == 77u8 {
            out.big = false
        } else {
            if b[126usize] != 77u8 || b[127usize] != 73u8 { ret (out, Unsupported) }
            out.big = true
        }
        let r = Rd { b: b, big: out.big }
        if un(r, 124usize, 2usize) == 512usize { ret (out, Unsupported) }
        let (n, e2) = parse_elements(a, r, 128usize, b.len, vars, 0usize)
        if e2 != ok { ret (out, e2) }
        out.nvars = n
        out.vars = vars[0usize..n]
        ret (out, ok)
    }
    out.level = 4usize
    let (n4, big4, e3) = parse4(a, b, vars)
    if e3 != ok { ret (out, e3) }
    out.big = big4
    out.nvars = n4
    out.vars = vars[0usize..n4]
    ret (out, ok)
}

// ---- writer (level 5, little endian, the layout R.matlab's writeMat produces) ----

fn round8(n: usize) -> usize { ret ((n + 7usize) / 8usize) * 8usize }

fn natural_type(cls: usize) -> usize {
    if cls == 4usize { ret 4usize }
    if cls == 6usize { ret 9usize }
    if cls == 7usize { ret 7usize }
    if cls == 8usize { ret 1usize }
    if cls == 9usize { ret 2usize }
    if cls == 10usize { ret 3usize }
    if cls == 11usize { ret 4usize }
    if cls == 12usize { ret 5usize }
    if cls == 13usize { ret 6usize }
    ret 0usize
}

fn supported(v: *const Var) -> bool {
    let cls = usize(v.class)
    if cls == 1usize || cls == 2usize {
        var k = 0usize
        while k < v.kids.len {
            if v.kids[k].class != 0u8 && !supported(&v.kids[k]) { ret false }
            k += 1usize
        }
        ret true
    }
    ret natural_type(cls) != 0usize
}

fn name_size(n: usize) -> usize {
    if n <= 4usize { ret 8usize }
    ret 8usize + round8(n)
}

fn part_size(ty: usize, n: usize) -> usize { ret 8usize + round8(n * size_of_type(ty)) }

// bytes of the miMATRIX payload (without its 8-byte tag)
fn payload_size(v: *const Var) -> usize {
    let cls = usize(v.class)
    var s = 16usize + 8usize + round8(4usize * v.nd) + name_size(v.name.len)
    if cls == 1usize || cls == 2usize {
        if cls == 2usize { s += 8usize + 8usize + round8(v.nf * v.flen) }
        var k = 0usize
        while k < v.kids.len {
            s += 8usize
            if v.kids[k].class != 0u8 { s += payload_size(&v.kids[k]) }
            k += 1usize
        }
        ret s
    }
    let ty = natural_type(cls)
    s += part_size(ty, v.count)
    if v.complex { s += part_size(ty, v.count) }
    ret s
}

fn put_u32(o: []u8, p: usize, x: usize) {
    o[p] = u8(x & 255usize)
    o[p + 1usize] = u8((x >> 8usize) & 255usize)
    o[p + 2usize] = u8((x >> 16usize) & 255usize)
    o[p + 3usize] = u8((x >> 24usize) & 255usize)
}

fn put_zero(o: []u8, p: usize, n: usize) {
    var i = 0usize
    while i < n {
        o[p + i] = 0u8
        i += 1usize
    }
}

// one value of MAT type `ty`, little endian, at p
fn put_value(o: []u8, p: usize, ty: usize, x: f64) {
    if ty == 9usize {
        let bits = mem.bitcast[u64](x)
        var k = 0usize
        while k < 8usize {
            o[p + k] = u8((bits >> u64(8usize * k)) & 255u64)
            k += 1usize
        }
    } else {
        if ty == 7usize {
            put_u32(o, p, usize(mem.bitcast[u32](f32(x))))
        } else {
            let sz = size_of_type(ty)
            var m = 1usize
            var k = 0usize
            while k < sz {
                m = m * 256usize
                k += 1usize
            }
            var y = x
            if y < 0.0f64 { y = y + f64(m) }
            let u = usize(y)
            k = 0usize
            while k < sz {
                o[p + k] = u8((u >> (8usize * k)) & 255usize)
                k += 1usize
            }
        }
    }
}

fn put_part(o: []u8, p: usize, ty: usize, vals: []const f64) -> usize {
    let n = vals.len * size_of_type(ty)
    put_u32(o, p, ty)
    put_u32(o, p + 4usize, n)
    var i = 0usize
    while i < vals.len {
        put_value(o, p + 8usize + i * size_of_type(ty), ty, vals[i])
        i += 1usize
    }
    put_zero(o, p + 8usize + n, round8(n) - n)
    ret p + 8usize + round8(n)
}

fn put_matrix(o: []u8, p0: usize, v: *const Var) -> usize {
    let cls = usize(v.class)
    put_u32(o, p0, 14usize)
    put_u32(o, p0 + 4usize, payload_size(v))
    var p = p0 + 8usize
    var fl = 0usize
    if v.logical { fl += 2usize }
    if v.global { fl += 4usize }
    if v.complex { fl += 8usize }
    put_u32(o, p, 6usize)
    put_u32(o, p + 4usize, 8usize)
    put_u32(o, p + 8usize, cls + 256usize * fl)
    put_u32(o, p + 12usize, 0usize)
    p += 16usize
    put_u32(o, p, 5usize)
    put_u32(o, p + 4usize, 4usize * v.nd)
    var d = 0usize
    while d < v.nd {
        put_u32(o, p + 8usize + 4usize * d, v.dims[d])
        d += 1usize
    }
    put_zero(o, p + 8usize + 4usize * v.nd, round8(4usize * v.nd) - 4usize * v.nd)
    p += 8usize + round8(4usize * v.nd)
    let nl = v.name.len
    if nl <= 4usize {
        if nl == 0usize {
            put_u32(o, p, 1usize)
            put_u32(o, p + 4usize, 0usize)
        } else {
            put_u32(o, p, 1usize + 65536usize * nl)
            put_zero(o, p + 4usize, 4usize)
            var k = 0usize
            while k < nl {
                o[p + 4usize + k] = v.name[k]
                k += 1usize
            }
        }
        p += 8usize
    } else {
        put_u32(o, p, 1usize)
        put_u32(o, p + 4usize, nl)
        var k = 0usize
        while k < nl {
            o[p + 8usize + k] = v.name[k]
            k += 1usize
        }
        put_zero(o, p + 8usize + nl, round8(nl) - nl)
        p += 8usize + round8(nl)
    }
    if cls == 1usize || cls == 2usize {
        if cls == 2usize {
            put_u32(o, p, 5usize + 65536usize * 4usize)
            put_u32(o, p + 4usize, v.flen)
            put_u32(o, p + 8usize, 1usize)
            put_u32(o, p + 12usize, v.nf * v.flen)
            var k = 0usize
            while k < v.nf * v.flen {
                o[p + 16usize + k] = v.fnames[k]
                k += 1usize
            }
            put_zero(o, p + 16usize + v.nf * v.flen, round8(v.nf * v.flen) - v.nf * v.flen)
            p += 16usize + round8(v.nf * v.flen)
        }
        var k = 0usize
        while k < v.kids.len {
            if v.kids[k].class == 0u8 {
                put_u32(o, p, 14usize)
                put_u32(o, p + 4usize, 0usize)
                p += 8usize
            } else {
                p = put_matrix(o, p, &v.kids[k])
            }
            k += 1usize
        }
        ret p
    }
    let ty = natural_type(cls)
    p = put_part(o, p, ty, v.re)
    if v.complex { p = put_part(o, p, ty, v.im) }
    ret p
}

fn write(a: *mem.Arena, vars: []const Var) -> ([]u8, err) {
    var total = 128usize
    var i = 0usize
    while i < vars.len {
        if !supported(&vars[i]) { ret (zero, Unsupported) }
        total += 8usize + payload_size(&vars[i])
        i += 1usize
    }
    let (o, e1) = mem.alloc[u8](a, total)
    if e1 != ok { ret (zero, e1) }
    var k = 0usize
    while k < 116usize {
        o[k] = 32u8
        k += 1usize
    }
    let text = "MATLAB 5.0 MAT-file, Platform: neper"
    k = 0usize
    while k < text.len {
        o[k] = text[k]
        k += 1usize
    }
    put_zero(o, 116usize, 8usize)
    o[124usize] = 0u8
    o[125usize] = 1u8
    o[126usize] = 73u8
    o[127usize] = 77u8
    var p = 128usize
    i = 0usize
    while i < vars.len {
        p = put_matrix(o, p, &vars[i])
        i += 1usize
    }
    ret (o, ok)
}
