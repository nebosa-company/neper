// A linear-sweep x64 decoder over the encodings emit_x64.e produces (D269): one line per
// instruction, Intel operand order, the function-relative offset first and the bytes
// last. A byte the table does not know is a `db` line, never a failure -- code selection
// lays trap text inline after a jump (D-section 11), and a sweep walks through it.

error Capacity

type Cursor = struct {
    code: []const usize,
    at: usize,
    out: []u8,
    written: usize,
}

fn okay(e: err) -> bool {
    ret e == ok
}

fn put(c: *Cursor, value: u8) -> err {
    if c.written == c.out.len { ret Capacity }
    c.out[c.written] = value
    c.written += 1usize
    ret ok
}

fn puts(c: *Cursor, value: str) -> err {
    var at = 0usize
    while at < value.len {
        try put(c, value[at])
        at += 1usize
    }
    ret ok
}

fn hex_digit(value: usize) -> u8 {
    if value < 10usize { ret u8(48usize + value) }
    ret u8(87usize + value)
}

fn put_hex(c: *Cursor, value: usize, digits: usize) -> err {
    var shift = digits
    while shift > 0usize {
        shift = shift - 1usize
        try put(c, hex_digit((value >> (shift * 4usize)) & 15usize))
    }
    ret ok
}

// `0x..` with no leading zeros beyond one digit.
fn put_number(c: *Cursor, value: usize) -> err {
    try puts(c, "0x")
    var digits = 1usize
    while digits < 16usize && (value >> (digits * 4usize)) != 0usize { digits += 1usize }
    ret put_hex(c, value, digits)
}

// A displacement or immediate that was sign-extended: negative values print as `-0x..`.
fn put_signed(c: *Cursor, value: usize, bits: usize) -> err {
    let sign = 1usize << (bits - 1usize)
    if (value & sign) != 0usize {
        try put(c, 45u8)
        let magnitude = ((1usize << bits) - value) & ((1usize << bits) - 1usize)
        ret put_number(c, magnitude)
    }
    ret put_number(c, value)
}

fn register64(c: *Cursor, index: usize) -> err {
    if index == 0usize { ret puts(c, "rax") }
    if index == 1usize { ret puts(c, "rcx") }
    if index == 2usize { ret puts(c, "rdx") }
    if index == 3usize { ret puts(c, "rbx") }
    if index == 4usize { ret puts(c, "rsp") }
    if index == 5usize { ret puts(c, "rbp") }
    if index == 6usize { ret puts(c, "rsi") }
    if index == 7usize { ret puts(c, "rdi") }
    try put(c, 114u8)
    if index >= 10usize { try put(c, 49u8) }
    ret put(c, u8(48usize + index % 10usize))
}

fn register32(c: *Cursor, index: usize) -> err {
    if index >= 8usize {
        try register64(c, index)
        ret put(c, 100u8)
    }
    if index == 0usize { ret puts(c, "eax") }
    if index == 1usize { ret puts(c, "ecx") }
    if index == 2usize { ret puts(c, "edx") }
    if index == 3usize { ret puts(c, "ebx") }
    if index == 4usize { ret puts(c, "esp") }
    if index == 5usize { ret puts(c, "ebp") }
    if index == 6usize { ret puts(c, "esi") }
    ret puts(c, "edi")
}

fn register16(c: *Cursor, index: usize) -> err {
    if index >= 8usize {
        try register64(c, index)
        ret put(c, 119u8)
    }
    if index == 0usize { ret puts(c, "ax") }
    if index == 1usize { ret puts(c, "cx") }
    if index == 2usize { ret puts(c, "dx") }
    if index == 3usize { ret puts(c, "bx") }
    if index == 4usize { ret puts(c, "sp") }
    if index == 5usize { ret puts(c, "bp") }
    if index == 6usize { ret puts(c, "si") }
    ret puts(c, "di")
}

// With a REX prefix the four high byte registers are spl/bpl/sil/dil, not ah..bh.
fn register8(c: *Cursor, index: usize, rex: bool) -> err {
    if index >= 8usize {
        try register64(c, index)
        ret put(c, 98u8)
    }
    if index == 0usize { ret puts(c, "al") }
    if index == 1usize { ret puts(c, "cl") }
    if index == 2usize { ret puts(c, "dl") }
    if index == 3usize { ret puts(c, "bl") }
    if rex {
        if index == 4usize { ret puts(c, "spl") }
        if index == 5usize { ret puts(c, "bpl") }
        if index == 6usize { ret puts(c, "sil") }
        ret puts(c, "dil")
    }
    if index == 4usize { ret puts(c, "ah") }
    if index == 5usize { ret puts(c, "ch") }
    if index == 6usize { ret puts(c, "dh") }
    ret puts(c, "bh")
}

fn register_xmm(c: *Cursor, index: usize) -> err {
    try puts(c, "xmm")
    if index >= 10usize { try put(c, 49u8) }
    ret put(c, u8(48usize + index % 10usize))
}

// A register operand by width: 0 byte, 1 word, 2 dword, 3 qword, 4 xmm.
fn register(c: *Cursor, index: usize, width: usize, rex: bool) -> err {
    if width == 0usize { ret register8(c, index, rex) }
    if width == 1usize { ret register16(c, index) }
    if width == 2usize { ret register32(c, index) }
    if width == 4usize { ret register_xmm(c, index) }
    ret register64(c, index)
}

fn size_word(c: *Cursor, width: usize) -> err {
    if width == 0usize { ret puts(c, "byte ") }
    if width == 1usize { ret puts(c, "word ") }
    if width == 2usize { ret puts(c, "dword ") }
    ret puts(c, "qword ")
}

fn fetch(c: *Cursor) -> (usize, bool) {
    if c.at >= c.code.len { ret (0usize, false) }
    let value = c.code[c.at] & 255usize
    c.at += 1usize
    ret (value, true)
}

fn fetch_little_at(code: []const usize, at: usize) -> (usize, bool) {
    if at + 4usize > code.len { ret (0usize, false) }
    var value = 0usize
    var index = 0usize
    while index < 4usize {
        value = value | ((code[at + index] & 255usize) << (index * 8usize))
        index += 1usize
    }
    ret (value, true)
}

fn fetch_little(c: *Cursor, count: usize) -> (usize, bool) {
    var value = 0usize
    var index = 0usize
    while index < count {
        let (octet, present) = fetch(c)
        if !present { ret (0usize, false) }
        value = value | (octet << (index * 8usize))
        index += 1usize
    }
    ret (value, true)
}

// The r/m operand of a ModRM byte already fetched: a register of `width`, or a memory
// operand -- `[base]`, `[base + disp]`, `[rsp]` through a SIB, `[rip + disp32]`.
// Returns the reg field, and whether the bytes were all there.
fn operand_rm(c: *Cursor, modrm: usize, rex_r: bool, rex_x: bool, rex_b: bool, width: usize, rex: bool) -> (usize, bool) {
    let mode = modrm >> 6usize
    var reg = (modrm >> 3usize) & 7usize
    if rex_r { reg += 8usize }
    var rm = modrm & 7usize
    if mode == 3usize {
        if rex_b { rm += 8usize }
        let register_error = register(c, rm, width, rex)
        ret (reg, register_error == ok)
    }
    var size_error = size_word(c, width)
    if width == 4usize { size_error = ok }
    if size_error != ok { ret (reg, false) }
    let open_error = put(c, 91u8)
    if open_error != ok { ret (reg, false) }
    var base = rm
    var index = 16usize
    var scale = 0usize
    var has_sib = false
    if rm == 4usize {
        let (sib, sib_present) = fetch(c)
        if !sib_present { ret (reg, false) }
        has_sib = true
        scale = sib >> 6usize
        index = (sib >> 3usize) & 7usize
        if rex_x { index += 8usize }
        base = sib & 7usize
        if index == 4usize { index = 16usize }
    }
    if rex_b { base += 8usize }
    var displacement = 0usize
    var displacement_bits = 0usize
    if mode == 0usize && (base & 7usize) == 5usize {
        if has_sib {
            // No base: a bare disp32.
            let (disp, present) = fetch_little(c, 4usize)
            if !present { ret (reg, false) }
            base = 17usize
            displacement = disp
            displacement_bits = 32usize
        } else {
            let (disp, present) = fetch_little(c, 4usize)
            if !present { ret (reg, false) }
            let rip_error = puts(c, "rip")
            if rip_error != ok { ret (reg, false) }
            base = 18usize
            displacement = disp
            displacement_bits = 32usize
        }
    } else {
        if mode == 1usize {
            let (disp, present) = fetch(c)
            if !present { ret (reg, false) }
            displacement = disp
            displacement_bits = 8usize
        }
        if mode == 2usize {
            let (disp, present) = fetch_little(c, 4usize)
            if !present { ret (reg, false) }
            displacement = disp
            displacement_bits = 32usize
        }
    }
    if base < 16usize {
        let base_error = register64(c, base)
        if base_error != ok { ret (reg, false) }
    }
    if index < 16usize {
        if base < 16usize {
            let plus_error = puts(c, " + ")
            if plus_error != ok { ret (reg, false) }
        }
        let index_error = register64(c, index)
        if index_error != ok { ret (reg, false) }
        if scale != 0usize {
            let scale_error = puts(c, "*")
            if scale_error != ok { ret (reg, false) }
            let factor_error = put(c, u8(48usize + (1usize << scale)))
            if factor_error != ok { ret (reg, false) }
        }
    }
    if displacement_bits != 0usize && (displacement != 0usize || base == 17usize) {
        if base != 17usize {
            let sign = 1usize << (displacement_bits - 1usize)
            if (displacement & sign) != 0usize {
                let minus_error = puts(c, " - ")
                if minus_error != ok { ret (reg, false) }
                let magnitude = ((1usize << displacement_bits) - displacement) & ((1usize << displacement_bits) - 1usize)
                let magnitude_error = put_number(c, magnitude)
                if magnitude_error != ok { ret (reg, false) }
            } else {
                let plus_error = puts(c, " + ")
                if plus_error != ok { ret (reg, false) }
                let value_error = put_number(c, displacement)
                if value_error != ok { ret (reg, false) }
            }
        } else {
            let value_error = put_number(c, displacement)
            if value_error != ok { ret (reg, false) }
        }
    }
    let close_error = put(c, 93u8)
    ret (reg, close_error == ok)
}

fn condition_name(c: *Cursor, condition: usize) -> err {
    if condition == 0usize { ret puts(c, "o") }
    if condition == 1usize { ret puts(c, "no") }
    if condition == 2usize { ret puts(c, "b") }
    if condition == 3usize { ret puts(c, "ae") }
    if condition == 4usize { ret puts(c, "e") }
    if condition == 5usize { ret puts(c, "ne") }
    if condition == 6usize { ret puts(c, "be") }
    if condition == 7usize { ret puts(c, "a") }
    if condition == 8usize { ret puts(c, "s") }
    if condition == 9usize { ret puts(c, "ns") }
    if condition == 10usize { ret puts(c, "p") }
    if condition == 11usize { ret puts(c, "np") }
    if condition == 12usize { ret puts(c, "l") }
    if condition == 13usize { ret puts(c, "ge") }
    if condition == 14usize { ret puts(c, "le") }
    ret puts(c, "g")
}

fn group1_name(c: *Cursor, extension: usize) -> err {
    if extension == 0usize { ret puts(c, "add ") }
    if extension == 1usize { ret puts(c, "or ") }
    if extension == 2usize { ret puts(c, "adc ") }
    if extension == 3usize { ret puts(c, "sbb ") }
    if extension == 4usize { ret puts(c, "and ") }
    if extension == 5usize { ret puts(c, "sub ") }
    if extension == 6usize { ret puts(c, "xor ") }
    ret puts(c, "cmp ")
}

fn shift_name(c: *Cursor, extension: usize) -> err {
    if extension == 0usize { ret puts(c, "rol ") }
    if extension == 1usize { ret puts(c, "ror ") }
    if extension == 4usize { ret puts(c, "shl ") }
    if extension == 5usize { ret puts(c, "shr ") }
    if extension == 7usize { ret puts(c, "sar ") }
    ret puts(c, "shx ")
}

fn group3_name(c: *Cursor, extension: usize) -> err {
    if extension == 0usize { ret puts(c, "test ") }
    if extension == 2usize { ret puts(c, "not ") }
    if extension == 3usize { ret puts(c, "neg ") }
    if extension == 4usize { ret puts(c, "mul ") }
    if extension == 5usize { ret puts(c, "imul ") }
    if extension == 6usize { ret puts(c, "div ") }
    ret puts(c, "idiv ")
}

// `reg, r/m` or `r/m, reg` around one ModRM byte.
fn two_operands(c: *Cursor, reg_first: bool, width: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex: bool, reg_width: usize) -> bool {
    let (modrm, present) = fetch(c)
    if !present { ret false }
    if reg_first {
        var reg = (modrm >> 3usize) & 7usize
        if rex_r { reg += 8usize }
        if !okay(register(c, reg, reg_width, rex)) { ret false }
        if !okay(puts(c, ", ")) { ret false }
        let (unused, rm_ok) = operand_rm(c, modrm, rex_r, rex_x, rex_b, width, rex)
        ret rm_ok
    }
    let (reg, rm_ok) = operand_rm(c, modrm, rex_r, rex_x, rex_b, width, rex)
    if !rm_ok { ret false }
    if !okay(puts(c, ", ")) { ret false }
    ret okay(register(c, reg, reg_width, rex))
}

// One instruction at the cursor; false when the bytes ran out or no table row matched,
// in which case the caller writes a `db` for the byte at `start`.
fn instruction(c: *Cursor, start: usize) -> bool {
    var lock = false
    var repeat = 0usize
    var operand16 = false
    var rex = false
    var rex_w = false
    var rex_r = false
    var rex_x = false
    var rex_b = false
    let (first, present) = fetch(c)
    var opcode = first
    if !present { ret false }
    var prefixes = 0usize
    while prefixes < 4usize && (opcode == 240usize || opcode == 243usize || opcode == 242usize || opcode == 102usize) {
        if opcode == 240usize { lock = true }
        if opcode == 243usize || opcode == 242usize { repeat = opcode }
        if opcode == 102usize { operand16 = true }
        let (next, next_present) = fetch(c)
        if !next_present { ret false }
        opcode = next
        prefixes += 1usize
    }
    if opcode >= 64usize && opcode <= 79usize {
        rex = true
        rex_w = (opcode & 8usize) != 0usize
        rex_r = (opcode & 4usize) != 0usize
        rex_x = (opcode & 2usize) != 0usize
        rex_b = (opcode & 1usize) != 0usize
        let (next, next_present) = fetch(c)
        if !next_present { ret false }
        opcode = next
    }
    var width = 2usize
    if rex_w { width = 3usize }
    if operand16 { width = 1usize }
    if lock { if !okay(puts(c, "lock ")) { ret false } }
    // One-byte opcodes.
    if opcode == 195usize { ret okay(puts(c, "ret")) }
    if opcode == 144usize { ret okay(puts(c, "nop")) }
    if opcode == 204usize { ret okay(puts(c, "int3")) }
    if opcode == 153usize {
        if rex_w { ret okay(puts(c, "cqo")) }
        ret okay(puts(c, "cdq"))
    }
    if opcode >= 80usize && opcode <= 87usize {
        if !okay(puts(c, "push ")) { ret false }
        var reg = opcode - 80usize
        if rex_b { reg += 8usize }
        ret okay(register64(c, reg))
    }
    if opcode >= 88usize && opcode <= 95usize {
        if !okay(puts(c, "pop ")) { ret false }
        var reg = opcode - 88usize
        if rex_b { reg += 8usize }
        ret okay(register64(c, reg))
    }
    if opcode >= 184usize && opcode <= 191usize {
        if !okay(puts(c, "mov ")) { ret false }
        var reg = opcode - 184usize
        if rex_b { reg += 8usize }
        if !okay(register(c, reg, width, rex)) { ret false }
        if !okay(puts(c, ", ")) { ret false }
        var immediate_bytes = 4usize
        if rex_w { immediate_bytes = 8usize }
        if operand16 { immediate_bytes = 2usize }
        let (value, value_present) = fetch_little(c, immediate_bytes)
        if !value_present { ret false }
        ret okay(put_number(c, value))
    }
    if opcode == 1usize || opcode == 9usize || opcode == 33usize || opcode == 41usize || opcode == 49usize || opcode == 57usize || opcode == 137usize || opcode == 133usize || opcode == 135usize {
        if opcode == 1usize { if !okay(puts(c, "add ")) { ret false } }
        if opcode == 9usize { if !okay(puts(c, "or ")) { ret false } }
        if opcode == 33usize { if !okay(puts(c, "and ")) { ret false } }
        if opcode == 41usize { if !okay(puts(c, "sub ")) { ret false } }
        if opcode == 49usize { if !okay(puts(c, "xor ")) { ret false } }
        if opcode == 57usize { if !okay(puts(c, "cmp ")) { ret false } }
        if opcode == 137usize { if !okay(puts(c, "mov ")) { ret false } }
        if opcode == 133usize { if !okay(puts(c, "test ")) { ret false } }
        if opcode == 135usize { if !okay(puts(c, "xchg ")) { ret false } }
        ret two_operands(c, false, width, rex_r, rex_x, rex_b, rex, width)
    }
    if opcode == 136usize || opcode == 134usize {
        if opcode == 136usize { if !okay(puts(c, "mov ")) { ret false } }
        if opcode == 134usize { if !okay(puts(c, "xchg ")) { ret false } }
        ret two_operands(c, false, 0usize, rex_r, rex_x, rex_b, rex, 0usize)
    }
    if opcode == 3usize || opcode == 11usize || opcode == 35usize || opcode == 43usize || opcode == 51usize || opcode == 59usize || opcode == 139usize || opcode == 141usize {
        if opcode == 3usize { if !okay(puts(c, "add ")) { ret false } }
        if opcode == 11usize { if !okay(puts(c, "or ")) { ret false } }
        if opcode == 35usize { if !okay(puts(c, "and ")) { ret false } }
        if opcode == 43usize { if !okay(puts(c, "sub ")) { ret false } }
        if opcode == 51usize { if !okay(puts(c, "xor ")) { ret false } }
        if opcode == 59usize { if !okay(puts(c, "cmp ")) { ret false } }
        if opcode == 139usize { if !okay(puts(c, "mov ")) { ret false } }
        if opcode == 141usize { if !okay(puts(c, "lea ")) { ret false } }
        ret two_operands(c, true, width, rex_r, rex_x, rex_b, rex, width)
    }
    if opcode == 138usize {
        if !okay(puts(c, "mov ")) { ret false }
        ret two_operands(c, true, 0usize, rex_r, rex_x, rex_b, rex, 0usize)
    }
    if opcode == 99usize {
        if !okay(puts(c, "movsxd ")) { ret false }
        ret two_operands(c, true, 2usize, rex_r, rex_x, rex_b, rex, 3usize)
    }
    if opcode == 129usize || opcode == 131usize {
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        if !okay(group1_name(c, (modrm >> 3usize) & 7usize)) { ret false }
        let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, width, rex)
        if !rm_ok { ret false }
        if !okay(puts(c, ", ")) { ret false }
        var immediate_bytes = 1usize
        var bits = 8usize
        if opcode == 129usize {
            immediate_bytes = 4usize
            bits = 32usize
            if operand16 {
                immediate_bytes = 2usize
                bits = 16usize
            }
        }
        let (value, value_present) = fetch_little(c, immediate_bytes)
        if !value_present { ret false }
        ret okay(put_signed(c, value, bits))
    }
    if opcode == 128usize {
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        if !okay(group1_name(c, (modrm >> 3usize) & 7usize)) { ret false }
        let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, 0usize, rex)
        if !rm_ok { ret false }
        if !okay(puts(c, ", ")) { ret false }
        let (value, value_present) = fetch(c)
        if !value_present { ret false }
        ret okay(put_number(c, value))
    }
    if opcode == 199usize || opcode == 198usize {
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        if !okay(puts(c, "mov ")) { ret false }
        var store_width = width
        if opcode == 198usize { store_width = 0usize }
        let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, store_width, rex)
        if !rm_ok { ret false }
        if !okay(puts(c, ", ")) { ret false }
        var immediate_bytes = 4usize
        var bits = 32usize
        if opcode == 198usize {
            immediate_bytes = 1usize
            bits = 8usize
        }
        if operand16 && opcode == 199usize {
            immediate_bytes = 2usize
            bits = 16usize
        }
        let (value, value_present) = fetch_little(c, immediate_bytes)
        if !value_present { ret false }
        ret okay(put_signed(c, value, bits))
    }
    if opcode == 247usize || opcode == 246usize {
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        let extension = (modrm >> 3usize) & 7usize
        if !okay(group3_name(c, extension)) { ret false }
        var group_width = width
        if opcode == 246usize { group_width = 0usize }
        let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, group_width, rex)
        if !rm_ok { ret false }
        if extension == 0usize {
            if !okay(puts(c, ", ")) { ret false }
            var immediate_bytes = 4usize
            if opcode == 246usize { immediate_bytes = 1usize }
            let (value, value_present) = fetch_little(c, immediate_bytes)
            if !value_present { ret false }
            ret okay(put_number(c, value))
        }
        ret true
    }
    if opcode == 193usize || opcode == 211usize || opcode == 209usize {
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        if !okay(shift_name(c, (modrm >> 3usize) & 7usize)) { ret false }
        let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, width, rex)
        if !rm_ok { ret false }
        if opcode == 211usize { ret okay(puts(c, ", cl")) }
        if opcode == 209usize { ret okay(puts(c, ", 1")) }
        if !okay(puts(c, ", ")) { ret false }
        let (value, value_present) = fetch(c)
        if !value_present { ret false }
        ret okay(put_number(c, value))
    }
    if opcode == 255usize {
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        let extension = (modrm >> 3usize) & 7usize
        if extension == 0usize { if !okay(puts(c, "inc ")) { ret false } }
        if extension == 1usize { if !okay(puts(c, "dec ")) { ret false } }
        if extension == 2usize { if !okay(puts(c, "call ")) { ret false } }
        if extension == 4usize { if !okay(puts(c, "jmp ")) { ret false } }
        if extension == 6usize { if !okay(puts(c, "push ")) { ret false } }
        if extension == 3usize || extension == 5usize || extension == 7usize { ret false }
        var rm_width = width
        if extension >= 2usize { rm_width = 3usize }
        let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, rm_width, rex)
        ret rm_ok
    }
    if opcode == 105usize || opcode == 107usize {
        if !okay(puts(c, "imul ")) { ret false }
        if !two_operands(c, true, width, rex_r, rex_x, rex_b, rex, width) { ret false }
        if !okay(puts(c, ", ")) { ret false }
        var immediate_bytes = 4usize
        var bits = 32usize
        if opcode == 107usize {
            immediate_bytes = 1usize
            bits = 8usize
        }
        let (value, value_present) = fetch_little(c, immediate_bytes)
        if !value_present { ret false }
        ret okay(put_signed(c, value, bits))
    }
    if opcode == 232usize || opcode == 233usize {
        if opcode == 232usize { if !okay(puts(c, "call ")) { ret false } }
        if opcode == 233usize { if !okay(puts(c, "jmp ")) { ret false } }
        let (displacement, displacement_present) = fetch_little(c, 4usize)
        if !displacement_present { ret false }
        ret relative_target(c, displacement, 32usize)
    }
    if opcode == 235usize {
        if !okay(puts(c, "jmp ")) { ret false }
        let (displacement, displacement_present) = fetch(c)
        if !displacement_present { ret false }
        ret relative_target(c, displacement, 8usize)
    }
    if opcode >= 112usize && opcode <= 127usize {
        if !okay(put(c, 106u8)) { ret false }
        if !okay(condition_name(c, opcode - 112usize)) { ret false }
        if !okay(put(c, 32u8)) { ret false }
        let (displacement, displacement_present) = fetch(c)
        if !displacement_present { ret false }
        ret relative_target(c, displacement, 8usize)
    }
    if opcode == 164usize || opcode == 165usize || opcode == 170usize || opcode == 171usize {
        if repeat == 243usize { if !okay(puts(c, "rep ")) { ret false } }
        if opcode == 164usize { ret okay(puts(c, "movsb")) }
        if opcode == 165usize {
            if rex_w { ret okay(puts(c, "movsq")) }
            ret okay(puts(c, "movsd"))
        }
        if opcode == 170usize { ret okay(puts(c, "stosb")) }
        if rex_w { ret okay(puts(c, "stosq")) }
        ret okay(puts(c, "stosd"))
    }
    if opcode != 15usize { ret false }
    // Two-byte opcodes.
    let (second, second_present) = fetch(c)
    if !second_present { ret false }
    if second == 5usize { ret okay(puts(c, "syscall")) }
    if second == 11usize { ret okay(puts(c, "ud2")) }
    if second == 174usize {
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        if modrm == 240usize { ret okay(puts(c, "mfence")) }
        if modrm == 232usize { ret okay(puts(c, "lfence")) }
        if modrm == 248usize { ret okay(puts(c, "sfence")) }
        ret false
    }
    if second >= 128usize && second <= 143usize {
        if !okay(put(c, 106u8)) { ret false }
        if !okay(condition_name(c, second - 128usize)) { ret false }
        if !okay(put(c, 32u8)) { ret false }
        let (displacement, displacement_present) = fetch_little(c, 4usize)
        if !displacement_present { ret false }
        ret relative_target(c, displacement, 32usize)
    }
    if second >= 144usize && second <= 159usize {
        if !okay(puts(c, "set")) { ret false }
        if !okay(condition_name(c, second - 144usize)) { ret false }
        if !okay(put(c, 32u8)) { ret false }
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, 0usize, rex)
        ret rm_ok
    }
    if second >= 64usize && second <= 79usize {
        if !okay(puts(c, "cmov")) { ret false }
        if !okay(condition_name(c, second - 64usize)) { ret false }
        if !okay(put(c, 32u8)) { ret false }
        ret two_operands(c, true, width, rex_r, rex_x, rex_b, rex, width)
    }
    if second == 175usize {
        if !okay(puts(c, "imul ")) { ret false }
        ret two_operands(c, true, width, rex_r, rex_x, rex_b, rex, width)
    }
    if second == 182usize || second == 183usize || second == 190usize || second == 191usize {
        if second == 182usize || second == 183usize { if !okay(puts(c, "movzx ")) { ret false } }
        if second == 190usize || second == 191usize { if !okay(puts(c, "movsx ")) { ret false } }
        var source_width = 0usize
        if second == 183usize || second == 191usize { source_width = 1usize }
        ret two_operands(c, true, source_width, rex_r, rex_x, rex_b, rex, width)
    }
    if second == 186usize {
        let (modrm, modrm_present) = fetch(c)
        if !modrm_present { ret false }
        let extension = (modrm >> 3usize) & 7usize
        if extension == 4usize { if !okay(puts(c, "bt ")) { ret false } }
        if extension == 5usize { if !okay(puts(c, "bts ")) { ret false } }
        if extension == 6usize { if !okay(puts(c, "btr ")) { ret false } }
        if extension == 7usize { if !okay(puts(c, "btc ")) { ret false } }
        if extension < 4usize { ret false }
        let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, width, rex)
        if !rm_ok { ret false }
        if !okay(puts(c, ", ")) { ret false }
        let (value, value_present) = fetch(c)
        if !value_present { ret false }
        ret okay(put_number(c, value))
    }
    if second == 192usize || second == 193usize || second == 176usize || second == 177usize {
        if second <= 193usize && second >= 192usize { if !okay(puts(c, "xadd ")) { ret false } }
        if second == 176usize || second == 177usize { if !okay(puts(c, "cmpxchg ")) { ret false } }
        var atomic_width = width
        if second == 192usize || second == 176usize { atomic_width = 0usize }
        ret two_operands(c, false, atomic_width, rex_r, rex_x, rex_b, rex, atomic_width)
    }
    // SSE2 packed forms, which operate on a whole sixteen-byte vector: no mandatory
    // prefix is the single-precision form and 66 the double-precision or the integer
    // one, where the scalar forms below are always F2 or F3.
    if repeat == 0usize {
        if second == 16usize || second == 17usize || second == 40usize {
            if second == 40usize { if !okay(puts(c, "movap")) { ret false } } else { if !okay(puts(c, "movup")) { ret false } }
            if operand16 { if !okay(puts(c, "d ")) { ret false } } else { if !okay(puts(c, "s ")) { ret false } }
            ret two_operands(c, second != 17usize, 4usize, rex_r, rex_x, rex_b, rex, 4usize)
        }
        // The quadword half of the register, which carries an eight-lane mask.
        if second == 18usize || second == 19usize {
            if !okay(puts(c, "movlps ")) { ret false }
            ret two_operands(c, second == 18usize, 4usize, rex_r, rex_x, rex_b, rex, 4usize)
        }
        if second == 88usize || second == 89usize || second == 92usize || second == 94usize || second == 81usize {
            if second == 88usize { if !okay(puts(c, "add")) { ret false } }
            if second == 89usize { if !okay(puts(c, "mul")) { ret false } }
            if second == 92usize { if !okay(puts(c, "sub")) { ret false } }
            if second == 94usize { if !okay(puts(c, "div")) { ret false } }
            if second == 81usize { if !okay(puts(c, "sqrt")) { ret false } }
            if operand16 { if !okay(puts(c, "pd ")) { ret false } } else { if !okay(puts(c, "ps ")) { ret false } }
            ret two_operands(c, true, 4usize, rex_r, rex_x, rex_b, rex, 4usize)
        }
        if second == 194usize {
            if !okay(puts(c, "cmp")) { ret false }
            if operand16 { if !okay(puts(c, "pd ")) { ret false } } else { if !okay(puts(c, "ps ")) { ret false } }
            if !two_operands(c, true, 4usize, rex_r, rex_x, rex_b, rex, 4usize) { ret false }
            if !okay(puts(c, ", ")) { ret false }
            let (predicate, predicate_present) = fetch(c)
            if !predicate_present { ret false }
            ret okay(put_number(c, predicate))
        }
        if operand16 && (second == 114usize || second == 115usize) {
            let (modrm, modrm_present) = fetch(c)
            if !modrm_present { ret false }
            let extension = (modrm >> 3usize) & 7usize
            if extension == 6usize { if !okay(puts(c, "psll")) { ret false } }
            if extension == 2usize { if !okay(puts(c, "psrl")) { ret false } }
            if extension != 6usize && extension != 2usize { ret false }
            if second == 114usize { if !okay(puts(c, "d ")) { ret false } } else { if !okay(puts(c, "q ")) { ret false } }
            let (unused, rm_ok) = operand_rm(c, modrm, false, rex_x, rex_b, 4usize, rex)
            if !rm_ok { ret false }
            if !okay(puts(c, ", ")) { ret false }
            let (count, count_present) = fetch(c)
            if !count_present { ret false }
            ret okay(put_number(c, count))
        }
        if operand16 {
            let mnemonic = packed_integer_mnemonic(second)
            if mnemonic.len != 0usize {
                if !okay(puts(c, mnemonic)) { ret false }
                ret two_operands(c, true, 4usize, rex_r, rex_x, rex_b, rex, 4usize)
            }
        }
    }
    // SSE scalar forms: the mandatory prefix picks single (F3) or double (F2), and a
    // 66 here is that prefix, not an operand-size override -- a general register in an
    // SSE form is 64 bits under REX.W and 32 otherwise.
    let double = repeat == 242usize
    var gpr = 2usize
    if rex_w { gpr = 3usize }
    if second == 16usize || second == 17usize {
        if !okay(puts(c, "movs")) { ret false }
        if double { if !okay(put(c, 100u8)) { ret false } } else { if !okay(put(c, 115u8)) { ret false } }
        if !okay(put(c, 32u8)) { ret false }
        ret two_operands(c, second == 16usize, 4usize, rex_r, rex_x, rex_b, rex, 4usize)
    }
    if second == 88usize || second == 89usize || second == 92usize || second == 94usize || second == 81usize {
        if second == 88usize { if !okay(puts(c, "add")) { ret false } }
        if second == 89usize { if !okay(puts(c, "mul")) { ret false } }
        if second == 92usize { if !okay(puts(c, "sub")) { ret false } }
        if second == 94usize { if !okay(puts(c, "div")) { ret false } }
        if second == 81usize { if !okay(puts(c, "sqrt")) { ret false } }
        if double { if !okay(puts(c, "sd ")) { ret false } } else { if !okay(puts(c, "ss ")) { ret false } }
        ret two_operands(c, true, 4usize, rex_r, rex_x, rex_b, rex, 4usize)
    }
    if second == 46usize || second == 47usize {
        if second == 46usize { if !okay(puts(c, "ucomis")) { ret false } }
        if second == 47usize { if !okay(puts(c, "comis")) { ret false } }
        if operand16 { if !okay(puts(c, "d ")) { ret false } } else { if !okay(puts(c, "s ")) { ret false } }
        ret two_operands(c, true, 4usize, rex_r, rex_x, rex_b, rex, 4usize)
    }
    if second == 42usize {
        if !okay(puts(c, "cvtsi2s")) { ret false }
        if double { if !okay(put(c, 100u8)) { ret false } } else { if !okay(put(c, 115u8)) { ret false } }
        if !okay(put(c, 32u8)) { ret false }
        ret two_operands(c, true, gpr, rex_r, rex_x, rex_b, rex, 4usize)
    }
    if second == 44usize || second == 45usize {
        if second == 44usize { if !okay(puts(c, "cvtts")) { ret false } } else { if !okay(puts(c, "cvts")) { ret false } }
        if double { if !okay(puts(c, "d2si ")) { ret false } } else { if !okay(puts(c, "s2si ")) { ret false } }
        ret two_operands(c, true, 4usize, rex_r, rex_x, rex_b, rex, gpr)
    }
    if second == 90usize {
        if double { if !okay(puts(c, "cvtsd2ss ")) { ret false } } else { if !okay(puts(c, "cvtss2sd ")) { ret false } }
        ret two_operands(c, true, 4usize, rex_r, rex_x, rex_b, rex, 4usize)
    }
    if second == 110usize || second == 126usize {
        if rex_w { if !okay(puts(c, "movq ")) { ret false } } else { if !okay(puts(c, "movd ")) { ret false } }
        if second == 110usize { ret two_operands(c, true, gpr, rex_r, rex_x, rex_b, rex, 4usize) }
        ret two_operands(c, false, gpr, rex_r, rex_x, rex_b, rex, 4usize)
    }
    ret false
}

// The 66-prefixed integer forms this back end emits, by their second opcode byte.
fn packed_integer_mnemonic(second: usize) -> str {
    if second == 252usize { ret "paddb " }
    if second == 253usize { ret "paddw " }
    if second == 254usize { ret "paddd " }
    if second == 212usize { ret "paddq " }
    if second == 248usize { ret "psubb " }
    if second == 249usize { ret "psubw " }
    if second == 250usize { ret "psubd " }
    if second == 251usize { ret "psubq " }
    if second == 213usize { ret "pmullw " }
    if second == 219usize { ret "pand " }
    if second == 223usize { ret "pandn " }
    if second == 235usize { ret "por " }
    if second == 239usize { ret "pxor " }
    if second == 118usize { ret "pcmpeqd " }
    if second == 116usize { ret "pcmpeqb " }
    ret ""
}

// A relative landing as the function-relative offset it lands on.
fn relative_target(c: *Cursor, displacement: usize, bits: usize) -> bool {
    let sign = 1usize << (bits - 1usize)
    var landing = c.at + displacement
    if (displacement & sign) != 0usize {
        let magnitude = ((1usize << bits) - displacement) & ((1usize << bits) - 1usize)
        if magnitude > c.at {
            if !okay(puts(c, "-")) { ret false }
            ret okay(put_number(c, magnitude - c.at))
        }
        landing = c.at - magnitude
    }
    ret okay(put_number(c, landing))
}

// Section 11's trap records are laid inline after an unconditional forward jump; a
// sweep would read them as code. The bytes a `jmp` skips are listed as one `text` line
// when they are text, and decoded as the else-branch they otherwise are.
fn skipped_is_trap_text(code: []const usize, from: usize, to: usize) -> bool {
    if to <= from { ret false }
    if text_bytes(code, from, to) { ret true }
    // Records (D922): a 16-bit length and that many bytes of text, end to end, filling
    // the skipped bytes exactly.
    var at = from
    while at + 2usize <= to {
        let length = (code[at] & 255usize) + (code[at + 1usize] & 255usize) * 256usize
        if at + 2usize + length > to || !text_bytes(code, at + 2usize, at + 2usize + length) { ret false }
        at += 2usize + length
    }
    ret at == to
}

// Printable ASCII, NUL and newlines and nothing else is text, not code: a record's
// bytes, or a value's name laid inline the same way; a jump over code always crosses an
// opcode outside that range.
fn text_bytes(code: []const usize, from: usize, to: usize) -> bool {
    var at = from
    while at < to {
        let value = code[at] & 255usize
        // 0 and 1 are the record's operand separators (unsigned, signed).
        if value > 1usize && value != 10usize && value != 9usize && (value < 32usize || value > 126usize) { ret false }
        at += 1usize
    }
    ret true
}

fn text_line(c: *Cursor, from: usize, to: usize) -> err {
    try put_hex(c, from, 4usize)
    try puts(c, "  text \"")
    var at = from
    while at < to {
        let value = c.code[at] & 255usize
        if value == 34usize || value == 92usize {
            try put(c, 92u8)
            try put(c, u8(value))
        } else {
            if value >= 32usize && value < 127usize {
                try put(c, u8(value))
            } else {
                if value == 10usize {
                    try put(c, 92u8)
                    try put(c, 110u8)
                    at += 1usize
                    continue
                }
                try put(c, 92u8)
                try put(c, 120u8)
                try put_hex(c, value, 2usize)
            }
        }
        at += 1usize
    }
    try puts(c, "\"  ; ")
    try put_number(c, to - from)
    try puts(c, " bytes")
    ret put(c, 10u8)
}

// The listing of `code`, into `out`; returns how much of `out` was written.
fn disassemble(code: []const usize, out: []u8) -> (usize, err) {
    var c = Cursor { code: code, at: 0usize, out: out, written: 0usize }
    while c.at < code.len {
        let start = c.at
        let line_start = c.written
        let offset_error = put_hex(&c, start, 4usize)
        if offset_error != ok { ret (0usize, offset_error) }
        let gap_error = puts(&c, "  ")
        if gap_error != ok { ret (0usize, gap_error) }
        // `jmp rel32` over trap text: list the text, resume at the landing.
        if (code[start] & 255usize) == 233usize && start + 5usize <= code.len {
            let (displacement, present) = fetch_little_at(code, start + 1usize)
            let landing = start + 5usize + displacement
            if present && displacement < 2147483648usize && landing <= code.len && skipped_is_trap_text(code, start + 5usize, landing) {
                c.at = start + 5usize
                let jump_error = puts(&c, "jmp ")
                if jump_error != ok { ret (0usize, jump_error) }
                let target_error = put_number(&c, landing)
                if target_error != ok { ret (0usize, target_error) }
                let bytes_error = puts(&c, "  ; e9 ")
                if bytes_error != ok { ret (0usize, bytes_error) }
                var b = 1usize
                while b < 5usize {
                    let byte_error = put_hex(&c, code[start + b] & 255usize, 2usize)
                    if byte_error != ok { ret (0usize, byte_error) }
                    if b != 4usize {
                        let space_error = put(&c, 32u8)
                        if space_error != ok { ret (0usize, space_error) }
                    }
                    b += 1usize
                }
                let newline_error = put(&c, 10u8)
                if newline_error != ok { ret (0usize, newline_error) }
                let text_error = text_line(&c, start + 5usize, landing)
                if text_error != ok { ret (0usize, text_error) }
                c.at = landing
                continue
            }
        }
        if !instruction(&c, start) {
            c.written = line_start
            c.at = start
            let redo_error = put_hex(&c, start, 4usize)
            if redo_error != ok { ret (0usize, redo_error) }
            let db_error = puts(&c, "  db 0x")
            if db_error != ok { ret (0usize, db_error) }
            let value_error = put_hex(&c, code[start] & 255usize, 2usize)
            if value_error != ok { ret (0usize, value_error) }
            c.at = start + 1usize
        }
        // The bytes, after the mnemonic.
        let sep_error = puts(&c, "  ; ")
        if sep_error != ok { ret (0usize, sep_error) }
        var at = start
        while at < c.at {
            if at != start {
                let space_error = put(&c, 32u8)
                if space_error != ok { ret (0usize, space_error) }
            }
            let byte_error = put_hex(&c, code[at] & 255usize, 2usize)
            if byte_error != ok { ret (0usize, byte_error) }
            at += 1usize
        }
        let newline_error = put(&c, 10u8)
        if newline_error != ok { ret (0usize, newline_error) }
    }
    ret (c.written, ok)
}
