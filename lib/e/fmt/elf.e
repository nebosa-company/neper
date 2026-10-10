// ELF readers (L052): the file header of an ELF32 or ELF64 object in either byte order, the program (segment) headers, the
// section headers with names from the section-name string table, symbol-table entries with names from their string table,
// and the dynamic section's tags. Read-only and bounds-checked over the caller's bytes: a table, entry or string that
// lies outside the data is `Truncated`, an identification, class, size or index that cannot be is `Invalid`; strings borrow
// from the input and nothing allocates. No relocation processing and no disassembly.

error Truncated
error Invalid

type Header = struct { class: u8, little: bool, version: u8, osabi: u8, abi_version: u8, kind: u16, machine: u16, entry: u64, phoff: u64, shoff: u64, flags: u32, ehsize: u16, phentsize: u16, phnum: u16, shentsize: u16, shnum: u16, shstrndx: u16 }

type Segment = struct { kind: u32, flags: u32, offset: u64, vaddr: u64, paddr: u64, filesz: u64, memsz: u64, align: u64 }

type Section = struct { name_offset: u32, kind: u32, flags: u64, addr: u64, offset: u64, size: u64, link: u32, info: u32, addralign: u64, entsize: u64 }

type Symbol = struct { name_offset: u32, info: u8, other: u8, shndx: u16, value: u64, size: u64 }

type Dynamic = struct { tag: u64, value: u64 }

fn rd16(b: []const u8, at: usize, little: bool) -> u16 {
    if little { ret (u16(b[at + 1usize]) << 8u16) | u16(b[at]) }
    ret (u16(b[at]) << 8u16) | u16(b[at + 1usize])
}

fn rd32(b: []const u8, at: usize, little: bool) -> u32 {
    var v = 0u32
    var i = 0usize
    while i < 4usize {
        if little {
            v = v | (u32(b[at + i]) << u32(8usize * i))
        } else {
            v = (v << 8u32) | u32(b[at + i])
        }
        i += 1usize
    }
    ret v
}

fn rd64(b: []const u8, at: usize, little: bool) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        if little {
            v = v | (u64(b[at + i]) << u64(8usize * i))
        } else {
            v = (v << 8u64) | u64(b[at + i])
        }
        i += 1usize
    }
    ret v
}

fn fits(data: []const u8, offset: u64, length: u64) -> bool {
    let n = u64(data.len)
    if offset > n { ret false }
    ret length <= n - offset
}

// The ELF file header: the identification (`\x7fELF`, class 1 or 2, data 1 or 2) and the fixed fields.
fn parse_header(data: []const u8) -> (Header, err) {
    var h: Header = zero
    if data.len < 16usize { ret (h, Truncated) }
    if data[0] != 127u8 || data[1] != 69u8 || data[2] != 76u8 || data[3] != 70u8 { ret (h, Invalid) }
    h.class = data[4]
    if h.class != 1u8 && h.class != 2u8 { ret (h, Invalid) }
    if data[5] != 1u8 && data[5] != 2u8 { ret (h, Invalid) }
    h.little = data[5] == 1u8
    h.version = data[6]
    h.osabi = data[7]
    h.abi_version = data[8]
    var size = 52usize
    if h.class == 2u8 { size = 64usize }
    if data.len < size { ret (h, Truncated) }
    h.kind = rd16(data, 16usize, h.little)
    h.machine = rd16(data, 18usize, h.little)
    if h.class == 2u8 {
        h.entry = rd64(data, 24usize, h.little)
        h.phoff = rd64(data, 32usize, h.little)
        h.shoff = rd64(data, 40usize, h.little)
        h.flags = rd32(data, 48usize, h.little)
        h.ehsize = rd16(data, 52usize, h.little)
        h.phentsize = rd16(data, 54usize, h.little)
        h.phnum = rd16(data, 56usize, h.little)
        h.shentsize = rd16(data, 58usize, h.little)
        h.shnum = rd16(data, 60usize, h.little)
        h.shstrndx = rd16(data, 62usize, h.little)
    } else {
        h.entry = u64(rd32(data, 24usize, h.little))
        h.phoff = u64(rd32(data, 28usize, h.little))
        h.shoff = u64(rd32(data, 32usize, h.little))
        h.flags = rd32(data, 36usize, h.little)
        h.ehsize = rd16(data, 40usize, h.little)
        h.phentsize = rd16(data, 42usize, h.little)
        h.phnum = rd16(data, 44usize, h.little)
        h.shentsize = rd16(data, 46usize, h.little)
        h.shnum = rd16(data, 48usize, h.little)
        h.shstrndx = rd16(data, 50usize, h.little)
    }
    ret (h, ok)
}

// Program header `index`.
fn segment(data: []const u8, h: Header, index: usize) -> (Segment, err) {
    var s: Segment = zero
    var want = 32usize
    if h.class == 2u8 { want = 56usize }
    if usize(h.phentsize) != want { ret (s, Invalid) }
    if index >= usize(h.phnum) { ret (s, Invalid) }
    let at = h.phoff + u64(index) * u64(want)
    if !fits(data, at, u64(want)) { ret (s, Truncated) }
    let p = usize(at)
    if h.class == 2u8 {
        s.kind = rd32(data, p, h.little)
        s.flags = rd32(data, p + 4usize, h.little)
        s.offset = rd64(data, p + 8usize, h.little)
        s.vaddr = rd64(data, p + 16usize, h.little)
        s.paddr = rd64(data, p + 24usize, h.little)
        s.filesz = rd64(data, p + 32usize, h.little)
        s.memsz = rd64(data, p + 40usize, h.little)
        s.align = rd64(data, p + 48usize, h.little)
    } else {
        s.kind = rd32(data, p, h.little)
        s.offset = u64(rd32(data, p + 4usize, h.little))
        s.vaddr = u64(rd32(data, p + 8usize, h.little))
        s.paddr = u64(rd32(data, p + 12usize, h.little))
        s.filesz = u64(rd32(data, p + 16usize, h.little))
        s.memsz = u64(rd32(data, p + 20usize, h.little))
        s.flags = rd32(data, p + 24usize, h.little)
        s.align = u64(rd32(data, p + 28usize, h.little))
    }
    ret (s, ok)
}

// Section header `index`.
fn section(data: []const u8, h: Header, index: usize) -> (Section, err) {
    var s: Section = zero
    var want = 40usize
    if h.class == 2u8 { want = 64usize }
    if usize(h.shentsize) != want { ret (s, Invalid) }
    if index >= usize(h.shnum) { ret (s, Invalid) }
    let at = h.shoff + u64(index) * u64(want)
    if !fits(data, at, u64(want)) { ret (s, Truncated) }
    let p = usize(at)
    s.name_offset = rd32(data, p, h.little)
    s.kind = rd32(data, p + 4usize, h.little)
    if h.class == 2u8 {
        s.flags = rd64(data, p + 8usize, h.little)
        s.addr = rd64(data, p + 16usize, h.little)
        s.offset = rd64(data, p + 24usize, h.little)
        s.size = rd64(data, p + 32usize, h.little)
        s.link = rd32(data, p + 40usize, h.little)
        s.info = rd32(data, p + 44usize, h.little)
        s.addralign = rd64(data, p + 48usize, h.little)
        s.entsize = rd64(data, p + 56usize, h.little)
    } else {
        s.flags = u64(rd32(data, p + 8usize, h.little))
        s.addr = u64(rd32(data, p + 12usize, h.little))
        s.offset = u64(rd32(data, p + 16usize, h.little))
        s.size = u64(rd32(data, p + 20usize, h.little))
        s.link = rd32(data, p + 24usize, h.little)
        s.info = rd32(data, p + 28usize, h.little)
        s.addralign = u64(rd32(data, p + 32usize, h.little))
        s.entsize = u64(rd32(data, p + 36usize, h.little))
    }
    ret (s, ok)
}

// A NUL-terminated string at `offset` inside the string table section `table`, borrowed from `data`.
fn string_at(data: []const u8, table: Section, offset: u32) -> (str, err) {
    if table.kind != 3u32 { ret ("", Invalid) }
    if u64(offset) >= table.size { ret ("", Invalid) }
    if !fits(data, table.offset, table.size) { ret ("", Truncated) }
    let start = usize(table.offset) + usize(offset)
    let end = usize(table.offset) + usize(table.size)
    var i = start
    while i < end {
        if data[i] == 0u8 { let name: str = data[start..i]
        ret (name, ok) }
        i += 1usize
    }
    ret ("", Truncated)
}

// The name of a section, from the section-name string table the header points at.
fn section_name(data: []const u8, h: Header, s: Section) -> (str, err) {
    let (table, e) = section(data, h, usize(h.shstrndx))
    if e != ok { ret ("", e) }
    let (name, ne) = string_at(data, table, s.name_offset)
    ret (name, ne)
}

// Entry `index` of a symbol table section (`.symtab` or `.dynsym`).
fn symbol(data: []const u8, h: Header, table: Section, index: usize) -> (Symbol, err) {
    var sym: Symbol = zero
    var want = 16usize
    if h.class == 2u8 { want = 24usize }
    if table.entsize != u64(want) { ret (sym, Invalid) }
    if u64(index) >= table.size / u64(want) { ret (sym, Invalid) }
    let at = table.offset + u64(index) * u64(want)
    if !fits(data, at, u64(want)) { ret (sym, Truncated) }
    let p = usize(at)
    sym.name_offset = rd32(data, p, h.little)
    if h.class == 2u8 {
        sym.info = data[p + 4usize]
        sym.other = data[p + 5usize]
        sym.shndx = rd16(data, p + 6usize, h.little)
        sym.value = rd64(data, p + 8usize, h.little)
        sym.size = rd64(data, p + 16usize, h.little)
    } else {
        sym.value = u64(rd32(data, p + 4usize, h.little))
        sym.size = u64(rd32(data, p + 8usize, h.little))
        sym.info = data[p + 12usize]
        sym.other = data[p + 13usize]
        sym.shndx = rd16(data, p + 14usize, h.little)
    }
    ret (sym, ok)
}

// Entry `index` of a dynamic section.
fn dynamic(data: []const u8, h: Header, table: Section, index: usize) -> (Dynamic, err) {
    var d: Dynamic = zero
    var want = 8usize
    if h.class == 2u8 { want = 16usize }
    if u64(index) >= table.size / u64(want) { ret (d, Invalid) }
    let at = table.offset + u64(index) * u64(want)
    if !fits(data, at, u64(want)) { ret (d, Truncated) }
    let p = usize(at)
    if h.class == 2u8 {
        d.tag = rd64(data, p, h.little)
        d.value = rd64(data, p + 8usize, h.little)
    } else {
        d.tag = u64(rd32(data, p, h.little))
        d.value = u64(rd32(data, p + 4usize, h.little))
    }
    ret (d, ok)
}
