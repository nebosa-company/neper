use e.fmt.macho as mo
use e.io
use e.mem
use e.str

error Failed

fn put32(b: []u8, at: usize, v: u32, little: bool) {
    var i = 0usize
    while i < 4usize {
        var shift = u32(8usize * i)
        if !little { shift = u32(8usize * (3usize - i)) }
        b[at + i] = u8((v >> shift) & 255u32)
        i += 1usize
    }
}

fn put64(b: []u8, at: usize, v: u64) {
    var i = 0usize
    while i < 8usize {
        b[at + i] = u8((v >> u64(8usize * i)) & 255u64)
        i += 1usize
    }
}

fn putname(b: []u8, at: usize, name: str) {
    var i = 0usize
    while i < name.len {
        b[at + i] = name[i]
        i += 1usize
    }
}

// a little-endian 64-bit executable: __TEXT with one section, a symbol table of _main and _start, dyld info, a UUID and one dylib
fn build64(b: []u8) -> usize {
    put32(b, 0usize, 0xfeedfacfu32, true)
    put32(b, 4usize, 0x0100000cu32, true)
    put32(b, 8usize, 0u32, true)
    put32(b, 12usize, 2u32, true)
    put32(b, 16usize, 5u32, true)
    put32(b, 20usize, 300u32, true)
    put32(b, 24usize, 0x200085u32, true)
    // LC_SEGMENT_64 at 32, 152 bytes
    put32(b, 32usize, 0x19u32, true)
    put32(b, 36usize, 152u32, true)
    putname(b, 40usize, "__TEXT")
    put64(b, 56usize, 0x100000000u64)
    put64(b, 64usize, 0x4000u64)
    put64(b, 72usize, 0u64)
    put64(b, 80usize, 0x4000u64)
    put32(b, 88usize, 5u32, true)
    put32(b, 92usize, 5u32, true)
    put32(b, 96usize, 1u32, true)
    put32(b, 100usize, 0u32, true)
    putname(b, 104usize, "__text")
    putname(b, 120usize, "__TEXT")
    put64(b, 136usize, 0x100000400u64)
    put64(b, 144usize, 0x20u64)
    put32(b, 152usize, 0x400u32, true)
    put32(b, 156usize, 2u32, true)
    put32(b, 160usize, 0u32, true)
    put32(b, 164usize, 0u32, true)
    put32(b, 168usize, 0x80000400u32, true)
    // LC_SYMTAB at 184
    put32(b, 184usize, 2u32, true)
    put32(b, 188usize, 24u32, true)
    put32(b, 192usize, 336u32, true)
    put32(b, 196usize, 2u32, true)
    put32(b, 200usize, 368u32, true)
    put32(b, 204usize, 16u32, true)
    // LC_DYLD_INFO_ONLY at 208, 48 bytes
    put32(b, 208usize, 0x80000022u32, true)
    put32(b, 212usize, 48u32, true)
    put32(b, 216usize, 100u32, true)
    put32(b, 220usize, 8u32, true)
    put32(b, 224usize, 108u32, true)
    put32(b, 228usize, 16u32, true)
    put32(b, 232usize, 0u32, true)
    put32(b, 236usize, 0u32, true)
    put32(b, 240usize, 124u32, true)
    put32(b, 244usize, 12u32, true)
    put32(b, 248usize, 136u32, true)
    put32(b, 252usize, 40u32, true)
    // LC_UUID at 256
    put32(b, 256usize, 0x1bu32, true)
    put32(b, 260usize, 24u32, true)
    var i = 0usize
    while i < 16usize {
        b[264usize + i] = u8(0xa0usize + i)
        i += 1usize
    }
    // LC_LOAD_DYLIB at 280, 52 bytes
    put32(b, 280usize, 0xcu32, true)
    put32(b, 284usize, 52u32, true)
    put32(b, 288usize, 24u32, true)
    putname(b, 304usize, "/usr/lib/libSystem.B.dylib")
    // symbols at 336: _main (type 0x0f, section 1) and _start
    put32(b, 336usize, 1u32, true)
    b[340usize] = 0x0fu8
    b[341usize] = 1u8
    b[342usize] = 0u8
    b[343usize] = 0u8
    put64(b, 344usize, 0x100000400u64)
    put32(b, 352usize, 7u32, true)
    b[356usize] = 0x0fu8
    b[357usize] = 1u8
    put64(b, 360usize, 0x100000410u64)
    // strings at 368
    putname(b, 369usize, "_main")
    putname(b, 375usize, "_start")
    ret 384usize
}

fn eq(a: []const u8, s: str) -> bool {
    if a.len != s.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != s[i] { ret false }
        i += 1usize
    }
    ret true
}

fn check64(data: []const u8) -> err {
    let (h, he) = mo.header(data)
    if he != ok { ret he }
    if !h.is64 || !h.little || h.cputype != 0x0100000cu32 || h.filetype != 2u32 || h.ncmds != 5u32 || h.sizeofcmds != 300u32 || h.flags != 0x200085u32 { ret Failed }
    let (seg_cmd, found, fe) = mo.find_command(data, &h, mo.LC_SEGMENT_64, 0usize)
    if fe != ok || !found { ret Failed }
    let (seg, se) = mo.segment(data, &h, &seg_cmd)
    if se != ok { ret se }
    if !eq(seg.name, "__TEXT") || seg.vmaddr != 0x100000000u64 || seg.vmsize != 0x4000u64 || seg.filesize != 0x4000u64 || seg.maxprot != 5u32 || seg.nsects != 1u32 { ret Failed }
    let (sec, sce) = mo.section(data, &h, &seg_cmd, &seg, 0usize)
    if sce != ok { ret sce }
    if !eq(sec.name, "__text") || !eq(sec.segment, "__TEXT") || sec.addr != 0x100000400u64 || sec.size != 0x20u64 || sec.offset != 0x400u32 || sec.align != 2u32 || sec.flags != 0x80000400u32 { ret Failed }
    let (sym_cmd, sfound, sye) = mo.find_command(data, &h, mo.LC_SYMTAB, 0usize)
    if sye != ok || !sfound { ret Failed }
    let (st, ste) = mo.symtab(data, &h, &sym_cmd)
    if ste != ok { ret ste }
    if st.nsyms != 2u32 || st.symoff != 336u32 || st.stroff != 368u32 || st.strsize != 16u32 { ret Failed }
    let (s0, e0) = mo.symbol(data, &h, &st, 0usize)
    if e0 != ok { ret e0 }
    let (n0, ne0) = mo.symbol_name(data, &st, s0.strx)
    if ne0 != ok { ret ne0 }
    // nm: 0000000100000400 T _main
    if !eq(n0, "_main") || s0.kind != 0x0fu8 || s0.sect != 1u8 || s0.value != 0x100000400u64 { ret Failed }
    let (s1, e1) = mo.symbol(data, &h, &st, 1usize)
    if e1 != ok { ret e1 }
    let (n1, ne1) = mo.symbol_name(data, &st, s1.strx)
    if ne1 != ok { ret ne1 }
    if !eq(n1, "_start") || s1.value != 0x100000410u64 { ret Failed }
    let (_, e2) = mo.symbol(data, &h, &st, 2usize)
    if e2 != mo.Invalid { ret Failed }
    let (dy_cmd, dfound, de) = mo.find_command(data, &h, mo.LC_DYLD_INFO_ONLY, 0usize)
    if de != ok || !dfound { ret Failed }
    let (dy, dye) = mo.dyld_info(data, &h, &dy_cmd)
    if dye != ok { ret dye }
    if dy.rebase_off != 100u32 || dy.bind_size != 16u32 || dy.export_off != 136u32 || dy.export_size != 40u32 { ret Failed }
    let (u_cmd, ufound, ue) = mo.find_command(data, &h, mo.LC_UUID, 0usize)
    if ue != ok || !ufound { ret Failed }
    let (id, ide) = mo.uuid(data, &u_cmd)
    if ide != ok || id.len != 16usize || id[0usize] != 0xa0u8 || id[15usize] != 0xafu8 { ret Failed }
    let (l_cmd, lfound, le) = mo.find_command(data, &h, mo.LC_LOAD_DYLIB, 0usize)
    if le != ok || !lfound { ret Failed }
    let (nm, nme) = mo.dylib_name(data, &h, &l_cmd)
    if nme != ok || !eq(nm, "/usr/lib/libSystem.B.dylib") { ret Failed }
    let (_, missing, me) = mo.find_command(data, &h, mo.LC_SEGMENT, 0usize)
    if me != ok || missing { ret Failed }
    ret ok
}

// walk everything that can be read from a possibly truncated image; the only requirement is that nothing panics
fn walk(data: []const u8) {
    let (h, he) = mo.header(data)
    if he != ok { ret }
    var at = h.size
    var i = 0usize
    while i < usize(h.ncmds) {
        let (c, ce) = mo.command_at(data, &h, at)
        if ce != ok { ret }
        let (seg, se) = mo.segment(data, &h, &c)
        if se == ok {
            var k = 0usize
            while k < usize(seg.nsects) && k < 8usize {
                let (_, sce) = mo.section(data, &h, &c, &seg, k)
                if sce != ok { break }
                k += 1usize
            }
        }
        let (st, ste) = mo.symtab(data, &h, &c)
        if ste == ok {
            var k = 0usize
            while k < usize(st.nsyms) && k < 8usize {
                let (sym, sye) = mo.symbol(data, &h, &st, k)
                if sye != ok { break }
                let (_, ne) = mo.symbol_name(data, &st, sym.strx)
                if ne != ok { break }
                k += 1usize
            }
        }
        let (_, dye) = mo.dyld_info(data, &h, &c)
        let (_, ue) = mo.uuid(data, &c)
        let (_, le) = mo.dylib_name(data, &h, &c)
        at += usize(c.size)
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buf: [512]u8 = zero
    let n = build64(buf[..])
    let r = check64(buf[..n])
    if r != ok { ret r }
    // every truncation reads without panicking, and the header and command area are reported truncated
    var cut = 0usize
    while cut < n {
        walk(buf[..cut])
        cut += 1usize
    }
    let (_, te) = mo.header(buf[..40usize])
    if te != mo.Truncated { ret Failed }
    // a bad magic is invalid
    var bad: [64]u8 = zero
    let (_, ie) = mo.header(bad[..])
    if ie != mo.Invalid { ret Failed }
    // a big-endian 32-bit image: header, one LC_SEGMENT with no sections
    var be: [128]u8 = zero
    put32(be[..], 0usize, 0xfeedfaceu32, false)
    put32(be[..], 4usize, 7u32, false)
    put32(be[..], 12usize, 1u32, false)
    put32(be[..], 16usize, 1u32, false)
    put32(be[..], 20usize, 56u32, false)
    put32(be[..], 28usize, 1u32, false)
    put32(be[..], 32usize, 56u32, false)
    putname(be[..], 36usize, "__DATA")
    put32(be[..], 52usize, 0x1000u32, false)
    put32(be[..], 56usize, 0x2000u32, false)
    put32(be[..], 72usize, 3u32, false)
    let (bh, bhe) = mo.header(be[..84usize])
    if bhe != ok || bh.is64 || bh.little || bh.cputype != 7u32 || bh.filetype != 1u32 { ret Failed }
    let (bc, bce) = mo.command_at(be[..84usize], &bh, 28usize)
    if bce != ok || bc.cmd != 1u32 || bc.size != 56u32 { ret Failed }
    let (bs, bse) = mo.segment(be[..84usize], &bh, &bc)
    if bse != ok || !eq(bs.name, "__DATA") || bs.vmaddr != 0x1000u64 || bs.vmsize != 0x2000u64 || bs.initprot != 3u32 { ret Failed }
    // a fat wrapper holding the 64-bit image at offset 64
    var fat: [512]u8 = zero
    var total = 64usize + n
    put32(fat[..], 0usize, 0xcafebabeu32, false)
    put32(fat[..], 4usize, 1u32, false)
    put32(fat[..], 8usize, 0x0100000cu32, false)
    put32(fat[..], 12usize, 0u32, false)
    put32(fat[..], 16usize, 64u32, false)
    put32(fat[..], 20usize, u32(n), false)
    put32(fat[..], 24usize, 14u32, false)
    var i = 0usize
    while i < n {
        fat[64usize + i] = buf[i]
        i += 1usize
    }
    let (count, ce) = mo.fat_count(fat[..total])
    if ce != ok || count != 1usize { ret Failed }
    let (arch, ae) = mo.fat_arch(fat[..total], 0usize)
    if ae != ok || arch.offset != 64u64 || arch.size != u64(n) || arch.cputype != 0x0100000cu32 { ret Failed }
    let inner = check64(fat[usize(arch.offset)..usize(arch.offset + arch.size)])
    if inner != ok { ret inner }
    let (_, oe) = mo.fat_arch(fat[..total], 1usize)
    if oe != mo.Invalid { ret Failed }
    let (_, tfe) = mo.fat_arch(fat[..40usize], 0usize)
    if tfe != mo.Truncated { ret Failed }
    ret ok
}
