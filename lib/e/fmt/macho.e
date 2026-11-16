// Mach-O readers (L221): thin 32- and 64-bit images in either byte order, fat (universal) wrappers, the load-command walk, segments
// and their sections, the symbol table with names from its string table, the dyld-info offsets and the UUID command. Read-only and
// bounds-checked over the caller's bytes: a header, command, table, entry or string that lies outside the data is `Truncated`; a
// magic, size or count that cannot be is `Invalid`. Strings borrow from the input and nothing allocates. No relocation or bind
// opcode decoding and no code-signature parsing.

error Truncated
error Invalid

const MAGIC_32: u32 = 0xfeedfaceu32
const MAGIC_64: u32 = 0xfeedfacfu32
const FAT_MAGIC: u32 = 0xcafebabeu32
const FAT_MAGIC_64: u32 = 0xcafebabfu32

const LC_SEGMENT: u32 = 0x1u32
const LC_SYMTAB: u32 = 0x2u32
const LC_LOAD_DYLIB: u32 = 0xcu32
const LC_UUID: u32 = 0x1bu32
const LC_SEGMENT_64: u32 = 0x19u32
const LC_DYLD_INFO: u32 = 0x22u32
const LC_DYLD_INFO_ONLY: u32 = 0x80000022u32

type Header = struct { is64: bool, little: bool, cputype: u32, cpusubtype: u32, filetype: u32, ncmds: u32, sizeofcmds: u32, flags: u32, size: usize }

type Command = struct { cmd: u32, size: u32, at: usize }

type Segment = struct { name: []const u8, vmaddr: u64, vmsize: u64, fileoff: u64, filesize: u64, maxprot: u32, initprot: u32, nsects: u32, flags: u32 }

type Section = struct { name: []const u8, segment: []const u8, addr: u64, size: u64, offset: u32, align: u32, reloff: u32, nreloc: u32, flags: u32 }

type Symtab = struct { symoff: u32, nsyms: u32, stroff: u32, strsize: u32 }

type Symbol = struct { strx: u32, kind: u8, sect: u8, desc: u16, value: u64 }

type DyldInfo = struct { rebase_off: u32, rebase_size: u32, bind_off: u32, bind_size: u32, weak_bind_off: u32, weak_bind_size: u32, lazy_bind_off: u32, lazy_bind_size: u32, export_off: u32, export_size: u32 }

type FatArch = struct { cputype: u32, cpusubtype: u32, offset: u64, size: u64, align: u32 }

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

fn rd16(b: []const u8, at: usize, little: bool) -> u16 {
    if little { ret (u16(b[at + 1usize]) << 8u16) | u16(b[at]) }
    ret (u16(b[at]) << 8u16) | u16(b[at + 1usize])
}

fn fits(data: []const u8, offset: usize, length: usize) -> bool {
    if offset > data.len { ret false }
    ret length <= data.len - offset
}

// a fixed-size, NUL-padded name field of 16 bytes
fn name16(data: []const u8, at: usize) -> []const u8 {
    var n = 0usize
    while n < 16usize && data[at + n] != 0u8 { n += 1usize }
    ret data[at..at + n]
}

// the number of architectures in a fat file; Invalid when the data does not start with a fat magic
fn fat_count(data: []const u8) -> (usize, err) {
    if data.len < 8usize { ret (0usize, Truncated) }
    let magic = rd32(data, 0usize, false)
    if magic != FAT_MAGIC && magic != FAT_MAGIC_64 { ret (0usize, Invalid) }
    let n = rd32(data, 4usize, false)
    // a sane bound: Mach-O fat files hold a handful of architectures
    if n > 64u32 { ret (0usize, Invalid) }
    var w = 20usize
    if magic == FAT_MAGIC_64 { w = 32usize }
    if !fits(data, 8usize, usize(n) * w) { ret (0usize, Truncated) }
    ret (usize(n), ok)
}

// the i-th architecture of a fat file; its image is data[offset .. offset + size]
fn fat_arch(data: []const u8, index: usize) -> (FatArch, err) {
    let (n, e) = fat_count(data)
    if e != ok { ret (zero, e) }
    if index >= n { ret (zero, Invalid) }
    let magic = rd32(data, 0usize, false)
    var a: FatArch = zero
    if magic == FAT_MAGIC {
        let at = 8usize + index * 20usize
        a = FatArch { cputype: rd32(data, at, false), cpusubtype: rd32(data, at + 4usize, false), offset: u64(rd32(data, at + 8usize, false)), size: u64(rd32(data, at + 12usize, false)), align: rd32(data, at + 16usize, false) }
    } else {
        let at = 8usize + index * 32usize
        a = FatArch { cputype: rd32(data, at, false), cpusubtype: rd32(data, at + 4usize, false), offset: rd64(data, at + 8usize, false), size: rd64(data, at + 16usize, false), align: rd32(data, at + 24usize, false) }
    }
    if a.offset > u64(data.len) || a.size > u64(data.len) - a.offset { ret (zero, Truncated) }
    ret (a, ok)
}

// the Mach-O header of the image that starts at data[0]
fn header(data: []const u8) -> (Header, err) {
    if data.len < 4usize { ret (zero, Truncated) }
    let be = rd32(data, 0usize, false)
    var is64 = false
    var little = false
    if be == MAGIC_32 {
        little = false
    } else if be == MAGIC_64 {
        is64 = true
    } else {
        let le = rd32(data, 0usize, true)
        if le == MAGIC_32 {
            little = true
        } else if le == MAGIC_64 {
            little = true
            is64 = true
        } else {
            ret (zero, Invalid)
        }
    }
    var size = 28usize
    if is64 { size = 32usize }
    if data.len < size { ret (zero, Truncated) }
    let h = Header { is64: is64, little: little, cputype: rd32(data, 4usize, little), cpusubtype: rd32(data, 8usize, little), filetype: rd32(data, 12usize, little), ncmds: rd32(data, 16usize, little), sizeofcmds: rd32(data, 20usize, little), flags: rd32(data, 24usize, little), size: size }
    if !fits(data, size, usize(h.sizeofcmds)) { ret (zero, Truncated) }
    if h.ncmds > 4096u32 || usize(h.ncmds) * 8usize > usize(h.sizeofcmds) { ret (zero, Invalid) }
    ret (h, ok)
}

// the load command that starts at offset `at`, which must lie inside the command area
fn command_at(data: []const u8, h: *const Header, at: usize) -> (Command, err) {
    let end = h.size + usize(h.sizeofcmds)
    if at < h.size || at + 8usize > end { ret (zero, Truncated) }
    let cmd = rd32(data, at, h.little)
    let size = rd32(data, at + 4usize, h.little)
    if size < 8u32 || size % 4u32 != 0u32 { ret (zero, Invalid) }
    if at + usize(size) > end { ret (zero, Truncated) }
    ret (Command { cmd: cmd, size: size, at: at }, ok)
}

// the offset of the first load command of kind `want` at or after command index `from` (the walk restarts from the header each call); n when absent
fn find_command(data: []const u8, h: *const Header, want: u32, from: usize) -> (Command, bool, err) {
    var at = h.size
    var i = 0usize
    while i < usize(h.ncmds) {
        let (c, e) = command_at(data, h, at)
        if e != ok { ret (zero, false, e) }
        if i >= from && c.cmd == want { ret (c, true, ok) }
        at += usize(c.size)
        i += 1usize
    }
    ret (zero, false, ok)
}

// the segment a LC_SEGMENT or LC_SEGMENT_64 command describes
fn segment(data: []const u8, h: *const Header, c: *const Command) -> (Segment, err) {
    var need = 56usize
    if h.is64 { need = 72usize }
    if c.cmd != LC_SEGMENT && c.cmd != LC_SEGMENT_64 { ret (zero, Invalid) }
    if usize(c.size) < need { ret (zero, Invalid) }
    let at = c.at
    if h.is64 {
        ret (Segment { name: name16(data, at + 8usize), vmaddr: rd64(data, at + 24usize, h.little), vmsize: rd64(data, at + 32usize, h.little), fileoff: rd64(data, at + 40usize, h.little), filesize: rd64(data, at + 48usize, h.little), maxprot: rd32(data, at + 56usize, h.little), initprot: rd32(data, at + 60usize, h.little), nsects: rd32(data, at + 64usize, h.little), flags: rd32(data, at + 68usize, h.little) }, ok)
    }
    ret (Segment { name: name16(data, at + 8usize), vmaddr: u64(rd32(data, at + 24usize, h.little)), vmsize: u64(rd32(data, at + 28usize, h.little)), fileoff: u64(rd32(data, at + 32usize, h.little)), filesize: u64(rd32(data, at + 36usize, h.little)), maxprot: rd32(data, at + 40usize, h.little), initprot: rd32(data, at + 44usize, h.little), nsects: rd32(data, at + 48usize, h.little), flags: rd32(data, at + 52usize, h.little) }, ok)
}

// the i-th section of a segment command
fn section(data: []const u8, h: *const Header, c: *const Command, seg: *const Segment, index: usize) -> (Section, err) {
    var head = 56usize
    var width = 68usize
    if h.is64 {
        head = 72usize
        width = 80usize
    }
    if index >= usize(seg.nsects) { ret (zero, Invalid) }
    if usize(seg.nsects) * width > usize(c.size) - head { ret (zero, Truncated) }
    let at = c.at + head + index * width
    if h.is64 {
        ret (Section { name: name16(data, at), segment: name16(data, at + 16usize), addr: rd64(data, at + 32usize, h.little), size: rd64(data, at + 40usize, h.little), offset: rd32(data, at + 48usize, h.little), align: rd32(data, at + 52usize, h.little), reloff: rd32(data, at + 56usize, h.little), nreloc: rd32(data, at + 60usize, h.little), flags: rd32(data, at + 64usize, h.little) }, ok)
    }
    ret (Section { name: name16(data, at), segment: name16(data, at + 16usize), addr: u64(rd32(data, at + 32usize, h.little)), size: u64(rd32(data, at + 36usize, h.little)), offset: rd32(data, at + 40usize, h.little), align: rd32(data, at + 44usize, h.little), reloff: rd32(data, at + 48usize, h.little), nreloc: rd32(data, at + 52usize, h.little), flags: rd32(data, at + 56usize, h.little) }, ok)
}

fn symtab(data: []const u8, h: *const Header, c: *const Command) -> (Symtab, err) {
    if c.cmd != LC_SYMTAB || c.size < 24u32 { ret (zero, Invalid) }
    ret (Symtab { symoff: rd32(data, c.at + 8usize, h.little), nsyms: rd32(data, c.at + 12usize, h.little), stroff: rd32(data, c.at + 16usize, h.little), strsize: rd32(data, c.at + 20usize, h.little) }, ok)
}

// the i-th symbol-table entry
fn symbol(data: []const u8, h: *const Header, st: *const Symtab, index: usize) -> (Symbol, err) {
    if index >= usize(st.nsyms) { ret (zero, Invalid) }
    var width = 12usize
    if h.is64 { width = 16usize }
    if usize(st.nsyms) > data.len / width { ret (zero, Truncated) }
    let at = usize(st.symoff) + index * width
    if !fits(data, at, width) { ret (zero, Truncated) }
    var value = u64(rd32(data, at + 8usize, h.little))
    if h.is64 { value = rd64(data, at + 8usize, h.little) }
    ret (Symbol { strx: rd32(data, at, h.little), kind: data[at + 4usize], sect: data[at + 5usize], desc: rd16(data, at + 6usize, h.little), value: value }, ok)
}

// the NUL-terminated name at strx in the string table
fn symbol_name(data: []const u8, st: *const Symtab, strx: u32) -> ([]const u8, err) {
    if strx >= st.strsize { ret (zero, Invalid) }
    let base = usize(st.stroff)
    if !fits(data, base, usize(st.strsize)) { ret (zero, Truncated) }
    var n = usize(strx)
    let end = usize(st.strsize)
    while n < end && data[base + n] != 0u8 { n += 1usize }
    if n >= end { ret (zero, Truncated) }
    ret (data[base + usize(strx)..base + n], ok)
}

fn dyld_info(data: []const u8, h: *const Header, c: *const Command) -> (DyldInfo, err) {
    if (c.cmd != LC_DYLD_INFO && c.cmd != LC_DYLD_INFO_ONLY) || c.size < 48u32 { ret (zero, Invalid) }
    let at = c.at + 8usize
    ret (DyldInfo { rebase_off: rd32(data, at, h.little), rebase_size: rd32(data, at + 4usize, h.little), bind_off: rd32(data, at + 8usize, h.little), bind_size: rd32(data, at + 12usize, h.little), weak_bind_off: rd32(data, at + 16usize, h.little), weak_bind_size: rd32(data, at + 20usize, h.little), lazy_bind_off: rd32(data, at + 24usize, h.little), lazy_bind_size: rd32(data, at + 28usize, h.little), export_off: rd32(data, at + 32usize, h.little), export_size: rd32(data, at + 36usize, h.little) }, ok)
}

// the 16 UUID bytes of an LC_UUID command
fn uuid(data: []const u8, c: *const Command) -> ([]const u8, err) {
    if c.cmd != LC_UUID || c.size < 24u32 { ret (zero, Invalid) }
    ret (data[c.at + 8usize..c.at + 24usize], ok)
}

// the install name of an LC_LOAD_DYLIB command
fn dylib_name(data: []const u8, h: *const Header, c: *const Command) -> ([]const u8, err) {
    if c.cmd != LC_LOAD_DYLIB || c.size < 24u32 { ret (zero, Invalid) }
    let off = usize(rd32(data, c.at + 8usize, h.little))
    if off < 24usize || off >= usize(c.size) { ret (zero, Invalid) }
    var n = c.at + off
    let end = c.at + usize(c.size)
    while n < end && data[n] != 0u8 { n += 1usize }
    if n >= end { ret (zero, Truncated) }
    ret (data[c.at + off..n], ok)
}
