// `e.fmt.elf` and `e.fmt.pe` against files built with `struct` by an independent writer: scripts/exe_vectors.py lays out ELF32/64
// (either byte order) and PE32/PE32+ images, walks them with its own reader and gives the expected dump; the fixture walks the
// same bytes with the codecs (every header, section, symbol, dynamic entry, import, export and RVA probe) and compares.
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.elf as elf
use e.fmt.json as json
use e.fmt.pe as pe
use e.io
use e.mem
use e.os
use e.str

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(81i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn bv(b: bool) -> json.Value { ret json.Value{ Bool: b } }

fn nv(a: *mem.Arena, n: f64) -> json.Value { ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, n) } } }

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, h: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(90i32) }
    var i = 0usize
    while i + 1usize < h.len {
        out[i / 2usize] = (nibble(h[i]) << 4u8) | nibble(h[i + 1usize])
        i += 2usize
    }
    ret out[0usize..h.len / 2usize]
}

// A u64 as minimal lowercase hex ("0" for zero), so 64-bit fields survive the f64 numbers of a JSON line.
fn hex64(a: *mem.Arena, v: u64) -> json.Value {
    let digits = "0123456789abcdef"
    let (out, e) = mem.alloc[u8](a, 17usize)
    if e != ok { os.exit(91i32) }
    var n = 0usize
    var shift = 60u64
    var started = false
    while true {
        let d = u8((v >> shift) & 15u64)
        if d != 0u8 || started || shift == 0u64 {
            started = true
            out[n] = digits[usize(d)]
            n += 1usize
        }
        if shift == 0u64 { break }
        shift -= 4u64
    }
    ret sv(out[0usize..n])
}

fn seal(a: *mem.Arena, items: []json.Value) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, items.len + 1usize)
    if e != ok { os.exit(92i32) }
    var i = 0usize
    while i < items.len {
        out[i] = items[i]
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..items.len] }
}

fn fail(a: *mem.Arena, truncated: bool) -> json.Value {
    var o = obj(a)
    put(&o, "ok", bv(false))
    if truncated {
        put(&o, "error", sv("truncated"))
    } else {
        put(&o, "error", sv("invalid"))
    }
    ret ir.obj_value(&o)
}

fn elf_dump(a: *mem.Arena, data: []const u8) -> json.Value {
    let (h, he) = elf.parse_header(data)
    if he != ok { ret fail(a, he == elf.Truncated) }
    var out = obj(a)
    var ho = obj(a)
    put(&ho, "class", nv(a, f64(h.class)))
    put(&ho, "little", bv(h.little))
    put(&ho, "version", nv(a, f64(h.version)))
    put(&ho, "osabi", nv(a, f64(h.osabi)))
    put(&ho, "abi", nv(a, f64(h.abi_version)))
    put(&ho, "kind", nv(a, f64(h.kind)))
    put(&ho, "machine", nv(a, f64(h.machine)))
    put(&ho, "entry", hex64(a, h.entry))
    put(&ho, "phoff", hex64(a, h.phoff))
    put(&ho, "shoff", hex64(a, h.shoff))
    put(&ho, "flags", nv(a, f64(h.flags)))
    put(&ho, "ehsize", nv(a, f64(h.ehsize)))
    put(&ho, "phentsize", nv(a, f64(h.phentsize)))
    put(&ho, "phnum", nv(a, f64(h.phnum)))
    put(&ho, "shentsize", nv(a, f64(h.shentsize)))
    put(&ho, "shnum", nv(a, f64(h.shnum)))
    put(&ho, "shstrndx", nv(a, f64(h.shstrndx)))
    put(&out, "hdr", ir.obj_value(&ho))
    var segs: [96]json.Value = zero
    var i = 0usize
    while i < usize(h.phnum) && i < 96usize {
        let (s, e) = elf.segment(data, h, i)
        if e != ok { ret fail(a, e == elf.Truncated) }
        var so = obj(a)
        put(&so, "kind", nv(a, f64(s.kind)))
        put(&so, "flags", nv(a, f64(s.flags)))
        put(&so, "off", hex64(a, s.offset))
        put(&so, "vaddr", hex64(a, s.vaddr))
        put(&so, "paddr", hex64(a, s.paddr))
        put(&so, "filesz", hex64(a, s.filesz))
        put(&so, "memsz", hex64(a, s.memsz))
        put(&so, "align", hex64(a, s.align))
        segs[i] = ir.obj_value(&so)
        i += 1usize
    }
    put(&out, "segs", seal(a, segs[0usize..i]))
    var secs: [96]json.Value = zero
    var syms: [96]json.Value = zero
    var dyns: [96]json.Value = zero
    var nsyms = 0usize
    var ndyns = 0usize
    var count = 0usize
    i = 0usize
    while i < usize(h.shnum) && i < 96usize {
        let (s, e) = elf.section(data, h, i)
        if e != ok { ret fail(a, e == elf.Truncated) }
        let (name, ne) = elf.section_name(data, h, s)
        if ne != ok { ret fail(a, ne == elf.Truncated) }
        var so = obj(a)
        put(&so, "name", sv(name))
        put(&so, "nameoff", nv(a, f64(s.name_offset)))
        put(&so, "kind", nv(a, f64(s.kind)))
        put(&so, "flags", hex64(a, s.flags))
        put(&so, "addr", hex64(a, s.addr))
        put(&so, "off", hex64(a, s.offset))
        put(&so, "size", hex64(a, s.size))
        put(&so, "link", nv(a, f64(s.link)))
        put(&so, "info", nv(a, f64(s.info)))
        put(&so, "align", hex64(a, s.addralign))
        put(&so, "entsize", hex64(a, s.entsize))
        secs[i] = ir.obj_value(&so)
        if s.kind == 2u32 || s.kind == 11u32 {
            let (strtab, te) = elf.section(data, h, usize(s.link))
            if te != ok { ret fail(a, te == elf.Truncated) }
            var j = 0usize
            var want = 16usize
            if h.class == 2u8 { want = 24usize }
            count = usize(s.size) / want
            while j < count && nsyms < 96usize {
                let (sym, se) = elf.symbol(data, h, s, j)
                if se != ok { ret fail(a, se == elf.Truncated) }
                let (sname, sne) = elf.string_at(data, strtab, sym.name_offset)
                if sne != ok { ret fail(a, sne == elf.Truncated) }
                var yo = obj(a)
                put(&yo, "sec", nv(a, f64(i)))
                put(&yo, "i", nv(a, f64(j)))
                put(&yo, "name", sv(sname))
                put(&yo, "info", nv(a, f64(sym.info)))
                put(&yo, "other", nv(a, f64(sym.other)))
                put(&yo, "shndx", nv(a, f64(sym.shndx)))
                put(&yo, "value", hex64(a, sym.value))
                put(&yo, "size", hex64(a, sym.size))
                syms[nsyms] = ir.obj_value(&yo)
                nsyms += 1usize
                j += 1usize
            }
        } else if s.kind == 6u32 {
            var j = 0usize
            var want = 8usize
            if h.class == 2u8 { want = 16usize }
            count = usize(s.size) / want
            while j < count && ndyns < 96usize {
                let (d, de) = elf.dynamic(data, h, s, j)
                if de != ok { ret fail(a, de == elf.Truncated) }
                var d_o = obj(a)
                put(&d_o, "sec", nv(a, f64(i)))
                put(&d_o, "i", nv(a, f64(j)))
                put(&d_o, "tag", hex64(a, d.tag))
                put(&d_o, "value", hex64(a, d.value))
                dyns[ndyns] = ir.obj_value(&d_o)
                ndyns += 1usize
                j += 1usize
            }
        }
        i += 1usize
    }
    put(&out, "secs", seal(a, secs[0usize..i]))
    put(&out, "syms", seal(a, syms[0usize..nsyms]))
    put(&out, "dyn", seal(a, dyns[0usize..ndyns]))
    var o = obj(a)
    put(&o, "ok", bv(true))
    put(&o, "v", ir.obj_value(&out))
    ret ir.obj_value(&o)
}

fn pe_dump(a: *mem.Arena, data: []const u8, probes: []const json.Value) -> json.Value {
    let (img, ie) = pe.parse(data)
    if ie != ok { ret fail(a, ie == pe.Truncated) }
    var out = obj(a)
    var io_ = obj(a)
    put(&io_, "machine", nv(a, f64(img.machine)))
    put(&io_, "nsec", nv(a, f64(img.section_count)))
    put(&io_, "ts", nv(a, f64(img.timestamp)))
    put(&io_, "chars", nv(a, f64(img.characteristics)))
    put(&io_, "magic", nv(a, f64(img.magic)))
    put(&io_, "plus", bv(img.plus))
    put(&io_, "entry", nv(a, f64(img.entry_rva)))
    put(&io_, "base", hex64(a, img.image_base))
    put(&io_, "salign", nv(a, f64(img.section_alignment)))
    put(&io_, "falign", nv(a, f64(img.file_alignment)))
    put(&io_, "subsys", nv(a, f64(img.subsystem)))
    put(&io_, "dllchars", nv(a, f64(img.dll_characteristics)))
    put(&io_, "imgsize", nv(a, f64(img.size_of_image)))
    put(&io_, "hdrsize", nv(a, f64(img.size_of_headers)))
    put(&io_, "ndirs", nv(a, f64(img.directory_count)))
    var dirs: [16]json.Value = zero
    var i = 0usize
    while i < 16usize {
        var pair: [2]json.Value = zero
        pair[0] = nv(a, f64(img.directories[i].rva))
        pair[1] = nv(a, f64(img.directories[i].size))
        dirs[i] = seal(a, pair[0usize..2usize])
        i += 1usize
    }
    put(&io_, "dirs", seal(a, dirs[0usize..16usize]))
    put(&out, "img", ir.obj_value(&io_))
    var secs: [96]json.Value = zero
    i = 0usize
    while i < usize(img.section_count) && i < 96usize {
        let (s, e) = pe.section(data, img, i)
        if e != ok { ret fail(a, e == pe.Truncated) }
        var so = obj(a)
        let n = pe.name_length(s)
        let (kept, ke) = mem.alloc[u8](a, 9usize)
        var b = 0usize
        while b < n {
            kept[b] = s.name[b]
            b += 1usize
        }
        put(&so, "name", sv(kept[0usize..n]))
        put(&so, "vsize", nv(a, f64(s.virtual_size)))
        put(&so, "va", nv(a, f64(s.virtual_address)))
        put(&so, "rsize", nv(a, f64(s.raw_size)))
        put(&so, "rptr", nv(a, f64(s.raw_pointer)))
        put(&so, "chars", nv(a, f64(s.characteristics)))
        secs[i] = ir.obj_value(&so)
        i += 1usize
    }
    put(&out, "secs", seal(a, secs[0usize..i]))
    var offs: [96]json.Value = zero
    i = 0usize
    while i < probes.len && i < 96usize {
        var x = 0.0f64
        switch probes[i] {
        case .Number as n:
            let (value, ne) = json.number_f64(n)
            x = value
        default:
            x = 0.0f64
        }
        let (off, e) = pe.rva_to_offset(data, img, u32(x))
        if e != ok {
            offs[i] = nv(a, -1.0f64)
        } else {
            offs[i] = nv(a, f64(off))
        }
        i += 1usize
    }
    put(&out, "probes", seal(a, offs[0usize..i]))
    var imports: [32]json.Value = zero
    var ni = 0usize
    while ni < 32usize {
        let (d, end, de) = pe.import_descriptor(data, img, ni)
        if de != ok { ret fail(a, de == pe.Truncated) }
        if end { break }
        let (dll, ne) = pe.string_at(data, img, d.name_rva)
        if ne != ok { ret fail(a, ne == pe.Truncated) }
        var funcs: [96]json.Value = zero
        var nf = 0usize
        while nf < 96usize {
            let (name, hint, by_name, tend, te) = pe.import_thunk(data, img, d, nf)
            if te != ok { ret fail(a, te == pe.Truncated) }
            if tend { break }
            var fo = obj(a)
            if by_name {
                put(&fo, "name", sv(name))
                put(&fo, "hint", nv(a, f64(hint)))
            } else {
                put(&fo, "ord", nv(a, f64(hint)))
            }
            funcs[nf] = ir.obj_value(&fo)
            nf += 1usize
        }
        var dobj = obj(a)
        put(&dobj, "dll", sv(dll))
        put(&dobj, "funcs", seal(a, funcs[0usize..nf]))
        imports[ni] = ir.obj_value(&dobj)
        ni += 1usize
    }
    put(&out, "imports", seal(a, imports[0usize..ni]))
    let (x, has, xe) = pe.exports(data, img)
    if xe != ok { ret fail(a, xe == pe.Truncated) }
    var xo = obj(a)
    put(&xo, "has", bv(has))
    if has {
        let (xname, xne) = pe.string_at(data, img, x.name_rva)
        if xne != ok { ret fail(a, xne == pe.Truncated) }
        put(&xo, "name", sv(xname))
        put(&xo, "base", nv(a, f64(x.ordinal_base)))
        put(&xo, "naddr", nv(a, f64(x.address_count)))
        put(&xo, "nnames", nv(a, f64(x.name_count)))
        var names: [96]json.Value = zero
        var k = 0usize
        while k < usize(x.name_count) && k < 96usize {
            let (name, ordinal, ee) = pe.export_name(data, img, x, k)
            if ee != ok { ret fail(a, ee == pe.Truncated) }
            var no = obj(a)
            put(&no, "name", sv(name))
            put(&no, "ord", nv(a, f64(ordinal)))
            names[k] = ir.obj_value(&no)
            k += 1usize
        }
        put(&xo, "names", seal(a, names[0usize..k]))
    }
    put(&out, "exports", ir.obj_value(&xo))
    var o = obj(a)
    put(&o, "ok", bv(true))
    put(&o, "v", ir.obj_value(&out))
    ret ir.obj_value(&o)
}

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let op = text_of(c, "op")
    let want = ir.value_of(c, "e")
    var got: json.Value = .Null
    let data = unhex(a, text_of(c, "h"))
    if str.eq(op, "elf") {
        got = elf_dump(a, data)
    } else {
        let (probes, is_array) = ir.items_of(ir.value_of(c, "probes"))
        got = pe_dump(a, data, probes)
    }
    let (g, ge) = chain.canonical_json(a, got)
    let (w, we) = chain.canonical_json(a, want)
    if ge != ok || we != ok { ret false }
    if !str.eq(g, w) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", g), f.join(a, "\nWANT ", w)))
        ret false
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 60u16 })
            if parse_error != ok || !run_one(a, root) {
                let shown = io.print(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("fmt exe ok")
    ret ok
}
