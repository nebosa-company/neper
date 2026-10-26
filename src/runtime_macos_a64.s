.text

// A BSD system call: the number in x16, trapped with svc #0x80. The kernel answers an error with
// the carry flag set and the positive errno in x0; the callers below test the sign as on Linux,
// so the error is negated here.
.macro sys number
    mov x16, #\number
    svc #0x80
    b.cc 1f
    neg x0, x0
1:
.endm

// The aarch64 macOS runtime: raw BSD system calls, no libSystem. One file, embedded whole
// into `runtime_macos_a64.e` by scripts/embed-elf-runtime.ps1 -Arch macos.
//
// Order matters as on x64 (D150): the linker appends this runtime as a prefix, cut after
// the last function the program reaches, so a function may call only what precedes it.
// The entry stub comes first and is always kept. A call between functions goes to a local
// label: a branch to a global symbol would be a relocation the embedding does not apply.
//
// Every function takes Neper's convention on this target, which is AAPCS64: arguments in
// x0-x7, an aggregate by its address, an aggregate result through the address in x0, and
// a pair of results in x0 and x1. System call numbers are aarch64's.

// The entry: the root arena mapped (its size the literal the linker patches), the
// arguments copied into it as a table of slices, `main(&arena, &args)` called, and the
// program ended with exit_group -- status 1 when main returned an error, 111 when the
// arena could not be had. x29 is zero in main's caller: the end of the frame chain.
.global neper_start
neper_start:
    // dyld calls LC_MAIN's entry as main(argc, argv): x19 is made to stand where the
    // kernel's initial stack would have put the count, the vector 8 bytes after it.
    // The environment pointer (x2) is kept beside the argument table for `os.env_block`.
    adr x9, .Lstart_args
    ldr x10, [x9]
    add x9, x9, x10
    str x2, [x9, #16]
    mov x22, x0
    sub x19, x1, #8
    ldr x20, .Lstart_arena
    mov x0, #0
    mov x1, x20
    mov x2, #3
    mov x3, #0x1002
    mov x4, #-1
    mov x5, #0
    sys 197
    tbnz x0, #63, .Lstart_fail
    mov x21, x0
    lsl x23, x22, #4
    cmp x23, x20
    b.hi .Lstart_fail
    mov x24, #0
.Lstart_argument:
    cmp x24, x22
    b.hs .Lstart_main
    add x9, x19, x24, lsl #3
    ldr x9, [x9, #8]
    mov x10, #0
.Lstart_length:
    ldrb w11, [x9, x10]
    cbz w11, .Lstart_counted
    add x10, x10, #1
    b .Lstart_length
.Lstart_counted:
    adds x12, x23, x10
    b.cs .Lstart_fail
    cmp x12, x20
    b.hi .Lstart_fail
    add x13, x21, x23
    add x14, x21, x24, lsl #4
    stp x13, x10, [x14]
    mov x15, #0
.Lstart_copy:
    cmp x15, x10
    b.hs .Lstart_copied
    ldrb w11, [x9, x15]
    strb w11, [x13, x15]
    add x15, x15, #1
    b .Lstart_copy
.Lstart_copied:
    mov x23, x12
    add x24, x24, #1
    b .Lstart_argument
.Lstart_main:
    // The argument table is kept in the slot at the start of __DATA for `os.args`; the
    // literal beside the arena's holds its distance from itself, patched by the linker.
    adr x9, .Lstart_args
    ldr x10, [x9]
    add x9, x9, x10
    stp x21, x22, [x9]
    sub sp, sp, #48
    stp x21, x20, [sp]
    str x23, [sp, #16]
    stp x21, x22, [sp, #24]
    mov x0, sp
    add x1, sp, #24
    mov x29, #0
    mov x30, #0
.global neper_start_main
neper_start_main:
    bl .
    cmp w0, #0
    cset x0, ne
    sys 1
.Lstart_fail:
    mov x0, #111
    sys 1
    brk #0
.global neper_start_args
neper_start_args:
.Lstart_args:
    .quad 0
.global neper_start_arena
neper_start_arena:
.Lstart_arena:
    .quad 0x40000000

// errno in w0 to the `e.os` error code in w0, the generic code for anything unlisted:
// the table's pairs, ended by errno 0 with the generic code.
np_error:
    adr x10, .Lerror_table
.Lerror_scan:
    ldp w11, w12, [x10], #8
    cbz w11, .Lerror_found
    cmp w11, w0
    b.ne .Lerror_scan
.Lerror_found:
    mov w0, w12
    ret
.Lerror_table:
    .word 2, 0x7683e2cd
    .word 20, 0x7683e2cd
    .word 13, 0xb0cb971d
    .word 1, 0xb0cb971d
    .word 17, 0x197f5566
    .word 4, 0xb66d7668
    .word 12, 0x6979aadc
    .word 60, 0x52812f09
    .word 35, 0xa18174bc
    .word 78, 0x2f8bb651
    .word 45, 0x2f8bb651
    .word 0, 0x6f777ebf

// `size` bytes of the arena at x0, aligned to x2 (a power of two): the address, or zero.
np_alloc:
    cbz x0, .Lalloc_fail
    cbz x2, .Lalloc_fail
    sub x3, x2, #1
    tst x2, x3
    b.ne .Lalloc_fail
    ldr x4, [x0, #16]
    adds x4, x4, x3
    b.cs .Lalloc_fail
    neg x5, x2
    and x4, x4, x5
    ldr x5, [x0, #8]
    cmp x4, x5
    b.hi .Lalloc_fail
    sub x5, x5, x4
    cmp x1, x5
    b.hi .Lalloc_fail
    add x6, x4, x1
    str x6, [x0, #16]
    ldr x7, [x0]
    cbz x7, .Lalloc_fail
    add x0, x7, x4
    ret
.Lalloc_fail:
    mov x0, #0
    ret

// mem.alloc: the result {data, len, err} at x0, from the arena at x1, x2 elements of x3
// bytes aligned to x4.
.global neper_mem_alloc
neper_mem_alloc:
np_mem_alloc:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x20, x2
    stp xzr, xzr, [x19]
    str wzr, [x19, #16]
    umulh x9, x2, x3
    cbnz x9, .Lmem_alloc_fail
    mul x9, x2, x3
    mov x0, x1
    mov x1, x9
    mov x2, x4
    bl np_alloc
    cbz x0, .Lmem_alloc_fail
    stp x0, x20, [x19]
    b .Lmem_alloc_done
.Lmem_alloc_fail:
    movz w9, #0x623a
    movk w9, #0x8f63, lsl #16
    str w9, [x19, #16]
.Lmem_alloc_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// Section 11's debug fill (D217): the allocation, then every byte of it 0xCD.
.global neper_mem_alloc_fill
neper_mem_alloc_fill:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mul x20, x2, x3
    bl np_mem_alloc
    ldr w9, [x19, #16]
    cbnz w9, .Lalloc_fill_done
    ldr x9, [x19]
    mov w10, #0xcd
.Lalloc_fill_byte:
    cbz x20, .Lalloc_fill_done
    strb w10, [x9], #1
    sub x20, x20, #1
    b .Lalloc_fill_byte
.Lalloc_fill_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.global neper_mem_mark
neper_mem_mark:
    ldr x0, [x0, #16]
    ret

.global neper_mem_reset
neper_mem_reset:
    str x1, [x0, #16]
    ret

// The other debug fill (D217): what the reset gives back is 0xDD before the offset moves.
.global neper_mem_reset_fill
neper_mem_reset_fill:
    ldr x2, [x0, #16]
    cmp x1, x2
    b.hs .Lreset_fill_store
    ldr x3, [x0]
    add x4, x3, x1
    add x5, x3, x2
    mov w6, #0xdd
.Lreset_fill_byte:
    strb w6, [x4], #1
    cmp x4, x5
    b.lo .Lreset_fill_byte
.Lreset_fill_store:
    str x1, [x0, #16]
    ret

.global neper_mem_stats
neper_mem_stats:
    ldr x2, [x1, #16]
    str x2, [x0]
    ldr x2, [x1, #8]
    str x2, [x0, #8]
    ret

.global neper_os_stdout
neper_os_stdout:
    mov x1, #1
    str x1, [x0]
    ret

.global neper_os_stderr
neper_os_stderr:
    mov x1, #2
    str x1, [x0]
    ret

// exit_group, not exit: section 8's exit ends the program (D246).
.global neper_os_exit
neper_os_exit:
    sys 1
    brk #0

// os.write(file: *File, bytes: *[]const u8) -> (usize, err).
.global neper_os_write
neper_os_write:
    ldr x2, [x1, #8]
    ldr x1, [x1]
    ldr x0, [x0]
    sys 4
    tbnz x0, #63, .Los_write_fail
    mov x1, #0
    ret
.Los_write_fail:
    stp x29, x30, [sp, #-16]!
    neg w0, w0
    bl np_error
    ldp x29, x30, [sp], #16
    mov w1, w0
    mov x0, #0
    ret

// os.copy_bytes(dst: *[]u8, src: *[]const u8) (D329): the shorter length's worth of
// bytes, forwards.
.global neper_os_copy_bytes
neper_os_copy_bytes:
    ldr x2, [x0, #8]
    ldr x3, [x1, #8]
    cmp x3, x2
    csel x2, x3, x2, lo
    ldr x0, [x0]
    ldr x1, [x1]
.Lcopy_bytes_word:
    cmp x2, #8
    b.lo .Lcopy_bytes_byte
    ldr x3, [x1], #8
    str x3, [x0], #8
    sub x2, x2, #8
    b .Lcopy_bytes_word
.Lcopy_bytes_byte:
    cbz x2, .Lcopy_bytes_done
    ldrb w3, [x1], #1
    strb w3, [x0], #1
    sub x2, x2, #1
    b .Lcopy_bytes_byte
.Lcopy_bytes_done:
    ret

// os.sha256_blocks (D332): how many 64-byte blocks were compressed in hardware -- none
// yet on this target, and the caller keeps its own rounds.
// ponytail: no SHA2 extension path; ARMv8.2 has SHA256H/SHA256SU0, add when a build is hashed here.
.global neper_os_sha256_blocks
neper_os_sha256_blocks:
    mov x0, #0
    ret

// os.crc32c_bytes(crc: []usize, bytes: []const u8) -> usize (D332): the bytes folded into
// the CRC-32C in `crc`'s first slot with CRC32CX and CRC32CB, mandatory since ARMv8.1;
// every byte is folded.
.global neper_os_crc32c_bytes
neper_os_crc32c_bytes:
    ldr x2, [x1, #8]
    ldr x3, [x1]
    ldr x4, [x0]
    ldr w5, [x4]
    mov x0, x2
    lsr x6, x2, #3
.Lcrc_words:
    cbz x6, .Lcrc_tail
    ldr x7, [x3], #8
    crc32cx w5, w5, x7
    sub x6, x6, #1
    b .Lcrc_words
.Lcrc_tail:
    and x6, x2, #7
.Lcrc_bytes:
    cbz x6, .Lcrc_store
    ldrb w7, [x3], #1
    crc32cb w5, w5, w7
    sub x6, x6, #1
    b .Lcrc_bytes
.Lcrc_store:
    str x5, [x4]
    ret

// A failed check (spec section 11): the site's path, `:line:column`, the message with the
// two operands wherever it holds a byte below 2 -- 0 unsigned, 1 signed -- a newline, the
// symbolised backtrace from the table at x5, all to stderr, and exit 134. A stub enters
// with x0 = the path's record and x4 = the message's (a 16-bit length and the bytes,
// D922), x1 = line << 16 | column, x2 and x3 = the operands, and x30 = the site. Nothing
// returns, so the callee-saved registers are not kept.

// x1 and x2 bytes to stderr.
np_trap_text:
    mov x0, #2
    sys 4
    ret

// The byte in w0 to stderr, through [sp].
np_trap_char:
    strb w0, [sp]
    mov x1, sp
    mov x2, #1
    b np_trap_text

// x0 in decimal to stderr.
np_trap_number:
    sub sp, sp, #32
    add x9, sp, #32
    mov x10, #10
.Ltrap_number_digit:
    udiv x11, x0, x10
    msub x12, x11, x10, x0
    add w12, w12, #48
    strb w12, [x9, #-1]!
    mov x0, x11
    cbnz x0, .Ltrap_number_digit
    mov x1, x9
    add x2, sp, #32
    sub x2, x2, x9
    mov x0, #2
    sys 4
    add sp, sp, #32
    ret

// A ULEB128 at x28 into x0, x28 past it; x9 and x10 are used (D1586).
np_trap_uleb:
    mov x0, #0
    mov x10, #0
.Ltrap_uleb_byte:
    ldrb w9, [x28], #1
    tbnz w9, #7, .Ltrap_uleb_more
    lsl x9, x9, x10
    orr x0, x0, x9
    ret
.Ltrap_uleb_more:
    and x9, x9, #127
    lsl x9, x9, x10
    orr x0, x0, x9
    add x10, x10, #7
    b .Ltrap_uleb_byte

.global neper_trap
neper_trap:
    mov x19, x0
    mov x20, x4
    mov x21, x2
    mov x22, x3
    mov x23, x5
    mov x24, x30
    mov x25, x29
    mov x26, x1
    mov x9, sp
    and x9, x9, #-16
    sub x9, x9, #64
    mov sp, x9
    ldrh w2, [x19]
    add x1, x19, #2
    bl np_trap_text
    mov w0, #58
    bl np_trap_char
    lsr x0, x26, #16
    bl np_trap_number
    mov w0, #58
    bl np_trap_char
    and x0, x26, #0xffff
    bl np_trap_number
    ldrh w9, [x20]
    add x19, x20, #2
    add x20, x19, x9
    mov x27, #0
.Ltrap_segment:
    mov x1, x19
.Ltrap_scan:
    cmp x19, x20
    b.hs .Ltrap_scanned
    ldrb w9, [x19]
    cmp w9, #2
    b.lo .Ltrap_scanned
    add x19, x19, #1
    b .Ltrap_scan
.Ltrap_scanned:
    sub x2, x19, x1
    bl np_trap_text
    cmp x19, x20
    b.hs .Ltrap_end
    ldrb w28, [x19]
    add x19, x19, #1
    mov x0, x21
    cbz x27, .Ltrap_digits
    mov x0, x22
.Ltrap_digits:
    add x27, x27, #1
    cbz w28, .Ltrap_unsigned
    tbz x0, #63, .Ltrap_unsigned
    neg x28, x0
    mov w0, #45
    bl np_trap_char
    mov x0, x28
.Ltrap_unsigned:
    bl np_trap_number
    b .Ltrap_segment
.Ltrap_end:
    mov w0, #10
    bl np_trap_char
// The backtrace: every frame keeps its x29/x30 record, so from the trapping function's
// frame and the site the walk is [x29 + 8] and [x29], each address looked up one byte
// back -- at its call -- in the `.nepersym` table (D1586) by a binary search over its
// entries, sorted by start, until none holds it, which is the runtime's own entry, or
// thirty-two frames have been printed.
    mov x27, #32
    sub x26, x24, #1
.Ltrap_frame:
    cbz x27, .Ltrap_exit
    sub x27, x27, #1
    // The table's entries are relative to the table (the image slides), so the address looked
    // up is too.
    sub x26, x26, x23
    mov x9, #0
    ldr w10, [x23, #8]
.Ltrap_search:
    cmp x9, x10
    b.hs .Ltrap_exit
    add x11, x9, x10
    lsr x11, x11, #1
    add x12, x23, x11, lsl #5
    add x12, x12, #12
    ldr x13, [x12]
    cmp x26, x13
    b.lo .Ltrap_lower
    ldr x13, [x12, #8]
    cmp x26, x13
    b.hs .Ltrap_upper
    b .Ltrap_found
.Ltrap_lower:
    mov x10, x11
    b .Ltrap_search
.Ltrap_upper:
    add x9, x11, #1
    b .Ltrap_search
.Ltrap_found:
    ldr x13, [x12]
    sub x21, x26, x13
    mov x22, x12
    adr x1, .Ltrap_at
    mov x2, #5
    bl np_trap_text
    ldr w9, [x22, #16]
    add x1, x23, x9
    ldr w2, [x1]
    add x1, x1, #4
    bl np_trap_text
// The line program: a row count, then per row a ULEB128 offset delta, a ULEB128 of the
// zigzag line delta times two plus a file-change bit, and then the new file. x24 and x11
// are the row's offset and line, x19 its file; [sp + 16] and [sp + 32] keep the last row
// at or below the call, [sp + 24] whether there is one.
    ldr w19, [x22, #20]
    ldr w9, [x22, #24]
    add x28, x23, x9
    ldr w20, [x28], #4
    mov x24, #0
    mov x11, #0
    str xzr, [sp, #24]
.Ltrap_row:
    cbz x20, .Ltrap_rows_done
    sub x20, x20, #1
    bl np_trap_uleb
    add x24, x24, x0
    bl np_trap_uleb
    mov x12, x0
    lsr x0, x0, #1
    lsr x13, x0, #1
    and x0, x0, #1
    neg x0, x0
    eor x0, x0, x13
    add x11, x11, x0
    tbz x12, #0, .Ltrap_row_file
    bl np_trap_uleb
    mov x19, x0
.Ltrap_row_file:
    cmp x24, x21
    b.hi .Ltrap_rows_done
    str x19, [sp, #16]
    str x11, [sp, #32]
    mov x9, #1
    str x9, [sp, #24]
    b .Ltrap_row
.Ltrap_rows_done:
    ldr x9, [sp, #24]
    cbz x9, .Ltrap_line_done
    mov w0, #32
    bl np_trap_char
    mov w0, #40
    bl np_trap_char
    ldr x9, [sp, #16]
    add x1, x23, x9
    ldr w2, [x1]
    add x1, x1, #4
    bl np_trap_text
    mov w0, #58
    bl np_trap_char
    ldr x0, [sp, #32]
    bl np_trap_number
    mov w0, #41
    bl np_trap_char
.Ltrap_line_done:
    mov w0, #10
    bl np_trap_char
    cbz x25, .Ltrap_exit
    ldr x26, [x25, #8]
    sub x26, x26, #1
    ldr x25, [x25]
    b .Ltrap_frame
.Ltrap_exit:
    mov x0, #134
    sys 1
    brk #0
.Ltrap_at:
    .ascii "  at "
    .p2align 2

// os.read(file: *File, bytes: *[]u8) -> (usize, err).
.global neper_os_read
neper_os_read:
    ldr x2, [x1, #8]
    ldr x1, [x1]
    ldr x0, [x0]
    sys 3
    tbnz x0, #63, .Los_read_fail
    mov x1, #0
    ret
.Los_read_fail:
    stp x29, x30, [sp, #-16]!
    neg w0, w0
    bl np_error
    ldp x29, x30, [sp], #16
    mov w1, w0
    mov x0, #0
    ret

// os.close(file: *File) -> err.
.global neper_os_close
neper_os_close:
    ldr x0, [x0]
    sys 6
    tbnz x0, #63, .Los_close_fail
    mov x0, #0
    ret
.Los_close_fail:
    stp x29, x30, [sp, #-16]!
    neg w0, w0
    bl np_error
    ldp x29, x30, [sp], #16
    ret


// os.open: the result {File, err} at x0, the arena at x1 (the path's terminated copy is
// taken from it and given back), the path's slice at x2, the OpenFlags at x3 -- read,
// write, create, truncate, append, one byte each. Darwin's open(2) takes the path, the
// flags and the mode; its O_CREAT is 0x200, O_TRUNC 0x400, O_APPEND 0x8, O_CLOEXEC 0x1000000.
.global neper_os_open
neper_os_open:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    mov x20, x1
    mov x21, x3
    str xzr, [x19]
    str wzr, [x19, #8]
    ldr x22, [x20, #16]
    ldr x9, [x2, #8]
    ldr x10, [x2]
    adds x1, x9, #1
    b.cs .Los_open_oom
    stp x9, x10, [sp, #-16]!
    mov x0, x20
    mov x2, #1
    bl np_alloc
    ldp x9, x10, [sp], #16
    cbz x0, .Los_open_oom
    mov x11, x0
.Los_open_copy:
    cbz x9, .Los_open_copied
    ldrb w12, [x10], #1
    strb w12, [x11], #1
    sub x9, x9, #1
    b .Los_open_copy
.Los_open_copied:
    strb wzr, [x11]
    mov w1, #0
    ldrb w9, [x21]
    ldrb w10, [x21, #1]
    cbz w9, .Los_open_write_only
    cbz w10, .Los_open_flags
    mov w1, #2
    b .Los_open_flags
.Los_open_write_only:
    cbz w10, .Los_open_flags
    mov w1, #1
.Los_open_flags:
    ldrb w9, [x21, #2]
    cbz w9, .Los_open_truncate
    orr w1, w1, #0x200
.Los_open_truncate:
    ldrb w9, [x21, #3]
    cbz w9, .Los_open_append
    orr w1, w1, #0x400
.Los_open_append:
    ldrb w9, [x21, #4]
    cbz w9, .Los_open_call
    orr w1, w1, #0x8
.Los_open_call:
    orr w1, w1, #0x1000000
    mov x2, #0x1b6
    sys 5
    str x22, [x20, #16]
    tbnz x0, #63, .Los_open_errno
    str x0, [x19]
    b .Los_open_done
.Los_open_errno:
    neg w0, w0
    bl np_error
    str w0, [x19, #8]
    b .Los_open_done
.Los_open_oom:
    str x22, [x20, #16]
    movz w9, #0xaadc
    movk w9, #0x6979, lsl #16
    str w9, [x19, #8]
.Los_open_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// os.seek(file: *File, offset, whence) -> (usize, err).
.global neper_os_seek
neper_os_seek:
    cmp w2, #2
    b.hi .Lseek_failed
    ldr x0, [x0]
    sys 199
    tbnz x0, #63, .Lseek_failed
    mov x1, #0
    ret
.Lseek_failed:
    mov x0, #0
    movz w1, #0x7ebf
    movk w1, #0x6f77, lsl #16
    ret

// os.args: the result ([]str, err) at x0. The table `neper_start` built is kept in the slot
// at the start of __DATA, the literal at neper_start_args holding its distance.
.global neper_os_args
neper_os_args:
    adr x9, .Lstart_args
    ldr x10, [x9]
    add x9, x9, x10
    ldp x2, x3, [x9]
    stp x2, x3, [x0]
    str wzr, [x0, #16]
    ret

// os.clock(kind) -> (u64, err): nanoseconds of the wall or monotonic clock. The wall clock
// is gettimeofday; the monotonic one is the virtual counter every Apple Silicon core lets
// user code read, scaled by its own frequency register.
.global neper_os_clock
neper_os_clock:
    cmp w0, #1
    b.hi .Lclock_unsupported
    movz x3, #0xca00
    movk x3, #0x3b9a, lsl #16
    cbnz w0, .Lclock_monotonic
    sub sp, sp, #16
    mov x0, sp
    mov x1, #0
    mov x2, #0
    sys 116
    tbnz x0, #63, .Lclock_failed_pop
    ldr x0, [sp]
    ldr w2, [sp, #8]
    add sp, sp, #16
    mov x4, #1000
    mul x2, x2, x4
    madd x0, x0, x3, x2
    mov x1, #0
    ret
.Lclock_failed_pop:
    add sp, sp, #16
.Lclock_failed:
    mov x0, #0
    movz w1, #0x7ebf
    movk w1, #0x6f77, lsl #16
    ret
.Lclock_monotonic:
    mrs x9, cntvct_el0
    mrs x10, cntfrq_el0
    cbz x10, .Lclock_failed
    udiv x11, x9, x10
    msub x12, x11, x10, x9
    mul x11, x11, x3
    mul x12, x12, x3
    udiv x12, x12, x10
    add x0, x11, x12
    mov x1, #0
    ret
.Lclock_unsupported:
    mov x0, #0
    movz w1, #0xb651
    movk w1, #0x2f8b, lsl #16
    ret

// os.syscall(n, a0..a5) -> isize: the raw BSD call, n in x16 and the six arguments in x0-x5.
// The result is the kernel's own, a negative errno on failure.
.global neper_os_syscall
neper_os_syscall:
    // pipe(2) answers with two descriptors, in x0 and x1; for it the first argument is the
    // address of two 32-bit slots they are stored to, and the result is zero.
    sub sp, sp, #16
    str x1, [sp]
    str x0, [sp, #8]
    mov x16, x0
    mov x0, x1
    mov x1, x2
    mov x2, x3
    mov x3, x4
    mov x4, x5
    mov x5, x6
    svc #0x80
    b.cc 1f
    neg x0, x0
    add sp, sp, #16
    ret
1:
    ldr x9, [sp, #8]
    cmp x9, #42
    b.ne 2f
    ldr x9, [sp]
    stp w0, w1, [x9]
    mov x0, #0
2:
    add sp, sp, #16
    ret

// os.env_block: the result (str, err) at x0, the arena at x1. The environment as the kernel
// gave it, NAME=VALUE records each ended by a NUL, copied into the arena.
.global neper_os_env_block
neper_os_env_block:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    str x21, [sp, #32]
    mov x19, x0
    mov x20, x1
    stp xzr, xzr, [x19]
    str wzr, [x19, #16]
    adr x9, .Lstart_args
    ldr x10, [x9]
    add x9, x9, x10
    ldr x21, [x9, #16]
    mov x11, #0
    mov x12, #0
.Lenv_measure:
    ldr x13, [x21, x12, lsl #3]
    cbz x13, .Lenv_measured
.Lenv_length:
    ldrb w15, [x13], #1
    add x11, x11, #1
    cbnz w15, .Lenv_length
    add x12, x12, #1
    b .Lenv_measure
.Lenv_measured:
    mov x0, x20
    add x1, x11, #1
    mov x2, #1
    stp x11, x21, [sp, #-16]!
    bl np_alloc
    ldp x11, x21, [sp], #16
    cbz x0, .Lenv_oom
    mov x14, x0
    mov x12, #0
.Lenv_copy:
    ldr x13, [x21, x12, lsl #3]
    cbz x13, .Lenv_done
.Lenv_byte:
    ldrb w15, [x13], #1
    strb w15, [x14], #1
    cbnz w15, .Lenv_byte
    add x12, x12, #1
    b .Lenv_copy
.Lenv_done:
    str x0, [x19]
    str x11, [x19, #8]
    b .Lenv_out
.Lenv_oom:
    movz w9, #0xaadc
    movk w9, #0x6979, lsl #16
    str w9, [x19, #16]
.Lenv_out:
    ldr x21, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// os.spawn: the result {Proc, err} at x0, the arena at x1, the argument slices at x2, the
// Stdio at x3 (stdin, stdout, stderr). The arguments are copied terminated into the arena, a
// child made with fork (BSD call 2: x1 is 1 in the child), its descriptors set with dup2 (90)
// and the program run with execve (59); a child whose exec fails ends with 127.
.global neper_os_spawn
neper_os_spawn:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    mov x19, x0
    mov x20, x1
    ldp x21, x22, [x2]
    mov x23, x3
    str xzr, [x19]
    str wzr, [x19, #8]
    cbz x22, .Lspawn_not_found
    ldr x24, [x20, #16]
    add x1, x22, #1
    lsl x1, x1, #3
    mov x0, x20
    mov x2, #8
    bl np_alloc
    cbz x0, .Lspawn_oom
    mov x25, x0
    mov x26, #0
.Lspawn_copy_argument:
    cmp x26, x22
    b.hs .Lspawn_copied
    add x9, x21, x26, lsl #4
    ldr x1, [x9, #8]
    add x1, x1, #1
    mov x0, x20
    mov x2, #1
    bl np_alloc
    cbz x0, .Lspawn_oom
    add x9, x21, x26, lsl #4
    ldp x10, x11, [x9]
    mov x12, x0
.Lspawn_copy_byte:
    cbz x11, .Lspawn_copy_done
    ldrb w13, [x10], #1
    strb w13, [x12], #1
    sub x11, x11, #1
    b .Lspawn_copy_byte
.Lspawn_copy_done:
    strb wzr, [x12]
    str x0, [x25, x26, lsl #3]
    add x26, x26, #1
    b .Lspawn_copy_argument
.Lspawn_copied:
    str xzr, [x25, x22, lsl #3]
    sys 2
    tbnz x0, #63, .Lspawn_failed
    cbnz x1, .Lspawn_child
    str x24, [x20, #16]
    str x0, [x19]
    b .Lspawn_done
.Lspawn_child:
    ldr x0, [x23]
    cbz x0, .Lspawn_stdout
    mov x1, #0
    sys 90
.Lspawn_stdout:
    ldr x0, [x23, #8]
    cmp x0, #1
    b.eq .Lspawn_stderr
    mov x1, #1
    sys 90
.Lspawn_stderr:
    ldr x0, [x23, #16]
    cmp x0, #2
    b.eq .Lspawn_exec
    mov x1, #2
    sys 90
.Lspawn_exec:
    ldr x0, [x25]
    mov x1, x25
    mov x2, #0
    sys 59
    mov x0, #127
    sys 1
.Lspawn_failed:
    str x24, [x20, #16]
    movz w9, #0x7ebf
    movk w9, #0x6f77, lsl #16
    str w9, [x19, #8]
    b .Lspawn_done
.Lspawn_not_found:
    movz w9, #0xe2cd
    movk w9, #0x7683, lsl #16
    str w9, [x19, #8]
    b .Lspawn_done
.Lspawn_oom:
    str x24, [x20, #16]
    movz w9, #0xaadc
    movk w9, #0x6979, lsl #16
    str w9, [x19, #8]
.Lspawn_done:
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret

// os.wait(proc: *Proc) -> (i32, err): the exit status, or 128 plus the signal that ended it.
.global neper_os_wait
neper_os_wait:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    ldr x0, [x0]
    add x1, sp, #16
    mov x2, #0
    mov x3, #0
    sys 7
    tbnz x0, #63, .Lwait_failed
    ldr w0, [sp, #16]
    ands w9, w0, #0x7f
    b.ne .Lwait_signal
    ubfx w0, w0, #8, #8
    mov x1, #0
    ldp x29, x30, [sp], #32
    ret
.Lwait_signal:
    add w0, w9, #128
    mov x1, #0
    ldp x29, x30, [sp], #32
    ret
.Lwait_failed:
    mov x0, #-1
    movz w1, #0x7ebf
    movk w1, #0x6f77, lsl #16
    ldp x29, x30, [sp], #32
    ret

// Threads are libSystem's: pthread_create, pthread_join and pthread_detach, which dyld binds
// into three slots the linker adds after the program's own imports whenever one of the
// functions below is reached. Each word of this table holds its distance from itself to its
// slot, patched by the linker.
.global neper_runtime_imports
neper_runtime_imports:
.Lruntime_imports:
    .quad 0, 0, 0, 0, 0, 0, 0

// x9 = 8 * the index of the pthread function: its address, in x9. Clobbers x10, x11.
np_pthread:
    adr x10, .Lruntime_imports
    add x10, x10, x9
    ldr x11, [x10]
    add x10, x10, x11
    ldr x9, [x10]
    ret

// os.thread_create: the result {Thread, err} at x0, the entry at x1, its context at x2, the
// stack size at x3. The thread gets that stack through a pthread attribute block (64 bytes at
// sp+48), rounded up to the 16 KB page and at least 64 KB as on Linux; a size the library
// refuses leaves the default.
.global neper_os_thread_create
neper_os_thread_create:
    stp x29, x30, [sp, #-128]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    add x0, sp, #48
    mov x9, #32
    bl np_pthread
    blr x9
    cbnz w0, .Lthread_create_failed
    mov x9, #65536
    cmp x22, x9
    csel x22, x9, x22, lo
    mov x9, #16383
    add x22, x22, x9
    and x22, x22, #-16384
    add x0, sp, #48
    mov x1, x22
    mov x9, #40
    bl np_pthread
    blr x9
    cbnz w0, .Lthread_create_failed
    add x0, sp, #112
    add x1, sp, #48
    mov x2, x20
    mov x3, x21
    mov x9, #0
    bl np_pthread
    blr x9
    mov w22, w0
    add x0, sp, #48
    mov x9, #48
    bl np_pthread
    blr x9
    cbnz w22, .Lthread_create_failed
    ldr x9, [sp, #112]
    str x9, [x19]
    str wzr, [x19, #8]
    b .Lthread_create_out
.Lthread_create_failed:
    str xzr, [x19]
    movz w9, #0x7ebf
    movk w9, #0x6f77, lsl #16
    str w9, [x19, #8]
.Lthread_create_out:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #128
    ret

// os.thread_join(thread: *Thread) -> err.
.global neper_os_thread_join
neper_os_thread_join:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x0, [x0]
    cbz x0, .Lthread_join_failed
    mov x1, #0
    mov x9, #8
    bl np_pthread
    blr x9
    cbnz w0, .Lthread_join_failed
    ldp x29, x30, [sp], #16
    ret
.Lthread_join_failed:
    movz w0, #0x7ebf
    movk w0, #0x6f77, lsl #16
    ldp x29, x30, [sp], #16
    ret

// os.thread_detach(thread: *Thread) -> err.
.global neper_os_thread_detach
neper_os_thread_detach:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x0, [x0]
    cbz x0, .Lthread_detach_failed
    mov x9, #16
    bl np_pthread
    blr x9
    cbnz w0, .Lthread_detach_failed
    ldp x29, x30, [sp], #16
    ret
.Lthread_detach_failed:
    movz w0, #0x7ebf
    movk w0, #0x6f77, lsl #16
    ldp x29, x30, [sp], #16
    ret

// Section 8's blocking primitives, __ulock_wait (515) and __ulock_wake (516) with
// UL_COMPARE_AND_WAIT (1) and ULF_WAKE_ALL (0x100). wait_u32(p, expected, timeout_ns) -> err:
// a wake, a value that already differs and a signal are all `ok` -- the fence promises
// spurious wakes -- a negative timeout waits for ever, and a zero one polls once: a value that differs is `ok`, the same one times out.
// The kernel's timeout is in microseconds, rounded up and capped at 32 bits.
.global neper_os_wait_u32
neper_os_wait_u32:
    mov x3, #0
    tbnz x2, #63, .Lwait_u32_go
    cbnz x2, .Lwait_u32_pos
    ldr w9, [x0]
    cmp w9, w1
    b.ne .Lwait_u32_ok
    b .Lwait_u32_timeout
.Lwait_u32_pos:
    mov x9, #1000
    add x2, x2, x9
    sub x2, x2, #1
    udiv x3, x2, x9
    mov x10, #0xffffffff
    cmp x3, x10
    csel x3, x10, x3, hi
.Lwait_u32_go:
    mov w2, w1
    mov x1, x0
    mov x0, #1
    sys 515
    tbz x0, #63, .Lwait_u32_ok
    cmn x0, #4
    b.eq .Lwait_u32_ok
    cmn x0, #35
    b.eq .Lwait_u32_ok
    cmn x0, #60
    b.eq .Lwait_u32_timeout
    movz w0, #0x7ebf
    movk w0, #0x6f77, lsl #16
    ret
.Lwait_u32_ok:
    mov x0, #0
    ret
.Lwait_u32_timeout:
    movz w0, #0x2f09
    movk w0, #0x5281, lsl #16
    ret

.global neper_os_wake_one_u32
neper_os_wake_one_u32:
    mov x1, x0
    mov x0, #1
    mov x2, #0
    sys 516
    ret

.global neper_os_wake_all_u32
neper_os_wake_all_u32:
    mov x1, x0
    mov x0, #0x101
    mov x2, #0
    sys 516
    ret

// os.reserve(size) -> (usize, err): address space and no memory, PROT_NONE.
.global neper_os_reserve
neper_os_reserve:
    mov x1, x0
    mov x0, #0
    mov x2, #0
    mov x3, #0x1002
    mov x4, #-1
    mov x5, #0
    sys 197
    tbnz x0, #63, .Lreserve_failed
    mov x1, #0
    ret
.Lreserve_failed:
    mov x0, #0
    movz w1, #0x7ebf
    movk w1, #0x6f77, lsl #16
    ret

// os.commit(address, size) -> err: the reserved pages made readable and writable.
.global neper_os_commit
neper_os_commit:
    mov x2, #3
    sys 74
    tbnz x0, #63, .Lcommit_failed
    mov x0, #0
    ret
.Lcommit_failed:
    movz w0, #0x7ebf
    movk w0, #0x6f77, lsl #16
    ret


// Spec section 9 rule 4: the supplied `hash` is xxHash64 with seed 0 over a value's
// canonical little-endian bytes; this agrees bit for bit with algo.hash.xxhash64, with
// the x86-64 runtime and with bootstrap/runtime.c. x0 = the bytes, x1 = their length.
.global neper_hash_bytes
neper_hash_bytes:
    ldr x11, .Lhash_p1
    ldr x12, .Lhash_p2
    ldr x13, .Lhash_p3
    ldr x14, .Lhash_p4
    ldr x15, .Lhash_p5
    mov x9, x0
    mov x10, x1
    mov x3, #0
    cmp x10, #32
    b.lo .Lhash_small
    add x5, x11, x12
    mov x6, x12
    mov x7, #0
    neg x8, x11
    sub x2, x10, #32
.Lhash_block:
    ldr x4, [x9, x3]
    mul x4, x4, x12
    add x5, x5, x4
    ror x5, x5, #33
    mul x5, x5, x11
    add x3, x3, #8
    ldr x4, [x9, x3]
    mul x4, x4, x12
    add x6, x6, x4
    ror x6, x6, #33
    mul x6, x6, x11
    add x3, x3, #8
    ldr x4, [x9, x3]
    mul x4, x4, x12
    add x7, x7, x4
    ror x7, x7, #33
    mul x7, x7, x11
    add x3, x3, #8
    ldr x4, [x9, x3]
    mul x4, x4, x12
    add x8, x8, x4
    ror x8, x8, #33
    mul x8, x8, x11
    add x3, x3, #8
    cmp x3, x2
    b.ls .Lhash_block
    ror x16, x5, #63
    ror x4, x6, #57
    add x16, x16, x4
    ror x4, x7, #52
    add x16, x16, x4
    ror x4, x8, #46
    add x16, x16, x4
    mul x4, x5, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    madd x16, x16, x11, x14
    mul x4, x6, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    madd x16, x16, x11, x14
    mul x4, x7, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    madd x16, x16, x11, x14
    mul x4, x8, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    madd x16, x16, x11, x14
    b .Lhash_sized
.Lhash_small:
    mov x16, x15
.Lhash_sized:
    add x16, x16, x10
.Lhash_tail8:
    add x4, x3, #8
    cmp x4, x10
    b.hi .Lhash_tail4
    ldr x4, [x9, x3]
    mul x4, x4, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    ror x16, x16, #37
    madd x16, x16, x11, x14
    add x3, x3, #8
    b .Lhash_tail8
.Lhash_tail4:
    add x4, x3, #4
    cmp x4, x10
    b.hi .Lhash_tail1
    ldr w4, [x9, x3]
    mul x4, x4, x11
    eor x16, x16, x4
    ror x16, x16, #41
    madd x16, x16, x12, x13
    add x3, x3, #4
.Lhash_tail1:
    cmp x3, x10
    b.hs .Lhash_final
    ldrb w4, [x9, x3]
    mul x4, x4, x15
    eor x16, x16, x4
    ror x16, x16, #53
    mul x16, x16, x11
    add x3, x3, #1
    b .Lhash_tail1
.Lhash_final:
    eor x16, x16, x16, lsr #33
    mul x16, x16, x12
    eor x16, x16, x16, lsr #29
    mul x16, x16, x13
    eor x0, x16, x16, lsr #32
    ret
    .p2align 3
.Lhash_p1:
    .quad 11400714785074694791
.Lhash_p2:
    .quad 14029467366897019727
.Lhash_p3:
    .quad 1609587929392839161
.Lhash_p4:
    .quad 9650029242287828579
.Lhash_p5:
    .quad 2870177450012600261

// os.aes_ctr and os.ghash_blocks (C098): the answer is none -- there is no AES-NI here, so the
// caller keeps its portable path. (ARMv8 AES and PMULL would be the same two functions.)
.global neper_os_aes_ctr
neper_os_aes_ctr:
    mov x0, #0
    ret
.global neper_os_ghash_blocks
neper_os_ghash_blocks:
    mov x0, #0
    ret
.global neper_os_cpu_features
neper_os_cpu_features:
    mov x0, #0
    ret
.global neper_os_aes_expand_key
neper_os_aes_expand_key:
    mov x0, #0
    ret
