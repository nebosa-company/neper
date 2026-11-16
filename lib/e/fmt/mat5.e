// MATLAB level 5 MAT-file reader (uncompressed, little-endian) as R.matlab::readMat reads it: the 128-byte header, then the data elements; each
// miMATRIX holds the array flags (class), the dimensions, the name and the real part. Numeric parts of any stored type become f64, characters become
// their code units. A file of several variables gives one `Var` each.
//
// Not here: compressed (miCOMPRESSED, v7) elements, big-endian files, structs, cells, sparse arrays, complex parts and v7.3 (HDF5) files.

use e.mem

error Malformed
error Unsupported
error TooMany

// class: the MATLAB class code (4 char, 6 double, 7 single, 8..15 integers, 9..10 ...); count: elements; sum: the sum of the real part
type Var = struct { class: u8, ndim: usize, rows: usize, cols: usize, count: usize, sum: f64, name_at: usize, name_len: usize }

type Mat = struct { nvars: usize, vars: []Var }

fn u32le(b: []const u8, at: usize) -> usize { ret usize(b[at]) + 256usize * usize(b[at + 1usize]) + 65536usize * usize(b[at + 2usize]) + 16777216usize * usize(b[at + 3usize]) }

fn pow2(e: usize) -> f64 {
    var r = 1.0f64
    var i = 0usize
    while i < e {
        r = r * 2.0f64
        i += 1usize
    }
    ret r
}

// element i of a numeric block of MAT type `ty` at `at`
fn numeric_at(b: []const u8, ty: usize, at: usize, i: usize) -> f64 {
    if ty == 1usize {
        var v = f64(b[at + i])
        if v > 127.0f64 { v -= 256.0f64 }
        ret v
    }
    if ty == 2usize { ret f64(b[at + i]) }
    if ty == 3usize {
        var v = f64(usize(b[at + 2usize * i]) + 256usize * usize(b[at + 2usize * i + 1usize]))
        if v > 32767.0f64 { v -= 65536.0f64 }
        ret v
    }
    if ty == 4usize { ret f64(usize(b[at + 2usize * i]) + 256usize * usize(b[at + 2usize * i + 1usize])) }
    if ty == 5usize {
        var v = f64(u32le(b, at + 4usize * i))
        if v > 2147483647.0f64 { v -= 4294967296.0f64 }
        ret v
    }
    if ty == 6usize { ret f64(u32le(b, at + 4usize * i)) }
    if ty == 7usize {
        // IEEE single
        let w = u32le(b, at + 4usize * i)
        let sign = (w >> 31usize) & 1usize
        let ex = (w >> 23usize) & 255usize
        let man = w & 8388607usize
        var v = 0.0f64
        if ex == 0usize {
            v = f64(man) / 8388608.0f64 / pow2(126usize)
        } else {
            v = (1.0f64 + f64(man) / 8388608.0f64) * pow2(ex) / pow2(127usize)
        }
        if sign == 1usize { v = 0.0f64 - v }
        ret v
    }
    if ty == 9usize {
        // IEEE double, assembled from two words
        let lo = u32le(b, at + 8usize * i)
        let hi = u32le(b, at + 8usize * i + 4usize)
        let sign = (hi >> 31usize) & 1usize
        let ex = (hi >> 20usize) & 2047usize
        let man = f64(hi & 1048575usize) * 4294967296.0f64 + f64(lo)
        var v = 0.0f64
        if ex == 0usize {
            v = man / 4503599627370496.0f64 / pow2(1022usize)
        } else {
            v = (1.0f64 + man / 4503599627370496.0f64)
            if ex >= 1023usize { v = v * pow2(ex - 1023usize) } else { v = v / pow2(1023usize - ex) }
        }
        if sign == 1usize { v = 0.0f64 - v }
        ret v
    }
    ret 0.0f64
}

fn size_of(ty: usize) -> usize {
    if ty == 1usize || ty == 2usize { ret 1usize }
    if ty == 3usize || ty == 4usize { ret 2usize }
    if ty == 5usize || ty == 6usize || ty == 7usize { ret 4usize }
    if ty == 9usize || ty == 12usize || ty == 13usize { ret 8usize }
    ret 0usize
}

fn parse(a: *mem.Arena, b: []const u8) -> (Mat, err) {
    var out: Mat = zero
    if b.len < 132usize { ret (out, Malformed) }
    if b[126usize] != 73u8 || b[127usize] != 77u8 { ret (out, Unsupported) }
    let (vars, e1) = mem.alloc[Var](a, 64usize)
    if e1 != ok { ret (out, e1) }
    var n = 0usize
    var p = 128usize
    while p + 8usize <= b.len {
        let t = u32le(b, p)
        if t == 15usize { ret (out, Unsupported) }
        if t != 14usize { ret (out, Unsupported) }
        let nb = u32le(b, p + 4usize)
        let end = p + 8usize + nb
        if end > b.len { ret (out, Malformed) }
        var q = p + 8usize
        var v: Var = zero
        // array flags
        let ft = u32le(b, q)
        if ft != 6usize { ret (out, Malformed) }
        v.class = b[q + 8usize]
        q += 16usize
        // dimensions
        let dt = u32le(b, q)
        let dn = u32le(b, q + 4usize)
        if dt != 5usize { ret (out, Malformed) }
        v.ndim = dn / 4usize
        v.rows = u32le(b, q + 8usize)
        v.cols = 1usize
        var cnt = v.rows
        var d = 1usize
        while d < v.ndim {
            let dd = u32le(b, q + 8usize + 4usize * d)
            cnt = cnt * dd
            if d == 1usize { v.cols = dd }
            d += 1usize
        }
        v.count = cnt
        q += 8usize + ((dn + 7usize) / 8usize) * 8usize
        // name (small element form when the upper half of the first word is non-zero)
        var nt = u32le(b, q)
        if nt >= 65536usize {
            v.name_len = nt >> 16usize
            v.name_at = q + 4usize
            q += 8usize
        } else {
            let nl = u32le(b, q + 4usize)
            v.name_len = nl
            v.name_at = q + 8usize
            q += 8usize + ((nl + 7usize) / 8usize) * 8usize
        }
        // the real part
        var rt = u32le(b, q)
        var rn = 0usize
        var ra = 0usize
        if rt >= 65536usize {
            rn = rt >> 16usize
            rt = rt & 65535usize
            ra = q + 4usize
        } else {
            rn = u32le(b, q + 4usize)
            ra = q + 8usize
        }
        let sz = size_of(rt)
        var s = 0.0f64
        if sz > 0usize {
            let total = rn / sz
            var i = 0usize
            while i < total && i < cnt {
                s += numeric_at(b, rt, ra, i)
                i += 1usize
            }
        }
        v.sum = s
        if n >= 64usize { ret (out, TooMany) }
        vars[n] = v
        n += 1usize
        p = end + (8usize - nb % 8usize) % 8usize
    }
    out.nvars = n
    out.vars = vars[0usize..n]
    ret (out, ok)
}
