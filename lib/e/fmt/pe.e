// PE/COFF readers (L052): the DOS stub's `e_lfanew`, the PE signature, the COFF file header, the PE32 or PE32+ optional
// header with its sixteen data directories, the section table, RVA to file offset mapping, the import directory (DLL
// names and the functions or ordinals each thunk table lists) and the export directory's names. Read-only and
// bounds-checked over the caller's bytes: anything outside the data is `Truncated`, a signature, magic, count or index
// that cannot be is `Invalid`; names borrow from the input and nothing allocates. No resources, relocations or signatures.

error Truncated
error Invalid

type Directory = struct { rva: u32, size: u32 }

type Image = struct { machine: u16, section_count: u16, timestamp: u32, characteristics: u16, magic: u16, plus: bool, entry_rva: u32, image_base: u64, section_alignment: u32, file_alignment: u32, subsystem: u16, dll_characteristics: u16, size_of_image: u32, size_of_headers: u32, directory_count: u32, directories: [16]Directory, section_table: usize }

type Section = struct { name: [8]u8, virtual_size: u32, virtual_address: u32, raw_size: u32, raw_pointer: u32, characteristics: u32 }

type Import = struct { original_first_thunk: u32, timestamp: u32, forwarder: u32, name_rva: u32, first_thunk: u32 }

type Exports = struct { characteristics: u32, timestamp: u32, name_rva: u32, ordinal_base: u32, address_count: u32, name_count: u32, address_table: u32, name_table: u32, ordinal_table: u32 }

fn rd16(b: []const u8, at: usize) -> u16 { ret (u16(b[at + 1usize]) << 8u16) | u16(b[at]) }

fn rd32(b: []const u8, at: usize) -> u32 { ret (u32(b[at + 3usize]) << 24u32) | (u32(b[at + 2usize]) << 16u32) | (u32(b[at + 1usize]) << 8u32) | u32(b[at]) }

fn rd64(b: []const u8, at: usize) -> u64 { ret (u64(rd32(b, at + 4usize)) << 32u64) | u64(rd32(b, at)) }

fn fits(data: []const u8, offset: usize, length: usize) -> bool {
    if offset > data.len { ret false }
    ret length <= data.len - offset
}

// The headers of a PE image: MZ, `e_lfanew`, `PE\0\0`, the COFF header and the optional header (PE32 `0x10b` or PE32+
// `0x20b`); data directories beyond the optional header's declared count read as zero.
fn parse(data: []const u8) -> (Image, err) {
    var img: Image = zero
    if data.len < 64usize { ret (img, Truncated) }
    if data[0] != 77u8 || data[1] != 90u8 { ret (img, Invalid) }
    let lfanew = usize(rd32(data, 60usize))
    if !fits(data, lfanew, 24usize) { ret (img, Truncated) }
    if data[lfanew] != 80u8 || data[lfanew + 1usize] != 69u8 || data[lfanew + 2usize] != 0u8 || data[lfanew + 3usize] != 0u8 { ret (img, Invalid) }
    let coff = lfanew + 4usize
    img.machine = rd16(data, coff)
    img.section_count = rd16(data, coff + 2usize)
    img.timestamp = rd32(data, coff + 4usize)
    let optional_size = usize(rd16(data, coff + 16usize))
    img.characteristics = rd16(data, coff + 18usize)
    let opt = coff + 20usize
    if optional_size < 2usize || !fits(data, opt, optional_size) { ret (img, Truncated) }
    img.magic = rd16(data, opt)
    var dirs_at = 0usize
    if img.magic == 267u16 {
        img.plus = false
        if optional_size < 96usize { ret (img, Invalid) }
        img.entry_rva = rd32(data, opt + 16usize)
        img.image_base = u64(rd32(data, opt + 28usize))
        img.section_alignment = rd32(data, opt + 32usize)
        img.file_alignment = rd32(data, opt + 36usize)
        img.size_of_image = rd32(data, opt + 56usize)
        img.size_of_headers = rd32(data, opt + 60usize)
        img.subsystem = rd16(data, opt + 68usize)
        img.dll_characteristics = rd16(data, opt + 70usize)
        img.directory_count = rd32(data, opt + 92usize)
        dirs_at = opt + 96usize
    } else if img.magic == 523u16 {
        img.plus = true
        if optional_size < 112usize { ret (img, Invalid) }
        img.entry_rva = rd32(data, opt + 16usize)
        img.image_base = rd64(data, opt + 24usize)
        img.section_alignment = rd32(data, opt + 32usize)
        img.file_alignment = rd32(data, opt + 36usize)
        img.size_of_image = rd32(data, opt + 56usize)
        img.size_of_headers = rd32(data, opt + 60usize)
        img.subsystem = rd16(data, opt + 68usize)
        img.dll_characteristics = rd16(data, opt + 70usize)
        img.directory_count = rd32(data, opt + 108usize)
        dirs_at = opt + 112usize
    } else {
        ret (img, Invalid)
    }
    var i = 0usize
    while i < 16usize && u32(i) < img.directory_count {
        let p = dirs_at + i * 8usize
        if p + 8usize > opt + optional_size { break }
        img.directories[i] = Directory { rva: rd32(data, p), size: rd32(data, p + 4usize) }
        i += 1usize
    }
    img.section_table = opt + optional_size
    if !fits(data, img.section_table, usize(img.section_count) * 40usize) { ret (img, Truncated) }
    ret (img, ok)
}

// Section header `index`.
fn section(data: []const u8, img: Image, index: usize) -> (Section, err) {
    var s: Section = zero
    if index >= usize(img.section_count) { ret (s, Invalid) }
    let p = img.section_table + index * 40usize
    if !fits(data, p, 40usize) { ret (s, Truncated) }
    var i = 0usize
    while i < 8usize {
        s.name[i] = data[p + i]
        i += 1usize
    }
    s.virtual_size = rd32(data, p + 8usize)
    s.virtual_address = rd32(data, p + 12usize)
    s.raw_size = rd32(data, p + 16usize)
    s.raw_pointer = rd32(data, p + 20usize)
    s.characteristics = rd32(data, p + 36usize)
    ret (s, ok)
}

// The length of a section's name (up to the first NUL, at most eight bytes).
fn name_length(s: Section) -> usize {
    var n = 0usize
    while n < 8usize && s.name[n] != 0u8 { n += 1usize }
    ret n
}

// The file offset of a relative virtual address: inside the headers, or inside a section's raw data.
fn rva_to_offset(data: []const u8, img: Image, rva: u32) -> (usize, err) {
    if rva < img.size_of_headers { ret (usize(rva), ok) }
    var i = 0usize
    while i < usize(img.section_count) {
        let (s, e) = section(data, img, i)
        if e != ok { ret (0usize, e) }
        var span = s.virtual_size
        if span < s.raw_size { span = s.raw_size }
        if rva >= s.virtual_address && rva - s.virtual_address < span {
            let within = rva - s.virtual_address
            if within >= s.raw_size { ret (0usize, Invalid) }
            ret (usize(s.raw_pointer) + usize(within), ok)
        }
        i += 1usize
    }
    ret (0usize, Invalid)
}

// A NUL-terminated string at `rva`, borrowed from `data`.
fn string_at(data: []const u8, img: Image, rva: u32) -> (str, err) {
    let (start, e) = rva_to_offset(data, img, rva)
    if e != ok { ret ("", e) }
    var i = start
    while i < data.len {
        if data[i] == 0u8 {
            let name: str = data[start..i]
            ret (name, ok)
        }
        i += 1usize
    }
    ret ("", Truncated)
}

// Import descriptor `index` (directory 1); the last, all-zero descriptor reports `end` true.
fn import_descriptor(data: []const u8, img: Image, index: usize) -> (Import, bool, err) {
    var d: Import = zero
    if img.directory_count < 2u32 || img.directories[1].rva == 0u32 { ret (d, true, ok) }
    let (base, e) = rva_to_offset(data, img, img.directories[1].rva)
    if e != ok { ret (d, true, e) }
    let p = base + index * 20usize
    if !fits(data, p, 20usize) { ret (d, true, Truncated) }
    d.original_first_thunk = rd32(data, p)
    d.timestamp = rd32(data, p + 4usize)
    d.forwarder = rd32(data, p + 8usize)
    d.name_rva = rd32(data, p + 12usize)
    d.first_thunk = rd32(data, p + 16usize)
    if d.name_rva == 0u32 && d.first_thunk == 0u32 && d.original_first_thunk == 0u32 { ret (d, true, ok) }
    ret (d, false, ok)
}

// Thunk `index` of an import: a function name (`by_name` true, with its hint) or an ordinal; `end` at the zero entry.
fn import_thunk(data: []const u8, img: Image, imp: Import, index: usize) -> (str, u16, bool, bool, err) {
    var table = imp.original_first_thunk
    if table == 0u32 { table = imp.first_thunk }
    let (base, e) = rva_to_offset(data, img, table)
    if e != ok { ret ("", 0u16, false, true, e) }
    var width = 4usize
    if img.plus { width = 8usize }
    let p = base + index * width
    if !fits(data, p, width) { ret ("", 0u16, false, true, Truncated) }
    var value = u64(rd32(data, p))
    if img.plus { value = rd64(data, p) }
    if value == 0u64 { ret ("", 0u16, false, true, ok) }
    var ordinal_flag = 2147483648u64
    if img.plus { ordinal_flag = 9223372036854775808u64 }
    if (value & ordinal_flag) != 0u64 { ret ("", u16(value & 65535u64), false, false, ok) }
    let (hint_at, he) = rva_to_offset(data, img, u32(value))
    if he != ok { ret ("", 0u16, false, true, he) }
    if !fits(data, hint_at, 2usize) { ret ("", 0u16, false, true, Truncated) }
    let (name, ne) = string_at(data, img, u32(value) + 2u32)
    if ne != ok { ret ("", 0u16, false, true, ne) }
    ret (name, rd16(data, hint_at), true, false, ok)
}

// The export directory (directory 0); false when the image has none.
fn exports(data: []const u8, img: Image) -> (Exports, bool, err) {
    var x: Exports = zero
    if img.directory_count < 1u32 || img.directories[0].rva == 0u32 { ret (x, false, ok) }
    let (p, e) = rva_to_offset(data, img, img.directories[0].rva)
    if e != ok { ret (x, false, e) }
    if !fits(data, p, 40usize) { ret (x, false, Truncated) }
    x.characteristics = rd32(data, p)
    x.timestamp = rd32(data, p + 4usize)
    x.name_rva = rd32(data, p + 12usize)
    x.ordinal_base = rd32(data, p + 16usize)
    x.address_count = rd32(data, p + 20usize)
    x.name_count = rd32(data, p + 24usize)
    x.address_table = rd32(data, p + 28usize)
    x.name_table = rd32(data, p + 32usize)
    x.ordinal_table = rd32(data, p + 36usize)
    ret (x, true, ok)
}

// Exported name `index` and the ordinal (base added) it maps to.
fn export_name(data: []const u8, img: Image, x: Exports, index: usize) -> (str, u32, err) {
    if u32(index) >= x.name_count { ret ("", 0u32, Invalid) }
    let (names, e1) = rva_to_offset(data, img, x.name_table)
    if e1 != ok { ret ("", 0u32, e1) }
    if !fits(data, names + index * 4usize, 4usize) { ret ("", 0u32, Truncated) }
    let name_rva = rd32(data, names + index * 4usize)
    let (ordinals, e2) = rva_to_offset(data, img, x.ordinal_table)
    if e2 != ok { ret ("", 0u32, e2) }
    if !fits(data, ordinals + index * 2usize, 2usize) { ret ("", 0u32, Truncated) }
    let ordinal = u32(rd16(data, ordinals + index * 2usize)) + x.ordinal_base
    let (name, e3) = string_at(data, img, name_rva)
    if e3 != ok { ret ("", 0u32, e3) }
    ret (name, ordinal, ok)
}
