// netCDF classic (CDF-1 and the 64-bit offset CDF-2) reader as ncdf4 reads these files: the dimensions, the variables with their types and shapes, the global attribute
// names and the values of a variable in file (row-major, C) order as doubles, record variables included.
//
// Not here: netCDF-4 and HDF5 files, CDF-5, writing, attribute values and the scale, offset and fill handling ncdf4 leaves to the caller.

use e.mem
use e.str

// types: 1 byte, 2 char, 3 short, 4 int, 5 float, 6 double
type Nc = struct {
    version: usize,
    numrecs: usize,
    ndims: usize,
    dim_name: []str,
    dim_len: []usize,
    nvars: usize,
    var_name: []str,
    var_type: []usize,
    var_nd: []usize,
    var_dims: []usize,
    var_begin: []usize,
    var_vsize: []usize,
    recsize: usize,
    rec_dim: usize,
    natts: usize,
    gatt_at: usize,
    var_att_at: []usize
}

error BadNetcdf

fn be32(b: []const u8, at: usize) -> usize {
    ret usize(b[at]) * 16777216usize + usize(b[at + 1usize]) * 65536usize + usize(b[at + 2usize]) * 256usize + usize(b[at + 3usize])
}

fn pad4(n: usize) -> usize { ret (n + 3usize) / 4usize * 4usize }

fn type_size(t: usize) -> usize {
    if t == 1usize || t == 2usize { ret 1usize }
    if t == 3usize { ret 2usize }
    if t == 4usize || t == 5usize { ret 4usize }
    ret 8usize
}

// the name at `at` (a length then padded bytes); returns the name and the end position
fn read_name(a: *mem.Arena, b: []const u8, at: usize) -> (str, usize) {
    let n = be32(b, at)
    let (bb, be) = str.builder(a, n + 1usize)
    var sb = bb
    var i = 0usize
    while i < n {
        let _ = str.push_byte(&sb, b[at + 4usize + i])
        i += 1usize
    }
    let name = str.done(&sb)
    ret (name, at + 4usize + pad4(n))
}

// skips an attribute list starting at `at` and returns the position after it; counts the attributes
fn skip_atts(b: []const u8, at0: usize) -> (usize, usize) {
    var at = at0
    let tag = be32(b, at)
    let n = be32(b, at + 4usize)
    at += 8usize
    if tag == 0usize { ret (at, n) }
    var i = 0usize
    while i < n {
        let nl = be32(b, at)
        at += 4usize + pad4(nl)
        let t = be32(b, at)
        let ne = be32(b, at + 4usize)
        at += 8usize + pad4(ne * type_size(t))
        i += 1usize
    }
    ret (at, n)
}

fn parse(a: *mem.Arena, b: []const u8) -> (Nc, err) {
    var nc: Nc = zero
    if b.len < 12usize || b[0usize] != 67u8 || b[1usize] != 68u8 || b[2usize] != 70u8 { ret (nc, BadNetcdf) }
    nc.version = usize(b[3usize])
    if nc.version != 1usize && nc.version != 2usize { ret (nc, BadNetcdf) }
    nc.numrecs = be32(b, 4usize)
    var at = 8usize
    var tag = be32(b, at)
    let nd = be32(b, at + 4usize)
    at += 8usize
    nc.ndims = nd
    let (dn, e1) = mem.alloc[str](a, nd + 1usize)
    let (dl, e2) = mem.alloc[usize](a, nd + 1usize)
    if e1 != ok || e2 != ok { ret (nc, e1) }
    nc.rec_dim = 1000000usize
    var i = 0usize
    while i < nd {
        let (nm0, at0) = read_name(a, b, at)
        at = at0
        dn[i] = nm0
        dl[i] = be32(b, at)
        if dl[i] == 0usize { nc.rec_dim = i }
        at += 4usize
        i += 1usize
    }
    nc.dim_name = dn
    nc.dim_len = dl
    nc.gatt_at = at
    let (at2, ng) = skip_atts(b, at)
    at = at2
    nc.natts = ng
    tag = be32(b, at)
    let nv = be32(b, at + 4usize)
    at += 8usize
    nc.nvars = nv
    let (vn, e3) = mem.alloc[str](a, nv + 1usize)
    let (vt, e4) = mem.alloc[usize](a, nv + 1usize)
    let (vnd, e5) = mem.alloc[usize](a, nv + 1usize)
    let (vd, e6) = mem.alloc[usize](a, 8usize * nv + 8usize)
    let (vb, e7) = mem.alloc[usize](a, nv + 1usize)
    let (vs, e8) = mem.alloc[usize](a, nv + 1usize)
    let (vaa, e8b) = mem.alloc[usize](a, nv + 1usize)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e8b != ok { ret (nc, e3) }
    var rs = 0usize
    var nrecvars = 0usize
    var lastrec = 0usize
    i = 0usize
    while i < nv {
        let (nm1, at1) = read_name(a, b, at)
        at = at1
        vn[i] = nm1
        let ndm = be32(b, at)
        at += 4usize
        vnd[i] = ndm
        var j = 0usize
        while j < ndm && j < 8usize {
            vd[i * 8usize + j] = be32(b, at)
            at += 4usize
            j += 1usize
        }
        vaa[i] = at
        let (at3, _nv) = skip_atts(b, at)
        at = at3
        vt[i] = be32(b, at)
        vs[i] = be32(b, at + 4usize)
        at += 8usize
        if nc.version == 1usize {
            vb[i] = be32(b, at)
            at += 4usize
        } else {
            vb[i] = be32(b, at) * 4294967296usize + be32(b, at + 4usize)
            at += 8usize
        }
        if ndm > 0usize && vd[i * 8usize] == nc.rec_dim {
            rs += vs[i]
            nrecvars += 1usize
            lastrec = vs[i]
        }
        i += 1usize
    }
    // a single record variable is stored without padding between records
    if nrecvars == 1usize { rs = lastrec }
    nc.var_name = vn
    nc.var_type = vt
    nc.var_nd = vnd
    nc.var_dims = vd
    nc.var_begin = vb
    nc.var_vsize = vs
    nc.var_att_at = vaa
    nc.recsize = rs
    let _ = tag
    ret (nc, ok)
}

fn find_var(nc: *const Nc, name: str) -> usize {
    var i = 0usize
    while i < nc.nvars {
        if str.eq(nc.var_name[i], name) { ret i }
        i += 1usize
    }
    ret nc.nvars
}

fn find_dim(nc: *const Nc, name: str) -> usize {
    var i = 0usize
    while i < nc.ndims {
        if str.eq(nc.dim_name[i], name) { ret i }
        i += 1usize
    }
    ret nc.ndims
}

// the length of the dimension, the record dimension taking numrecs
fn dim_length(nc: *const Nc, d: usize) -> usize {
    if d == nc.rec_dim { ret nc.numrecs }
    ret nc.dim_len[d]
}

// the number of elements of variable v
fn var_count(nc: *const Nc, v: usize) -> usize {
    var n = 1usize
    var j = 0usize
    while j < nc.var_nd[v] {
        n *= dim_length(nc, nc.var_dims[v * 8usize + j])
        j += 1usize
    }
    ret n
}

fn element(b: []const u8, at: usize, t: usize) -> f64 {
    if t == 1usize {
        var v = i64(b[at])
        if v > 127i64 { v -= 256i64 }
        ret f64(v)
    }
    if t == 2usize { ret f64(b[at]) }
    if t == 3usize {
        var v = i64(b[at]) * 256i64 + i64(b[at + 1usize])
        if v > 32767i64 { v -= 65536i64 }
        ret f64(v)
    }
    if t == 4usize {
        var v = i64(be32(b, at))
        if v > 2147483647i64 { v -= 4294967296i64 }
        ret f64(v)
    }
    if t == 5usize {
        let bits = u32(be32(b, at))
        ret f64(mem.bitcast[f32](bits))
    }
    let hi = u64(be32(b, at))
    let lo = u64(be32(b, at + 4usize))
    ret mem.bitcast[f64](hi * 4294967296u64 + lo)
}

// the values of variable v in file order into out (var_count entries)
fn var_values(nc: *const Nc, b: []const u8, v: usize, out: []f64) {
    let t = nc.var_type[v]
    let sz = type_size(t)
    let nd = nc.var_nd[v]
    let total = var_count(nc, v)
    var is_rec = false
    if nd > 0usize && nc.var_dims[v * 8usize] == nc.rec_dim { is_rec = true }
    if !is_rec {
        var i = 0usize
        while i < total {
            out[i] = element(b, nc.var_begin[v] + i * sz, t)
            i += 1usize
        }
        ret
    }
    var per = 1usize
    var j = 1usize
    while j < nd {
        per *= dim_length(nc, nc.var_dims[v * 8usize + j])
        j += 1usize
    }
    var r = 0usize
    while r < nc.numrecs {
        var i = 0usize
        while i < per {
            out[r * per + i] = element(b, nc.var_begin[v] + r * nc.recsize + i * sz, t)
            i += 1usize
        }
        r += 1usize
    }
}

// finds attribute `name` in the list at `list_at`: answers (found, type, element count, value position)
fn find_att(a: *mem.Arena, b: []const u8, list_at: usize, name: str) -> (bool, usize, usize, usize) {
    var at = list_at
    let tag = be32(b, at)
    let n = be32(b, at + 4usize)
    at += 8usize
    if tag == 0usize { ret (false, 0usize, 0usize, 0usize) }
    var i = 0usize
    while i < n {
        let (nm, at1) = read_name(a, b, at)
        at = at1
        let t = be32(b, at)
        let ne = be32(b, at + 4usize)
        at += 8usize
        if str.eq(nm, name) { ret (true, t, ne, at) }
        at += pad4(ne * type_size(t))
        i += 1usize
    }
    ret (false, 0usize, 0usize, 0usize)
}

// the numeric value k of attribute `name` of variable v (v = nvars for a global attribute); NaN when the attribute is absent; a char attribute answers its k-th byte
fn att_value(a: *mem.Arena, nc: *const Nc, b: []const u8, v: usize, name: str, k: usize) -> f64 {
    var list = nc.gatt_at
    if v < nc.nvars { list = nc.var_att_at[v] }
    let (found, t, ne, pos) = find_att(a, b, list, name)
    if !found || k >= ne { ret 0.0f64 / 0.0f64 }
    ret element(b, pos + k * type_size(t), t)
}

// the element count of attribute `name` (0 when absent)
fn att_count(a: *mem.Arena, nc: *const Nc, b: []const u8, v: usize, name: str) -> usize {
    var list = nc.gatt_at
    if v < nc.nvars { list = nc.var_att_at[v] }
    let (found, t, ne, pos) = find_att(a, b, list, name)
    let _ = t
    let _ = pos
    if !found { ret 0usize }
    ret ne
}
